import Foundation

public enum NGramFormat {
    public static let bigramMagic = "PKLMBI01"
    public static let trigramMagic = "PKLMTRI1"
    public static let version: UInt32 = 1
    public static let headerSize = 40
    public static let bigramRecordSize = 24
    public static let trigramRecordSize = 32
}

public struct BigramBuildEntry: Equatable, Sendable {
    public var context: String
    public var token: String
    public var count: UInt32
    public init(context: String, token: String, count: UInt32) {
        self.context = context
        self.token = token
        self.count = count
    }
}

public struct TrigramBuildEntry: Equatable, Sendable {
    public var first: String
    public var second: String
    public var token: String
    public var count: UInt32
    public init(first: String, second: String, token: String, count: UInt32) {
        self.first = first
        self.second = second
        self.token = token
        self.count = count
    }
}

public final class BigramLanguageModel {
    private let reader: BinaryReader
    private let recordCount: Int
    private let dataOffset: Int

    public init(url: URL) throws {
        let reader = try BinaryReader(url: url)
        try reader.checkMagic(NGramFormat.bigramMagic, version: NGramFormat.version)
        let count = Int(try reader.uint32(at: 12))
        let recordSize = Int(try reader.uint32(at: 16))
        let offset = Int(try reader.uint64(at: 24))
        guard recordSize == NGramFormat.bigramRecordSize,
              offset >= NGramFormat.headerSize,
              offset + count * recordSize <= reader.count
        else {
            throw BinaryFileError.malformed("bigram section bounds")
        }
        self.reader = reader
        self.recordCount = count
        self.dataOffset = offset
    }

    public var count: Int { recordCount }

    public func rawScore(context: String, token: String) -> Double? {
        let contextHash = StableHash.fnv1a64(context)
        let tokenHash = StableHash.fnv1a64(token)
        var low = 0
        var high = recordCount
        while low < high {
            let mid = (low + high) / 2
            let base = dataOffset + mid * NGramFormat.bigramRecordSize
            guard let midContext = try? reader.uint64(at: base),
                  let midToken = try? reader.uint64(at: base + 8)
            else { return nil }
            if midContext < contextHash || (midContext == contextHash && midToken < tokenHash) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        guard low < recordCount else { return nil }
        let base = dataOffset + low * NGramFormat.bigramRecordSize
        guard (try? reader.uint64(at: base)) == contextHash,
              (try? reader.uint64(at: base + 8)) == tokenHash,
              let score = try? reader.int32(at: base + 16)
        else {
            return nil
        }
        return Double(score) / 1000.0
    }

    public func normalizedScore(context: String, token: String) -> Double {
        guard let raw = rawScore(context: context, token: token) else { return 0 }
        return max(0, min(1, 1 + raw / 6.0))
    }
}

public final class TrigramLanguageModel {
    private let reader: BinaryReader
    private let recordCount: Int
    private let dataOffset: Int

    public init(url: URL) throws {
        let reader = try BinaryReader(url: url)
        try reader.checkMagic(NGramFormat.trigramMagic, version: NGramFormat.version)
        let count = Int(try reader.uint32(at: 12))
        let recordSize = Int(try reader.uint32(at: 16))
        let offset = Int(try reader.uint64(at: 24))
        guard recordSize == NGramFormat.trigramRecordSize,
              offset >= NGramFormat.headerSize,
              offset + count * recordSize <= reader.count
        else {
            throw BinaryFileError.malformed("trigram section bounds")
        }
        self.reader = reader
        self.recordCount = count
        self.dataOffset = offset
    }

    public var count: Int { recordCount }

    public func rawScore(first: String, second: String, token: String) -> Double? {
        let firstHash = StableHash.fnv1a64(first)
        let secondHash = StableHash.fnv1a64(second)
        let tokenHash = StableHash.fnv1a64(token)
        var low = 0
        var high = recordCount
        while low < high {
            let mid = (low + high) / 2
            let base = dataOffset + mid * NGramFormat.trigramRecordSize
            guard let midFirst = try? reader.uint64(at: base),
                  let midSecond = try? reader.uint64(at: base + 8),
                  let midToken = try? reader.uint64(at: base + 16)
            else { return nil }
            let isBefore = midFirst < firstHash
                || (midFirst == firstHash && midSecond < secondHash)
                || (midFirst == firstHash && midSecond == secondHash && midToken < tokenHash)
            if isBefore {
                low = mid + 1
            } else {
                high = mid
            }
        }
        guard low < recordCount else { return nil }
        let base = dataOffset + low * NGramFormat.trigramRecordSize
        guard (try? reader.uint64(at: base)) == firstHash,
              (try? reader.uint64(at: base + 8)) == secondHash,
              (try? reader.uint64(at: base + 16)) == tokenHash,
              let score = try? reader.int32(at: base + 24)
        else {
            return nil
        }
        return Double(score) / 1000.0
    }

    public func normalizedScore(first: String, second: String, token: String) -> Double {
        guard let raw = rawScore(first: first, second: second, token: token) else { return 0 }
        return max(0, min(1, 1 + raw / 6.0))
    }
}

public struct ContextLanguageModel {
    public let bigram: BigramLanguageModel
    public let trigram: TrigramLanguageModel

    public init(bigram: BigramLanguageModel, trigram: TrigramLanguageModel) {
        self.bigram = bigram
        self.trigram = trigram
    }

    public func scores(previousWords: [String], candidate: String) -> (bigram: Double, trigram: Double) {
        var bi = 0.0
        var tri = 0.0
        if let last = previousWords.last {
            bi = bigram.normalizedScore(context: last, token: candidate)
        }
        if previousWords.count >= 2 {
            let first = previousWords[previousWords.count - 2]
            let second = previousWords[previousWords.count - 1]
            tri = trigram.normalizedScore(first: first, second: second, token: candidate)
        }
        return (bi, tri)
    }
}

public enum NGramBinaryWriter {
    public static func writeBigrams(_ input: [BigramBuildEntry], to url: URL) throws {
        var aggregated: [String: [String: UInt32]] = [:]
        for entry in input {
            aggregated[entry.context, default: [:]][entry.token, default: 0] &+= entry.count
        }
        struct Record {
            let contextHash: UInt64
            let tokenHash: UInt64
            let score: Int32
            let count: UInt32
        }
        var records: [Record] = []
        for (context, tokens) in aggregated {
            let total = tokens.values.reduce(UInt64(0)) { $0 + UInt64($1) }
            guard total > 0 else { continue }
            for (token, count) in tokens {
                let probability = Double(count) / Double(total)
                let raw = log(max(probability, 1e-9)) * 1000.0
                records.append(
                    Record(
                        contextHash: StableHash.fnv1a64(context),
                        tokenHash: StableHash.fnv1a64(token),
                        score: Int32(max(Double(Int32.min + 1), min(Double(Int32.max), raw))),
                        count: count
                    )
                )
            }
        }
        records.sort {
            $0.contextHash == $1.contextHash ? $0.tokenHash < $1.tokenHash : $0.contextHash < $1.contextHash
        }
        try write(records: records, recordSize: NGramFormat.bigramRecordSize, magic: NGramFormat.bigramMagic, url: url) { writer, record in
            writer.append(uint64: record.contextHash)
            writer.append(uint64: record.tokenHash)
            writer.append(uint32: UInt32(bitPattern: record.score))
            writer.append(uint32: record.count)
        }
    }

    public static func writeTrigrams(_ input: [TrigramBuildEntry], to url: URL) throws {
        var aggregated: [String: [String: [String: UInt32]]] = [:]
        for entry in input {
            aggregated[entry.first, default: [:]][entry.second, default: [:]][entry.token, default: 0] &+= entry.count
        }
        struct Record {
            let firstHash: UInt64
            let secondHash: UInt64
            let tokenHash: UInt64
            let score: Int32
            let count: UInt32
        }
        var records: [Record] = []
        for (first, seconds) in aggregated {
            for (second, tokens) in seconds {
                let total = tokens.values.reduce(UInt64(0)) { $0 + UInt64($1) }
                guard total > 0 else { continue }
                for (token, count) in tokens {
                    let probability = Double(count) / Double(total)
                    let raw = log(max(probability, 1e-9)) * 1000.0
                    records.append(
                        Record(
                            firstHash: StableHash.fnv1a64(first),
                            secondHash: StableHash.fnv1a64(second),
                            tokenHash: StableHash.fnv1a64(token),
                            score: Int32(max(Double(Int32.min + 1), min(Double(Int32.max), raw))),
                            count: count
                        )
                    )
                }
            }
        }
        records.sort {
            if $0.firstHash != $1.firstHash { return $0.firstHash < $1.firstHash }
            if $0.secondHash != $1.secondHash { return $0.secondHash < $1.secondHash }
            return $0.tokenHash < $1.tokenHash
        }
        try write(records: records, recordSize: NGramFormat.trigramRecordSize, magic: NGramFormat.trigramMagic, url: url) { writer, record in
            writer.append(uint64: record.firstHash)
            writer.append(uint64: record.secondHash)
            writer.append(uint64: record.tokenHash)
            writer.append(uint32: UInt32(bitPattern: record.score))
            writer.append(uint32: record.count)
        }
    }

    private static func write<Record>(
        records: [Record],
        recordSize: Int,
        magic: String,
        url: URL,
        body: (inout BinaryWriter, Record) -> Void
    ) throws {
        var writer = BinaryWriter()
        writer.append(magic)
        writer.append(uint32: NGramFormat.version)
        writer.append(uint32: UInt32(records.count))
        writer.append(uint32: UInt32(recordSize))
        writer.append(uint32: 0)
        writer.append(uint64: UInt64(NGramFormat.headerSize))
        writer.append(uint64: 0)
        for record in records {
            body(&writer, record)
        }
        try writer.write(to: url)
    }
}
