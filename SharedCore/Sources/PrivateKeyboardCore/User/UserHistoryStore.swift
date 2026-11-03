import Foundation

public struct UserHistorySnapshot: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var frequencies: [String: Int] = [:]
    public var recents: [RecentWord] = []
    public var updatedAt: TimeInterval = 0

    public init(
        schemaVersion: Int = 1,
        frequencies: [String: Int] = [:],
        recents: [RecentWord] = [],
        updatedAt: TimeInterval = 0
    ) {
        self.schemaVersion = schemaVersion
        self.frequencies = frequencies
        self.recents = recents
        self.updatedAt = updatedAt
    }
}

public struct RecentWord: Codable, Equatable, Sendable {
    public var word: String
    public var timestamp: TimeInterval

    public init(word: String, timestamp: TimeInterval) {
        self.word = word
        self.timestamp = timestamp
    }
}

/// Personal word frequencies and recency live only in the App Group container.
/// Nothing here is ever uploaded, logged, or attached to analytics.
public final class UserHistoryStore {
    public static let maximumTrackedWords = 5_000
    public static let maximumRecentWords = 64

    private let fileURL: URL
    private let lock = NSRecursiveLock()
    private var snapshot: UserHistorySnapshot
    private let now: () -> Date

    public init(fileURL: URL, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL
        self.now = now
        self.snapshot = Self.load(from: fileURL)
    }

    public convenience init(containerURL: URL, now: @escaping () -> Date = Date.init) {
        self.init(
            fileURL: containerURL.appendingPathComponent("user-history.json"),
            now: now
        )
    }

    public var currentSnapshot: UserHistorySnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }

    public var trackedWordCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return snapshot.frequencies.count
    }

    public func count(for word: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return snapshot.frequencies[word] ?? 0
    }

    public func normalizedFrequency(for word: String) -> Double {
        lock.lock()
        defer { lock.unlock() }
        let count = snapshot.frequencies[word] ?? 0
        return min(1, log1p(Double(count)) / 6.0)
    }

    public func recencyScore(for word: String) -> Double {
        lock.lock()
        defer { lock.unlock() }
        guard let index = snapshot.recents.firstIndex(where: { $0.word == word }) else {
            return 0
        }
        let rank = Double(index)
        let timestamp = snapshot.recents[index].timestamp
        let age = max(0, now().timeIntervalSince1970 - timestamp)
        let decay = exp(-age / (7 * 24 * 3600))
        return (1.0 / (1.0 + rank)) * (0.5 + 0.5 * decay)
    }

    public func recordSelection(of word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else { return }
        lock.lock()
        let timestamp = now().timeIntervalSince1970
        snapshot.frequencies[trimmed, default: 0] += 1
        snapshot.recents.removeAll { $0.word == trimmed }
        snapshot.recents.insert(RecentWord(word: trimmed, timestamp: timestamp), at: 0)
        if snapshot.recents.count > Self.maximumRecentWords {
            snapshot.recents.removeLast(snapshot.recents.count - Self.maximumRecentWords)
        }
        if snapshot.frequencies.count > Self.maximumTrackedWords {
            let overflow = snapshot.frequencies.count - Self.maximumTrackedWords
            let victims = snapshot.frequencies
                .sorted { $0.value < $1.value }
                .prefix(overflow)
                .map(\.key)
            for victim in victims {
                snapshot.frequencies.removeValue(forKey: victim)
            }
        }
        snapshot.updatedAt = timestamp
        let encoded = snapshot
        lock.unlock()
        persist(encoded)
    }

    public func clear() {
        lock.lock()
        snapshot = UserHistorySnapshot(updatedAt: now().timeIntervalSince1970)
        lock.unlock()
        try? FileManager.default.removeItem(at: fileURL)
    }

    public func reload() {
        lock.lock()
        snapshot = Self.load(from: fileURL)
        lock.unlock()
    }

    private func persist(_ value: UserHistorySnapshot) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(value)
            try data.write(to: fileURL, options: [.atomic])
            BackupExclusion.exclude(fileURL)
        } catch {
            // A failed write must never break typing. The in-memory values stay
            // valid for this session and the next successful write retries.
        }
    }

    private static func load(from url: URL) -> UserHistorySnapshot {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(UserHistorySnapshot.self, from: data)
        else {
            return UserHistorySnapshot()
        }
        return decoded
    }
}

public enum AppGroup {
    public static func containerURL(
        fileManager: FileManager = .default
    ) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: SharedConstants.appGroupIdentifier)
    }

    public static func settingsDefaults(
        suiteName: String = SharedConstants.appGroupIdentifier
    ) -> UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}
