import FermataCore
import Foundation
import Observation

/// A row in one of the device lists.
struct DeviceRow: Identifiable, Equatable {
    var id: String
    var name: String
    var symbol: String
    var isConnected: Bool
    var isCurrent: Bool
    var isMuted: Bool
    var isNeverAuto: Bool
    var isHidden: Bool
    var lastSeen: Date?
}

/// A connected device the user has hidden, and the list it is hidden from.
struct HiddenDevice: Identifiable, Equatable {
    var uid: String
    var name: String
    var role: HiddenRole
    var id: String { "\(role.rawValue):\(uid)" }
}

/// The app's state: settings, the current hardware, and the actions that change them.
@Observable
final class AppModel {
    private(set) var settings: Settings {
        didSet { store?.save(settings) }
    }
    private(set) var snapshot = HardwareSnapshot()
    private(set) var levels = Levels()
    /// Set while the app is holding the microphone muted. Saved before the hardware is
    /// touched, so a crash can't leave a microphone silenced.
    private(set) var microphoneMute = MicrophoneMuteRecord.load() {
        didSet { MicrophoneMuteRecord.save(microphoneMute) }
    }
    private(set) var notice: String?
    var isEditing = false

    private let store: SettingsStore?
    private let hardware = AudioHardware()
    private var engine = SwitchEngine()
    private var listenTask: Task<Void, Never>?
    private var recheckTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?

    init(store: SettingsStore = SettingsStore()) {
        self.store = store
        settings = store.load()
    }

    #if DEBUG
    /// A model that shows `snapshot` in place of the hardware and saves nothing, for screenshots.
    init(demo snapshot: HardwareSnapshot, settings: Settings) {
        store = nil
        self.settings = settings
        self.snapshot = snapshot
    }
    #endif

    // MARK: - Lifecycle

    func start() {
        guard listenTask == nil else { return }
        listenTask = Task {
            // Left over from a crash while muted: put the microphone back first.
            await unmuteMicrophone()
            for await change in await hardware.changes() {
                if change.contains(.devices) {
                    await refreshDevices()
                    settings.remember(snapshot.devices, now: .now)
                    await evaluate()
                }
                levels = await hardware.levels(for: snapshot.devices)
            }
        }
    }

    /// Leaves the system as the user would expect with the app gone.
    func stop() async {
        listenTask?.cancel()
        listenTask = nil
        await unmuteMicrophone()
        await hardware.stop()
    }

    private func refreshDevices() async {
        snapshot = await hardware.snapshot()
        // The mute belongs to "the microphone", not one device: when the default input
        // moves, the old one is restored and the new one muted.
        if let record = microphoneMute, record.uid != snapshot.defaultInput {
            await unmuteMicrophone()
            await muteMicrophone()
        }
    }

    /// Runs the switching engine against the latest snapshot and applies what it decides.
    private func evaluate() async {
        let decision = engine.evaluate(snapshot, settings: settings, userIsPicking: SystemSoundPicker.isOpen())
        if let mode = decision.mode {
            settings.mode = mode
        }
        for (direction, uid) in decision.yielded {
            show("\(name(of: uid)) keeps taking over the \(direction == .input ? "microphone" : "output"), so it stays for now.")
        }
        for (direction, uid) in decision.defaults {
            do {
                try await hardware.setDefault(uid, for: direction)
            } catch {
                show("Couldn’t switch to \(name(of: uid)).")
            }
        }
        if let recheckAt = decision.recheckAt {
            recheckTask?.cancel()
            recheckTask = Task {
                try? await Task.sleep(for: .seconds(max(recheckAt.timeIntervalSinceNow, 0)))
                guard !Task.isCancelled else { return }
                await refreshDevices()
                await evaluate()
            }
        }
    }

    /// Changes settings, then lets priorities decide again for the affected direction.
    private func update(following direction: Direction? = nil, _ change: (inout Settings) -> Void) {
        change(&settings)
        engine.followPriorities(direction)
        Task { await evaluate() }
    }

    private func show(_ message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { notice = nil }
        }
    }

    func dismissNotice() {
        noticeTask?.cancel()
        notice = nil
    }

    // MARK: - Lists

    /// The microphone list currently in effect, which may be the headphone one.
    var activeMicrophoneList: PriorityList {
        settings.list(for: .input, in: settings.mode)
    }

    func rows(for list: PriorityList) -> [DeviceRow] {
        let direction = list.direction
        var uids = snapshot.devices
            .filter { $0.isUsable(as: direction) && (list.category == nil || settings.category(of: $0) == list.category) }
            .map(\.uid)
        if isEditing {
            // Add devices seen before but not connected now.
            let connected = Set(snapshot.devices.map(\.uid))
            uids += settings.known.filter { uid, known in
                !connected.contains(uid)
                    && (direction == .input ? known.hasInput : known.hasOutput)
                    && (list.category == nil || (settings.categoryOverrides[uid] ?? guessCategory(known.name)) == list.category)
            }.keys
        } else {
            uids.removeAll { settings.isHidden($0, in: list.hiddenRole) }
        }

        return settings.ordered(uids, by: list).map { uid in
            let device = snapshot.device(uid: uid)
            let isConnected = device?.isUsable(as: direction) ?? false
            let name = name(of: uid)
            return DeviceRow(
                id: uid,
                name: name,
                symbol: DeviceSymbol.name(
                    for: name,
                    model: device?.model ?? settings.known[uid]?.model,
                    transport: device?.transport,
                    direction: direction,
                    category: list.category ?? device.map(settings.category)
                ),
                isConnected: isConnected,
                isCurrent: isConnected && snapshot.defaultUID(direction) == uid,
                isMuted: isConnected && levels.mutedUIDs.contains(uid),
                isNeverAuto: settings.neverAuto.contains(uid),
                isHidden: settings.isHidden(uid, in: list.hiddenRole),
                lastSeen: isConnected ? nil : settings.known[uid]?.lastSeen
            )
        }
    }

    var hiddenDevices: [HiddenDevice] {
        HiddenRole.allCases.flatMap { role in
            snapshot.devices
                .filter { device in
                    settings.isHidden(device.uid, in: role)
                        && device.isUsable(as: role.direction)
                        && (role == .microphone || HiddenRole(settings.category(of: device)) == role)
                }
                .map { HiddenDevice(uid: $0.uid, name: $0.name, role: role) }
        }
    }

    private func guessCategory(_ name: String) -> OutputCategory {
        DeviceClassifier.nameSuggestsHeadphones(name) ? .headphone : .speaker
    }

    private func name(of uid: String) -> String {
        snapshot.device(uid: uid)?.name ?? settings.known[uid]?.name ?? uid
    }

    var isOutputMuted: Bool {
        snapshot.defaultOutput.map(levels.mutedUIDs.contains) ?? false
    }

    var isMicrophoneMuted: Bool {
        microphoneMute != nil || (snapshot.defaultInput.map(levels.mutedUIDs.contains) ?? false)
    }

    // MARK: - Actions

    func perform(_ command: URLCommand) {
        switch command {
        case .toggleMicMute: toggleMicrophoneMute()
        case .muteMic: setMicrophoneMuted(true)
        case .unmuteMic: setMicrophoneMuted(false)
        case .toggleAutomatic: setAutomatic(!settings.isAutomatic)
        case .enableAutomatic: setAutomatic(true)
        case .disableAutomatic: setAutomatic(false)
        case .speakers: setMode(.speaker)
        case .headphones: setMode(.headphone)
        }
    }

    func select(_ uid: String, in list: PriorityList) {
        if settings.isAutomatic {
            if let category = list.category { settings.mode = category }
            engine.userPicked(uid, for: list.direction)
        }
        Task {
            try? await hardware.setDefault(uid, for: list.direction)
            await refreshDevices()
        }
    }

    /// Saves a new order for a list; the top connected device takes over.
    func reorder(_ list: PriorityList, to uids: [String]) {
        update(following: list.direction) { $0.setOrder(uids, for: list) }
    }

    func setMode(_ mode: OutputCategory) {
        update(following: settings.micFollowsOutput ? nil : .output) { $0.mode = mode }
    }

    func setAutomatic(_ isAutomatic: Bool) {
        update { $0.isAutomatic = isAutomatic }
    }

    func setMicFollowsOutput(_ enabled: Bool) {
        update(following: .input) { $0.setMicFollowsOutput(enabled) }
    }

    func setCategory(_ category: OutputCategory, for uid: String) {
        update(following: .output) { $0.categoryOverrides[uid] = category }
    }

    func setHidden(_ hidden: Bool, uid: String, in roles: HiddenRole...) {
        update(following: roles.first?.direction) { settings in
            for role in roles { settings.setHidden(hidden, uid: uid, in: role) }
        }
    }

    func setNeverAuto(_ neverAuto: Bool, uid: String) {
        update { settings in
            if neverAuto { settings.neverAuto.insert(uid) } else { settings.neverAuto.remove(uid) }
        }
    }

    func forget(_ uid: String) {
        settings.forget(uid)
    }

    // MARK: - Microphone mute

    func toggleMicrophoneMute() {
        setMicrophoneMuted(microphoneMute == nil)
    }

    func setMicrophoneMuted(_ muted: Bool) {
        Task {
            if muted { await muteMicrophone() } else { await unmuteMicrophone() }
            levels = await hardware.levels(for: snapshot.devices)
        }
    }

    private func muteMicrophone() async {
        guard microphoneMute == nil, let uid = snapshot.defaultInput else { return }
        guard let method = await hardware.microphoneMuteMethod(uid) else {
            show("\(name(of: uid)) can’t be muted.")
            return
        }
        let record = MicrophoneMuteRecord(uid: uid, method: method)
        microphoneMute = record
        await hardware.applyMicrophoneMute(record)
    }

    private func unmuteMicrophone() async {
        guard let record = microphoneMute else { return }
        microphoneMute = nil
        await hardware.restoreMicrophone(record)
    }
}
