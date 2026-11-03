import Foundation

public enum PinyinTokenKind: String, Equatable, Sendable {
    case full
    case initial
    case partialFull
}

public struct PinyinToken: Equatable, Sendable {
    public let surface: String
    public let kind: PinyinTokenKind
    public let score: Double

    public init(surface: String, kind: PinyinTokenKind, score: Double) {
        self.surface = surface
        self.kind = kind
        self.score = score
    }

    public var firstLetter: Character? { surface.first }
}

public struct PinyinSegmentation: Equatable, Sendable {
    public let tokens: [PinyinToken]
    public let score: Double
    public let input: String

    public init(tokens: [PinyinToken], score: Double, input: String) {
        self.tokens = tokens
        self.score = score
        self.input = input
    }

    public var isComplete: Bool { tokens.allSatisfy { $0.surface.count > 0 } }
    public var hasPartialToken: Bool { tokens.contains { $0.kind == .partialFull } }
    public var allFullSyllables: Bool { tokens.allSatisfy { $0.kind == .full } }

    public var fullKey: String? {
        guard allFullSyllables else { return nil }
        return tokens.map(\.surface).joined(separator: " ")
    }

    public var abbreviationKey: String {
        tokens.compactMap(\.firstLetter).map(String.init).joined()
    }

    public var fullPrefixKey: String? {
        guard let index = tokens.firstIndex(where: { $0.kind == .partialFull }) else {
            return fullKey
        }
        guard index == tokens.count - 1 else { return nil }
        let prefixTokens = tokens[..<index].map(\.surface)
        return (prefixTokens + [tokens[index].surface]).joined(separator: " ")
    }

    public var description: String {
        tokens.map { token in
            switch token.kind {
            case .full: return token.surface
            case .initial: return token.surface.uppercased()
            case .partialFull: return token.surface + "…"
            }
        }.joined(separator: " ")
    }
}

public struct PinyinSegmenter: Sendable {
    public let inventory: PinyinInventory
    public var beamWidth: Int

    private struct SegmentState {
        var tokens: [PinyinToken]
        var score: Double
        var position: Int
    }

    public init(inventory: PinyinInventory, beamWidth: Int = 128) {
        self.inventory = inventory
        self.beamWidth = beamWidth
    }

    public func segment(
        _ rawInput: String,
        fuzzy: FuzzyPinyinOptions = .common,
        limit: Int = 16
    ) -> [PinyinSegmentation] {
        let input = PinyinText.normalizeInput(rawInput)
        guard !input.isEmpty else { return [] }
        let characters = Array(input)
        let length = characters.count

        var statesByPosition: [Int: [SegmentState]] = [0: [SegmentState(tokens: [], score: 0, position: 0)]]
        var completed: [PinyinSegmentation] = []

        for position in 0..<length {
            guard let states = statesByPosition[position] else { continue }
            for state in states {
                let remaining = length - position
                let maxLength = min(inventory.maximumSyllableLength, remaining)
                if maxLength >= 1 {
                    for syllableLength in 1...maxLength {
                        let surface = String(characters[position..<(position + syllableLength)])
                        let fuzzyVariants = FuzzyPinyin.variants(for: surface, options: fuzzy, inventory: inventory)
                            .filter { inventory.isSyllable($0.syllable) }
                        guard let bestFuzzy = fuzzyVariants.min(by: { $0.penalty < $1.penalty }) else {
                            continue
                        }
                        let tokenScore = tokenScore(
                            surface: bestFuzzy.syllable,
                            kind: .full,
                            fuzzyPenalty: bestFuzzy.penalty
                        )
                        let next = SegmentState(
                            tokens: state.tokens + [PinyinToken(surface: surface, kind: .full, score: tokenScore)],
                            score: state.score + tokenScore,
                            position: position + syllableLength
                        )
                        statesByPosition[next.position, default: []].append(next)
                    }
                }

                let initial = String(characters[position])
                if inventory.isInitial(Character(initial)) {
                    let tokenScore = tokenScore(surface: initial, kind: .initial, fuzzyPenalty: 0)
                    let next = SegmentState(
                        tokens: state.tokens + [PinyinToken(surface: initial, kind: .initial, score: tokenScore)],
                        score: state.score + tokenScore,
                        position: position + 1
                    )
                    statesByPosition[next.position, default: []].append(next)
                }

                let remainder = String(characters[position...])
                if remainder.count > 1,
                   inventory.isPrefixOfSyllable(remainder),
                   position + remainder.count == length {
                    let tokenScore = tokenScore(surface: remainder, kind: .partialFull, fuzzyPenalty: 0)
                    let next = SegmentState(
                        tokens: state.tokens + [PinyinToken(surface: remainder, kind: .partialFull, score: tokenScore)],
                        score: state.score + tokenScore,
                        position: length
                    )
                    statesByPosition[length, default: []].append(next)
                }
            }

            let futureKeys = statesByPosition.keys.filter { $0 > position }
            for key in futureKeys {
                if let values = statesByPosition[key], values.count > beamWidth {
                    statesByPosition[key] = Array(values.sorted { $0.score > $1.score }.prefix(beamWidth))
                }
            }
            statesByPosition[position] = nil
        }

        if let finalStates = statesByPosition[length] {
            for state in finalStates {
                completed.append(PinyinSegmentation(
                    tokens: state.tokens,
                    score: completionScore(state: state),
                    input: input
                ))
            }
        }

        var seen = Set<String>()
        var results: [PinyinSegmentation] = []
        for segmentation in completed.sorted(by: {
            if abs($0.score - $1.score) > 0.0001 { return $0.score > $1.score }
            return $0.description < $1.description
        }) {
            let key = segmentation.tokens.map { "\($0.kind.rawValue):\($0.surface)" }.joined(separator: "|")
            if seen.insert(key).inserted {
                results.append(segmentation)
            }
            if results.count >= limit { break }
        }
        return results
    }

    private func tokenScore(surface: String, kind: PinyinTokenKind, fuzzyPenalty: Double) -> Double {
        let frequency = inventory.frequency(of: surface)
        let frequencyScore = min(1.15, log1p(Double(frequency)) * 0.08)
        switch kind {
        case .full:
            return frequencyScore - 1.15 - fuzzyPenalty
        case .initial:
            return frequencyScore - 2.40
        case .partialFull:
            return frequencyScore - 1.00
        }
    }

    private func completionScore(state: SegmentState) -> Double {
        // Prefer the fewest syllables that cover the input. A path of four valid
        // syllables must beat a path that shreds the same input into initials and
        // standalone vowels, while still allowing genuine initial abbreviations.
        state.score + 0.20 - 0.30 * Double(state.tokens.count)
    }
}
