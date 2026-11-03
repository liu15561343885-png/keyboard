import XCTest
@testable import PrivateKeyboardCore
import PrivateKeyboardUpdater

final class UserAndScoringTests: XCTestCase {
    func testUserHistoryPersistsAndClears() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PKHistory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = UserHistoryStore(containerURL: directory)
        store.recordSelection(of: "你比你")
        store.recordSelection(of: "你好")
        XCTAssertEqual(store.count(for: "你好"), 1)
        XCTAssertGreaterThan(store.recencyScore(for: "你好"), 0)

        let reloaded = UserHistoryStore(containerURL: directory)
        XCTAssertEqual(reloaded.count(for: "你好"), 1)
        reloaded.clear()
        XCTAssertEqual(reloaded.trackedWordCount, 0)
    }

    func testExplainableWeightedScoreContainsEveryRequestedSignal() {
        let scorer = WeightedPredictionScorer()
        let features = CandidateFeatures(
            baseFrequency: 0.8,
            userFrequency: 0.5,
            recency: 0.4,
            bigram: 0.3,
            trigram: 0.2,
            pinyinMatch: 0.9,
            translationAvailability: 1,
            candidateLength: 0.2,
            contextLength: 0.3
        )
        let context = PredictionContext(previousWords: ["今天"], typedPinyin: "tianqi", language: .chinese)
        let score = scorer.score(features: features, context: context)
        XCTAssertGreaterThan(score.baseFrequency, 0)
        XCTAssertGreaterThan(score.userFrequency, 0)
        XCTAssertGreaterThan(score.recency, 0)
        XCTAssertGreaterThan(score.bigram, 0)
        XCTAssertGreaterThan(score.trigram, 0)
        XCTAssertGreaterThan(score.pinyinMatch, 0)
        XCTAssertGreaterThan(score.translationAvailability, 0)
        XCTAssertGreaterThan(score.total, 0)
    }

    func testUserFrequencyCanPromoteCandidate() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let history = UserHistoryStore(containerURL: built.directory)
        let engine = try PredictionEngine(paths: built.paths, userHistory: history, fuzzyOptions: .common)
        let before = try engine.predict(input: "wo", language: .chinese, contextWords: [], limit: 20)
        XCTAssertNotEqual(before.first?.text, "我比你")
        for _ in 0..<12 { history.recordSelection(of: "我比你") }
        let after = try engine.predict(input: "wo", language: .chinese, contextWords: [], limit: 20)
        XCTAssertEqual(after.first?.text, "我比你")
    }

    func testHybridScorerFallsBackWithoutModel() {
        let scorer = HybridPredictionScorer(model: nil)
        let features = CandidateFeatures(
            baseFrequency: 0.6,
            userFrequency: 0.1,
            recency: 0.1,
            bigram: 0.2,
            trigram: 0.1,
            pinyinMatch: 1.0,
            translationAvailability: 1,
            candidateLength: 0.2,
            contextLength: 0.3
        )
        let context = PredictionContext(previousWords: ["今天"], typedPinyin: "tianqi", language: .chinese)
        let breakdown = scorer.score(features: features, context: context)
        XCTAssertEqual(breakdown.model, 0)
        XCTAssertGreaterThan(breakdown.total, 0)
        XCTAssertTrue(scorer.identifier.contains("fallback"))
    }

    func testManifestSignatureRejectsTampering() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let keyPair = try TestManifest.makeKeyPair()
        var manifest = try TestManifest.make(version: "2.0.0", built: built, privateKey: keyPair.privateKey)
        try Ed25519ManifestSigner.verify(manifest: manifest, publicKeyBase64: keyPair.publicKey)
        manifest.dataVersion = "2.0.1"
        XCTAssertThrowsError(try Ed25519ManifestSigner.verify(manifest: manifest, publicKeyBase64: keyPair.publicKey))
    }
}

enum TestManifest {
    struct KeyPair {
        let privateKey: String
        let publicKey: String
    }

    static func makeKeyPair() throws -> KeyPair {
        let key = Curve25519Keys.newPrivateKey()
        let publicKey = try Ed25519ManifestSigner.publicKeyBase64(fromPrivateKey: key)
        return KeyPair(privateKey: key, publicKey: publicKey)
    }

    static func make(version: String, built: TestDataset.Built, privateKey: String) throws -> UpdateManifest {
        var files: [ManifestFile] = []
        for file in DatasetFile.required {
            let url = built.directory.appendingPathComponent(file.rawValue)
            let size = Int64((try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            let digest = try FileDigest.sha256Hex(ofFileAt: url)
            files.append(
                ManifestFile(
                    name: file.rawValue,
                    kind: file.kind,
                    url: "https://example.invalid/\(file.rawValue)",
                    size: size,
                    sha256: digest
                )
            )
        }
        var manifest = UpdateManifest(
            dataVersion: version,
            minAppVersion: "1.0.0",
            builtAt: ISO8601DateFormatter().string(from: Date()),
            source: ManifestSource(
                name: "Test",
                url: "https://example.invalid",
                license: "test-only",
                attribution: "test",
                notes: ""
            ),
            files: files
        )
        try Ed25519ManifestSigner.sign(manifest: &manifest, privateKeyBase64: privateKey)
        return manifest
    }
}
