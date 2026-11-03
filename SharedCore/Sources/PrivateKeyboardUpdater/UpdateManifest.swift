import CryptoKit
import Foundation
import PrivateKeyboardCore

public enum ManifestError: Error, Equatable, CustomStringConvertible {
    case malformed(String)
    case unsupportedSchema(Int)
    case incompatibleApp(minimum: String)
    case incompatibleOS(minimum: String)
    case missingPublicKey
    case invalidPublicKey
    case invalidSignature
    case insecureURL(String)
    case missingFile(String)
    case unexpectedFile(String)
    case sizeMismatch(name: String, expected: Int64, actual: Int64)
    case hashMismatch(name: String, expected: String, actual: String)

    public var description: String {
        switch self {
        case .malformed(let reason): return "manifest malformed: \(reason)"
        case .unsupportedSchema(let version): return "unsupported manifest schema: \(version)"
        case .incompatibleApp(let minimum): return "app update required: \(minimum)"
        case .incompatibleOS(let minimum): return "iOS \(minimum) required"
        case .missingPublicKey: return "Ed25519 public key is not configured"
        case .invalidPublicKey: return "Ed25519 public key is invalid"
        case .invalidSignature: return "manifest signature is invalid"
        case .insecureURL(let url): return "dataset URL must use HTTPS: \(url)"
        case .missingFile(let name): return "manifest file missing locally: \(name)"
        case .unexpectedFile(let name): return "unexpected dataset file: \(name)"
        case .sizeMismatch(let name, let expected, let actual):
            return "size mismatch for \(name): expected \(expected), got \(actual)"
        case .hashMismatch(let name, let expected, let actual):
            return "SHA-256 mismatch for \(name): expected \(expected), got \(actual)"
        }
    }
}

public struct ManifestSource: Codable, Equatable, Sendable {
    public var name: String
    public var url: String
    public var license: String
    public var attribution: String
    public var notes: String

    public init(name: String, url: String, license: String, attribution: String, notes: String) {
        self.name = name
        self.url = url
        self.license = license
        self.attribution = attribution
        self.notes = notes
    }
}

public struct ManifestFile: Codable, Equatable, Sendable {
    public var name: String
    public var kind: String
    public var url: String
    public var size: Int64
    public var sha256: String
    public var compression: String
    public var modelVersion: String

    public init(
        name: String,
        kind: String,
        url: String,
        size: Int64,
        sha256: String,
        compression: String = "none",
        modelVersion: String = ""
    ) {
        self.name = name
        self.kind = kind
        self.url = url
        self.size = size
        self.sha256 = sha256
        self.compression = compression
        self.modelVersion = modelVersion
    }
}

public struct UpdateManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var dataVersion: String
    public var minAppVersion: String
    public var minOSVersion: String
    public var builtAt: String
    public var source: ManifestSource
    public var files: [ManifestFile]
    public var signature: String

    public init(
        schemaVersion: Int = 1,
        dataVersion: String,
        minAppVersion: String,
        minOSVersion: String = "17.0",
        builtAt: String,
        source: ManifestSource,
        files: [ManifestFile],
        signature: String = ""
    ) {
        self.schemaVersion = schemaVersion
        self.dataVersion = dataVersion
        self.minAppVersion = minAppVersion
        self.minOSVersion = minOSVersion
        self.builtAt = builtAt
        self.source = source
        self.files = files
        self.signature = signature
    }

    public func validateStructure(requireModel: Bool = false) throws {
        guard schemaVersion == 1 else {
            throw ManifestError.unsupportedSchema(schemaVersion)
        }
        guard !dataVersion.isEmpty, !minAppVersion.isEmpty, !builtAt.isEmpty else {
            throw ManifestError.malformed("missing version or build time")
        }
        var seen = Set<String>()
        for file in files {
            guard !file.name.isEmpty, !file.name.contains("/"), !file.name.contains("..") else {
                throw ManifestError.malformed("unsafe file name: \(file.name)")
            }
            guard seen.insert(file.name).inserted else {
                throw ManifestError.malformed("duplicate file: \(file.name)")
            }
            guard file.size > 0, file.size <= 512 * 1024 * 1024 else {
                throw ManifestError.malformed("invalid size for \(file.name)")
            }
            guard file.sha256.count == 64,
                  file.sha256.allSatisfy({ $0.isHexDigit })
            else {
                throw ManifestError.malformed("invalid SHA-256 for \(file.name)")
            }
            guard file.compression == "none" else {
                throw ManifestError.malformed("unsupported compression for \(file.name)")
            }
        }
        for required in DatasetFile.required {
            if !seen.contains(required.rawValue) {
                throw ManifestError.missingFile(required.rawValue)
            }
        }
        if requireModel, !seen.contains(DatasetFile.model.rawValue) {
            throw ManifestError.missingFile(DatasetFile.model.rawValue)
        }
    }

    public func unsignedPayload() throws -> Data {
        let unsigned = UnsignedUpdateManifest(
            schemaVersion: schemaVersion,
            dataVersion: dataVersion,
            minAppVersion: minAppVersion,
            minOSVersion: minOSVersion,
            builtAt: builtAt,
            source: source,
            files: files
        )
        return try CanonicalJSON.encode(unsigned)
    }
}

public struct UnsignedUpdateManifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var dataVersion: String
    public var minAppVersion: String
    public var minOSVersion: String
    public var builtAt: String
    public var source: ManifestSource
    public var files: [ManifestFile]
}

public enum CanonicalJSON {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    public static func encodePretty<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
}

public enum Ed25519ManifestSigner {
    public static func sign(manifest: inout UpdateManifest, privateKeyBase64: String) throws {
        guard let keyData = Data(base64Encoded: privateKeyBase64), keyData.count == 32 else {
            throw ManifestError.invalidPublicKey
        }
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
        let payload = try manifest.unsignedPayload()
        manifest.signature = try key.signature(for: payload).base64EncodedString()
    }

    public static func publicKeyBase64(fromPrivateKey privateKeyBase64: String) throws -> String {
        guard let keyData = Data(base64Encoded: privateKeyBase64), keyData.count == 32 else {
            throw ManifestError.invalidPublicKey
        }
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
        return key.publicKey.rawRepresentation.base64EncodedString()
    }

    public static func verify(manifest: UpdateManifest, publicKeyBase64: String) throws {
        let trimmed = publicKeyBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ManifestError.missingPublicKey }
        guard let keyData = Data(base64Encoded: trimmed), keyData.count == 32 else {
            throw ManifestError.invalidPublicKey
        }
        guard let signatureData = Data(base64Encoded: manifest.signature), signatureData.count == 64 else {
            throw ManifestError.invalidSignature
        }
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        } catch {
            throw ManifestError.invalidPublicKey
        }
        let payload = try manifest.unsignedPayload()
        guard publicKey.isValidSignature(signatureData, for: payload) else {
            throw ManifestError.invalidSignature
        }
    }
}

public enum UpdatePublicKey {
    public static func load(from bundle: Bundle = .main) -> String? {
        guard let url = bundle.url(forResource: "UpdatePublicKey", withExtension: "txt"),
              let value = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public struct ManifestVersion: Comparable, Sendable {
    public let components: [Int]
    public init(_ value: String) {
        let core = value.split(separator: "-", maxSplits: 1).first ?? Substring(value)
        self.components = core.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }
    public static func < (lhs: ManifestVersion, rhs: ManifestVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let l = index < lhs.components.count ? lhs.components[index] : 0
            let r = index < rhs.components.count ? rhs.components[index] : 0
            if l != r { return l < r }
        }
        return false
    }
    public static func == (lhs: ManifestVersion, rhs: ManifestVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
