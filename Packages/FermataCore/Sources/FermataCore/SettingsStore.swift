import Foundation

/// Loads and saves `Settings` in UserDefaults.
public struct SettingsStore {
    public static let key = "settings"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> Settings {
        defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Settings.self, from: $0) } ?? Settings()
    }

    public func save(_ settings: Settings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
