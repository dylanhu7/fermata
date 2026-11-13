/// Which side of the audio system a device or list belongs to.
public enum Direction: String, Codable, Sendable, CaseIterable {
    case input
    case output
}

/// Output devices are split into two priority lists; the active one is the current mode.
public enum OutputCategory: String, Codable, Sendable, CaseIterable {
    case speaker
    case headphone
}

/// A priority list. Microphones have a second list used while in headphone mode
/// when "microphone follows output" is on.
public enum PriorityList: String, Codable, Sendable, CaseIterable {
    case microphones
    case microphonesWithHeadphones
    case speakers
    case headphones

    /// The list of outputs of one kind.
    public init(_ category: OutputCategory) {
        self = category == .speaker ? .speakers : .headphones
    }

    public var direction: Direction {
        category == nil ? .input : .output
    }

    /// The kind of output in this list; `nil` for microphones.
    public var category: OutputCategory? {
        switch self {
        case .microphones, .microphonesWithHeadphones: nil
        case .speakers: .speaker
        case .headphones: .headphone
        }
    }

    /// Both microphone lists share one set of hidden devices.
    public var hiddenRole: HiddenRole {
        switch self {
        case .microphones, .microphonesWithHeadphones: .microphone
        case .speakers: .speaker
        case .headphones: .headphone
        }
    }
}

/// One CoreAudio device as seen at a point in time. Input and output halves of a
/// physical product usually have different UIDs, but some USB interfaces share one.
public struct Device: Sendable, Hashable, Identifiable {
    public var uid: String
    public var objectID: UInt32
    public var name: String
    public var transport: Transport
    public var hasInput: Bool
    public var hasOutput: Bool
    public var isAlive: Bool
    public var canBeDefaultInput: Bool
    public var canBeDefaultOutput: Bool
    /// Category suggested by the hardware's stream terminal types, if it said anything useful.
    public var terminalCategory: OutputCategory?
    /// CoreAudio's model identifier, which survives renaming: "2014 4c" for AirPods Pro
    /// (Bluetooth product and vendor IDs), "AudioAccessory5,1" for a HomePod mini over AirPlay.
    public var model: String?

    public var id: String { uid }

    public init(
        uid: String,
        objectID: UInt32 = 0,
        name: String,
        transport: Transport = .unknown,
        hasInput: Bool = false,
        hasOutput: Bool = false,
        isAlive: Bool = true,
        canBeDefaultInput: Bool? = nil,
        canBeDefaultOutput: Bool? = nil,
        terminalCategory: OutputCategory? = nil,
        model: String? = nil
    ) {
        self.uid = uid
        self.objectID = objectID
        self.name = name
        self.transport = transport
        self.hasInput = hasInput
        self.hasOutput = hasOutput
        self.isAlive = isAlive
        self.canBeDefaultInput = canBeDefaultInput ?? hasInput
        self.canBeDefaultOutput = canBeDefaultOutput ?? hasOutput
        self.terminalCategory = terminalCategory
        self.model = model
    }

    public func has(_ direction: Direction) -> Bool {
        direction == .input ? hasInput : hasOutput
    }

    /// Whether this device may be made the system default for `direction` right now.
    public func isUsable(as direction: Direction) -> Bool {
        guard isAlive, has(direction) else { return false }
        return direction == .input ? canBeDefaultInput : canBeDefaultOutput
    }
}

/// Everything the switching logic needs to know about the hardware.
public struct HardwareSnapshot: Sendable, Equatable {
    public var devices: [Device]
    public var defaultInput: String?
    public var defaultOutput: String?

    public init(devices: [Device] = [], defaultInput: String? = nil, defaultOutput: String? = nil) {
        self.devices = devices
        self.defaultInput = defaultInput
        self.defaultOutput = defaultOutput
    }

    public func defaultUID(_ direction: Direction) -> String? {
        direction == .input ? defaultInput : defaultOutput
    }

    public func device(uid: String) -> Device? {
        devices.first { $0.uid == uid }
    }

    public func usableUIDs(_ direction: Direction) -> Set<String> {
        Set(devices.filter { $0.isUsable(as: direction) }.map(\.uid))
    }
}
