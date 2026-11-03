import Foundation

public struct FuzzyPinyinOptions: Codable, Equatable, Sendable {
    public var zhZ: Bool
    public var chC: Bool
    public var shS: Bool
    public var nL: Bool
    public var fH: Bool
    public var angAn: Bool
    public var engEn: Bool
    public var ingIn: Bool

    public init(
        zhZ: Bool = false,
        chC: Bool = false,
        shS: Bool = false,
        nL: Bool = false,
        fH: Bool = false,
        angAn: Bool = false,
        engEn: Bool = false,
        ingIn: Bool = false
    ) {
        self.zhZ = zhZ
        self.chC = chC
        self.shS = shS
        self.nL = nL
        self.fH = fH
        self.angAn = angAn
        self.engEn = engEn
        self.ingIn = ingIn
    }

    public static let none = FuzzyPinyinOptions()
    public static let common = FuzzyPinyinOptions(zhZ: true, chC: true, shS: true)

    public var enabledCount: Int {
        [zhZ, chC, shS, nL, fH, angAn, engEn, ingIn].filter { $0 }.count
    }
}

public struct FuzzyVariant: Equatable, Sendable {
    public let syllable: String
    public let penalty: Double

    public init(syllable: String, penalty: Double) {
        self.syllable = syllable
        self.penalty = penalty
    }
}

public enum FuzzyPinyin {
    private struct Rule {
        let enabled: Bool
        let from: String
        let to: String
        let prefix: Bool
    }

    /// Expands a typed syllable to valid dictionary spellings.
    ///
    /// The mapping is symmetric: typing `zong` can reach `zhong`, and typing
    /// `zhong` can reach `zong`. Invalid expansions are filtered by the
    /// inventory, so `hao` never turns into the non-syllable `fao`.
    public static func variants(
        for syllable: String,
        options: FuzzyPinyinOptions,
        inventory: PinyinInventory
    ) -> [FuzzyVariant] {
        let base = PinyinText.normalizeSyllable(syllable)
        guard !base.isEmpty else { return [] }
        let rules: [Rule] = [
            Rule(enabled: options.zhZ, from: "zh", to: "z", prefix: true),
            Rule(enabled: options.zhZ, from: "z", to: "zh", prefix: true),
            Rule(enabled: options.chC, from: "ch", to: "c", prefix: true),
            Rule(enabled: options.chC, from: "c", to: "ch", prefix: true),
            Rule(enabled: options.shS, from: "sh", to: "s", prefix: true),
            Rule(enabled: options.shS, from: "s", to: "sh", prefix: true),
            Rule(enabled: options.nL, from: "n", to: "l", prefix: true),
            Rule(enabled: options.nL, from: "l", to: "n", prefix: true),
            Rule(enabled: options.fH, from: "f", to: "h", prefix: true),
            Rule(enabled: options.fH, from: "h", to: "f", prefix: true),
            Rule(enabled: options.angAn, from: "ang", to: "an", prefix: false),
            Rule(enabled: options.angAn, from: "an", to: "ang", prefix: false),
            Rule(enabled: options.engEn, from: "eng", to: "en", prefix: false),
            Rule(enabled: options.engEn, from: "en", to: "eng", prefix: false),
            Rule(enabled: options.ingIn, from: "ing", to: "in", prefix: false),
            Rule(enabled: options.ingIn, from: "in", to: "ing", prefix: false)
        ]

        var result: [String: Double] = [base: 0]
        var frontier: [String] = [base]
        for _ in 0..<2 {
            var additions: [String: Double] = [:]
            for value in frontier {
                for rule in rules where rule.enabled {
                    let transformed: String?
                    if rule.prefix {
                        if value.hasPrefix(rule.from) {
                            transformed = rule.to + value.dropFirst(rule.from.count)
                        } else {
                            transformed = nil
                        }
                    } else {
                        if value.hasSuffix(rule.from) {
                            transformed = String(value.dropLast(rule.from.count)) + rule.to
                        } else {
                            transformed = nil
                        }
                    }
                    if let transformed, inventory.isSyllable(transformed), result[transformed] == nil {
                        additions[transformed] = (result[value] ?? 0) + 0.08
                    }
                }
            }
            if additions.isEmpty { break }
            for (key, penalty) in additions {
                result[key] = penalty
                frontier.append(key)
            }
            if result.count >= 16 { break }
        }
        return result
            .map { FuzzyVariant(syllable: $0.key, penalty: $0.value) }
            .sorted { $0.penalty == $1.penalty ? $0.syllable < $1.syllable : $0.penalty < $1.penalty }
    }
}
