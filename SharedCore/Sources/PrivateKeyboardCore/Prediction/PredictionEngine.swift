import Foundation

public final class PredictionEngine {
    public let dictionary: ZhEnDictionary
    public let englishDictionary: EnZhDictionary
    public let inventory: PinyinInventory
    public let languageModel: ContextLanguageModel
    public let userHistory: UserHistoryStore
    public let scorer: HybridPredictionScorer
    public let paths: DatasetPaths
    public let fuzzyOptions: FuzzyPinyinOptions
    public let userLexicon: UserLexiconStore?

    private let generator: PinyinCandidateGenerator
    private let englishGenerator: EnglishSuggestionEngine
    private let maximumBaseLog: Double

    public init(
        paths: DatasetPaths,
        userHistory: UserHistoryStore,
        userLexicon: UserLexiconStore? = nil,
        fuzzyOptions: FuzzyPinyinOptions = .common,
        weighted: WeightedPredictionScorer = WeightedPredictionScorer()
    ) throws {
        self.paths = paths
        self.dictionary = try ZhEnDictionary(url: paths.zhEn)
        self.englishDictionary = try EnZhDictionary(url: paths.enZh)
        self.inventory = try PinyinInventory(url: paths.pinyin)
        let bigram = try BigramLanguageModel(url: paths.bigram)
        let trigram = try TrigramLanguageModel(url: paths.trigram)
        self.languageModel = ContextLanguageModel(bigram: bigram, trigram: trigram)
        self.userHistory = userHistory
        self.userLexicon = userLexicon
        self.fuzzyOptions = fuzzyOptions
        self.generator = PinyinCandidateGenerator(dictionary: dictionary, inventory: inventory)
        self.englishGenerator = EnglishSuggestionEngine(dictionary: englishDictionary)
        self.maximumBaseLog = max(1.0, log1p(Double(dictionary.maxFrequency)))
        let coreML: CoreMLCandidateScorer?
        if let modelURL = paths.model {
            coreML = try? CoreMLCandidateScorer(url: modelURL)
        } else {
            coreML = nil
        }
        self.scorer = HybridPredictionScorer(weighted: weighted, model: coreML)
    }

    public var modelStatusDescription: String { scorer.modelStatusDescription }

    public func predict(
        input: String,
        language: InputLanguage,
        contextWords: [String],
        fuzzy: FuzzyPinyinOptions? = nil,
        scriptPreference: ScriptPreference = .simplified,
        limit: Int = 40
    ) throws -> [InputCandidate] {
        let normalized = PinyinText.normalizeInput(input)
        guard !normalized.isEmpty, limit > 0 else { return [] }

        var scored: [(candidate: InputCandidate, total: Double)] = []
        var seenText = Set<String>()
        let context = PredictionContext(previousWords: contextWords, typedPinyin: normalized, language: language)

        func append(seed: CandidateSeed) {
            let displayText: String
            if seed.kind == .chinese || seed.kind == .composed {
                displayText = scriptPreference == .traditional && !seed.traditional.isEmpty
                    ? seed.traditional
                    : seed.text
            } else {
                displayText = seed.text
            }
            let features = features(for: seed, displayText: displayText, contextWords: contextWords)
            let breakdown = scorer.score(features: features, context: context)
            let detail = detailText(for: seed, contextWords: contextWords)
            let candidate = InputCandidate(
                id: seed.entryID.map { "zh-\($0)" } ?? "\(seed.kind.rawValue)-\(displayText)",
                text: displayText,
                detail: detail,
                kind: seed.kind,
                pinyin: seed.pinyin,
                matchScore: seed.matchScore,
                entryID: seed.entryID,
                baseFrequency: seed.frequency,
                glosses: seed.glosses,
                breakdown: breakdown
            )
            scored.append((candidate, breakdown.total))
        }

        if language == .chinese {
            let generated = try generator.candidates(for: normalized, fuzzy: fuzzy ?? fuzzyOptions, limit: 80)
            for seed in generated.seeds {
                append(seed: seed)
            }
            if let userLexicon {
                let compactInput = normalized.replacingOccurrences(of: " ", with: "")
                for entry in userLexicon.allEntries {
                    let compactKey = entry.pinyin.replacingOccurrences(of: " ", with: "")
                    let abbreviation = PinyinText.abbreviation(ofKey: entry.pinyin)
                    let matchScore: Double?
                    if compactKey == compactInput {
                        matchScore = 1.0
                    } else if abbreviation == compactInput {
                        matchScore = 0.9
                    } else if compactInput.count >= 2 && compactKey.hasPrefix(compactInput) {
                        matchScore = 0.65
                    } else {
                        matchScore = nil
                    }
                    guard let matchScore else { continue }
                    append(
                        seed: CandidateSeed(
                            text: entry.word,
                            traditional: entry.word,
                            pinyin: entry.pinyin,
                            pinyinKey: compactKey,
                            frequency: 50_000,
                            glosses: entry.note.isEmpty ? [] : [Gloss(definition: entry.note)],
                            matchScore: matchScore,
                            entryID: nil,
                            kind: .custom
                        )
                    )
                }
            }
            if normalized.count >= 2 {
                let english = try englishGenerator.suggestions(for: normalized, limit: 8)
                for seed in english {
                    append(seed: seed)
                }
            }
        } else {
            let english = try englishGenerator.suggestions(for: normalized, limit: 24)
            for seed in english {
                append(seed: seed)
            }
        }

        scored.sort {
            if abs($0.total - $1.total) > 0.0001 { return $0.total > $1.total }
            if $0.candidate.baseFrequency != $1.candidate.baseFrequency {
                return $0.candidate.baseFrequency > $1.candidate.baseFrequency
            }
            return $0.candidate.text < $1.candidate.text
        }

        var results: [InputCandidate] = []
        results.reserveCapacity(min(limit, scored.count))
        for item in scored {
            guard seenText.insert(item.candidate.text).inserted else { continue }
            results.append(item.candidate)
            if results.count >= limit { break }
        }

        if results.isEmpty, language == .chinese {
            let raw = InputCandidate(
                id: "raw-\(normalized)",
                text: normalized,
                detail: "无匹配 · 空格上屏",
                kind: .raw,
                pinyin: normalized,
                matchScore: 0,
                entryID: nil,
                baseFrequency: 1,
                glosses: []
            )
            results.append(raw)
        }
        return results
    }

    private func features(
        for seed: CandidateSeed,
        displayText: String,
        contextWords: [String]
    ) -> CandidateFeatures {
        let base = min(1, log1p(Double(seed.frequency)) / maximumBaseLog)
        let user = userHistory.normalizedFrequency(for: displayText)
        let recency = userHistory.recencyScore(for: displayText)
        // The bundled n-gram model is keyed by simplified text; use the
        // dictionary form for context scoring even when displaying traditional.
        let lm = languageModel.scores(previousWords: contextWords, candidate: seed.text)
        let pinyinMatch: Double
        switch seed.kind {
        case .chinese:
            pinyinMatch = seed.matchScore
        case .composed:
            pinyinMatch = seed.matchScore * 0.85
        case .english:
            pinyinMatch = seed.matchScore * 0.55
        case .custom:
            pinyinMatch = seed.matchScore
        case .raw:
            pinyinMatch = 0
        }
        return CandidateFeatures(
            baseFrequency: base,
            userFrequency: user,
            recency: recency,
            bigram: lm.bigram,
            trigram: lm.trigram,
            pinyinMatch: pinyinMatch,
            translationAvailability: seed.glosses.isEmpty ? 0 : 1,
            candidateLength: min(1, Double(seed.text.count) / 12.0),
            contextLength: min(1, Double(contextWords.count) / 3.0)
        )
    }

    private func detailText(for seed: CandidateSeed, contextWords: [String]) -> String {
        if seed.kind == .english, !seed.glosses.isEmpty {
            return seed.glosses.prefix(2).map(\.display).joined(separator: " · ")
        }
        if let gloss = seed.glosses.first {
            return gloss.display
        }
        if seed.kind == .composed {
            return "本地组合 · 连续拼音"
        }
        if seed.kind == .custom {
            return "自定义词"
        }
        if let previous = contextWords.last {
            return "本地联想 · \(previous)"
        }
        return "常用词"
    }
}
