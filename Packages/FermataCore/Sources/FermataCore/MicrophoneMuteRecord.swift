import Foundation

/// Kept while the app holds the microphone muted, so that it can be put back even after
/// a crash.
public struct MicrophoneMuteRecord: Codable, Sendable, Equatable {
    public enum Method: Codable, Sendable, Equatable {
        case muteProperty
        case volume(previous: Float)
    }

    public var uid: String
    public var method: Method

    public init(uid: String, method: Method) {
        self.uid = uid
        self.method = method
    }

    public static let key = "microphoneMuteRecord"

    public static func load(from defaults: UserDefaults = .standard) -> MicrophoneMuteRecord? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    public static func save(_ record: MicrophoneMuteRecord?, to defaults: UserDefaults = .standard) {
        if let record, let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
