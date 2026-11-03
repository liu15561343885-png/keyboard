import Foundation

/// Maps a phone keypad digit sequence to plausible pinyin keys.
/// T9 is intentionally conservative: complete syllable segmentations are
/// preferred, with a plain letter-combination fallback for very short input.
public struct T9PinyinDecoder: Sendable {
    private static let digitLetters: [Character: [Character]] = [
        "2": ["a", "b", "c"],
        "3": ["d", "e", "f"],
        "4": ["g", "h", "i"],
        "5": ["j", "k", "l"],
        "6": ["m", "n", "o"],
        "7": ["p", "q", "r", "s"],
        "8": ["t", "u", "v"],
        "9": ["w", "x", "y", "z"],
    ]

    private let syllablesByDigits: [String: [String]]
    private let syllablePrefixes: [Character: [(digits: String, syllables: [String])]]

    public init(inventory: PinyinInventory) {
        var grouped: [String: [String]] = [:]
        for syllable in inventory.frequencies.keys {
            let digits = Self.digits(for: syllable)
            guard !digits.isEmpty else { continue }
            grouped[digits, default: []].append(syllable)
        }
        self.syllablesByDigits = grouped
        var prefixes: [Character: [(String, [String])]] = [:]
        for (digits, syllables) in grouped {
            guard let first = digits.first else { continue }
            prefixes[first, default: []].append((digits, syllables))
        }
        self.syllablePrefixes = prefixes
    }

    public static func digits(for syllable: String) -> String {
        var result = ""
        for character in syllable.lowercased() {
            switch character {
            case "a", "b", "c": result.append("2")
            case "d", "e", "f": result.append("3")
            case "g", "h", "i": result.append("4")
            case "j", "k", "l": result.append("5")
            case "m", "n", "o": result.append("6")
            case "p", "q", "r", "s": result.append("7")
            case "t", "u", "v": result.append("8")
            case "w", "x", "y", "z": result.append("9")
            default: break
            }
        }
        return result
    }

    public func keys(for rawDigits: String, limit: Int = 32) -> [String] {
        let digits = String(rawDigits.filter { $0 >= "2" && $0 <= "9" })
        guard !digits.isEmpty, limit > 0 else { return [] }
        let characters = Array(digits)
        var results: [String] = []
        var seen = Set<String>()

        func add(_ tokens: [String]) {
            guard results.count < limit else { return }
            let key = tokens.joined(separator: " ")
            if seen.insert(key).inserted { results.append(key) }
        }

        func recurse(_ position: Int, _ tokens: [String]) {
            guard results.count < limit else { return }
            if position == characters.count {
                add(tokens)
                return
            }
            let first = characters[position]
            guard let candidates = syllablePrefixes[first] else { return }
            for candidate in candidates {
                let length = candidate.digits.count
                guard position + length <= characters.count else { continue }
                guard String(characters[position..<(position + length)]) == candidate.digits else { continue }
                for syllable in candidate.syllables {
                    recurse(position + length, tokens + [syllable])
                }
            }
        }

        recurse(0, [])
        if results.isEmpty, digits.count <= 5 {
            let combos = letterCombinations(for: digits, limit: limit)
            for combo in combos { add([combo]) }
        }
        return results
    }

    private func letterCombinations(for digits: String, limit: Int) -> [String] {
        var results: [String] = []
        var buffer = ""
        let characters = Array(digits)
        func recurse(_ index: Int) {
            guard results.count < limit else { return }
            if index == characters.count {
                results.append(buffer)
                return
            }
            let letters = Self.digitLetters[characters[index]] ?? []
            for letter in letters {
                buffer.append(letter)
                recurse(index + 1)
                buffer.removeLast()
            }
        }
        recurse(0)
        return results
    }
}
