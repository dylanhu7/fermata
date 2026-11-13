import AppIntents
import FermataCore

// Shortcuts actions and a Focus filter. The model is shared through AppDependencyManager,
// registered by the app delegate.

enum OutputModeOption: String, AppEnum {
    case speakers
    case headphones

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Output Mode"
    static let caseDisplayRepresentations: [OutputModeOption: DisplayRepresentation] = [
        .speakers: DisplayRepresentation(title: "Speakers", image: .init(systemName: "speaker.wave.2.fill")),
        .headphones: DisplayRepresentation(title: "Headphones", image: .init(systemName: "headphones")),
    ]

    var category: OutputCategory { self == .speakers ? .speaker : .headphone }
}

enum MuteAction: String, AppEnum {
    case toggle
    case mute
    case unmute

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Microphone Action"
    static let caseDisplayRepresentations: [MuteAction: DisplayRepresentation] = [
        .toggle: "Toggle", .mute: "Mute", .unmute: "Unmute",
    ]
}

struct AudioDeviceEntity: AppEntity {
    let uid: String
    let name: String
    let isInput: Bool
    /// A device can be both an output and a microphone, so each role is its own entity.
    var id: String { "\(isInput ? "input" : "output"):\(uid)" }

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Audio Device"
    static let defaultQuery = AudioDeviceQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: isInput ? "Microphone" : "Output")
    }
}

struct AudioDeviceQuery: EntityQuery {
    @Dependency private var model: AppModel

    func entities(for identifiers: [String]) async throws -> [AudioDeviceEntity] {
        await allDevices().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AudioDeviceEntity] {
        await allDevices()
    }

    @MainActor private func allDevices() -> [AudioDeviceEntity] {
        model.snapshot.devices.flatMap { device in
            Direction.allCases
                .filter(device.isUsable)
                .map { AudioDeviceEntity(uid: device.uid, name: device.name, isInput: $0 == .input) }
        }
    }
}

struct SelectAudioDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Use Audio Device"
    static let description = IntentDescription("Makes a device the default output or microphone.")

    @Parameter(title: "Device") var device: AudioDeviceEntity
    @Dependency private var model: AppModel

    @MainActor func perform() async throws -> some IntentResult {
        if device.isInput {
            model.select(device.uid, in: model.activeMicrophoneList)
        } else {
            let category = model.snapshot.device(uid: device.uid).map(model.settings.category) ?? .speaker
            model.select(device.uid, in: PriorityList(category))
        }
        return .result()
    }
}

struct SetOutputModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Output Mode"
    static let description = IntentDescription("Switches between the speaker and headphone lists.")

    @Parameter(title: "Mode") var mode: OutputModeOption
    @Dependency private var model: AppModel

    @MainActor func perform() async throws -> some IntentResult {
        model.setMode(mode.category)
        return .result()
    }
}

struct SetAutomaticSwitchingIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Automatic Switching"
    static let description = IntentDescription("Turns automatic device switching on or off.")

    @Parameter(title: "Automatic") var isAutomatic: Bool
    @Dependency private var model: AppModel

    @MainActor func perform() async throws -> some IntentResult {
        model.setAutomatic(isAutomatic)
        return .result()
    }
}

struct MicrophoneMuteIntent: AppIntent {
    static let title: LocalizedStringResource = "Mute Microphone"
    static let description = IntentDescription("Mutes, unmutes or toggles the current microphone.")

    @Parameter(title: "Action", default: .toggle) var action: MuteAction
    @Dependency private var model: AppModel

    @MainActor func perform() async throws -> some IntentResult {
        switch action {
        case .toggle: model.toggleMicrophoneMute()
        case .mute: model.setMicrophoneMuted(true)
        case .unmute: model.setMicrophoneMuted(false)
        }
        return .result()
    }
}

/// Applies an output mode and switching behaviour while a Focus is on, for example
/// headphones and a muted microphone during "Deep Work".
struct AudioFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Fermata"
    static let description: IntentDescription? = "Choose the output mode and microphone for this Focus."

    @Parameter(title: "Output Mode") var mode: OutputModeOption?
    @Parameter(title: "Automatic Switching") var isAutomatic: Bool?
    @Parameter(title: "Mute Microphone") var muteMicrophone: Bool?
    @Dependency private var model: AppModel

    var displayRepresentation: DisplayRepresentation {
        let parts = [
            mode?.category.title,
            isAutomatic.map { $0 ? "Automatic" : "Manual" },
            muteMicrophone == true ? "Mic muted" : nil,
        ].compactMap(\.self)
        return DisplayRepresentation(title: parts.isEmpty ? "No changes" : "\(parts.joined(separator: ", "))")
    }

    @MainActor func perform() async throws -> some IntentResult {
        if let isAutomatic { model.setAutomatic(isAutomatic) }
        if let mode { model.setMode(mode.category) }
        if let muteMicrophone { model.setMicrophoneMuted(muteMicrophone) }
        return .result()
    }
}

struct FermataShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MicrophoneMuteIntent(),
            phrases: ["Toggle microphone with \(.applicationName)", "Mute my mic with \(.applicationName)"],
            shortTitle: "Mute Microphone",
            systemImageName: "mic.slash"
        )
        AppShortcut(
            intent: SetOutputModeIntent(),
            phrases: ["Switch to \(\.$mode) with \(.applicationName)"],
            shortTitle: "Output Mode",
            systemImageName: "headphones"
        )
    }
}
