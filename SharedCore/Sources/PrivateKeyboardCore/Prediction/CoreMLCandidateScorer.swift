import CoreML
import Foundation

/// Runs the tiny, replaceable candidate ranker. The model receives only numeric
/// features derived from local dictionary frequency, context n-grams, personal
/// frequency and recency. It never receives raw text beyond those features, and
/// it never performs I/O.
public final class CoreMLCandidateScorer {
    private let model: MLModel
    private let inputNames: [String]
    private let outputName: String
    public let modelVersion: String
    public let sha256: String

    public init(url: URL) throws {
        let compiledURL: URL
        if url.pathExtension == "mlmodelc" {
            compiledURL = url
        } else {
            compiledURL = try MLModel.compileModel(at: url)
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuOnly
        self.model = try MLModel(contentsOf: compiledURL, configuration: configuration)
        self.sha256 = (try? FileDigest.sha256Hex(ofFileAt: url)) ?? "unknown"
        let metadataVersion = model.modelDescription.metadata[.versionString] as? String
        self.modelVersion = metadataVersion ?? "unversioned"
        self.inputNames = CandidateFeatures.featureNames
        self.outputName = model.modelDescription.outputDescriptionsByName.keys.first ?? "score"
    }

    public var identifier: String { "coreml-micro-\(modelVersion)" }

    public func score(features: CandidateFeatures) -> Double? {
        let vector = features.vector
        guard vector.count == inputNames.count else { return nil }
        var dictionary: [String: Any] = [:]
        for (index, name) in inputNames.enumerated() {
            dictionary[name] = NSNumber(value: vector[index])
        }
        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: dictionary)
            let prediction = try model.prediction(from: provider)
            guard let value = prediction.featureValue(for: outputName)?.doubleValue else {
                return nil
            }
            if value.isFinite {
                return max(0, min(1, value))
            }
            return nil
        } catch {
            return nil
        }
    }
}
