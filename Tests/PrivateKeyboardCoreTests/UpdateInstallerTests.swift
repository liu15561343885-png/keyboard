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
