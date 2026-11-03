import XCTest
@testable import PrivateKeyboardCore

final class PinyinTests: XCTestCase {
    private func makeEngine(_ built: TestDataset.Built) throws -> PredictionEngine {
        let history = UserHistoryStore(containerURL: built.directory)
        return try PredictionEngine(
            paths: built.paths,
            userHistory: history,
            fuzzyOptions: .common
        )
    }

    func testContinuousSegmentation() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let inventory = try PinyinInventory(url: built.paths.pinyin)
        let segmenter = PinyinSegmenter(inventory: inventory)
        let results = segmenter.segment("nihaobeijing", fuzzy: .common, limit: 8)
        XCTAssertFalse(results.isEmpty)
        let best = try XCTUnwrap(results.first)
        XCTAssertTrue(best.tokens.contains { $0.surface == "bei" })
        XCTAssertTrue(best.tokens.contains { $0.surface == "jing" })
    }

    func testInitialAbbreviation() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let inventory = try PinyinInventory(url: built.paths.pinyin)
        let segmenter = PinyinSegmenter(inventory: inventory)
        let results = segmenter.segment("nh", fuzzy: .none, limit: 4)
        XCTAssertEqual(results.first?.tokens.map(\.kind), [.initial, .initial])
    }

    func testFuzzyZhongAndZong() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let inventory = try PinyinInventory(url: built.paths.pinyin)
        let segmenter = PinyinSegmenter(inventory: inventory)
        let fuzzy = segmenter.segment("zongguo", fuzzy: FuzzyPinyinOptions(zhZ: true), limit: 4)
        XCTAssertFalse(fuzzy.isEmpty)
    }


    func testEveryConfigurableFuzzyGroup() {
        let inventory = PinyinInventory.fallback
        let options = FuzzyPinyinOptions(
            zhZ: true, chC: true, shS: true, nL: true, fH: true,
            angAn: true, engEn: true, ingIn: true
        )
        let lan = FuzzyPinyin.variants(for: "lan", options: options, inventory: inventory)
        let hang = FuzzyPinyin.variants(for: "hang", options: options, inventory: inventory)
        let cang = FuzzyPinyin.variants(for: "cang", options: options, inventory: inventory)
        let sang = FuzzyPinyin.variants(for: "sang", options: options, inventory: inventory)
        XCTAssertTrue(lan.contains { $0.syllable == "nan" })
        XCTAssertTrue(hang.contains { $0.syllable == "fang" })
        XCTAssertTrue(cang.contains { $0.syllable == "chang" })
        XCTAssertTrue(sang.contains { $0.syllable == "shang" })
        XCTAssertFalse(FuzzyPinyin.variants(for: "lan", options: .none, inventory: inventory).contains { $0.syllable == "nan" })
    }

    func testTopCandidateAndTranslationLine() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let engine = try makeEngine(built)
        let candidates = try engine.predict(input: "nihao", language: .chinese, contextWords: [], limit: 8)
        XCTAssertEqual(candidates.first?.text, "你好")
        XCTAssertTrue(candidates.first?.detail.contains("hello") ?? false)
    }

    func testComposedContinuousPhrase() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let engine = try makeEngine(built)
        let candidates = try engine.predict(input: "nihaobeijing", language: .chinese, contextWords: [], limit: 12)
        XCTAssertTrue(candidates.contains { $0.text == "你好北京" })
    }

    func testFuzzyCandidateGeneration() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let engine = try makeEngine(built)
        let candidates = try engine.predict(input: "zongguo", language: .chinese, contextWords: [], limit: 12)
        XCTAssertTrue(candidates.contains { $0.text == "中国" })
    }

    func testT9DecoderMapsNihao() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let engine = try makeEngine(built)
        let keys = T9PinyinDecoder(inventory: engine.inventory).keys(for: "64426")
        XCTAssertTrue(keys.contains("ni hao"), "decoded keys: \(keys)")
        let candidates = try engine.predictT9(digits: "64426", contextWords: [], limit: 10)
        XCTAssertTrue(candidates.contains { $0.text == "你好" }, "T9 candidates: \(candidates.map(\.text))")
    }

    func testTraditionalScriptPreference() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let engine = try makeEngine(built)
        let simplified = try engine.predict(input: "ai", language: .chinese, contextWords: [], limit: 5)
        let traditional = try engine.predict(
            input: "ai",
            language: .chinese,
            contextWords: [],
            scriptPreference: .traditional,
            limit: 5
        )
        XCTAssertEqual(simplified.first?.text, "爱")
        XCTAssertEqual(traditional.first?.text, "愛")
    }

    func testEnglishToChineseCandidate() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let engine = try makeEngine(built)
        let candidates = try engine.predict(input: "love", language: .english, contextWords: [], limit: 8)
        XCTAssertTrue(candidates.contains { $0.text == "love" && $0.detail.contains("我爱你") })
    }

    func testContextLanguageModelAffectsScore() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let engine = try makeEngine(built)
        let bare = try engine.predict(input: "tianqi", language: .chinese, contextWords: [], limit: 5)
        let contextual = try engine.predict(input: "tianqi", language: .chinese, contextWords: ["今天"], limit: 5)
        let bareScore = try XCTUnwrap(bare.first?.breakdown?.bigram)
        let contextualScore = try XCTUnwrap(contextual.first?.breakdown?.bigram)
        XCTAssertGreaterThan(contextualScore, bareScore)
    }
}
