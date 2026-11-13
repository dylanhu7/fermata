import FermataCore

// How the core types are named and drawn in the interface.

nonisolated extension OutputCategory {
    var title: String {
        switch self {
        case .speaker: "Speakers"
        case .headphone: "Headphones"
        }
    }

    var symbol: String {
        switch self {
        case .speaker: "speaker.wave.2.fill"
        case .headphone: "headphones"
        }
    }
}

nonisolated extension PriorityList {
    /// The heading above the list.
    var title: String {
        switch self {
        case .microphones: "Microphone"
        case .microphonesWithHeadphones: "Microphone with Headphones"
        case .speakers, .headphones: hiddenRole.title
        }
    }
}

nonisolated extension HiddenRole {
    /// The kind of device in the plural: "Hide from Microphones".
    var title: String {
        switch self {
        case .microphone: "Microphones"
        case .speaker: "Speakers"
        case .headphone: "Headphones"
        }
    }

    var symbol: String {
        switch self {
        case .microphone: "mic.fill"
        case .speaker: "hifispeaker.fill"
        case .headphone: "headphones"
        }
    }
}
