import CryptoKit
import XCTest
@testable import PrivateKeyboardCore
import PrivateKeyboardUpdater

final class UpdateInstallerTests: XCTestCase {
    func testInstallAndRollback() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("PKContainer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let keys = try TestManifest.makeKeyPair()
        let installer = DatasetInstaller(containerURL: container)
        let v1 = try TestManifest.make(version: "1.0.0", built: built, privateKey: keys.privateKey)
        let state1 = try installer.install(
            manifest: v1,
            downloadedFiles: downloadedFiles(from: built),
            publicKeyBase64: keys.publicKey,
            appVersion: "1.0.0",
            osVersion: "17.0"
        )
        XCTAssertEqual(state1.current?.dataVersion, "1.0.0")
        XCTAssertNotNil(installer.paths())

        let v2 = try TestManifest.make(version: "1.0.1", built: built, privateKey: keys.privateKey)
        let state2 = try installer.install(
            manifest: v2,
            downloadedFiles: downloadedFiles(from: built),
            publicKeyBase64: keys.publicKey,
            appVersion: "1.0.0",
            osVersion: "17.0"
        )
        XCTAssertEqual(state2.current?.dataVersion, "1.0.1")
        XCTAssertEqual(state2.previous?.dataVersion, "1.0.0")

        let rolledBack = try installer.rollback()
        XCTAssertEqual(rolledBack.current?.dataVersion, "1.0.0")
        XCTAssertNotNil(installer.paths(for: rolledBack))
    }

    func testHashMismatchIsRejected() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("PKContainer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let keys = try TestManifest.makeKeyPair()
        let manifest = try TestManifest.make(version: "1.0.0", built: built, privateKey: keys.privateKey)
        var downloads = downloadedFiles(from: built)
        let bad = built.directory.appendingPathComponent("bad.bin")
        try Data("not the signed bytes".utf8).write(to: bad)
        downloads[DatasetFile.zhEn.rawValue] = bad
        let installer = DatasetInstaller(containerURL: container)
        XCTAssertThrowsError(
            try installer.install(
                manifest: manifest,
                downloadedFiles: downloads,
                publicKeyBase64: keys.publicKey,
                appVersion: "1.0.0",
                osVersion: "17.0"
            )
        ) { error in
            guard let manifestError = error as? ManifestError,
                  case .sizeMismatch = manifestError
            else {
                return XCTFail("expected size mismatch, got \(error)")
            }
        }
    }

    func testFailedUpdateKeepsPreviousVersion() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("PKContainer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let keys = try TestManifest.makeKeyPair()
        let installer = DatasetInstaller(containerURL: container)
        let v1 = try TestManifest.make(version: "1.0.0", built: built, privateKey: keys.privateKey)
        _ = try installer.install(
            manifest: v1,
            downloadedFiles: downloadedFiles(from: built),
            publicKeyBase64: keys.publicKey,
            appVersion: "1.0.0",
            osVersion: "17.0"
        )
        let v2 = try TestManifest.make(version: "1.0.1", built: built, privateKey: keys.privateKey)
        var downloads = downloadedFiles(from: built)
        let broken = built.directory.appendingPathComponent("broken.bin")
        try Data("broken".utf8).write(to: broken)
        downloads[DatasetFile.zhEn.rawValue] = broken

        XCTAssertThrowsError(
            try installer.install(
                manifest: v2,
                downloadedFiles: downloads,
                publicKeyBase64: keys.publicKey,
                appVersion: "1.0.0",
                osVersion: "17.0"
            )
        )
        XCTAssertEqual(installer.currentState().current?.dataVersion, "1.0.0")
        XCTAssertNotNil(installer.paths())
    }

    func testModelFileVersionIsInstalledAndRolledBack() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("PKContainer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let keys = try TestManifest.makeKeyPair()
        let modelURL = built.directory.appendingPathComponent("candidate_scorer.mlmodel")
        let modelBytes = Data("test-model-bytes".utf8)
        try modelBytes.write(to: modelURL)
        var manifest = try TestManifest.make(version: "3.0.0", built: built, privateKey: keys.privateKey)
        manifest.files.append(
            ManifestFile(
                name: DatasetFile.model.rawValue,
                kind: DatasetFile.model.kind,
                url: "https://example.invalid/candidate_scorer.mlmodel",
                size: Int64(modelBytes.count),
                sha256: FileDigest.sha256Hex(of: modelBytes),
                modelVersion: "test-model-1"
            )
        )
        try Ed25519ManifestSigner.sign(manifest: &manifest, privateKeyBase64: keys.privateKey)
        var downloads = downloadedFiles(from: built)
        downloads[DatasetFile.model.rawValue] = modelURL

        let installer = DatasetInstaller(containerURL: container)
        let state = try installer.install(
            manifest: manifest,
            downloadedFiles: downloads,
            publicKeyBase64: keys.publicKey,
            appVersion: "1.0.0",
            osVersion: "17.0"
        )
        XCTAssertEqual(state.current?.modelVersion, "test-model-1")
        XCTAssertNotNil(installer.paths()?.model)

        let next = try TestManifest.make(version: "3.0.1", built: built, privateKey: keys.privateKey)
        _ = try installer.install(
            manifest: next,
            downloadedFiles: downloadedFiles(from: built),
            publicKeyBase64: keys.publicKey,
            appVersion: "1.0.0",
            osVersion: "17.0"
        )
        let rolledBack = try installer.rollback()
        XCTAssertEqual(rolledBack.current?.dataVersion, "3.0.0")
        XCTAssertEqual(rolledBack.current?.modelVersion, "test-model-1")
        XCTAssertNotNil(installer.paths(for: rolledBack)?.model)
    }

    func testManifestRejectsPathTraversal() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let keys = try TestManifest.makeKeyPair()
        var manifest = try TestManifest.make(version: "1.0.0", built: built, privateKey: keys.privateKey)
        var files = manifest.files
        files[0].name = "../pinyin.bin"
        manifest.files = files
        XCTAssertThrowsError(try manifest.validateStructure()) { error in
            guard let manifestError = error as? ManifestError,
                  case .malformed = manifestError
            else {
                return XCTFail("expected malformed manifest, got \(error)")
            }
        }
    }

    func testIncompatibleMinimumAppVersionIsRejected() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("PKContainer-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let keys = try TestManifest.makeKeyPair()
        var manifest = try TestManifest.make(version: "9.0.0", built: built, privateKey: keys.privateKey)
        manifest.minAppVersion = "9.0.0"
        manifest.signature = ""
        try Ed25519ManifestSigner.sign(manifest: &manifest, privateKeyBase64: keys.privateKey)
        let installer = DatasetInstaller(containerURL: container)
        XCTAssertThrowsError(
            try installer.install(
                manifest: manifest,
                downloadedFiles: downloadedFiles(from: built),
                publicKeyBase64: keys.publicKey,
                appVersion: "1.0.0",
                osVersion: "17.0"
            )
        )
    }

    private func downloadedFiles(from built: TestDataset.Built) -> [String: URL] {
        Dictionary(uniqueKeysWithValues: DatasetFile.required.map {
            ($0.rawValue, built.directory.appendingPathComponent($0.rawValue))
        })
    }
}

enum Curve25519Keys {
    static func newPrivateKey() -> String {
        Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
    }
}
