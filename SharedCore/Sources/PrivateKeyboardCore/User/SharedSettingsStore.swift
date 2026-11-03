import Foundation

public struct KeyboardSettings: Codable, Equatable, Sendable {
    public var soundEnabled: Bool
    public var hapticsEnabled: Bool
    public var fuzzy: FuzzyPinyinOptions
    public var lastLanguage: InputLanguage
    public var schemaVersion: Int

    public init(
        soundEnabled: Bool = true,
        hapticsEnabled: Bool = true,
        fuzzy: FuzzyPinyinOptions = .common,
        lastLanguage: InputLanguage = .chinese,
        schemaVersion: Int = 1
    ) {
        self.soundEnabled = soundEnabled
        self.hapticsEnabled = hapticsEnabled
        self.fuzzy = fuzzy
        self.lastLanguage = lastLanguage
        self.schemaVersion = schemaVersion
    }
}

public final class SharedSettingsStore {
    private let defaults: UserDefaults
    private let key = "PrivateKeyboard.settings.v1"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public convenience init() {
        self.init(defaults: AppGroup.settingsDefaults())
    }

    public func load() -> KeyboardSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(KeyboardSettings.self, from: data)
        else {
            return KeyboardSettings()
        }
        return settings
    }

    public func save(_ settings: KeyboardSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }

    public func reset() {
        defaults.removeObject(forKey: key)
    }
}
