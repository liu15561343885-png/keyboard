import Foundation

public struct Gloss: Codable, Equatable, Hashable, Sendable {
    public var partOfSpeech: String
    public var definition: String

    public init(partOfSpeech: String = "", definition: String) {
        self.partOfSpeech = partOfSpeech
        self.definition = definition
    }

    public var display: String {
        partOfSpeech.isEmpty ? definition : "\(partOfSpeech) \(definition)"
    }
}

public struct LexiconEntry: Equatable, Hashable, Sendable {
    public let id: UInt32
    public let simplified: String
    public let traditional: String
    public let pinyin: String
    public let pinyinKey: String
    public let abbreviation: String
    public let frequency: UInt32
    public let glosses: [Gloss]

    public init(
        id: UInt32,
        simplified: String,
        traditional: String,
        pinyin: String,
        pinyinKey: String,
        abbreviation: String,
        frequency: UInt32,
        glosses: [Gloss]
    ) {
        self.id = id
        self.simplified = simplified
        self.traditional = traditional
        self.pinyin = pinyin
        self.pinyinKey = pinyinKey
        self.abbreviation = abbreviation
        self.frequency = frequency
        self.glosses = glosses
    }

    public var primaryGloss: Gloss? { glosses.first }

    public func detailText(fallback: String? = nil) -> String {
        if let gloss = primaryGloss {
            return gloss.display
        }
        return fallback ?? "常用词"
    }
}

public struct EnglishEntry: Equatable, Hashable, Sendable {
    public let id: UInt32
    public let english: String
    public let partOfSpeech: String
    public let chinese: String
    public let definition: String
    public let frequency: UInt32

    public init(
        id: UInt32,
        english: String,
        partOfSpeech: String,
        chinese: String,
        definition: String,
        frequency: UInt32
    ) {
        self.id = id
        self.english = english
        self.partOfSpeech = partOfSpeech
        self.chinese = chinese
        self.definition = definition
        self.frequency = frequency
    }

    public var detailText: String {
        if partOfSpeech.isEmpty {
            return "\(chinese) · \(definition)"
        }
        return "\(partOfSpeech) \(chinese)"
    }
}

public enum CandidateKind: String, Codable, Sendable {
    case chinese
    case english
    case composed
    case raw
}

public struct InputCandidate: Identifiable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let detail: String
    public let kind: CandidateKind
    public let pinyin: String
    public let matchScore: Double
    public let entryID: UInt32?
    public let baseFrequency: UInt32
    public let glosses: [Gloss]
    public let breakdown: ScoreBreakdown?

    public init(
        id: String,
        text: String,
        detail: String,
        kind: CandidateKind,
        pinyin: String,
        matchScore: Double,
        entryID: UInt32?,
        baseFrequency: UInt32,
        glosses: [Gloss],
        breakdown: ScoreBreakdown? = nil
    ) {
        self.id = id
        self.text = text
        self.detail = detail
        self.kind = kind
        self.pinyin = pinyin
        self.matchScore = matchScore
        self.entryID = entryID
        self.baseFrequency = baseFrequency
        self.glosses = glosses
        self.breakdown = breakdown
    }
}

public struct ScoreBreakdown: Equatable, Sendable {
    public var baseFrequency: Double = 0
    public var userFrequency: Double = 0
    public var recency: Double = 0
    public var bigram: Double = 0
    public var trigram: Double = 0
    public var pinyinMatch: Double = 0
    public var translationAvailability: Double = 0
    public var model: Double = 0
    public var total: Double = 0

    public init() {}

    public var explanation: String {
        String(
            format: "base %.2f · user %.2f · recent %.2f · bi %.2f · tri %.2f · pinyin %.2f · dict %.2f · ml %.2f",
            baseFrequency, userFrequency, recency, bigram, trigram,
            pinyinMatch, translationAvailability, model
        )
    }
}

public struct CandidateFeatures: Equatable, Sendable {
    public var baseFrequency: Double
    public var userFrequency: Double
    public var recency: Double
    public var bigram: Double
    public var trigram: Double
    public var pinyinMatch: Double
    public var translationAvailability: Double
    public var candidateLength: Double
    public var contextLength: Double

    public init(
        baseFrequency: Double = 0,
        userFrequency: Double = 0,
        recency: Double = 0,
        bigram: Double = 0,
        trigram: Double = 0,
        pinyinMatch: Double = 0,
        translationAvailability: Double = 0,
        candidateLength: Double = 0,
        contextLength: Double = 0
    ) {
        self.baseFrequency = baseFrequency
        self.userFrequency = userFrequency
        self.recency = recency
        self.bigram = bigram
        self.trigram = trigram
        self.pinyinMatch = pinyinMatch
        self.translationAvailability = translationAvailability
        self.candidateLength = candidateLength
        self.contextLength = contextLength
    }

    /// The exact order consumed by the generated Core ML model.
    public var vector: [Double] {
        [
            baseFrequency,
            userFrequency,
            recency,
            bigram,
            trigram,
            pinyinMatch,
            translationAvailability,
            candidateLength,
            contextLength
        ]
    }

    public static let featureNames = [
        "baseFrequency",
        "userFrequency",
        "recency",
        "bigram",
        "trigram",
        "pinyinMatch",
        "translationAvailability",
        "candidateLength",
        "contextLength"
    ]
}

public struct PredictionContext: Equatable, Sendable {
    public var previousWords: [String]
    public var typedPinyin: String
    public var language: InputLanguage

    public init(previousWords: [String] = [], typedPinyin: String = "", language: InputLanguage = .chinese) {
        self.previousWords = previousWords
        self.typedPinyin = typedPinyin
        self.language = language
    }

    public var previousWord: String? { previousWords.last }
    public var previousPreviousWord: String? {
        previousWords.count >= 2 ? previousWords[previousWords.count - 2] : nil
    }
}

public enum ScriptPreference: String, Codable, CaseIterable, Sendable {
    case simplified
    case traditional

    public var displayName: String {
        switch self {
        case .simplified: return "简体"
        case .traditional: return "繁體"
        }
    }
}

public enum InputLanguage: String, Codable, CaseIterable, Sendable {
    case chinese
    case english

    public var displayName: String {
        switch self {
        case .chinese: return "中"
        case .english: return "EN"
        }
    }
}
