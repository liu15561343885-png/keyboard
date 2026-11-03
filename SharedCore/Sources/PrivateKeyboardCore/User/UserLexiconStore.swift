import Foundation

public enum UserLexiconError: Error, Equatable, CustomStringConvertible {
    case emptyWord
    case emptyPinyin
    case wordTooLong
    case invalidPinyin
    case duplicate

    public var description: String {
        switch self {
        case .emptyWord: return "自定义词不能为空"
        case .emptyPinyin: return "拼音不能为空"
        case .wordTooLong: return "自定义词不能超过 32 个字符"
        case .invalidPinyin: return "拼音只能包含字母和空格"
        case .duplicate: return "相同的词和拼音已经存在"
        }
    }
}

public struct UserLexiconEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var word: String
    public var pinyin: String
    public var note: String
    public var createdAt: TimeInterval

    public init(
        id: UUID = UUID(),
        word: String,
        pinyin: String,
        note: String = "",
        createdAt: TimeInterval = Date().timeIntervalSince1970
    ) {
        self.id = id
        self.word = word
        self.pinyin = pinyin
        self.note = note
        self.createdAt = createdAt
    }
}

public final class UserLexiconStore {
    public static let maximumEntries = 2_000

    private let fileURL: URL
    private let lock = NSRecursiveLock()
    private var entries: [UserLexiconEntry]

    public init(containerURL: URL) {
        self.fileURL = containerURL.appendingPathComponent("user-lexicon.json")
        self.entries = Self.load(from: fileURL)
    }

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.entries = Self.load(from: fileURL)
    }

    public var allEntries: [UserLexiconEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entries.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    public func add(word: String, pinyin: String, note: String = "") throws -> UserLexiconEntry {
        let cleanWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanWord.isEmpty else { throw UserLexiconError.emptyWord }
        guard cleanWord.count <= 32 else { throw UserLexiconError.wordTooLong }
        let key = Self.normalizedKey(pinyin)
        guard !key.isEmpty else { throw UserLexiconError.emptyPinyin }
        guard key.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == " ") }) else {
            throw UserLexiconError.invalidPinyin
        }
        let cleanNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock()
        defer { lock.unlock() }
        guard !entries.contains(where: { $0.word == cleanWord && $0.pinyin == key }) else {
            throw UserLexiconError.duplicate
        }
        let entry = UserLexiconEntry(word: cleanWord, pinyin: key, note: cleanNote)
        entries.append(entry)
        if entries.count > Self.maximumEntries {
            entries.removeFirst(entries.count - Self.maximumEntries)
        }
        persistLocked()
        return entry
    }

    public func remove(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll { $0.id == id }
        persistLocked()
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
        persistLocked()
    }

    public func reload() {
        lock.lock()
        defer { lock.unlock() }
        entries = Self.load(from: fileURL)
    }

    public static func normalizedKey(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "u:", with: "v")
            .split(whereSeparator: { $0 == " " || $0 == "'" })
            .map { PinyinText.normalizeSyllable(String($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func persistLocked() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: [.atomic])
            BackupExclusion.exclude(fileURL)
        } catch {
            // Keep the in-memory list; a later mutation retries persistence.
        }
    }

    private static func load(from url: URL) -> [UserLexiconEntry] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([UserLexiconEntry].self, from: data)
        else { return [] }
        return decoded
    }
}
