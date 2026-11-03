import Foundation
import PrivateKeyboardCore

public struct UpdateConfiguration: Equatable, Sendable {
    public var manifestURL: URL?
    public var publicKeyBase64: String?

    public init(manifestURL: URL?, publicKeyBase64: String?) {
        self.manifestURL = manifestURL
        self.publicKeyBase64 = publicKeyBase64
    }

    public var isConfigured: Bool {
        manifestURL != nil && !(publicKeyBase64 ?? "").isEmpty
    }

    public static func load(from bundle: Bundle = .main) -> UpdateConfiguration {
        let rawURL = (bundle.object(forInfoDictionaryKey: "PBManifestURL") as? String) ?? ""
        let url = URL(string: rawURL)
        let key = UpdatePublicKey.load(from: bundle)
        return UpdateConfiguration(manifestURL: url, publicKeyBase64: key)
    }
}

public struct UpdateCheckResult: Sendable {
    public let manifest: UpdateManifest
    public let installedVersion: String
    public var isNewer: Bool { ManifestVersion(manifest.dataVersion) > ManifestVersion(installedVersion) }
}

public final class UpdateService {
    private let installer: DatasetInstaller
    private let configuration: UpdateConfiguration
    private let session: URLSession

    public init(
        installer: DatasetInstaller,
        configuration: UpdateConfiguration,
        session: URLSession = .shared
    ) {
        self.installer = installer
        self.configuration = configuration
        self.session = session
    }

    public func checkForUpdate(currentVersion: String) async throws -> UpdateCheckResult? {
        guard let url = configuration.manifestURL,
              let publicKey = configuration.publicKeyBase64,
              !publicKey.isEmpty
        else {
            return nil
        }
        try Self.validate(url: url)
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response)
        guard data.count <= 2 * 1024 * 1024 else {
            throw ManifestError.malformed("manifest is too large")
        }
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
        try manifest.validateStructure()
        try Ed25519ManifestVerifier.verify(manifest: manifest, publicKeyBase64: publicKey)
        return UpdateCheckResult(manifest: manifest, installedVersion: currentVersion)
    }

    public func install(_ manifest: UpdateManifest, appVersion: String) async throws -> InstalledDatasetState {
        guard let publicKey = configuration.publicKeyBase64, !publicKey.isEmpty else {
            throw ManifestError.missingPublicKey
        }
        try manifest.validateStructure()
        try Ed25519ManifestVerifier.verify(manifest: manifest, publicKeyBase64: publicKey)

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivateKeyboardDownload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        var downloaded: [String: URL] = [:]
        for file in manifest.files {
            guard let url = URL(string: file.url) else {
                throw ManifestError.malformed("invalid download URL for \(file.name)")
            }
            try Self.validate(url: url)
            var request = URLRequest(url: url)
            request.timeoutInterval = 60
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (temporaryURL, response) = try await session.download(for: request)
            try Self.validate(response: response)
            let destination = temporaryDirectory.appendingPathComponent(file.name)
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            let size = Int64((try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1)
            guard size == file.size else {
                throw ManifestError.sizeMismatch(name: file.name, expected: file.size, actual: size)
            }
            let digest = try FileDigest.sha256Hex(ofFileAt: destination)
            guard digest == file.sha256.lowercased() else {
                throw ManifestError.hashMismatch(name: file.name, expected: file.sha256, actual: digest)
            }
            downloaded[file.name] = destination
        }

        return try installer.install(
            manifest: manifest,
            downloadedFiles: downloaded,
            publicKeyBase64: publicKey,
            appVersion: appVersion,
            osVersion: Self.currentOSVersion
        )
    }

    private static var currentOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw DatasetError.installFailed("HTTP \(http.statusCode)")
        }
    }

    private static func validate(url: URL) throws {
        if url.scheme?.lowercased() == "https" { return }
        if url.host == "127.0.0.1" || url.host == "localhost" { return }
        throw ManifestError.insecureURL(url.absoluteString)
    }
}
