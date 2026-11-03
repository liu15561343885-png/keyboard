import Foundation
@testable import PrivateKeyboardCore

enum TestDataset {
    struct Built {
        let directory: URL
        let paths: DatasetPaths

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    static func make() throws -> Built {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivateKeyboardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let raw: [(String, String, String, UInt32, String, String)] = [
            ("我", "我", "wo", 900_000, "pron.", "I; me"),
            ("你", "你", "ni", 800_000, "pron.", "you"),
            ("他", "他", "ta", 700_000, "pron.", "he; him"),
            ("好", "好", "hao", 500_000, "adj.", "good; well"),
            ("你好", "你好", "ni hao", 400_000, "phr.", "hello"),
            ("您好", "您好", "nin hao", 100_000, "phr.", "hello (polite)"),
            ("爱", "愛", "ai", 300_000, "v.", "to love"),
            ("我爱你", "我愛你", "wo ai ni", 120_000, "phr.", "I love you"),
            ("我比你", "我比你", "wo bi ni", 40_000, "phr.", "more ... than you"),
            ("卧病", "臥病", "wo bing", 20_000, "v.", "be bedridden"),
            ("中国", "中國", "zhong guo", 450_000, "n.", "China"),
            ("北京", "北京", "bei jing", 350_000, "n.", "Beijing"),
            ("上海", "上海", "shang hai", 250_000, "n.", "Shanghai"),
            ("今天", "今天", "jin tian", 350_000, "n.", "today"),
            ("天气", "天氣", "tian qi", 280_000, "n.", "weather"),
            ("很", "很", "hen", 500_000, "adv.", "very"),
            ("喜欢", "喜歡", "xi huan", 260_000, "v.", "to like"),
            ("谢谢", "謝謝", "xie xie", 280_000, "phr.", "thank you"),
            ("再见", "再見", "zai jian", 200_000, "phr.", "goodbye"),
            ("学习", "學習", "xue xi", 230_000, "v.", "to study"),
            ("工作", "工作", "gong zuo", 240_000, "n.", "work"),
            ("朋友", "朋友", "peng you", 220_000, "n.", "friend"),
            ("点赞", "點讚", "dian zan", 80_000, "v.", "to like a post"),
            ("北", "北", "bei", 20_000, "n.", "north"),
            ("京", "京", "jing", 20_000, "n.", "capital"),
            ("中", "中", "zhong", 20_000, "n.", "middle"),
            ("国", "國", "guo", 20_000, "n.", "country")
        ]

        let entries = raw.map {
            DictionaryBuildEntry(
                simplified: $0.0,
                traditional: $0.1,
                pinyin: $0.2,
                pinyinKey: $0.2,
                frequency: $0.3,
                glosses: [Gloss(partOfSpeech: $0.4, definition: $0.5)]
            )
        }
        try DictionaryBinaryWriter.write(entries: entries, to: directory.appendingPathComponent("dictionary.zh-en.bin"))

        var english: [EnglishBuildEntry] = []
        for item in raw {
            for token in EnglishText.searchTokens(in: item.5) {
                english.append(
                    EnglishBuildEntry(
                        english: token,
                        partOfSpeech: item.4,
                        chinese: item.0,
                        definition: item.5,
                        frequency: item.3
                    )
                )
            }
        }
        try EnglishDictionaryBinaryWriter.write(entries: english, to: directory.appendingPathComponent("dictionary.en-zh.bin"))

        var syllables: [String: UInt32] = [:]
        for item in raw {
            for syllable in item.2.split(separator: " ") {
                syllables[String(syllable), default: 0] &+= item.3
            }
        }
        try PinyinBinaryWriter.write(frequencies: syllables, to: directory.appendingPathComponent("pinyin.bin"))

        let bigrams = [
            BigramBuildEntry(context: "今天", token: "天气", count: 42),
            BigramBuildEntry(context: "天气", token: "很", count: 28),
            BigramBuildEntry(context: "很", token: "好", count: 20),
            BigramBuildEntry(context: "我", token: "爱", count: 16),
            BigramBuildEntry(context: "爱", token: "你", count: 22)
        ]
        let trigrams = [
            TrigramBuildEntry(first: "今天", second: "天气", token: "很", count: 22),
            TrigramBuildEntry(first: "我", second: "爱", token: "你", count: 16)
        ]
        try NGramBinaryWriter.writeBigrams(bigrams, to: directory.appendingPathComponent("lm.bigram.bin"))
        try NGramBinaryWriter.writeTrigrams(trigrams, to: directory.appendingPathComponent("lm.trigram.bin"))

        guard let paths = DatasetPaths.inDirectory(directory) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return Built(directory: directory, paths: paths)
    }
}
