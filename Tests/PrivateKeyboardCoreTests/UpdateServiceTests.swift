import Foundation
import XCTest
@testable import PrivateKeyboardCore
import PrivateKeyboardUpdater

final class UpdateServiceTests: XCTestCase {
    func testCheckForUpdateDownloadsAndVerifiesManifest() async throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let keys = try TestManifest.makeKeyPair()
        let manifest = try TestManifest.make(version: "2.0.0", built: built, privateKey: keys.privateKey)
        let payload = try CanonicalJSON.encode(manifest)

        MockManifestProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/manifest.json")
            return (200, payload)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockManifestProtocol.self]
        let session = URLSession(configuration: configuration)
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("PKUpdateService-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let service = UpdateService(
            installer: DatasetInstaller(containerURL: container),
            configuration: UpdateConfiguration(
                manifestURL: URL(string: "http://127.0.0.1:8080/manifest.json"),
                publicKeyBase64: keys.publicKey
            ),
            session: session
        )
        let result = try await service.checkForUpdate(currentVersion: "1.0.0")
        XCTAssertEqual(result?.manifest.dataVersion, "2.0.0")
        XCTAssertEqual(result?.isNewer, true)
    }

    func testInsecureManifestURLIsRejected() async throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let keys = try TestManifest.makeKeyPair()
        let manifest = try TestManifest.make(version: "2.0.0", built: built, privateKey: keys.privateKey)
        let payload = try CanonicalJSON.encode(manifest)
        MockManifestProtocol.handler = { _ in (200, payload) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockManifestProtocol.self]
        let session = URLSession(configuration: configuration)
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("PKUpdateService-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let service = UpdateService(
            installer: DatasetInstaller(containerURL: container),
            configuration: UpdateConfiguration(
                manifestURL: URL(string: "http://example.com/manifest.json"),
                publicKeyBase64: keys.publicKey
            ),
            session: session
        )
        do {
            _ = try await service.checkForUpdate(currentVersion: "1.0.0")
            XCTFail("insecure URL should be rejected")
        } catch {
            guard let manifestError = error as? ManifestError,
                  case .insecureURL = manifestError
            else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }
}

private final class MockManifestProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
