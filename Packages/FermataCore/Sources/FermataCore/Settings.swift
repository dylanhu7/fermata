import Foundation

/// What is remembered about a device between connections.
public struct KnownDevice: Codable, Sendable, Equatable {
    public var name: String
    public var hasInput: Bool
    public var hasOutput: Bool
    public var lastSeen: Date
    public var model: String?

    public init(name: String, hasInput: Bool, hasOutput: Bool, lastSeen: Date, model: String? = nil) {
        self.name = name
        self.hasInput = hasInput
        self.hasOutput = hasOutput
        self.lastSeen = lastSeen
        self.model = model
    }
}

/// Where a device can be hidden. Hiding is per role, so a USB headset can be hidden as a
/// speaker but still listed as headphones.
public enum HiddenRole: String, Codable, Sendable, CaseIterable, CodingKeyRepresentable {
    case microphone
    case speaker
    case headphone

    public init(_ category: OutputCategory) {
        self = category == .speaker ? .speaker : .headphone
    }

    public var direction: Direction { self == .microphone ? .input : .output }
}

extension PriorityList: CodingKeyRepresentable {}

/// Everything the user has configured, stored as one JSON value. Devices are identified
/// by their CoreAudio UID.
public struct Settings: Codable, Sendable, Equatable {
    /// When false the app never changes the default devices on its own ("manual mode").
    public var isAutomatic = true
    public var mode: OutputCategory = .speaker
    public var micFollowsOutput = false
    public var lists: [PriorityList: [String]] = [:]
    public var categoryOverrides: [String: OutputCategory] = [:]
    public var hidden: [HiddenRole: Set<String>] = [:]
    /// Listed and selectable by hand, but never chosen automatically.
    public var neverAuto: Set<String> = []
    public var known: [String: KnownDevice] = [:]
    /// Devices that have already had first-sight defaults applied.
    public var classified: Set<String> = []

    public init() {}

    // MARK: - Queries

    public func category(of device: Device) -> OutputCategory {
        categoryOverrides[device.uid] ?? DeviceClassifier.category(for: device)
    }

    public func isHidden(_ uid: String, in role: HiddenRole) -> Bool {
        hidden[role, default: []].contains(uid)
    }

    /// The list that decides the default device for `direction` in the given output mode.
    public func list(for direction: Direction, in mode: OutputCategory) -> PriorityList {
        switch direction {
        case .output: PriorityList(mode)
        case .input: micFollowsOutput && mode == .headphone ? .microphonesWithHeadphones : .microphones
        }
    }

    /// Orders `uids` by `list`; anything the user hasn't ranked goes last, by name.
    public func ordered(_ uids: [String], by list: PriorityList) -> [String] {
        let ranking = lists[list, default: []]
        func rank(_ uid: String) -> Int { ranking.firstIndex(of: uid) ?? .max }
        func name(_ uid: String) -> String { known[uid]?.name ?? uid }
        return uids.sorted {
            let (a, b) = (rank($0), rank($1))
            return a != b ? a < b : name($0).localizedStandardCompare(name($1)) == .orderedAscending
        }
    }

    // MARK: - Mutations

    /// Records devices as seen and applies first-sight defaults: software and AirPlay devices
    /// are never picked automatically, and brand-new monitor speakers start hidden.
    public mutating func remember(_ devices: [Device], now: Date) {
        for device in devices {
            let isNew = known[device.uid] == nil
            var entry = known[device.uid] ?? KnownDevice(name: device.name, hasInput: false, hasOutput: false, lastSeen: now)
            entry.name = device.name
            entry.hasInput = entry.hasInput || device.hasInput
            entry.hasOutput = entry.hasOutput || device.hasOutput
            entry.lastSeen = now
            entry.model = device.model ?? entry.model
            known[device.uid] = entry

            guard !classified.contains(device.uid) else { continue }
            classified.insert(device.uid)
            if device.transport.isSoftware || device.transport.isPickedOnly {
                neverAuto.insert(device.uid)
            }
            if isNew, device.transport.isDisplay, device.hasOutput {
                hidden[.speaker, default: []].insert(device.uid)
                hidden[.headphone, default: []].insert(device.uid)
            }
        }
    }

    /// Replaces a list's order with `uids`, keeping ranked devices that aren't shown at the end
    /// so hiding or disconnecting a device doesn't lose its place.
    public mutating func setOrder(_ uids: [String], for list: PriorityList) {
        let rest = lists[list, default: []].filter { !uids.contains($0) }
        lists[list] = uids + rest
    }

    public mutating func forget(_ uid: String) {
        known[uid] = nil
        classified.remove(uid)
        neverAuto.remove(uid)
        categoryOverrides[uid] = nil
        for list in PriorityList.allCases { lists[list]?.removeAll { $0 == uid } }
        for role in HiddenRole.allCases { hidden[role]?.remove(uid) }
    }

    public mutating func setHidden(_ isHidden: Bool, uid: String, in role: HiddenRole) {
        if isHidden {
            hidden[role, default: []].insert(uid)
        } else {
            hidden[role]?.remove(uid)
        }
    }

    /// Turning on "microphone follows output" starts the headphone list as a copy.
    public mutating func setMicFollowsOutput(_ enabled: Bool) {
        micFollowsOutput = enabled
        if enabled, lists[.microphonesWithHeadphones] == nil {
            lists[.microphonesWithHeadphones] = lists[.microphones, default: []]
        }
    }
}
