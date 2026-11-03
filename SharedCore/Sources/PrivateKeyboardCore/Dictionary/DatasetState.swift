import Foundation

public struct InstalledRelease: Codable, Equatable, Sendable {
    public var dataVersion: String
    public var directoryName: String
    public var installedAt: String
    public var modelVersion: String
    public var hashes: [String: String]

    public init(
        dataVersion: String,
        directoryName: String,
        installedAt: String,
        modelVersion: String,
        hashes: [String: String]
    ) {
        self.dataVersion = dataVersion
        self.directoryName = directoryName
        self.installedAt = installedAt
        self.modelVersion = modelVersion
        self.hashes = hashes
    }
}

public struct InstalledDatasetState: Codable, Equatable, Sendable {
    public var current: InstalledRelease?
    public var previous: InstalledRelease?

    public init(current: InstalledRelease? = nil, previous: InstalledRelease? = nil) {
        self.current = current
        self.previous = previous
    }
}

/// Reads and writes the small atomic pointer that selects the active dataset.
/// This type intentionally contains no network or update-fetching code, so the
/// keyboard extension can link it without linking any networking library.
public struct DatasetStateStore {
    public let rootURL: URL
    public let stateURL: URL

    public init(containerURL: URL) {
        self.rootURL = containerURL.appendingPathComponent(SharedConstants.datasetDirectoryName, isDirectory: true)
        self.stateURL = rootURL.appendingPathComponent("current.json")
    }

    public func currentState() -> InstalledDatasetState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(InstalledDatasetState.self, from: data)
        else {
            return InstalledDatasetState()
        }
        return state
    }

    public func write(state: InstalledDatasetState) throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: stateURL, options: [.atomic])
    }
}

public enum DatasetResolver {
    public struct Resolved: Equatable, Sendable {
        public let paths: DatasetPaths
        public let version: String
        public let source: Source

        public enum Source: String, Sendable {
            case appGroup
            case bundled
        }
    }

    public static func resolve(
        containerURL: URL? = AppGroup.containerURL(),
        bundle: Bundle = .main
    ) -> Resolved? {
        if let containerURL {
            let store = DatasetStateStore(containerURL: containerURL)
            let state = store.currentState()
            if let current = state.current {
                let directory = store.rootURL
                    .appendingPathComponent("datasets", isDirectory: true)
                    .appendingPathComponent(current.directoryName, isDirectory: true)
                if let paths = DatasetPaths.inDirectory(directory) {
                    return Resolved(paths: paths, version: current.dataVersion, source: .appGroup)
                }
            }
        }
        let version = bundle.object(forInfoDictionaryKey: "PBDataVersion") as? String ?? "bundled-dev"
        for directory in candidateBundleDirectories(bundle) {
            if let paths = DatasetPaths.inDirectory(directory) {
                return Resolved(paths: paths, version: version, source: .bundled)
            }
        }
        return nil
    }

    private static func candidateBundleDirectories(_ bundle: Bundle) -> [URL] {
        var candidates: [URL] = []
        if let resourceURL = bundle.resourceURL {
            candidates.append(resourceURL)
            candidates.append(resourceURL.appendingPathComponent("Generated", isDirectory: true))
            candidates.append(resourceURL.appendingPathComponent("Resources/Generated", isDirectory: true))
        }
        candidates.append(bundle.bundleURL)
        candidates.append(bundle.bundleURL.appendingPathComponent("Generated", isDirectory: true))
        return candidates
    }
}
