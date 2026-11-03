import Foundation

public protocol PredictionScorer {
    var identifier: String { get }
    func score(features: CandidateFeatures, context: PredictionContext) -> ScoreBreakdown
}

public struct WeightedPredictionScorer: PredictionScorer {
    public var baseWeight: Double
    public var userWeight: Double
    public var recencyWeight: Double
    public var bigramWeight: Double
    public var trigramWeight: Double
    public var pinyinWeight: Double
    public var translationWeight: Double
    public var modelWeight: Double

    public init(
        baseWeight: Double = 1.35,
        userWeight: Double = 1.80,
        recencyWeight: Double = 0.95,
        bigramWeight: Double = 1.05,
        trigramWeight: Double = 1.20,
        pinyinWeight: Double = 2.10,
        translationWeight: Double = 0.15,
        modelWeight: Double = 1.25
    ) {
        self.baseWeight = baseWeight
        self.userWeight = userWeight
        self.recencyWeight = recencyWeight
        self.bigramWeight = bigramWeight
        self.trigramWeight = trigramWeight
        self.pinyinWeight = pinyinWeight
        self.translationWeight = translationWeight
        self.modelWeight = modelWeight
    }

    public var identifier: String { "weighted-explainable-v1" }

    public func score(features: CandidateFeatures, context: PredictionContext) -> ScoreBreakdown {
        var result = ScoreBreakdown()
        result.baseFrequency = features.baseFrequency * baseWeight
        result.userFrequency = features.userFrequency * userWeight
        result.recency = features.recency * recencyWeight
        result.bigram = features.bigram * bigramWeight
        result.trigram = features.trigram * trigramWeight
        result.pinyinMatch = features.pinyinMatch * pinyinWeight
        result.translationAvailability = features.translationAvailability * translationWeight
        result.total = result.baseFrequency
            + result.userFrequency
            + result.recency
            + result.bigram
            + result.trigram
            + result.pinyinMatch
            + result.translationAvailability
        return result
    }
}

/// Blends the explainable scorer with the local Core ML micro-model. If model
/// inference fails at any point, the explainable score is still returned.
public final class HybridPredictionScorer: PredictionScorer {
    public let weighted: WeightedPredictionScorer
    public private(set) var modelScorer: CoreMLCandidateScorer?

    public init(weighted: WeightedPredictionScorer = WeightedPredictionScorer(), model: CoreMLCandidateScorer?) {
        self.weighted = weighted
        self.modelScorer = model
    }

    public var identifier: String {
        if let modelScorer {
            return "hybrid-weighted+\(modelScorer.identifier)"
        }
        return "hybrid-weighted-fallback"
    }

    public var modelStatusDescription: String {
        if let modelScorer {
            return "Core ML \(modelScorer.modelVersion) · \(modelScorer.sha256.prefix(10))"
        }
        return "加权排序（Core ML 不可用）"
    }

    public func score(features: CandidateFeatures, context: PredictionContext) -> ScoreBreakdown {
        var result = weighted.score(features: features, context: context)
        guard let modelScorer, let modelScore = modelScorer.score(features: features) else {
            return result
        }
        result.model = modelScore * weighted.modelWeight
        result.total += result.model
        return result
    }
}
