import Foundation
import XCTest
@testable import PrivateKeyboardCore

final class QualityMetricsTests: XCTestCase {
    func testSeedTop1Top3AndLatency() throws {
        let built = try TestDataset.make()
        defer { built.remove() }
        let history = UserHistoryStore(containerURL: built.directory)
        let engine = try PredictionEngine(paths: built.paths, userHistory: history, fuzzyOptions: .common)
        let queries: [(String, String)] = [
            ("nihao", "你好"),
            ("woaini", "我爱你"),
            ("zhongguo", "中国"),
            ("beijing", "北京"),
            ("jintian", "今天"),
            ("tianqi", "天气"),
            ("xihuan", "喜欢"),
            ("xiexie", "谢谢"),
            ("zaijian", "再见"),
            ("pengyou", "朋友"),
            ("gongzuo", "工作"),
            ("xuexi", "学习")
        ]
        var top1 = 0
        var top3 = 0
        let start = Date().timeIntervalSinceReferenceDate
        for (input, expected) in queries {
            let candidates = try engine.predict(input: input, language: .chinese, contextWords: [], limit: 5)
            if candidates.first?.text == expected { top1 += 1 }
            if candidates.prefix(3).contains(where: { $0.text == expected }) { top3 += 1 }
        }
        let elapsed = Date().timeIntervalSinceReferenceDate - start
        let top1Rate = Double(top1) / Double(queries.count)
        let top3Rate = Double(top3) / Double(queries.count)
        print("seed quality: top1=\(top1Rate), top3=\(top3Rate), mean=\(elapsed / Double(queries.count) * 1000)ms")
        XCTAssertGreaterThanOrEqual(top1Rate, 0.80)
        XCTAssertGreaterThanOrEqual(top3Rate, 0.95)
        XCTAssertLessThan(elapsed / Double(queries.count), 0.25)
    }
}
