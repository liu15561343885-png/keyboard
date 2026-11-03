import Foundation
import PrivateKeyboardCore
import PrivateKeyboardUpdater

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

func section(_ name: String) { print("\n== \(name) ==") }

let generatorDir = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "/tmp/pkgen")
let inventory = try PinyinInventory(url: generatorDir.appendingPathComponent("pinyin.bin"))
let dictionary = try ZhEnDictionary(url: generatorDir.appendingPathComponent("dictionary.zh-en.bin"))
let english = try EnZhDictionary(url: generatorDir.appendingPathComponent("dictionary.en-zh.bin"))
let bigram = try BigramLanguageModel(url: generatorDir.appendingPathComponent("lm.bigram.bin"))
let trigram = try TrigramLanguageModel(url: generatorDir.appendingPathComponent("lm.trigram.bin"))
let segmenter = PinyinSegmenter(inventory: inventory)

section("dictionary")
print("word entries: \(dictionary.count), English senses: \(english.count)")
let nihao = try dictionary.entries(matching: "ni hao", index: .full, limit: 10)
print("ni hao -> \(nihao.map(\.simplified).joined(separator: ","))")
require(nihao.contains { $0.simplified == "你好" }, "ni hao lookup")
let nh = try dictionary.entries(matching: "nh", index: .abbreviation, limit: 10)
print("nh -> \(nh.map(\.simplified).joined(separator: ","))")
require(nh.contains { $0.simplified == "你好" }, "abbreviation lookup")

section("single syllables")
for syllable in ["ni", "hao", "bei", "jing", "wo", "ai"] {
    let entries = try dictionary.entries(matching: syllable, index: .full, limit: 20)
    print("\(syllable): " + entries.map { "\($0.simplified)(\($0.frequency))" }.joined(separator: ","))
}

section("generator seeds")
let seedGen = PinyinCandidateGenerator(dictionary: dictionary, inventory: inventory)
let generated = try seedGen.candidates(for: "nihaobeijing", fuzzy: .common, limit: 80)
print("seeds: " + generated.seeds.prefix(20).map { "\($0.text):\(String(format: "%.2f", $0.matchScore))" }.joined(separator: ","))
print("segs: " + generated.segmentations.prefix(3).map(\.description).joined(separator: " | "))

section("segmentation")
for input in ["nihaobeijing", "nh", "xian", "woaini", "zongguo", "nih"] {
    let result = segmenter.segment(input, limit: 5)
    print("\(input): " + result.prefix(3).map { "\($0.description) [\(String(format: "%.2f", $0.score))]" }.joined(separator: " | "))
    require(!result.isEmpty, "segmentation \(input)")
}

section("language model")
print("P(天气|今天)=\(String(format: "%.3f", bigram.rawScore(context: "今天", token: "天气") ?? 0))")
print("P(很好|今天 天气)=\(String(format: "%.3f", trigram.rawScore(first: "今天", second: "天气", token: "很好") ?? 0))")
require(bigram.rawScore(context: "今天", token: "天气") != nil, "bigram lookup")
require(trigram.rawScore(first: "今天", second: "天气", token: "很好") != nil, "trigram lookup")

section("English lookup")
let love = try english.prefixEntries(prefix: "love", limit: 10)
print("love -> \(love.prefix(6).map { "\($0.english)=\($0.chinese)" }.joined(separator: ", "))")
require(!love.isEmpty, "English prefix lookup")

section("prediction")
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("pk-core-check-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
let user = UserHistoryStore(containerURL: tmp)
let engine = try PredictionEngine(
    paths: DatasetPaths.inDirectory(generatorDir)!,
    userHistory: user
)
for (input, language) in [("nihao", InputLanguage.chinese), ("woaini", .chinese), ("nihaobeijing", .chinese), ("zongguo", .chinese), ("love", .chinese), ("love", .english)] {
    let candidates = try engine.predict(input: input, language: language, contextWords: [], limit: 8)
    print("\(input)/\(language.rawValue): " + candidates.prefix(5).map { "\($0.text)[\($0.detail)] \(String(format: "%.2f", $0.breakdown?.total ?? 0))" }.joined(separator: " | "))
    require(!candidates.isEmpty, "candidates for \(input)")
}
let nihaoCandidates = try engine.predict(input: "nihao", language: .chinese, contextWords: [], limit: 5)
require(nihaoCandidates.first?.text == "你好", "Top-1 nihao should be 你好, got \(nihaoCandidates.first?.text ?? "nil")")
let woaini = try engine.predict(input: "woaini", language: .chinese, contextWords: [], limit: 5)
require(woaini.contains { $0.text == "我爱你" }, "woaini contains 我爱你")
let fuzzy = try engine.predict(input: "zongguo", language: .chinese, contextWords: [], limit: 20)
print("zongguo fuzzy -> \(fuzzy.prefix(8).map(\.text).joined(separator: ","))")
require(fuzzy.contains { $0.text == "中国" }, "fuzzy zongguo -> 中国")

section("user learning")
let base = try engine.predict(input: "wo", language: .chinese, contextWords: [], limit: 20)
print("wo before: \(base.prefix(5).map(\.text).joined(separator: ","))")
user.recordSelection(of: "我比你")
let learned = try engine.predict(input: "wo", language: .chinese, contextWords: ["我"], limit: 20)
print("wo after: \(learned.prefix(5).map(\.text).joined(separator: ","))")
if try dictionary.entries(matching: "wo", index: .full, limit: 500).contains(where: { $0.simplified == "我比你" }) {
    require(learned.contains { $0.text == "我比你" }, "user word appears")
}

section("metrics")
user.clear()
let gold: [(String, String)] = [
    ("nihao", "你好"), ("woaini", "我爱你"), ("zhongguo", "中国"),
    ("beijing", "北京"), ("jintian", "今天"), ("tianqi", "天气"),
    ("xiexie", "谢谢"), ("zaijian", "再见"), ("pengyou", "朋友"),
    ("gongzuo", "工作"), ("xuexi", "学习"), ("nihaobeijing", "你好北京"),
    ("zongguo", "中国"), ("wo", "我"), ("ni", "你"), ("ai", "爱"),
    ("dianzan", "点赞"), ("wobing", "卧病"), ("wobini", "我比你"),
    ("beijinghuanyingni", "北京欢迎你"),
    ("shanghai", "上海"), ("guangzhou", "广州"), ("shenzhen", "深圳"),
    ("mingtian", "明天"), ("zuotian", "昨天"), ("xianzai", "现在"),
    ("shijian", "时间"), ("xuexiao", "学校"), ("xuesheng", "学生"),
    ("laoshi", "老师"), ("shouji", "手机"), ("diannao", "电脑"),
    ("wangluo", "网络"), ("shurufa", "输入法"), ("jianpan", "键盘"),
    ("zhongwen", "中文"), ("yingwen", "英文"), ("fanyi", "翻译"),
    ("ciku", "词库"), ("yinsi", "隐私"), ("anquan", "安全"),
    ("bendi", "本地"), ("zaixian", "在线"), ("gengxin", "更新"),
    ("banben", "版本"), ("duibuqi", "对不起"), ("meiguanxi", "没关系"),
    ("chifan", "吃饭"), ("heshui", "喝水"), ("shuijiao", "睡觉"),
    ("qichuang", "起床"), ("shangban", "上班"), ("xiaban", "下班"),
    ("huijia", "回家"), ("kandianying", "看电影"),
    ("tingyinyue", "听音乐"), ("wanyouxi", "玩游戏"),
    ("yiyuan", "医院"), ("bangzhu", "帮助"), ("xuyao", "需要"),
    ("zhidao", "知道"), ("juede", "觉得"), ("renwei", "认为"),
    ("xiwang", "希望"), ("kaishi", "开始"), ("jieshu", "结束"),
    ("yijing", "已经"), ("zhengzai", "正在"), ("keneng", "可能"),
    ("danshi", "但是"), ("yinwei", "因为"), ("suoyi", "所以"),
    ("ruguo", "如果"), ("haishi", "还是"), ("huozhe", "或者"),
    ("erqie", "而且"), ("suiran", "虽然"), ("ranhou", "然后"),
    ("zuihou", "最后"), ("yiqi", "一起"), ("yidian", "一点"),
    ("yixia", "一下"), ("feichang", "非常"), ("zhende", "真的"),
    ("zhibo", "直播"), ("duanshipin", "短视频"), ("biaoqingbao", "表情包"),
    ("liuliang", "流量"), ("zhongcao", "种草"), ("daka", "打卡"),
    ("wangyou", "网友"), ("resou", "热搜"),
    ("tanmu", "弹幕"), ("neijuan", "内卷"), ("qingxujiazhi", "情绪价值"),
    ("xianyanbao", "显眼包"), ("damoxing", "大模型"), ("duobaan", "多巴胺")
]
var hit1 = 0, hit3 = 0, hit5 = 0
var latencies: [Double] = []
for (input, expected) in gold {
    let started = CFAbsoluteTimeGetCurrent()
    let results = try engine.predict(input: input, language: .chinese, contextWords: [], limit: 5)
    latencies.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
    if results.first?.text == expected { hit1 += 1 }
    if results.prefix(3).contains(where: { $0.text == expected }) { hit3 += 1 }
    if results.contains(where: { $0.text == expected }) { hit5 += 1 }
    if results.first?.text != expected {
        print("metric miss: \(input) expected=\(expected) got=\(results.prefix(3).map(\.text).joined(separator: ","))")
    }
}
let count = Double(gold.count)
latencies.sort()
let mean = latencies.reduce(0, +) / count
let median = latencies[latencies.count / 2]
let p95 = latencies[min(latencies.count - 1, Int(Double(latencies.count - 1) * 0.95))]
print(String(format: "gold n=%.0f top1=%.1f%% top3=%.1f%% top5=%.1f%%", count, Double(hit1)/count*100, Double(hit3)/count*100, Double(hit5)/count*100))
print(String(format: "latency mean=%.2fms median=%.2fms p95=%.2fms max=%.2fms (CoreCheck process, macOS)", mean, median, p95, latencies.last ?? 0))
let engineStart = CFAbsoluteTimeGetCurrent()
let probeEngine = try PredictionEngine(paths: DatasetPaths.inDirectory(generatorDir)!, userHistory: UserHistoryStore(containerURL: tmp), fuzzyOptions: .common)
let initMs = (CFAbsoluteTimeGetCurrent() - engineStart) * 1000
let firstStart = CFAbsoluteTimeGetCurrent()
_ = try probeEngine.predict(input: "nihao", language: .chinese, contextWords: [], limit: 5)
let firstMs = (CFAbsoluteTimeGetCurrent() - firstStart) * 1000
print(String(format: "engine init=%.2fms first prediction=%.2fms (macOS; iOS unmeasured)", initMs, firstMs))
print("model: \(engine.modelStatusDescription)")
print("dictionary: \(dictionary.count) words, \(english.count) English senses, \(inventory.syllableCount) syllables")

let englishQueries = ["love", "hello", "china", "beijing", "weather", "today", "friend", "work", "study", "thank"]
var englishHits = 0
for query in englishQueries {
    if !(try english.prefixEntries(prefix: query, limit: 1)).isEmpty { englishHits += 1 }
}
print(String(format: "English prefix hit rate: %.1f%% (%d/%d)", Double(englishHits)/Double(englishQueries.count)*100, englishHits, englishQueries.count))

section("manifest / installer")
let privateKey = Curve25519Keys.makePrivateKey()
let publicKey = try Ed25519ManifestSigner.publicKeyBase64(fromPrivateKey: privateKey)
var files: [ManifestFile] = []
var downloads: [String: URL] = [:]
for file in DatasetFile.required {
    let url = generatorDir.appendingPathComponent(file.rawValue)
    let size = Int64((try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    let digest = try FileDigest.sha256Hex(ofFileAt: url)
    files.append(ManifestFile(name: file.rawValue, kind: file.kind, url: "https://example.invalid/\(file.rawValue)", size: size, sha256: digest))
    downloads[file.rawValue] = url
}
var manifest = UpdateManifest(
    dataVersion: "test-2",
    minAppVersion: "1.0.0",
    builtAt: ISO8601DateFormatter().string(from: Date()),
    source: ManifestSource(name: "test", url: "https://example.invalid", license: "test", attribution: "test", notes: ""),
    files: files
)
try Ed25519ManifestSigner.sign(manifest: &manifest, privateKeyBase64: privateKey)
try Ed25519ManifestSigner.verify(manifest: manifest, publicKeyBase64: publicKey)
let installer = DatasetInstaller(containerURL: tmp)
let state = try installer.install(
    manifest: manifest,
    downloadedFiles: downloads,
    publicKeyBase64: publicKey,
    appVersion: "1.0.0",
    osVersion: "17.0"
)
require(state.current?.dataVersion == "test-2", "installed version")
require(installer.paths() != nil, "installed paths")
let resolved = DatasetResolver.resolve(containerURL: tmp)
require(resolved?.source == .appGroup, "resolved app group")
print("installed: \(state.current?.directoryName ?? "nil")")

try? FileManager.default.removeItem(at: tmp)
print("\nALL CORE CHECKS PASSED")
