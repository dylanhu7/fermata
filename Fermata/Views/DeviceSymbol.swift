import FermataCore

/// The SF Symbol for a device, matching what macOS shows in its own Sound menu where it can.
/// The model identifier comes first because it survives renaming ("Living Room" is still a
/// HomePod), then the name, then the kind of connection.
enum DeviceSymbol {
    static func name(for deviceName: String, model: String?, transport: Transport?, direction: Direction, category: OutputCategory?) -> String {
        if let model, let symbol = symbol(forModel: model) {
            return symbol
        }
        let name = deviceName.lowercased()
        if let match = byName.first(where: { name.contains($0.0) }) {
            return match.1
        }
        switch transport {
        case .hdmi, .displayPort: return "display"
        case .airPlay: return "airplay.audio"
        case .virtual, .aggregate: return "waveform"
        case .continuity: return "iphone"
        default: break
        }
        if direction == .input {
            return category == .headphone ? "headphones" : "mic.fill"
        }
        return category == .headphone ? "headphones" : "hifispeaker.fill"
    }

    private static func symbol(forModel model: String) -> String? {
        // AirPlay receivers report their Apple model identifier.
        let airPlay: [(String, String)] = [
            ("AudioAccessory5", "homepod.mini.fill"),
            ("AudioAccessory6", "homepod.2.fill"),
            ("AudioAccessory", "homepod.fill"),
            ("AppleTV", "appletv.fill"),
        ]
        if let match = airPlay.first(where: { model.hasPrefix($0.0) }) {
            return match.1
        }
        // Bluetooth devices report "<product ID> <vendor ID>" in hex; 4c is Apple.
        let parts = model.lowercased().split(separator: " ")
        guard parts.count == 2, parts[1] == "4c", let product = Int(parts[0], radix: 16) else { return nil }
        return appleBluetooth[product]
    }

    /// Apple and Beats Bluetooth product IDs.
    private static let appleBluetooth: [Int: String] = [
        0x2002: "airpods", 0x200F: "airpods", 0x2013: "airpods.gen3",
        0x2019: "airpods.gen4", 0x201B: "airpods.gen4",
        0x200E: "airpods.pro", 0x2014: "airpods.pro", 0x2024: "airpods.pro",
        0x200A: "airpods.max", 0x201F: "airpods.max",
        0x200B: "beats.powerbeats.pro", 0x2011: "beats.studiobuds",
    ]

    private static let byName: [(String, String)] = [
        ("airpods max", "airpods.max"),
        ("airpods pro", "airpods.pro"),
        ("airpods", "airpods"),
        ("powerbeats", "beats.powerbeats.pro"),
        ("studio buds", "beats.studiobuds"),
        ("beats", "beats.headphones"),
        ("homepod mini", "homepod.mini.fill"),
        ("homepod", "homepod.fill"),
        ("apple tv", "appletv.fill"),
        ("iphone", "iphone"),
        ("ipad", "ipad"),
        ("macbook", "laptopcomputer"),
        ("imac", "desktopcomputer"),
        ("studio display", "display"),
        ("pro display", "display"),
    ]
}
