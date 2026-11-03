import Foundation

public struct CandidateSeed: Equatable, Sendable {
    public let text: String
    public let traditional: String
    public let pinyin: String
    public let pinyinKey: String
    public let frequency: UInt32
    public let glosses: [Gloss]
    public let matchScore: Double
    public let entryID: UInt32?
    public let kind: CandidateKind

    public init(
        text: String,
        traditional: String,
        pinyin: String,
        pinyinKey: String,
        frequency: UInt32,
        glosses: [Gloss],
        matchScore: Double,
        entryID: UInt32?,
        kind: CandidateKind
    ) {
        self.text = text
        self.traditional = traditional
        self.pinyin = pinyin
        self.pinyinKey = pinyinKey
        self.frequency = frequency
        self.glosses = glosses
        self.matchScore = matchScore
        self.entryID = entryID
        self.kind = kind
    }
}

public struct PinyinCandidateGenerator {
    public let dictionary: ZhEnDictionary
    public let inventory: PinyinInventory
    public let segmenter: PinyinSegmenter

    public init(dictionary: ZhEnDictionary, inventory: PinyinInventory) {
        self.dictionary = dictionary
        self.inventory = inventory
        self.segmenter = PinyinSegmenter(inventory: inventory)
    }

    public func candidates(
        for rawInput: String,
        fuzzy: FuzzyPinyinOptions,
        limit: Int = 64
    ) throws -> (seeds: [CandidateSeed], segmentations: [PinyinSegmentation]) {
        let input = PinyinText.normalizeInput(rawInput)
        guard !input.isEmpty else { return ([], []) }
        let segmentations = segmenter.segment(input, fuzzy: fuzzy, limit: 10)
        var seedsByKey: [String: CandidateSeed] = [:]

        func add(_ seed: CandidateSeed) {
            let key = seed.entryID.map { String($0) } ?? "text:\(seed.text)"
            if let existing = seedsByKey[key] {
                if seed.matchScore > existing.matchScore {
                    seedsByKey[key] = seed
                }
            } else {
                seedsByKey[key] = seed
            }
        }

        for (rank, segmentation) in segmentations.enumerated() {
            let fullVariants = fullKeyVariants(for: segmentation, fuzzy: fuzzy, limit: 32)
            for variant in fullVariants {
                let queryKey = variant.key
                let exact = segmentation.allFullSyllables && queryKey == segmentation.fullKey
                let entries = try dictionary.prefixEntries(key: queryKey, index: .full, limit: 72)
                for entry in entries {
                    let isExact = entry.pinyinKey == queryKey
                    let baseMatch = isExact ? 1.0 : (exact ? 0.86 : 0.80)
                    let score = max(0, baseMatch - variant.penalty * 0.6)
                    add(
                        CandidateSeed(
                            text: entry.simplified,
                            traditional: entry.traditional,
                            pinyin: entry.pinyin,
                            pinyinKey: entry.pinyinKey,
                            frequency: entry.frequency,
                            glosses: entry.glosses,
                            matchScore: score,
                            entryID: entry.id,
                            kind: .chinese
                        )
                    )
                }
            }

            if let prefixKey = segmentation.fullPrefixKey, segmentation.hasPartialToken {
                let entries = try dictionary.prefixEntries(key: prefixKey, index: .full, limit: 72)
                for entry in entries {
                    add(
                        CandidateSeed(
                            text: entry.simplified,
                            traditional: entry.traditional,
                            pinyin: entry.pinyin,
                            pinyinKey: entry.pinyinKey,
                            frequency: entry.frequency,
                            glosses: entry.glosses,
                            matchScore: entry.pinyinKey == prefixKey ? 0.82 : 0.74,
                            entryID: entry.id,
                            kind: .chinese
                        )
                    )
                }
            }

            let abbreviation = segmentation.abbreviationKey
            if !abbreviation.isEmpty {
                let entries = try dictionary.prefixEntries(key: abbreviation, index: .abbreviation, limit: 64)
                for entry in entries {
                    let exact = entry.abbreviation == abbreviation
                    add(
                        CandidateSeed(
                            text: entry.simplified,
                            traditional: entry.traditional,
                            pinyin: entry.pinyin,
                            pinyinKey: entry.pinyinKey,
                            frequency: entry.frequency,
                            glosses: entry.glosses,
                            matchScore: exact ? 0.72 : 0.58,
                            entryID: entry.id,
                            kind: .chinese
                        )
                    )
                }
            }

            if rank < 4,
               segmentation.tokens.count >= 2,
               let composed = try composedCandidate(
                   for: segmentation,
                   fuzzy: fuzzy,
                   matchScore: max(0.50, 0.74 - Double(rank) * 0.05)
               ) {
                add(composed)
            }
        }

        var seeds = Array(seedsByKey.values)
        seeds.sort {
            if abs($0.matchScore - $1.matchScore) > 0.0001 { return $0.matchScore > $1.matchScore }
            if $0.frequency != $1.frequency { return $0.frequency > $1.frequency }
            return $0.text < $1.text
        }
        if seeds.count > limit {
            seeds = Array(seeds.prefix(limit))
        }
        return (seeds, segmentations)
    }

    private struct VariantKey {
        let syllables: [String]
        let key: String
        let penalty: Double
    }

    private func fullKeyVariants(
        for segmentation: PinyinSegmentation,
        fuzzy: FuzzyPinyinOptions,
        limit: Int
    ) -> [VariantKey] {
        guard segmentation.allFullSyllables else { return [] }
        var variants: [VariantKey] = [VariantKey(syllables: [], key: "", penalty: 0)]
        for token in segmentation.tokens {
            let options = FuzzyPinyin.variants(for: token.surface, options: fuzzy, inventory: inventory)
            var next: [VariantKey] = []
            for existing in variants {
                for option in options {
                    next.append(
                        VariantKey(
                            syllables: existing.syllables + [option.syllable],
                            key: "",
                            penalty: existing.penalty + option.penalty
                        )
                    )
                    if next.count >= limit * 4 { break }
                }
                if next.count >= limit * 4 { break }
            }
            variants = next
        }
        var seen = Set<String>()
        var result: [VariantKey] = []
        for variant in variants.sorted(by: { $0.penalty < $1.penalty }) {
            let key = variant.syllables.joined(separator: " ")
            if seen.insert(key).inserted {
                result.append(VariantKey(syllables: variant.syllables, key: key, penalty: variant.penalty))
            }
            if result.count >= limit { break }
        }
        return result
    }

    private func composedCandidate(
        for segmentation: PinyinSegmentation,
        fuzzy: FuzzyPinyinOptions,
        matchScore: Double
    ) throws -> CandidateSeed? {
        let tokens = segmentation.tokens
        guard tokens.count >= 2 else { return nil }
        let count = tokens.count
        var bestScore = [Double](repeating: -Double.greatestFiniteMagnitude, count: count + 1)
        var previousIndex = [Int](repeating: -1, count: count + 1)
        var chosenEntry = [LexiconEntry?](repeating: nil, count: count + 1)
        bestScore[0] = 0

        for start in 0..<count where bestScore[start] > -Double.greatestFiniteMagnitude / 2 {
            let maxSpan = min(4, count - start)
            for span in 1...maxSpan {
                let syllables = tokens[start..<(start + span)].map(\.surface)
                guard let entry = try bestEntry(forSyllables: syllables, fuzzy: fuzzy) else { continue }
                // Word-level segmentation must prefer a real multi-syllable word
                // over the sum of its individual characters, whose corpus
                // frequencies are naturally larger. A single-character path is
                // also penalized so that "bei jing" resolves to 北京 rather than
                // 被 + 经 when no phrase-level entry exists.
                let singleCharacterPenalty = span == 1 ? 10.0 : 0.0
                let score = bestScore[start]
                    + log1p(Double(entry.frequency))
                    + Double(span - 1) * 8.0
                    - singleCharacterPenalty
                if score > bestScore[start + span] {
                    bestScore[start + span] = score
                    previousIndex[start + span] = start
                    chosenEntry[start + span] = entry
                }
            }
        }

        guard bestScore[count] > -Double.greatestFiniteMagnitude / 2 else {
            return nil
        }
        var parts: [LexiconEntry] = []
        var cursor = count
        while cursor > 0 {
            let previous = previousIndex[cursor]
            guard previous >= 0, let entry = chosenEntry[cursor] else { return nil }
            parts.append(entry)
            cursor = previous
        }
        parts.reverse()
        guard parts.count > 1 else { return nil }
        let text = parts.map(\.simplified).joined()
        let traditional = parts.map(\.traditional).joined()
        let pinyin = parts.map(\.pinyin).joined(separator: " ")
        let frequency = parts.reduce(UInt32(0)) { $0 &+ $1.frequency } / UInt32(max(1, parts.count))
        return CandidateSeed(
            text: text,
            traditional: traditional,
            pinyin: pinyin,
            pinyinKey: segmentation.tokens.map(\.surface).joined(separator: " "),
            frequency: frequency,
            glosses: [],
            matchScore: matchScore,
            entryID: nil,
            kind: .composed
        )
    }

    private func bestEntry(forSyllables syllables: [String], fuzzy: FuzzyPinyinOptions) throws -> LexiconEntry? {
        var variants: [[FuzzyVariant]] = []
        for syllable in syllables {
            let expanded = FuzzyPinyin.variants(for: syllable, options: fuzzy, inventory: inventory)
                .filter { inventory.isSyllable($0.syllable) }
            guard !expanded.isEmpty else { return nil }
            variants.append(expanded)
        }
        var keys: [[String]] = [[]]
        for options in variants {
            var next: [[String]] = []
            for prefix in keys {
                for option in options {
                    next.append(prefix + [option.syllable])
                    if next.count >= 24 { break }
                }
                if next.count >= 24 { break }
            }
            keys = next
        }
        var best: LexiconEntry?
        for key in keys {
            let joined = key.joined(separator: " ")
            let entries = try dictionary.entries(matching: joined, index: .full, limit: 8)
            for entry in entries where best == nil || entry.frequency > best!.frequency {
                best = entry
            }
        }
        return best
    }
}

public struct EnglishSuggestionEngine {
    public let dictionary: EnZhDictionary

    public init(dictionary: EnZhDictionary) {
        self.dictionary = dictionary
    }

    public func suggestions(for rawInput: String, limit: Int = 12) throws -> [CandidateSeed] {
        let prefix = EnglishText.normalizeKey(rawInput)
        guard !prefix.isEmpty else { return [] }
        let entries = try dictionary.prefixEntries(prefix: prefix, limit: limit)
        var seen = Set<String>()
        var result: [CandidateSeed] = []
        for entry in entries {
            guard seen.insert(entry.english).inserted else { continue }
            result.append(
                CandidateSeed(
                    text: entry.english,
                    traditional: "",
                    pinyin: "",
                    pinyinKey: "",
                    frequency: 1,
                    glosses: [Gloss(partOfSpeech: entry.partOfSpeech, definition: entry.chinese)],
                    matchScore: entry.english == prefix ? 0.95 : 0.78,
                    entryID: nil,
                    kind: .english
                )
            )
        }
        return result
    }
}
