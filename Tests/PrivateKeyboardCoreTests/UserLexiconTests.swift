import XCTest
@testable import PrivateKeyboardCore

final class UserLexiconTests: XCTestCase {
    func testUserLexiconPersistenceValidationAndBackupExclusion() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PKUserLexicon-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = UserLexiconStore(containerURL: directory)
        let entry = try store.add(word: "测试词", pinyin: "ce shi ci", note: "local note")
        XCTAssertEqual(store.allEntries.count, 1)
        XCTAssertThrowsError(try store.add(word: "测试词", pinyin: "ce shi ci")) { error in
            XCTAssertEqual(error as? UserLexiconError, .duplicate)
        }
        XCTAssertThrowsError(try store.add(word: "词", pinyin: ""))
        XCTAssertThrowsError(try store.add(word: "词", pinyin: "ce shi 1"))
        let reloaded = UserLexiconStore(containerURL: directory)
        XCTAssertEqual(reloaded.allEntries.first?.id, entry.id)
        let backupFlag = try? directory.appendingPathComponent("user-lexicon.json")
            .resourceValues(forKeys: [.isExcludedFromBackupKey])
            .isExcludedFromBackup
        XCTAssertEqual(backupFlag ?? nil, true)
        reloaded.remove(id: entry.id)
        XCTAssertTrue(reloaded.allEntries.isEmpty)
    }

    func testCustomWordBecomesCandidate() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let lexicon = UserLexiconStore(containerURL: built.directory)
        _ = try lexicon.add(word: "测试词", pinyin: "ce shi ci", note: "local note")
        let engine = try PredictionEngine(
            paths: built.paths,
            userHistory: UserHistoryStore(containerURL: built.directory),
            userLexicon: lexicon,
            fuzzyOptions: .common
        )
        let candidates = try engine.predict(input: "ceshici", language: .chinese, contextWords: [], limit: 10)
        XCTAssertEqual(candidates.first?.text, "测试词")
        XCTAssertEqual(candidates.first?.detail, "local note")
    }

    func testCustomWordAbbreviation() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let lexicon = UserLexiconStore(containerURL: built.directory)
        _ = try lexicon.add(word: "测试词", pinyin: "ce shi ci")
        let engine = try PredictionEngine(
            paths: built.paths,
            userHistory: UserHistoryStore(containerURL: built.directory),
            userLexicon: lexicon,
            fuzzyOptions: .common
        )
        let candidates = try engine.predict(input: "csc", language: .chinese, contextWords: [], limit: 10)
        XCTAssertTrue(candidates.contains { $0.text == "测试词" && $0.detail == "自定义词" })
    }
}
