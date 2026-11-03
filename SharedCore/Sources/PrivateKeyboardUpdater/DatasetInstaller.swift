import Foundation
import PrivateKeyboardCore

public enum DatasetError: Error, Equatable, CustomStringConvertible {
    case noContainer
    case noBundledDataset
    case invalidState
    case noPreviousVersion
    case installFailed(String)

    public var description: String {
        switch self {
        case .noContainer: return "App Group container is unavailable"
        case .noBundledDataset: return "no bundled dataset found"
        case .invalidState: return "installed dataset state is invalid"
        case .noPreviousVersion: return "no previous dataset version to roll back to"
        case .installFailed(let reason): return "dataset install failed: \(reason)"
        }
    }
}

public final class DatasetInstaller {
    public let containerURL: URL
    public let rootURL: URL
    public let datasetsURL: URL
    public let stateStore: DatasetStateStore

    public init(containerURL: URL) {
        self.containerURL = containerURL
        self.stateStore = DatasetStateStore(containerURL: containerURL)
        self.rootURL = stateStore.rootURL
        self.datasetsURL = stateStore.rootURL.appendingPathComponent("datasets", isDirectory: true)
    }

    public var stateURL: URL { stateStore.stateURL }

    public func currentState() -> InstalledDatasetState {
        stateStore.currentState()
    }

    public func install(
        manifest: UpdateManifest,
        downloadedFiles: [String: URL],
        publicKeyBase64: String,
        appVersion: String,
        osVersion: String,
        now: Date = Date()
    ) throws -> InstalledDatasetState {
        try manifest.validateStructure()
        try Ed25519ManifestVerifier.verify(manifest: manifest, publicKeyBase64: publicKeyBase64)
        guard ManifestVersion(appVersion) >= ManifestVersion(manifest.minAppVersion) else {
            throw ManifestError.incompatibleApp(minimum: manifest.minAppVersion)
        }
        guard ManifestVersion(osVersion) >= ManifestVersion(manifest.minOSVersion) else {
            throw ManifestError.incompatibleOS(minimum: manifest.minOSVersion)
        }

        let allowed = Set(DatasetFile.allCases.map(\.rawValue))
        for file in manifest.files {
            guard allowed.contains(file.name) else {
                throw ManifestError.unexpectedFile(file.name)
            }
        }

        let manager = FileManager.default
        try manager.createDirectory(at: datasetsURL, withIntermediateDirectories: true)
        let staging = rootURL.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        var staged = false
        defer {
            if !staged { try? manager.removeItem(at: staging) }
        }

        for file in manifest.files {
            guard let source = downloadedFiles[file.name] else {
                throw ManifestError.missingFile(file.name)
            }
            let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
            guard Int64(size) == file.size else {
                throw ManifestError.sizeMismatch(name: file.name, expected: file.size, actual: Int64(size))
            }
            let digest = try FileDigest.sha256Hex(ofFileAt: source)
            guard digest == file.sha256.lowercased() else {
                throw ManifestError.hashMismatch(name: file.name, expected: file.sha256, actual: digest)
            }
            let destination = staging.appendingPathComponent(file.name)
            try manager.copyItem(at: source, to: destination)
        }

        // Re-verify the bytes that will be kept, not only the downloaded source.
        for file in manifest.files {
            let stagedURL = staging.appendingPathComponent(file.name)
            let digest = try FileDigest.sha256Hex(ofFileAt: stagedURL)
            guard digest == file.sha256.lowercased() else {
                throw ManifestError.hashMismatch(name: file.name, expected: file.sha256, actual: digest)
            }
        }

        let state = currentState()
        let safeVersion = sanitize(manifest.dataVersion)
        let directoryName = "v-\(safeVersion)-\(UUID().uuidString.lowercased())"
        let finalURL = datasetsURL.appendingPathComponent(directoryName, isDirectory: true)
        try manager.moveItem(at: staging, to: finalURL)
        staged = true

        var hashes: [String: String] = [:]
        var modelVersion = ""
        for file in manifest.files {
            hashes[file.name] = file.sha256.lowercased()
            if file.name == DatasetFile.model.rawValue {
                modelVersion = file.modelVersion
            }
        }
        let release = InstalledRelease(
            dataVersion: manifest.dataVersion,
            directoryName: directoryName,
            installedAt: ISO8601DateFormatter().string(from: now),
            modelVersion: modelVersion,
            hashes: hashes
        )
        let newState = InstalledDatasetState(current: release, previous: state.current)
        do {
            try stateStore.write(state: newState)
        } catch {
            try? manager.removeItem(at: finalURL)
            throw DatasetError.installFailed(error.localizedDescription)
        }
        prune(keeping: [release.directoryName, state.current?.directoryName].compactMap { $0 })
        return newState
    }

    @discardableResult
    public func rollback() throws -> InstalledDatasetState {
        let state = currentState()
        guard let previous = state.previous,
              FileManager.default.fileExists(atPath: datasetsURL.appendingPathComponent(previous.directoryName).path)
        else {
            throw DatasetError.noPreviousVersion
        }
        let oldCurrent = state.current
        let newState = InstalledDatasetState(current: previous, previous: oldCurrent)
        try stateStore.write(state: newState)
        return newState
    }

    public func paths(for state: InstalledDatasetState? = nil) -> DatasetPaths? {
        let state = state ?? currentState()
        guard let current = state.current else { return nil }
        let directory = datasetsURL.appendingPathComponent(current.directoryName, isDirectory: true)
        return DatasetPaths.inDirectory(directory)
    }

    public func clearInstalledDatasets() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    private func prune(keeping names: [String]) {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: datasetsURL,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return }
        for entry in entries {
            let name = entry.lastPathComponent
            guard name.hasPrefix("v-"), !names.contains(name) else { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        let scalars = value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let result = String(scalars).prefix(80)
        return result.isEmpty ? "unknown" : String(result)
    }
}

public enum Ed25519ManifestVerifier {
    public static func verify(manifest: UpdateManifest, publicKeyBase64: String) throws {
        try Ed25519ManifestSigner.verify(manifest: manifest, publicKeyBase64: publicKeyBase64)
    }
}
