import CryptoKit
import Foundation

public enum StableHash {
    /// FNV-1a 64. Used only as an opaque n-gram key. A collision can at worst
    /// mix two contextual scores; it can never corrupt user text or dictionary
    /// identities. The builder and runtime share this exact function.
    public static func fnv1a64(_ value: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }

    public static func fnv1a64(_ value: Substring) -> UInt64 {
        fnv1a64(String(value))
    }
}

public enum FileDigest {
    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func sha256Hex(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

public enum SemanticVersion {
    /// Compares dotted integer versions. Non-numeric suffixes are ignored after
    /// the first '-' or '+'. Missing components compare as zero.
    public static func compare(_ lhs: String, _ rhs: String) -> Int {
        func components(_ value: String) -> [Int] {
            let core = value.split(separator: "-", maxSplits: 1).first ?? Substring(value)
            let plusTrimmed = core.split(separator: "+", maxSplits: 1).first ?? core
            return plusTrimmed.split(separator: ".").map { component in
                Int(component.prefix { $0.isNumber }) ?? 0
            }
        }
        let left = components(lhs)
        let right = components(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return -1 }
            if l > r { return 1 }
        }
        return 0
    }

    public static func isAtLeast(_ version: String, minimum: String) -> Bool {
        compare(version, minimum) >= 0
    }
}

public enum BackupExclusion {
    /// Best-effort exclusion from iCloud/iTunes backups for local-only data.
    /// This is not a substitute for iOS Data Protection, but it ensures that
    /// personal frequencies and downloaded datasets are not silently backed up.
    public static func exclude(_ url: URL) {
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutableURL.setResourceValues(values)
    }
}

public enum SharedConstants {
    /// Replace this value together with both entitlements and the bundle IDs in
    /// `project.yml` before shipping. The extension never opens a network
    /// connection; App Groups are its only cross-process channel.
    public static let appGroupIdentifier = "group.com.liu15561343885.privatekeyboard"
    public static let keyboardBundleIdentifier = "com.liu15561343885.privatekeyboard.keyboard"
    public static let datasetDirectoryName = "PrivateKeyboardDatasets"
    public static let settingsSuiteFallback = "PrivateKeyboardSettings"
}

public enum DatasetFile: String, CaseIterable, Sendable {
    case pinyin = "pinyin.bin"
    case zhEn = "dictionary.zh-en.bin"
    case enZh = "dictionary.en-zh.bin"
    case bigram = "lm.bigram.bin"
    case trigram = "lm.trigram.bin"
    case model = "candidate_scorer.mlmodel"

    public var kind: String {
        switch self {
        case .pinyin: return "pinyin"
        case .zhEn: return "zh-en"
        case .enZh: return "en-zh"
        case .bigram, .trigram: return "ngram"
        case .model: return "coreml"
        }
    }

    /// Files that must exist for the keyboard to work. The Core ML model is
    /// optional at runtime: the explainable weighted scorer remains available.
    public static var required: [DatasetFile] {
        [.pinyin, .zhEn, .enZh, .bigram, .trigram]
    }
}

public struct DatasetPaths: Equatable, Sendable {
    public let directory: URL
    public let pinyin: URL
    public let zhEn: URL
    public let enZh: URL
    public let bigram: URL
    public let trigram: URL
    public let model: URL?

    public init(
        directory: URL,
        pinyin: URL,
        zhEn: URL,
        enZh: URL,
        bigram: URL,
        trigram: URL,
        model: URL?
    ) {
        self.directory = directory
        self.pinyin = pinyin
        self.zhEn = zhEn
        self.enZh = enZh
        self.bigram = bigram
        self.trigram = trigram
        self.model = model
    }

    public static func inDirectory(_ directory: URL) -> DatasetPaths? {
        let manager = FileManager.default
        for file in DatasetFile.required {
            let url = directory.appendingPathComponent(file.rawValue)
            guard manager.fileExists(atPath: url.path) else { return nil }
        }
        let sourceModelURL = directory.appendingPathComponent(DatasetFile.model.rawValue)
        let compiledModelURL = directory.appendingPathComponent("candidate_scorer.mlmodelc", isDirectory: true)
        let modelURL: URL?
        if manager.fileExists(atPath: sourceModelURL.path) {
            modelURL = sourceModelURL
        } else if manager.fileExists(atPath: compiledModelURL.path) {
            modelURL = compiledModelURL
        } else {
            modelURL = nil
        }
        return DatasetPaths(
            directory: directory,
            pinyin: directory.appendingPathComponent(DatasetFile.pinyin.rawValue),
            zhEn: directory.appendingPathComponent(DatasetFile.zhEn.rawValue),
            enZh: directory.appendingPathComponent(DatasetFile.enZh.rawValue),
            bigram: directory.appendingPathComponent(DatasetFile.bigram.rawValue),
            trigram: directory.appendingPathComponent(DatasetFile.trigram.rawValue),
            model: modelURL
        )
    }
}
