import XCTest
@testable import PrivateKeyboardCore

final class BinaryFormatTests: XCTestCase {
    func testDictionaryRoundTripAndPrefixQueries() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let dictionary = try ZhEnDictionary(url: built.paths.zhEn)
        XCTAssertEqual(dictionary.count, 27)
        let exact = try dictionary.entries(matching: "ni hao", index: .full, limit: 5)
        XCTAssertEqual(exact.first?.simplified, "你好")
        let abbreviation = try dictionary.entries(matching: "nh", index: .abbreviation, limit: 5)
        XCTAssertTrue(abbreviation.contains { $0.simplified == "你好" })
        let prefix = try dictionary.prefixEntries(key: "bei", index: .full, limit: 5)
        XCTAssertTrue(prefix.contains { $0.simplified == "北京" })
    }

    func testEnglishDictionaryRoundTrip() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let dictionary = try EnZhDictionary(url: built.paths.enZh)
        let results = try dictionary.prefixEntries(prefix: "love", limit: 10)
        XCTAssertTrue(results.contains { $0.chinese == "我爱你" })
        XCTAssertTrue(results.allSatisfy { !$0.english.isEmpty })
    }

    func testNGramLookups() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let bigram = try BigramLanguageModel(url: built.paths.bigram)
        let trigram = try TrigramLanguageModel(url: built.paths.trigram)
        XCTAssertNotNil(bigram.rawScore(context: "今天", token: "天气"))
        XCTAssertNil(bigram.rawScore(context: "天气", token: "今天"))
        XCTAssertNotNil(trigram.rawScore(first: "今天", second: "天气", token: "很"))
        XCTAssertGreaterThan(bigram.normalizedScore(context: "今天", token: "天气"), 0.5)
    }
}
