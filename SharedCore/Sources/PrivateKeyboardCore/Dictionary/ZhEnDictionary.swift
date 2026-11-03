import Foundation

public enum DictionaryFormat {
    public static let magic = "PKDICT01"
    public static let version: UInt32 = 1
    public static let headerSize = 80
    public static let entrySize = 32
    public static let indexRecordSize = 8
    public static let glossRecordSize = 8
}

public struct DictionaryBuildEntry: Equatable, Sendable {
    public var simplified: String
    public var traditional: String
    public var pinyin: String
    public var pinyinKey: String
    public var frequency: UInt32
    public var glosses: [Gloss]

    public init(
        simplified: String,
        traditional: String,
        pinyin: String,
        pinyinKey: String,
        frequency: UInt32,
        glosses: [Gloss]
    ) {
        self.simplified = simplified
        self.traditional = traditional
        self.pinyin = pinyin
        self.pinyinKey = pinyinKey
        self.frequency = frequency
        self.glosses = glosses
    }

    public var abbreviation: String {
        PinyinText.abbreviation(ofKey: pinyinKey)
    }
}

public enum DictionaryKeyIndex: Sendable {
    case full
    case abbreviation
}

public final class ZhEnDictionary {
    private let reader: BinaryReader
    private let entryCount: UInt32
    private let fullKeyCount: UInt32
    private let abbreviationKeyCount: UInt32
    private let glossCount: UInt32
    private let entryTableOffset: Int
    private let fullIndexOffset: Int
    private let abbreviationIndexOffset: Int
    private let glossTableOffset: Int
    private let stringPoolOffset: Int
    private let maxFrequencyValue: UInt32

    public init(url: URL) throws {
        let reader = try BinaryReader(url: url)
        try reader.checkMagic(DictionaryFormat.magic, version: DictionaryFormat.version)
        self.reader = reader
        self.entryCount = try reader.uint32(at: 12)
        self.fullKeyCount = try reader.uint32(at: 16)
        self.abbreviationKeyCount = try reader.uint32(at: 20)
        self.glossCount = try reader.uint32(at: 24)
        self.entryTableOffset = Int(try reader.uint64(at: 32))
        self.fullIndexOffset = Int(try reader.uint64(at: 40))
        self.abbreviationIndexOffset = Int(try reader.uint64(at: 48))
        self.glossTableOffset = Int(try reader.uint64(at: 56))
        self.stringPoolOffset = Int(try reader.uint64(at: 64))
        let poolLength = Int(try reader.uint64(at: 72))

        guard entryTableOffset >= DictionaryFormat.headerSize,
              entryTableOffset + Int(entryCount) * DictionaryFormat.entrySize <= reader.count,
              fullIndexOffset >= 0,
              fullIndexOffset + Int(fullKeyCount) * DictionaryFormat.indexRecordSize <= reader.count,
              abbreviationIndexOffset >= 0,
              abbreviationIndexOffset + Int(abbreviationKeyCount) * DictionaryFormat.indexRecordSize <= reader.count,
              glossTableOffset >= 0,
              glossTableOffset + Int(glossCount) * DictionaryFormat.glossRecordSize <= reader.count,
              stringPoolOffset >= 0,
              poolLength >= 0,
              stringPoolOffset + poolLength <= reader.count
        else {
            throw BinaryFileError.malformed("dictionary section bounds")
        }

        let headerMax = try reader.uint32(at: 28)
        if headerMax > 0 {
            self.maxFrequencyValue = headerMax
        } else {
            var maxFrequency: UInt32 = 1
            for id in 0..<Int(entryCount) {
                let frequency = try reader.uint32(at: entryTableOffset + id * DictionaryFormat.entrySize)
                maxFrequency = max(maxFrequency, frequency)
            }
            self.maxFrequencyValue = maxFrequency
        }
    }

    public var count: Int { Int(entryCount) }
    public var maxFrequency: UInt32 { maxFrequencyValue }

    public func entry(id: UInt32) throws -> LexiconEntry {
        guard id < entryCount else {
            throw BinaryFileError.malformed("entry id \(id) out of range")
        }
        let base = entryTableOffset + Int(id) * DictionaryFormat.entrySize
        let frequency = try reader.uint32(at: base)
        let glossCountForEntry = Int(try reader.uint16(at: base + 6))
        let glossStart = Int(try reader.uint32(at: base + 28))
        guard glossStart + glossCountForEntry <= Int(glossCount) else {
            throw BinaryFileError.malformed("gloss range for entry \(id)")
        }
        let simplified = try string(atPoolOffset: Int(try reader.uint32(at: base + 8)))
        let traditional = try string(atPoolOffset: Int(try reader.uint32(at: base + 12)))
        let pinyin = try string(atPoolOffset: Int(try reader.uint32(at: base + 16)))
        let pinyinKey = try string(atPoolOffset: Int(try reader.uint32(at: base + 20)))
        let abbreviation = try string(atPoolOffset: Int(try reader.uint32(at: base + 24)))
        var glosses: [Gloss] = []
        glosses.reserveCapacity(glossCountForEntry)
        for index in 0..<glossCountForEntry {
            let record = glossTableOffset + (glossStart + index) * DictionaryFormat.glossRecordSize
            let pos = try string(atPoolOffset: Int(try reader.uint32(at: record)))
            let definition = try string(atPoolOffset: Int(try reader.uint32(at: record + 4)))
            glosses.append(Gloss(partOfSpeech: pos, definition: definition))
        }
        return LexiconEntry(
            id: id,
            simplified: simplified,
            traditional: traditional,
            pinyin: pinyin,
            pinyinKey: pinyinKey,
            abbreviation: abbreviation,
            frequency: frequency,
            glosses: glosses
        )
    }

    public func entries(matching key: String, index: DictionaryKeyIndex, limit: Int = 64) throws -> [LexiconEntry] {
        try prefixEntries(key: key, index: index, limit: limit, exactOnly: true)
    }

    public func prefixEntries(
        key: String,
        index: DictionaryKeyIndex,
        limit: Int = 64,
        exactOnly: Bool = false
    ) throws -> [LexiconEntry] {
        guard limit > 0, !key.isEmpty else { return [] }
        let isFull = index == .full
        let offset = isFull ? fullIndexOffset : abbreviationIndexOffset
        let count = Int(isFull ? fullKeyCount : abbreviationKeyCount)
        var low = 0
        var high = count
        while low < high {
            let mid = (low + high) / 2
            let midKey = try keyString(atIndex: mid, tableOffset: offset)
            if midKey < key {
                low = mid + 1
            } else {
                high = mid
            }
        }

        var result: [LexiconEntry] = []
        var cursor = low
        while cursor < count, result.count < limit {
            let candidateKey = try keyString(atIndex: cursor, tableOffset: offset)
            if exactOnly {
                guard candidateKey == key else { break }
            } else {
                guard candidateKey.hasPrefix(key) else { break }
            }
            let recordOffset = offset + cursor * DictionaryFormat.indexRecordSize
            let entryID = try reader.uint32(at: recordOffset + 4)
            result.append(try entry(id: entryID))
            cursor += 1
        }
        return result
    }

    public func allEntries(limit: Int = 100_000) throws -> [LexiconEntry] {
        guard limit > 0 else { return [] }
        var result: [LexiconEntry] = []
        let upper = min(Int(entryCount), limit)
        for id in 0..<upper {
            result.append(try entry(id: UInt32(id)))
        }
        return result
    }

    private func keyString(atIndex index: Int, tableOffset: Int) throws -> String {
        let recordOffset = tableOffset + index * DictionaryFormat.indexRecordSize
        return try string(atPoolOffset: Int(try reader.uint32(at: recordOffset)))
    }

    private func string(atPoolOffset offset: Int) throws -> String {
        let absolute = stringPoolOffset + offset
        guard offset >= 0, absolute < reader.count else {
            throw BinaryFileError.malformed("string pool offset out of range")
        }
        return try reader.string(at: absolute)
    }
}

public enum DictionaryBinaryWriter {
    public static func write(entries input: [DictionaryBuildEntry], to url: URL) throws {
        precondition(input.count <= Int(UInt32.max))
        let entries = input.sorted {
            if $0.pinyinKey != $1.pinyinKey { return $0.pinyinKey < $1.pinyinKey }
            if $0.simplified != $1.simplified { return $0.simplified < $1.simplified }
            return $0.traditional < $1.traditional
        }

        var pool = StringPoolBuilder()
        struct PreparedEntry {
            let frequency: UInt32
            let glossCount: UInt16
            let simplified: UInt32
            let traditional: UInt32
            let pinyin: UInt32
            let fullKey: UInt32
            let abbreviation: UInt32
            let glossStart: UInt32
        }
        var prepared: [PreparedEntry] = []
        prepared.reserveCapacity(entries.count)
        var glossRecords: [(String, String)] = []

        for entry in entries {
            let start = glossRecords.count
            let glosses = Array(entry.glosses.prefix(Int(UInt16.max)))
            for gloss in glosses {
                glossRecords.append((gloss.partOfSpeech, gloss.definition))
            }
            prepared.append(
                PreparedEntry(
                    frequency: entry.frequency,
                    glossCount: UInt16(glosses.count),
                    simplified: pool.offset(for: entry.simplified),
                    traditional: pool.offset(for: entry.traditional),
                    pinyin: pool.offset(for: entry.pinyin),
                    fullKey: pool.offset(for: entry.pinyinKey),
                    abbreviation: pool.offset(for: entry.abbreviation),
                    glossStart: UInt32(start)
                )
            )
        }

        var fullIndex: [(key: String, id: UInt32, frequency: UInt32)] = []
        var abbreviationIndex: [(key: String, id: UInt32, frequency: UInt32)] = []
        fullIndex.reserveCapacity(entries.count)
        abbreviationIndex.reserveCapacity(entries.count)
        for (id, entry) in entries.enumerated() {
            fullIndex.append((entry.pinyinKey, UInt32(id), entry.frequency))
            abbreviationIndex.append((entry.abbreviation, UInt32(id), entry.frequency))
        }
        // Equal keys are ordered by frequency descending so that a bounded
        // prefix query (notably an ambiguous initial key such as "nh") does not
        // return arbitrary rare words first.
        let indexOrder: ((key: String, id: UInt32, frequency: UInt32), (key: String, id: UInt32, frequency: UInt32)) -> Bool = { lhs, rhs in
            if lhs.key != rhs.key { return lhs.key < rhs.key }
            if lhs.frequency != rhs.frequency { return lhs.frequency > rhs.frequency }
            return lhs.id < rhs.id
        }
        fullIndex.sort(by: indexOrder)
        abbreviationIndex.sort(by: indexOrder)

        let poolData = pool.data
        let entryTableOffset = DictionaryFormat.headerSize
        let fullIndexOffset = entryTableOffset + entries.count * DictionaryFormat.entrySize
        let abbreviationIndexOffset = fullIndexOffset + fullIndex.count * DictionaryFormat.indexRecordSize
        let glossTableOffset = abbreviationIndexOffset + abbreviationIndex.count * DictionaryFormat.indexRecordSize
        let stringPoolOffset = glossTableOffset + glossRecords.count * DictionaryFormat.glossRecordSize

        var writer = BinaryWriter()
        writer.append(DictionaryFormat.magic)
        writer.append(uint32: DictionaryFormat.version)
        writer.append(uint32: UInt32(entries.count))
        writer.append(uint32: UInt32(fullIndex.count))
        writer.append(uint32: UInt32(abbreviationIndex.count))
        writer.append(uint32: UInt32(glossRecords.count))
        writer.append(uint32: prepared.map(\.frequency).max() ?? 1)
        writer.append(uint64: UInt64(entryTableOffset))
        writer.append(uint64: UInt64(fullIndexOffset))
        writer.append(uint64: UInt64(abbreviationIndexOffset))
        writer.append(uint64: UInt64(glossTableOffset))
        writer.append(uint64: UInt64(stringPoolOffset))
        writer.append(uint64: UInt64(poolData.count))

        for entry in prepared {
            writer.append(uint32: entry.frequency)
            writer.append(uint16: 0)
            writer.append(uint16: entry.glossCount)
            writer.append(uint32: entry.simplified)
            writer.append(uint32: entry.traditional)
            writer.append(uint32: entry.pinyin)
            writer.append(uint32: entry.fullKey)
            writer.append(uint32: entry.abbreviation)
            writer.append(uint32: entry.glossStart)
        }
        for item in fullIndex {
            writer.append(uint32: pool.offset(for: item.key))
            writer.append(uint32: item.id)
        }
        for item in abbreviationIndex {
            writer.append(uint32: pool.offset(for: item.key))
            writer.append(uint32: item.id)
        }
        for (pos, definition) in glossRecords {
            writer.append(uint32: pool.offset(for: pos))
            writer.append(uint32: pool.offset(for: definition))
        }
        writer.append(contentsOf: pool.data)
        try writer.write(to: url)
    }
}
