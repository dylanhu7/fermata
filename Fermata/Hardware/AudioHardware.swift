import AudioToolbox
import CoreAudio
import FermataCore
import Foundation

/// What changed since the last report from `AudioHardware`.
nonisolated struct HardwareChange: OptionSet, Sendable {
    let rawValue: Int
    /// Devices or the default devices changed.
    static let devices = HardwareChange(rawValue: 1 << 0)
    /// Volume or mute on the current default devices.
    static let levels = HardwareChange(rawValue: 1 << 1)
}

nonisolated struct Levels: Sendable, Equatable {
    var outputVolume: Float = 0
    var mutedUIDs: Set<String> = []
}

/// The only place the app talks to CoreAudio.
///
/// CoreAudio calls are IPC to `coreaudiod` and can stall while devices come and go, so they
/// run on this actor's own serial queue rather than the main thread. Property listeners are
/// delivered on the same queue, and bursts of them (a Bluetooth headset connecting produces
/// a dozen) are merged into one report.
actor AudioHardware {
    /// How long to collect events after the first one before reporting.
    private static let coalescingDelay = Duration.milliseconds(150)

    private let queue = DispatchSerialQueue(label: "hu.dylan.fermata.coreaudio", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let system = AudioHardwareSystem.shared
    private var continuation: AsyncStream<HardwareChange>.Continuation?
    private var unreported: HardwareChange = []
    private var pendingReport: Task<Void, Never>?
    /// The default devices being watched for volume and mute. CoreAudio hands out a new
    /// object per lookup and keeps listeners per object, so these must be kept to remove them.
    private var watched: [AudioHardwareDevice] = []

    private static let systemProperties = [
        PropertyAddress(kAudioHardwarePropertyDevices),
        PropertyAddress(kAudioHardwarePropertyDefaultInputDevice),
        PropertyAddress(kAudioHardwarePropertyDefaultOutputDevice),
    ]
    private static let levelSelectors: Set = [kAudioDevicePropertyMute, kAudioHardwareServiceDeviceProperty_VirtualMainVolume]

    // MARK: - Events

    /// Starts listening. The stream reports everything immediately, then each merged change,
    /// until `stop()`.
    func changes() -> AsyncStream<HardwareChange> {
        stop()
        let (stream, continuation) = AsyncStream.makeStream(of: HardwareChange.self)
        self.continuation = continuation
        system.delegates = [self]
        try? system.addListener(forProperties: Self.systemProperties, dispatchQueue: queue)
        watchDefaultDevices()
        continuation.yield([.devices, .levels])
        return stream
    }

    func stop() {
        try? system.removeListener(forProperties: Self.systemProperties, dispatchQueue: queue)
        system.delegates = []
        unwatchDevices()
        pendingReport?.cancel()
        pendingReport = nil
        continuation?.finish()
        continuation = nil
    }

    private func note(_ change: HardwareChange) {
        unreported.formUnion(change)
        guard pendingReport == nil else { return }
        pendingReport = Task {
            try? await Task.sleep(for: Self.coalescingDelay)
            guard !Task.isCancelled else { return }
            let change = unreported
            unreported = []
            pendingReport = nil
            if change.contains(.devices) { watchDefaultDevices() }
            continuation?.yield(change)
        }
    }

    /// Volume and mute listeners go on the current default devices only, rebuilt whenever
    /// the devices change because CoreAudio reuses object IDs for different devices.
    private func watchDefaultDevices() {
        unwatchDevices()
        for direction in Direction.allCases {
            guard let device = try? defaultDevice(direction) else { continue }
            let properties = [Property.mute(direction), Property.volume(direction)].filter { device.hasProperty(address: $0) }
            guard (try? device.addListener(forProperties: properties, dispatchQueue: queue)) != nil else { continue }
            device.delegates = [self]
            watched.append(device)
        }
    }

    private func unwatchDevices() {
        for device in watched {
            for direction in Direction.allCases {
                // Fails harmlessly for a device that has already gone away.
                try? device.removeListener(forProperties: [Property.mute(direction), Property.volume(direction)], dispatchQueue: queue)
            }
            device.delegates = []
        }
        watched = []
    }

    // MARK: - Reading

    func snapshot() -> HardwareSnapshot {
        HardwareSnapshot(
            devices: ((try? system.devices) ?? []).compactMap(describe),
            defaultInput: try? system.defaultInputDevice?.uid,
            defaultOutput: try? system.defaultOutputDevice?.uid
        )
    }

    private func describe(_ device: AudioHardwareDevice) -> Device? {
        guard let uid = try? device.uid, (try? device.isHidden) != true else { return nil }
        let streams = (try? device.streams) ?? []
        let inputs = streams.filter { (try? $0.direction) == .input }
        let outputs = streams.filter { (try? $0.direction) == .output }
        guard !inputs.isEmpty || !outputs.isEmpty else { return nil }

        let transport = Transport(code: (try? device.transportType) ?? 0)
        return Device(
            uid: uid,
            objectID: device.id,
            name: (try? device.name) ?? uid,
            transport: transport,
            hasInput: !inputs.isEmpty,
            hasOutput: !outputs.isEmpty,
            isAlive: (try? device.isAlive) ?? false,
            canBeDefaultInput: (try? device.canBeDefaultInputDevice) ?? false,
            canBeDefaultOutput: (try? device.canBeDefaultOutputDevice) ?? false,
            terminalCategory: DeviceClassifier.category(outputTerminalTypes: outputs.compactMap { try? $0.terminalType }, transport: transport),
            model: (try? device.modelUID).flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    func levels(for devices: [Device]) -> Levels {
        var levels = Levels()
        if let output = try? system.defaultOutputDevice {
            levels.outputVolume = output.value(Property.volume(.output), as: Float32.self) ?? 0
        }
        for device in devices where device.isAlive {
            let object = AudioHardwareDevice(id: device.objectID)
            for direction in Direction.allCases where device.has(direction) {
                // Some devices only expose mute on their first channel; outputs at zero count as muted.
                let muted = [kAudioObjectPropertyElementMain, 1].contains {
                    object.value(Property.mute(direction, element: $0), as: UInt32.self) ?? 0 != 0
                } || (direction == .output && (object.value(Property.volume(.output), as: Float32.self) ?? 1) < 0.01)
                if muted { levels.mutedUIDs.insert(device.uid) }
            }
        }
        return levels
    }

    private func defaultDevice(_ direction: Direction) throws -> AudioHardwareDevice? {
        direction == .input ? try system.defaultInputDevice : try system.defaultOutputDevice
    }

    // MARK: - Changing

    func setDefault(_ uid: String, for direction: Direction) throws {
        guard let device = try system.device(forUID: uid), try defaultDevice(direction)?.id != device.id else { return }
        switch direction {
        case .input: try system.setDefaultInputDevice(device)
        case .output: try system.setDefaultOutputDevice(device)
        }
    }

    /// How a microphone can be muted: by its mute switch when it has one, otherwise by
    /// turning its input volume to zero. Nothing is changed yet, so the caller can record
    /// how to undo it first.
    func microphoneMuteMethod(_ uid: String) -> MicrophoneMuteRecord.Method? {
        guard let device = try? system.device(forUID: uid) else { return nil }
        if device.isSettable(Property.mute(.input)) { return .muteProperty }
        guard device.isSettable(Property.volume(.input)),
              let previous = device.value(Property.volume(.input), as: Float32.self)
        else { return nil }
        return .volume(previous: previous)
    }

    func applyMicrophoneMute(_ record: MicrophoneMuteRecord) {
        guard let device = try? system.device(forUID: record.uid) else { return }
        switch record.method {
        case .muteProperty: device.set(UInt32(1), for: Property.mute(.input))
        case .volume: device.set(Float32(0), for: Property.volume(.input))
        }
    }

    func restoreMicrophone(_ record: MicrophoneMuteRecord) {
        guard let device = try? system.device(forUID: record.uid) else { return }
        switch record.method {
        case .muteProperty: device.set(UInt32(0), for: Property.mute(.input))
        case let .volume(previous): device.set(Float32(previous), for: Property.volume(.input))
        }
    }
}

extension AudioHardware: PropertyListenerDelegate {
    /// Called on `queue`, which is this actor's executor.
    nonisolated func propertiesChanged(properties: [AudioObjectPropertyAddress]) {
        let isLevels = properties.allSatisfy { Self.levelSelectors.contains($0.mSelector) }
        assumeIsolated { $0.note(isLevels ? .levels : [.devices, .levels]) }
    }
}

// MARK: - Raw properties

/// Volume and mute, which the Swift CoreAudio classes only expose per channel.
private nonisolated enum Property {
    static func mute(_ direction: Direction, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        PropertyAddress(kAudioDevicePropertyMute, scope: direction.scope, element: element)
    }

    static func volume(_ direction: Direction) -> AudioObjectPropertyAddress {
        PropertyAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: direction.scope)
    }
}

private nonisolated extension Direction {
    var scope: AudioObjectPropertyScope {
        self == .input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
    }
}

private nonisolated extension AudioHardwareObject {
    func value<Value: BitwiseCopyable>(_ address: AudioObjectPropertyAddress, as _: Value.Type) -> Value? {
        guard hasProperty(address: address),
              let data = try? propertyData(address: address),
              data.count >= MemoryLayout<Value>.size
        else { return nil }
        return data.withUnsafeBytes { $0.loadUnaligned(as: Value.self) }
    }

    func isSettable(_ address: AudioObjectPropertyAddress) -> Bool {
        hasProperty(address: address) && (try? isPropertySettable(address: address)) == true
    }

    func set<Value: BitwiseCopyable>(_ value: Value, for address: AudioObjectPropertyAddress) {
        try? setPropertyData(address: address, data: withUnsafeBytes(of: value) { Data($0) })
    }
}
