import Foundation

/// Commands accepted on the `fermata://` URL scheme, for example from Raycast,
/// Stream Deck or a shell: `open fermata://toggle-mic-mute`.
public enum URLCommand: String, Sendable, CaseIterable {
    case toggleMicMute = "toggle-mic-mute"
    case muteMic = "mute-mic"
    case unmuteMic = "unmute-mic"
    case toggleAutomatic = "toggle-automatic"
    case enableAutomatic = "enable-automatic"
    case disableAutomatic = "disable-automatic"
    case speakers
    case headphones

    public static let scheme = "fermata"

    /// Accepts only the bare form: no path, query, fragment, port or credentials.
    public init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == Self.scheme,
              parts.path.isEmpty || parts.path == "/",
              parts.query == nil, parts.fragment == nil, parts.port == nil,
              parts.user == nil, parts.password == nil,
              let host = parts.host?.lowercased()
        else { return nil }
        self.init(rawValue: host)
    }
}
