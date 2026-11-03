import Foundation
import PrivateKeyboardCore

struct Options {
    var source = "DataSources/seed"
    var output = "Resources/Generated"
    var dataVersion = "seed-1"
    var sourceName = "PrivateKeyboard development seed"
    var sourceURL = "https://github.com/cc-cedict/cc-cedict"
    var license = "CC BY-SA 4.0 (CC-CEDICT-derived fields)"
    var attribution = "Contains data derived from CC-CEDICT, published by MDBG; see THIRD_PARTY_LICENSES.md."
    var minAppVersion = "1.0.0"
}

enum BuildError: Error, CustomStringConvertible {
    case badArguments(String)
    case badTSV(file: String, line: Int, reason: String)
    case empty(String)

    var description: String {
        switch self {
        case .badArguments(let value): return "arguments: \(value)"
        case .badTSV(let file, let line, let reason): return "\(file):\(line): \(reason)"
        case .empty(let value): return "no data for \(value)"
        }
    }
}

func parseOptions() throws -> Options {
    var options = Options()
    var args = Array(CommandLine.arguments.dropFirst())
    var index = 0
    while index < args.count {
        let key = args[index]
        func next() throws -> String {
            index += 1
            guard index < args.count else { throw BuildError.badArguments("missing value for \(key)") }
            return args[index]
        }
        switch key {
        case "--source": options.source = try next()
        case "--out": options.output = try next()
        case "--data-version": options.dataVersion = try next()
        case "--source-name": options.sourceName = try next()
        case "--source-url": options.sourceURL = try next()
        case "--license": options.license = try next()
        case "--attribution": options.attribution = try next()
        case "--min-app-version": options.minAppVersion = try next()
        case "--help", "-h":
            print("dictionary-builder [--source DIR] [--out DIR] [--data-version VERSION]")
            exit(0)
        default:
            throw BuildError.badArguments("unknown \(key)")
        }
        index += 1
    }
    return options
}

func readTSV(_ url: URL) throws -> [(line: Int, fields: [String])] {
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw BuildError.empty(url.lastPathComponent)
    }
    let text = try String(contentsOf: url, encoding: .utf8)
    var rows: [(Int, [String])] = []
    for (zeroBased, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty || line.hasPrefix("#") { continue }
        let fields = line.components(separatedBy: "\t")
        let header = fields.first?.lowercased()
        if header == "simplified" || header == "type" || header == "syllable" { continue }
        rows.append((zeroBased + 1, fields))
    }
    return rows
}

func normalizedKey(_ raw: String) -> String {
    let syllables = raw
        .lowercased()
        .replacingOccurrences(of: "u:", with: "v")
        .split(whereSeparator: { $0 == " " || $0 == "'" || $0 == "’" })
        .map { PinyinText.normalizeSyllable(String($0)) }
        .filter { !$0.isEmpty }
    return syllables.joined(separator: " ")
}

func cleanGloss(_ raw: String) -> String {
    var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while text.hasPrefix("/") { text.removeFirst() }
    while text.hasSuffix("/") { text.removeLast() }
    return text
}

do {
    let options = try parseOptions()
    let sourceURL = URL(fileURLWithPath: options.source, isDirectory: true)
    let outputURL = URL(fileURLWithPath: options.output, isDirectory: true)
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

    let wordRows = try readTSV(sourceURL.appendingPathComponent("words.tsv"))
    let translationRows = try readTSV(sourceURL.appendingPathComponent("translations.tsv"))
    let pinyinRows = try readTSV(sourceURL.appendingPathComponent("pinyin.tsv"))
    let ngramRows = try readTSV(sourceURL.appendingPathComponent("ngram.tsv"))

    var translationsByWord: [String: [Gloss]] = [:]
    for row in translationRows {
        guard row.fields.count >= 3 else {
            throw BuildError.badTSV(file: "translations.tsv", line: row.line, reason: "expected 4 columns")
        }
        let word = row.fields[0]
        let pos = row.fields[1]
        let definition = cleanGloss(row.fields[2])
        guard !word.isEmpty, !definition.isEmpty else { continue }
        let gloss = Gloss(partOfSpeech: pos, definition: definition)
        if !(translationsByWord[word]?.contains(gloss) ?? false) {
            translationsByWord[word, default: []].append(gloss)
        }
    }

    struct Draft {
        var simplified: String
        var traditional: String
        var pinyinKey: String
        var frequency: UInt32
        var glosses: [Gloss]
    }
    var drafts: [Draft] = []
    var seen = Set<String>()
    var syllableFrequency: [String: UInt32] = [:]
    for row in pinyinRows {
        guard let first = row.fields.first, row.fields.count >= 2,
              let frequency = UInt32(row.fields[1])
        else { continue }
        let syllable = PinyinText.normalizeSyllable(first)
        guard !syllable.isEmpty else { continue }
        syllableFrequency[syllable, default: 0] &+= max(1, frequency)
    }

    for row in wordRows {
        guard row.fields.count >= 4 else {
            throw BuildError.badTSV(file: "words.tsv", line: row.line, reason: "expected simplified, traditional, pinyin, frequency")
        }
        let simplified = row.fields[0].trimmingCharacters(in: .whitespaces)
        let traditional = row.fields[1].trimmingCharacters(in: .whitespaces)
        let pinyinKey = normalizedKey(row.fields[2])
        let frequency = UInt32(row.fields[3]) ?? 1
        guard !simplified.isEmpty, !pinyinKey.isEmpty else { continue }
        let identity = "\(simplified)\t\(traditional)\t\(pinyinKey)"
        guard seen.insert(identity).inserted else { continue }
        let glosses = translationsByWord[simplified] ?? []
        drafts.append(
            Draft(
                simplified: simplified,
                traditional: traditional.isEmpty ? simplified : traditional,
                pinyinKey: pinyinKey,
                frequency: frequency,
                glosses: glosses
            )
        )
        for syllable in pinyinKey.split(separator: " ") {
            syllableFrequency[String(syllable), default: 0] &+= max(1, frequency)
        }
    }
    guard !drafts.isEmpty else { throw BuildError.empty("words") }

    // Keep only syllables that exist in the word data. This avoids offering a
    // dictionary-independent syllable that can never produce a candidate.
    let usedSyllables = Set(drafts.flatMap { $0.pinyinKey.split(separator: " ").map(String.init) })
    syllableFrequency = syllableFrequency.filter { usedSyllables.contains($0.key) }

    let entries = drafts.map {
        DictionaryBuildEntry(
            simplified: $0.simplified,
            traditional: $0.traditional,
            pinyin: $0.pinyinKey,
            pinyinKey: $0.pinyinKey,
            frequency: $0.frequency,
            glosses: $0.glosses
        )
    }

    var englishEntries: [EnglishBuildEntry] = []
    var englishSeen = Set<String>()
    for draft in drafts {
        for gloss in draft.glosses {
            for token in EnglishText.searchTokens(in: gloss.definition).prefix(8) {
                let key = "\(token)\t\(draft.simplified)\t\(gloss.partOfSpeech)"
                guard englishSeen.insert(key).inserted else { continue }
                englishEntries.append(
                    EnglishBuildEntry(
                        english: token,
                        partOfSpeech: gloss.partOfSpeech,
                        chinese: draft.simplified,
                        definition: gloss.definition,
                        frequency: draft.frequency
                    )
                )
            }
        }
    }

    var bigrams: [BigramBuildEntry] = []
    var trigrams: [TrigramBuildEntry] = []
    for row in ngramRows {
        guard row.fields.count >= 4 else {
            throw BuildError.badTSV(file: "ngram.tsv", line: row.line, reason: "expected type and 3-4 values")
        }
        let type = row.fields[0].lowercased()
        if type == "bi", row.fields.count >= 4, let count = UInt32(row.fields[3]) {
            bigrams.append(BigramBuildEntry(context: row.fields[1], token: row.fields[2], count: count))
        } else if type == "tri", row.fields.count >= 5, let count = UInt32(row.fields[4]) {
            trigrams.append(
                TrigramBuildEntry(first: row.fields[1], second: row.fields[2], token: row.fields[3], count: count)
            )
        }
    }

    try PinyinBinaryWriter.write(frequencies: syllableFrequency, to: outputURL.appendingPathComponent("pinyin.bin"))
    try DictionaryBinaryWriter.write(entries: entries, to: outputURL.appendingPathComponent("dictionary.zh-en.bin"))
    try EnglishDictionaryBinaryWriter.write(entries: englishEntries, to: outputURL.appendingPathComponent("dictionary.en-zh.bin"))
    try NGramBinaryWriter.writeBigrams(bigrams, to: outputURL.appendingPathComponent("lm.bigram.bin"))
    try NGramBinaryWriter.writeTrigrams(trigrams, to: outputURL.appendingPathComponent("lm.trigram.bin"))

    struct DatasetMetadata: Codable {
        var schemaVersion: Int
        var dataVersion: String
        var builtAt: String
        var minAppVersion: String
        var sourceName: String
        var sourceURL: String
        var license: String
        var attribution: String
        var wordCount: Int
        var englishSenseCount: Int
        var syllableCount: Int
        var bigramCount: Int
        var trigramCount: Int
        var files: [String: String]
    }
    var hashes: [String: String] = [:]
    for file in DatasetFile.required {
        let url = outputURL.appendingPathComponent(file.rawValue)
        hashes[file.rawValue] = try FileDigest.sha256Hex(ofFileAt: url)
    }
    let metadata = DatasetMetadata(
        schemaVersion: 1,
        dataVersion: options.dataVersion,
        builtAt: ISO8601DateFormatter().string(from: Date()),
        minAppVersion: options.minAppVersion,
        sourceName: options.sourceName,
        sourceURL: options.sourceURL,
        license: options.license,
        attribution: options.attribution,
        wordCount: entries.count,
        englishSenseCount: englishEntries.count,
        syllableCount: syllableFrequency.count,
        bigramCount: bigrams.count,
        trigramCount: trigrams.count,
        files: hashes
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(metadata).write(to: outputURL.appendingPathComponent("dataset.json"), options: [.atomic])

    print("Built \(options.dataVersion)")
    print("  words: \(entries.count)")
    print("  English senses: \(englishEntries.count)")
    print("  syllables: \(syllableFrequency.count)")
    print("  bigrams: \(bigrams.count), trigrams: \(trigrams.count)")
    print("  output: \(outputURL.path)")
} catch {
    FileHandle.standardError.write(Data("dictionary-builder: \(error)\n".utf8))
    exit(1)
}
