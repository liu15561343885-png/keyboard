import Foundation

public struct KeyboardSettings: Codable, Equatable, Sendable {
    public var soundEnabled: Bool
    public var hapticsEnabled: Bool
    public var fuzzy: FuzzyPinyinOptions
    public var lastLanguage: InputLanguage
    public var script: ScriptPreference
    public var nineKeyEnabled: Bool
    public var schemaVersion: Int

    public init(
        soundEnabled: Bool = true,
        hapticsEnabled: Bool = true,
        fuzzy: FuzzyPinyinOptions = .common,
        lastLanguage: InputLanguage = .chinese,
        script: ScriptPreference = .simplified,
        nineKeyEnabled: Bool = false,
        schemaVersion: Int = 3
    ) {
        self.soundEnabled = soundEnabled
        self.hapticsEnabled = hapticsEnabled
        self.fuzzy = fuzzy
        self.lastLanguage = lastLanguage
        self.script = script
        self.nineKeyEnabled = nineKeyEnabled
        self.schemaVersion = schemaVersion
    }

    private enum CodingKeys: String, CodingKey {
        case soundEnabled, hapticsEnabled, fuzzy, lastLanguage, script, nineKeyEnabled, schemaVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        self.hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        self.fuzzy = try container.decodeIfPresent(FuzzyPinyinOptions.self, forKey: .fuzzy) ?? .common
        self.lastLanguage = try container.decodeIfPresent(InputLanguage.self, forKey: .lastLanguage) ?? .chinese
        self.script = try container.decodeIfPresent(ScriptPreference.self, forKey: .script) ?? .simplified
        self.nineKeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .nineKeyEnabled) ?? false
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 3
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(soundEnabled, forKey: .soundEnabled)
        try container.encode(hapticsEnabled, forKey: .hapticsEnabled)
        try container.encode(fuzzy, forKey: .fuzzy)
        try container.encode(lastLanguage, forKey: .lastLanguage)
        try container.encode(script, forKey: .script)
        try container.encode(nineKeyEnabled, forKey: .nineKeyEnabled)
        try container.encode(schemaVersion, forKey: .schemaVersion)
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
