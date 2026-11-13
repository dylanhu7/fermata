import Foundation

/// What the engine wants done after looking at the hardware.
public struct SwitchDecision: Equatable, Sendable {
    /// Devices to make the system default.
    public var defaults: [Direction: String] = [:]
    /// The output mode to move to, if it should change.
    public var mode: OutputCategory?
    /// Devices that took the default again soon after being moved off it, and are now
    /// left in place.
    public var yielded: [Direction: String] = [:]
    /// A device that just appeared is given time to finish starting up before it becomes
    /// the default. Evaluate again at this time.
    public var recheckAt: Date?

    public init() {}
}

/// Decides when to change the system default devices.
///
/// Every change to the default device makes every app playing audio reconfigure, and apps
/// such as Klack can wedge when that happens several times in quick succession. So the
/// engine changes a default only when it differs from what is wanted, at most once per
/// evaluation, never while a change it asked for is still on its way, and only after a
/// newly connected device has had a moment to start. When something else keeps taking the
/// default, the engine stops fighting it.
public struct SwitchEngine: Sendable {
    /// How long a newly usable device is left to settle before it is made the default.
    public static let settleTime: TimeInterval = 0.75
    /// A device that changes the default again within this window of being reverted is left alone.
    public static let takeoverWindow: TimeInterval = 30
    /// A default moving to a device that appeared this recently is part of its arrival, not a takeover.
    public static let arrivalWindow: TimeInterval = 3
    /// A requested change that CoreAudio hasn't confirmed after this long is assumed to have failed.
    public static let echoTimeout: TimeInterval = 2

    private struct Request: Sendable {
        var uid: String
        var at: Date
    }

    private var previous: HardwareSnapshot?
    /// When each recently connected device became usable.
    private var arrivals: [String: Date] = [:]
    /// Changes asked for that CoreAudio hasn't reported back yet.
    private var requested: [Direction: Request] = [:]
    private var lastRevert: [Direction: Date] = [:]
    /// Choices made by the user, or ceded to another app, that stand until the device goes
    /// away or a new candidate arrives.
    private var kept: [Direction: String] = [:]

    public init() {}

    /// The user picked a device in the app; keep it rather than reapplying priorities.
    public mutating func userPicked(_ uid: String, for direction: Direction, now: Date = .now) {
        kept[direction] = uid
        requested[direction] = Request(uid: uid, at: now)
    }

    /// Priorities or the mode changed, so the next evaluation should follow them again.
    /// `nil` means both directions.
    public mutating func followPriorities(_ direction: Direction? = nil) {
        for direction in direction.map({ [$0] }) ?? Direction.allCases {
            kept[direction] = nil
            lastRevert[direction] = nil
        }
    }

    /// - Parameter userIsPicking: Control Center's sound menu or System Settings is open, so
    ///   a change to the default device is the user's own.
    public mutating func evaluate(
        _ snapshot: HardwareSnapshot,
        settings: Settings,
        now: Date = .now,
        userIsPicking: Bool = false
    ) -> SwitchDecision {
        var decision = SwitchDecision()
        defer { previous = snapshot }

        // Devices that became usable since last time.
        var added: [Direction: Set<String>] = [:]
        for direction in Direction.allCases {
            let usable = snapshot.usableUIDs(direction)
            added[direction] = usable.subtracting(previous?.usableUIDs(direction) ?? usable)
            for uid in added[direction, default: []] { arrivals[uid] = now }
        }
        arrivals = arrivals.filter { now.timeIntervalSince($0.value) < Self.arrivalWindow }

        // The output mode follows headphones coming and going.
        var mode = settings.mode
        if settings.isAutomatic {
            let headphones = candidates(for: .headphones, in: snapshot, settings: settings)
            if mode == .speaker {
                // Headphones just connected, or were already in use when the app started.
                let inUse = previous == nil && snapshot.defaultOutput.map(headphones.contains) == true
                if inUse || headphones.contains(where: added[.output, default: []].contains) {
                    mode = .headphone
                }
            } else if headphones.isEmpty, !candidates(for: .speakers, in: snapshot, settings: settings).isEmpty {
                mode = .speaker
            }
            if mode != settings.mode {
                decision.mode = mode
                kept[.output] = nil
                if settings.micFollowsOutput { kept[.input] = nil }
            }
        }

        // Changes to the defaults that the engine didn't ask for.
        var changedByOthers: Set<Direction> = []
        for direction in Direction.allCases {
            let current = snapshot.defaultUID(direction)
            let ours = requested[direction]
            if let ours, ours.uid == current || now.timeIntervalSince(ours.at) > Self.echoTimeout {
                requested[direction] = nil
            }

            // A kept choice lasts until its device goes away (not merely while it is still
            // starting up, as AirPlay speakers do) or a new device the user ranks arrives.
            if let keptUID = kept[direction] {
                let ranked = candidates(for: settings.list(for: direction, in: mode), in: snapshot, settings: settings)
                let newCandidate = added[direction, default: []].contains { $0 != keptUID && ranked.contains($0) }
                if snapshot.device(uid: keptUID) == nil || newCandidate { kept[direction] = nil }
            }

            guard settings.isAutomatic, let previous, let current,
                  current != previous.defaultUID(direction), current != ours?.uid
            else { continue }
            let device = snapshot.device(uid: current)

            // The user's own choice: made in Control Center or System Settings, or a move to
            // AirPlay, which macOS never does by itself. Such devices often appear only as they
            // are picked, so this comes before treating a new device as an arrival.
            if userIsPicking || device?.transport.isPickedOnly == true {
                kept[direction] = current
                if direction == .output, let device, settings.category(of: device) != mode {
                    mode = settings.category(of: device)
                    decision.mode = mode
                }
                continue
            }

            // macOS moving to a device as it connects; priorities decide below.
            guard arrivals[current] == nil else { continue }

            if let last = lastRevert[direction], now.timeIntervalSince(last) < Self.takeoverWindow {
                kept[direction] = current
                decision.yielded[direction] = current
            } else {
                changedByOthers.insert(direction)
            }
        }

        guard settings.isAutomatic else { return decision }

        // Move to the best candidate where nothing is being kept.
        for direction in Direction.allCases where kept[direction] == nil {
            let list = settings.list(for: direction, in: mode)
            guard let wanted = candidates(for: list, in: snapshot, settings: settings).first,
                  wanted != snapshot.defaultUID(direction),
                  requested[direction]?.uid != wanted
            else { continue }

            if let arrived = arrivals[wanted], now.timeIntervalSince(arrived) < Self.settleTime {
                let settled = arrived.addingTimeInterval(Self.settleTime)
                decision.recheckAt = min(decision.recheckAt ?? settled, settled)
                continue
            }
            decision.defaults[direction] = wanted
            requested[direction] = Request(uid: wanted, at: now)
            if changedByOthers.contains(direction) { lastRevert[direction] = now }
        }
        return decision
    }

    /// Usable devices in `list` that may be chosen automatically, best first.
    func candidates(for list: PriorityList, in snapshot: HardwareSnapshot, settings: Settings) -> [String] {
        let uids = snapshot.devices
            .filter { $0.isUsable(as: list.direction) }
            .filter { list.category == nil || settings.category(of: $0) == list.category }
            .map(\.uid)
            .filter { !settings.neverAuto.contains($0) && !settings.isHidden($0, in: list.hiddenRole) }
        return settings.ordered(uids, by: list)
    }
}
