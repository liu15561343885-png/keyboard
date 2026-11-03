import Foundation

public enum BinaryFileError: Error, Equatable, CustomStringConvertible {
    case cannotRead(String)
    case tooLarge(Int)
    case truncated(needed: Int, available: Int)
    case badMagic(expected: String, actual: String)
    case unsupportedVersion(UInt32)
    case malformed(String)

    public var description: String {
        switch self {
        case .cannotRead(let path):
            return "cannot read binary file: \(path)"
        case .tooLarge(let size):
            return "binary file is too large: \(size) bytes"
        case .truncated(let needed, let available):
            return "truncated binary file: need \(needed) bytes, have \(available)"
        case .badMagic(let expected, let actual):
            return "bad magic: expected \(expected), got \(actual)"
        case .unsupportedVersion(let version):
            return "unsupported format version: \(version)"
        case .malformed(let reason):
            return "malformed binary file: \(reason)"
        }
    }
}

/// Read-only bounds-checked little-endian access to a memory-mapped dataset.
///
/// The files are opened with `.mappedIfSafe`; a 20 MB dictionary therefore does
/// not become a 20 MB heap allocation. Accessors never read outside the file.
public struct BinaryReader {
    public let data: Data
    public let url: URL

    public init(url: URL, maximumSize: Int = 512 * 1024 * 1024) throws {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        } catch {
            throw BinaryFileError.cannotRead(url.path)
        }
        guard values.isRegularFile == true else {
            throw BinaryFileError.cannotRead(url.path)
        }
        let size = values.fileSize ?? 0
        guard size <= maximumSize else {
            throw BinaryFileError.tooLarge(size)
        }
        do {
            self.data = try Data(contentsOf: url, options: [.mappedIfSafe])
        } catch {
            throw BinaryFileError.cannotRead(url.path)
        }
        self.url = url
    }

    public var count: Int { data.count }

    @inline(__always)
    private func require(_ offset: Int, _ length: Int) throws {
        guard offset >= 0, length >= 0, offset <= data.count, length <= data.count - offset else {
            throw BinaryFileError.truncated(needed: offset + length, available: data.count)
        }
    }

    public func uint8(at offset: Int) throws -> UInt8 {
        try require(offset, 1)
        return data[offset]
    }

    public func uint16(at offset: Int) throws -> UInt16 {
        try require(offset, 2)
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    public func uint32(at offset: Int) throws -> UInt32 {
        try require(offset, 4)
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    public func uint64(at offset: Int) throws -> UInt64 {
        try require(offset, 8)
        var value: UInt64 = 0
        for index in 0..<8 {
            value |= UInt64(data[offset + index]) << UInt64(index * 8)
        }
        return value
    }

    public func int32(at offset: Int) throws -> Int32 {
        Int32(bitPattern: try uint32(at: offset))
    }

    public func bytes(at offset: Int, length: Int) throws -> Data {
        try require(offset, length)
        return data.subdata(in: offset..<(offset + length))
    }

    public func magic(at offset: Int = 0, length: Int = 8) throws -> String {
        let raw = try bytes(at: offset, length: length)
        return String(decoding: raw, as: UTF8.self)
    }

    public func string(at offset: Int) throws -> String {
        guard offset >= 0, offset < data.count else {
            throw BinaryFileError.truncated(needed: offset + 1, available: data.count)
        }
        var end = offset
        while end < data.count, data[end] != 0 {
            end += 1
        }
        guard end < data.count else {
            throw BinaryFileError.malformed("unterminated string at offset \(offset)")
        }
        let raw = data.subdata(in: offset..<end)
        guard let value = String(data: raw, encoding: .utf8) else {
            throw BinaryFileError.malformed("invalid UTF-8 string at offset \(offset)")
        }
        return value
    }

    public func checkMagic(_ expected: String, version: UInt32, versionOffset: Int = 8) throws {
        let actual = try magic(length: 8)
        guard actual == expected else {
            throw BinaryFileError.badMagic(expected: expected, actual: actual)
        }
        let actualVersion = try uint32(at: versionOffset)
        guard actualVersion == version else {
            throw BinaryFileError.unsupportedVersion(actualVersion)
        }
    }
}

/// Deterministic little-endian builder used by both tests and the CLI builders.
public struct BinaryWriter {
    public private(set) var data = Data()

    public init() {}

    public mutating func append(_ byte: UInt8) {
        data.append(byte)
    }

    public mutating func append(uint16 value: UInt16) {
        data.append(UInt8(truncatingIfNeeded: value))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
    }

    public mutating func append(uint32 value: UInt32) {
        for shift in stride(from: 0, through: 24, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt32(shift)))
        }
    }

    public mutating func append(uint64 value: UInt64) {
        for shift in stride(from: 0, through: 56, by: 8) {
            data.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }

    public mutating func append(_ string: String) {
        data.append(contentsOf: string.utf8)
    }

    public mutating func append(nullTerminated string: String) {
        append(string)
        append(0)
    }

    public mutating func append(contentsOf other: Data) {
        data.append(other)
    }

    public mutating func padTo(_ alignment: Int, byte: UInt8 = 0) {
        while data.count % alignment != 0 {
            data.append(byte)
        }
    }

    public mutating func patchUInt32(at offset: Int, value: UInt32) {
        guard offset >= 0, offset + 4 <= data.count else { return }
        for index in 0..<4 {
            data[offset + index] = UInt8(truncatingIfNeeded: value >> UInt32(index * 8))
        }
    }

    public mutating func patchUInt64(at offset: Int, value: UInt64) {
        guard offset >= 0, offset + 8 <= data.count else { return }
        for index in 0..<8 {
            data[offset + index] = UInt8(truncatingIfNeeded: value >> UInt64(index * 8))
        }
    }

    public func write(to url: URL, atomic: Bool = true) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: atomic ? [.atomic] : [])
    }
}

/// A null-terminated UTF-8 pool shared by all string tables in a file.
public struct StringPoolBuilder {
    private var pool = Data()
    private var offsets: [String: UInt32] = [:]

    public init() {}

    public mutating func offset(for value: String) -> UInt32 {
        if let existing = offsets[value] { return existing }
        guard pool.count <= Int(UInt32.max) - value.utf8.count - 1 else {
            preconditionFailure("string pool exceeds 4 GiB")
        }
        let offset = UInt32(pool.count)
        pool.append(contentsOf: value.utf8)
        pool.append(0)
        offsets[value] = offset
        return offset
    }

    public var data: Data { pool }
    public var count: Int { pool.count }
}
