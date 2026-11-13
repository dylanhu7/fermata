/// Decides whether an output device is a speaker or a pair of headphones when the user
/// hasn't said so explicitly.
public enum DeviceClassifier {
    /// Reads the output streams' terminal types. USB devices report raw USB Audio terminal
    /// codes; others report CoreAudio four-character codes. Bluetooth's `hdph` is ignored
    /// because speakers such as an Echo report it too.
    public static func category(outputTerminalTypes types: [UInt32], transport: Transport) -> OutputCategory? {
        for type in types {
            switch type {
            case 0x0302, 0x0402: // USB headphones, USB headset
                return .headphone
            case fourCC("hdph") where transport != .bluetooth && transport != .bluetoothLE:
                return .headphone
            case 0x0301, fourCC("spkr"), fourCC("lfes"), fourCC("hdmi"), fourCC("dprt"):
                return .speaker
            default:
                continue
            }
        }
        return nil
    }

    /// Best guess for a device with no user override.
    public static func category(for device: Device) -> OutputCategory {
        if let category = device.terminalCategory { return category }
        switch device.transport {
        case .builtIn, .hdmi, .displayPort, .airPlay, .virtual, .aggregate:
            return .speaker
        default:
            return nameSuggestsHeadphones(device.name) ? .headphone : .speaker
        }
    }

    public static func nameSuggestsHeadphones(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return headphoneKeywords.contains { lowered.contains($0) }
    }

    /// Product names that are almost always worn. Brands that also sell speakers
    /// (Marshall, JBL, Anker, Edifier) are only matched by their headphone lines.
    static let headphoneKeywords: [String] = [
        "headphone", "headset", "earphone", "earbud", "buds", "pods",
        "airpods", "earpods", "beats", "powerbeats",
        "wh-1000", "wf-1000", "linkbuds", "inzone",
        "quietcomfort", "qc ultra", "qc45", "qc35",
        "momentum", "pxc", "hd 4", "hd 5",
        "jabra", "evolve", "plantronics",
        "jbl tune", "jbl live", "jbl tour",
        "soundcore life", "soundcore liberty", "soundcore space",
        "skullcandy", "nothing ear", "freebuds", "enco",
        "technics eah", "b&w px", "bathys", "aonic", "audio-technica ath",
        "beyerdynamic", "hifiman", "steelseries arctis", "hyperx cloud",
        "logitech g pro", "astro a", "corsair hs", "corsair void", "razer barracuda",
        "razer kraken", "razer blackshark", "marshall major", "marshall monitor",
    ]
}
