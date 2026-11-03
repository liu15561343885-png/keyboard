import CryptoKit
import Foundation
import PrivateKeyboardCore
import PrivateKeyboardUpdater

enum ToolError: Error, CustomStringConvertible {
    case usage(String)
    case badData(String)

    var description: String {
        switch self {
        case .usage(let text): return text
        case .badData(let text): return text
        }
    }
}

struct BuildMetadata: Decodable {
    var dataVersion: String?
    var minAppVersion: String?
    var sourceName: String?
    var sourceURL: String?
    var license: String?
    var attribution: String?
}

func keygen(_ arguments: [String]) throws {
    guard arguments.count == 2 else {
        throw ToolError.usage("keygen <private-key-file> <public-key-file>")
    }
    let privateKey = Curve25519.Signing.PrivateKey()
    let privateBase64 = privateKey.rawRepresentation.base64EncodedString()
    let publicBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()
    try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: arguments[0]).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try (privateBase64 + "\n").write(toFile: arguments[0], atomically: true, encoding: .utf8)
    try (publicBase64 + "\n").write(toFile: arguments[1], atomically: true, encoding: .utf8)
    print("public key: \(publicBase64)")
    print("private key written to \(arguments[0]) — keep it out of git and in a CI secret")
}

func sign(_ arguments: [String]) throws {
    guard arguments.count == 2 || arguments.count == 3 else {
        throw ToolError.usage("sign <manifest.json> <private-key-file> [output.json]")
    }
    let inputURL = URL(fileURLWithPath: arguments[0])
    let outputURL = URL(fileURLWithPath: arguments.count == 3 ? arguments[2] : arguments[0])
    let key = try String(contentsOfFile: arguments[1], encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let data = try Data(contentsOf: inputURL)
    var manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
    try Ed25519ManifestSigner.sign(manifest: &manifest, privateKeyBase64: key)
    try CanonicalJSON.encodePretty(manifest).write(to: outputURL, options: [.atomic])
    print("signed \(outputURL.path)")
}

func publicKey(_ arguments: [String]) throws {
    guard arguments.count == 1 else {
        throw ToolError.usage("public-key <private-key-file>")
    }
    let key = try String(contentsOfFile: arguments[0], encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    print(try Ed25519ManifestSigner.publicKeyBase64(fromPrivateKey: key))
}

func verify(_ arguments: [String]) throws {
    guard arguments.count == 2 else {
        throw ToolError.usage("verify <manifest.json> <public-key-file>")
    }
    let manifest = try JSONDecoder().decode(UpdateManifest.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[0])))
    let key = try String(contentsOfFile: arguments[1], encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    try Ed25519ManifestSigner.verify(manifest: manifest, publicKeyBase64: key)
    print("signature OK: \(manifest.dataVersion)")
}

func make(_ arguments: [String]) throws {
    guard arguments.count == 6 else {
        throw ToolError.usage("make <data-dir> <data-version> <base-url> <min-app-version> <private-key-file> <manifest-out>")
    }
    let directory = URL(fileURLWithPath: arguments[0], isDirectory: true)
    let dataVersion = arguments[1]
    var baseURL = arguments[2]
    if !baseURL.hasSuffix("/") { baseURL += "/" }
    let minAppVersion = arguments[3]
    let key = try String(contentsOfFile: arguments[4], encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let outputURL = URL(fileURLWithPath: arguments[5])

    let metadataURL = directory.appendingPathComponent("dataset.json")
    let metadata: BuildMetadata? = {
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        return try? JSONDecoder().decode(BuildMetadata.self, from: data)
    }()

    var modelVersion = ""
    let modelMetadataURL = directory.appendingPathComponent("candidate_scorer.model.json")
    if let data = try? Data(contentsOf: modelMetadataURL),
       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let value = object["modelVersion"] as? String {
        modelVersion = value
    }

    var files: [ManifestFile] = []
    for file in DatasetFile.allCases {
        let url = directory.appendingPathComponent(file.rawValue)
        guard FileManager.default.fileExists(atPath: url.path) else { continue }
        let size = Int64((try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        let digest = try FileDigest.sha256Hex(ofFileAt: url)
        files.append(
            ManifestFile(
                name: file.rawValue,
                kind: file.kind,
                url: baseURL + file.rawValue,
                size: size,
                sha256: digest,
                compression: "none",
                modelVersion: file == .model ? modelVersion : ""
            )
        )
    }
    guard files.count >= DatasetFile.required.count else {
        throw ToolError.badData("data directory is missing required .bin files")
    }
    let source = ManifestSource(
        name: metadata?.sourceName ?? "PrivateKeyboard",
        url: metadata?.sourceURL ?? "https://github.com/",
        license: metadata?.license ?? "See THIRD_PARTY_LICENSES.md",
        attribution: metadata?.attribution ?? "See THIRD_PARTY_LICENSES.md",
        notes: "Generated by DictionaryBuilder; only hashes and signed assets are published."
    )
    var manifest = UpdateManifest(
        dataVersion: dataVersion,
        minAppVersion: metadata?.minAppVersion ?? minAppVersion,
        minOSVersion: "17.0",
        builtAt: ISO8601DateFormatter().string(from: Date()),
        source: source,
        files: files
    )
    try Ed25519ManifestSigner.sign(manifest: &manifest, privateKeyBase64: key)
    try CanonicalJSON.encodePretty(manifest).write(to: outputURL, options: [.atomic])
    print("manifest: \(outputURL.path)")
    print("files: \(files.count), data version: \(dataVersion)")
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else {
        throw ToolError.usage("commands: keygen | sign | make | public-key | verify")
    }
    switch command {
    case "keygen": try keygen(Array(args.dropFirst()))
    case "sign": try sign(Array(args.dropFirst()))
    case "make": try make(Array(args.dropFirst()))
    case "public-key": try publicKey(Array(args.dropFirst()))
    case "verify": try verify(Array(args.dropFirst()))
    default: throw ToolError.usage("unknown command \(command)")
    }
} catch {
    FileHandle.standardError.write(Data("manifest-tool: \(error)\n".utf8))
    exit(1)
}
