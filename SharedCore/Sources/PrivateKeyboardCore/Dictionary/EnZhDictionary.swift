import Foundation

public enum EnglishDictionaryFormat {
    public static let magic = "PKENZH01"
    public static let version: UInt32 = 1
    public static let headerSize = 64
    public static let recordSize = 16
    public static let indexRecordSize = 8
}

public struct EnglishBuildEntry: Equatable, Sendable {
    public var english: String
    public var partOfSpeech: String
    public var chinese: String
    public var definition: String
    public var frequency: UInt32

    public init(
        english: String,
        partOfSpeech: String,
        chinese: String,
        definition: String,
        frequency: UInt32
    ) {
        self.english = english
        self.partOfSpeech = partOfSpeech
        self.chinese = chinese
        self.definition = definition
        self.frequency = frequency
    }
}

public final class EnZhDictionary {
    private let reader: BinaryReader
    private let recordCount: UInt32
    private let indexCount: UInt32
    private let recordTableOffset: Int
    private let indexOffset: Int
    private let stringPoolOffset: Int

    public init(url: URL) throws {
        let reader = try BinaryReader(url: url)
        try reader.checkMagic(EnglishDictionaryFormat.magic, version: EnglishDictionaryFormat.version)
        self.reader = reader
        self.recordCount = try reader.uint32(at: 12)
        self.indexCount = try reader.uint32(at: 16)
        self.recordTableOffset = Int(try reader.uint64(at: 24))
        self.indexOffset = Int(try reader.uint64(at: 32))
        self.stringPoolOffset = Int(try reader.uint64(at: 40))
        _ = try reader.uint64(at: 48)
        guard recordTableOffset >= EnglishDictionaryFormat.headerSize,
              recordTableOffset + Int(recordCount) * EnglishDictionaryFormat.recordSize <= reader.count,
              indexOffset >= 0,
              indexOffset + Int(indexCount) * EnglishDictionaryFormat.indexRecordSize <= reader.count,
              stringPoolOffset >= 0,
              stringPoolOffset <= reader.count
        else {
            throw BinaryFileError.malformed("en-zh dictionary section bounds")
        }
    }

    public var count: Int { Int(recordCount) }

    public func entry(id: UInt32) throws -> EnglishEntry {
        guard id < recordCount else {
            throw BinaryFileError.malformed("English entry id \(id) out of range")
        }
        let base = recordTableOffset + Int(id) * EnglishDictionaryFormat.recordSize
        let key = try string(atPoolOffset: Int(try reader.uint32(at: base)))
        let partOfSpeech = try string(atPoolOffset: Int(try reader.uint32(at: base + 4)))
        let chinese = try string(atPoolOffset: Int(try reader.uint32(at: base + 8)))
        let definition = try string(atPoolOffset: Int(try reader.uint32(at: base + 12)))
        return EnglishEntry(
            id: id,
            english: key,
            partOfSpeech: partOfSpeech,
            chinese: chinese,
            definition: definition,
            frequency: 1
        )
    }

    public func prefixEntries(prefix: String, limit: Int = 32) throws -> [EnglishEntry] {
        guard limit > 0 else { return [] }
        let normalized = EnglishText.normalizeKey(prefix)
        guard !normalized.isEmpty else { return [] }
        var low = 0
        var high = Int(indexCount)
        while low < high {
            let mid = (low + high) / 2
            let key = try keyString(atIndex: mid)
            if key < normalized {
                low = mid + 1
            } else {
                high = mid
            }
        }
        var result: [EnglishEntry] = []
        var cursor = low
        while cursor < Int(indexCount), result.count < limit {
            let key = try keyString(atIndex: cursor)
            guard key.hasPrefix(normalized) else { break }
            let record = indexOffset + cursor * EnglishDictionaryFormat.indexRecordSize
            let id = try reader.uint32(at: record + 4)
            result.append(try entry(id: id))
            cursor += 1
        }
        return result
    }

    private func keyString(atIndex index: Int) throws -> String {
        let record = indexOffset + index * EnglishDictionaryFormat.indexRecordSize
        return try string(atPoolOffset: Int(try reader.uint32(at: record)))
    }

    private func string(atPoolOffset offset: Int) throws -> String {
        let absolute = stringPoolOffset + offset
        guard offset >= 0, absolute < reader.count else {
            throw BinaryFileError.malformed("en-zh string pool offset out of range")
        }
        return try reader.string(at: absolute)
    }
}

public enum EnglishDictionaryBinaryWriter {
    public static func write(entries input: [EnglishBuildEntry], to url: URL) throws {
        let entries = input
            .filter { !EnglishText.normalizeKey($0.english).isEmpty }
            .sorted {
                let l = EnglishText.normalizeKey($0.english)
                let r = EnglishText.normalizeKey($1.english)
                if l != r { return l < r }
                if $0.chinese != $1.chinese { return $0.chinese < $1.chinese }
                return $0.partOfSpeech < $1.partOfSpeech
            }

        var pool = StringPoolBuilder()
        struct Prepared {
            let key: UInt32
            let pos: UInt32
            let chinese: UInt32
            let definition: UInt32
        }
        var prepared: [Prepared] = []
        prepared.reserveCapacity(entries.count)
        var index: [(key: String, id: UInt32, frequency: UInt32)] = []
        index.reserveCapacity(entries.count)
        for (id, entry) in entries.enumerated() {
            let normalized = EnglishText.normalizeKey(entry.english)
            prepared.append(
                Prepared(
                    key: pool.offset(for: normalized),
                    pos: pool.offset(for: entry.partOfSpeech),
                    chinese: pool.offset(for: entry.chinese),
                    definition: pool.offset(for: entry.definition)
                )
            )
            index.append((normalized, UInt32(id), entry.frequency))
        }
        index.sort {
            if $0.key != $1.key { return $0.key < $1.key }
            if $0.frequency != $1.frequency { return $0.frequency > $1.frequency }
            return $0.id < $1.id
        }

        let poolData = pool.data
        let recordTableOffset = EnglishDictionaryFormat.headerSize
        let indexOffset = recordTableOffset + entries.count * EnglishDictionaryFormat.recordSize
        let stringPoolOffset = indexOffset + index.count * EnglishDictionaryFormat.indexRecordSize

        var writer = BinaryWriter()
        writer.append(EnglishDictionaryFormat.magic)
        writer.append(uint32: EnglishDictionaryFormat.version)
        writer.append(uint32: UInt32(entries.count))
        writer.append(uint32: UInt32(index.count))
        writer.append(uint32: 0)
        writer.append(uint64: UInt64(recordTableOffset))
        writer.append(uint64: UInt64(indexOffset))
        writer.append(uint64: UInt64(stringPoolOffset))
        writer.append(uint64: UInt64(poolData.count))
        writer.append(uint64: 0)
        for entry in prepared {
            writer.append(uint32: entry.key)
            writer.append(uint32: entry.pos)
            writer.append(uint32: entry.chinese)
            writer.append(uint32: entry.definition)
        }
        for item in index {
            writer.append(uint32: pool.offset(for: item.key))
            writer.append(uint32: item.id)
        }
        writer.append(contentsOf: poolData)
        try writer.write(to: url)
    }
}

public enum EnglishText {
    public static func normalizeKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
            .lowercased()
    }

    public static func searchTokens(in gloss: String) -> [String] {
        let cleaned = gloss
            .replacingOccurrences(of: "；", with: ";")
            .replacingOccurrences(of: "/", with: ";")
            .replacingOccurrences(of: "(", with: " ")
            .replacingOccurrences(of: ")", with: " ")
            .replacingOccurrences(of: "[", with: " ")
            .replacingOccurrences(of: "]", with: " ")
        var tokens: [String] = []
        for part in cleaned.split(separator: ";") {
            var text = normalizeKey(String(part))
            for prefix in ["to ", "a ", "an ", "the "] where text.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
            }
            text = text.trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: " -'")))
            guard text.count >= 2, text.count <= 48 else { continue }
            guard text.rangeOfCharacter(from: CharacterSet.letters) != nil else { continue }
            tokens.append(text)
            let words = text.split(separator: " ").map(String.init)
            if words.count > 1 {
                tokens.append(contentsOf: words.filter { $0.count >= 3 })
            } else {
                tokens.append(text)
            }
            if tokens.count >= 8 { break }
        }
        return Array(Set(tokens)).sorted()
    }
}
