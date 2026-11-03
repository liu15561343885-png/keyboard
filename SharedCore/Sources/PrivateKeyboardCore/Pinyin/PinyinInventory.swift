import Foundation

public enum PinyinText {
    public static func normalizeInput(_ value: String) -> String {
        let folded = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
        var result = ""
        result.reserveCapacity(folded.count)
        for scalar in folded.unicodeScalars {
            if scalar.value >= 97 && scalar.value <= 122 {
                result.unicodeScalars.append(scalar)
            } else if scalar == "'" || scalar == " " || scalar == "’" {
                continue
            } else if scalar.value == 252 { // ü
                result.append("v")
            }
        }
        return result
    }

    public static func normalizeSyllable(_ value: String) -> String {
        var normalized = value
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        normalized = normalized.replacingOccurrences(of: "ü", with: "v")
        normalized = normalized.replacingOccurrences(of: "u:", with: "v")
        normalized = normalized.replacingOccurrences(of: " ", with: "")
        return normalized
    }

    public static func abbreviation(ofKey key: String) -> String {
        key.split(separator: " ").compactMap(\.first).map(String.init).joined()
    }

    public static func abbreviation(ofSyllables syllables: [String]) -> String {
        syllables.compactMap(\.first).map(String.init).joined()
    }

    public static func splitKey(_ key: String) -> [String] {
        key.split(separator: " ").map(String.init)
    }

    public static func displayKey(_ syllables: [String]) -> String {
        syllables.joined(separator: " ")
    }
}

public struct PinyinInventory: Sendable {
    public let frequencies: [String: UInt32]
    public let initials: Set<Character>
    public let maximumSyllableLength: Int

    public init(frequencies: [String: UInt32]) {
        var cleaned: [String: UInt32] = [:]
        for (key, value) in frequencies {
            let normalized = PinyinText.normalizeSyllable(key)
            guard !normalized.isEmpty, normalized.allSatisfy({ $0.isASCII && $0.isLetter }) else { continue }
            cleaned[normalized, default: 0] &+= value
        }
        self.frequencies = cleaned
        self.initials = Set(cleaned.keys.compactMap(\.first))
        self.maximumSyllableLength = cleaned.keys.map(\.count).max() ?? 6
    }

    public init(url: URL) throws {
        let reader = try BinaryReader(url: url)
        guard try reader.magic(length: 8) == "PKPINY01" else {
            throw BinaryFileError.badMagic(expected: "PKPINY01", actual: try reader.magic(length: 8))
        }
        let version = try reader.uint32(at: 8)
        guard version == 1 else {
            throw BinaryFileError.unsupportedVersion(version)
        }
        let count = Int(try reader.uint32(at: 12))
        let tableOffset = Int(try reader.uint64(at: 16))
        let poolOffset = Int(try reader.uint64(at: 24))
        let poolLength = Int(try reader.uint64(at: 32))
        guard tableOffset >= 0,
              tableOffset + count * 8 <= reader.count,
              poolOffset >= 0,
              poolLength >= 0,
              poolOffset + poolLength <= reader.count
        else {
            throw BinaryFileError.malformed("pinyin section bounds")
        }
        var values: [String: UInt32] = [:]
        values.reserveCapacity(count)
        for index in 0..<count {
            let record = tableOffset + index * 8
            let stringOffset = Int(try reader.uint32(at: record))
            let frequency = try reader.uint32(at: record + 4)
            let value = try reader.string(at: poolOffset + stringOffset)
            values[value] = frequency
        }
        self.init(frequencies: values)
    }

    public static let fallback = PinyinInventory(frequencies: StandardPinyinSyllables.frequencies)

    public var syllableCount: Int { frequencies.count }

    public func isSyllable(_ value: String) -> Bool {
        frequencies[value] != nil
    }

    public func isInitial(_ character: Character) -> Bool {
        initials.contains(character)
    }

    public func isPrefixOfSyllable(_ value: String) -> Bool {
        guard !value.isEmpty, value.count < maximumSyllableLength else { return false }
        return frequencies.keys.contains { $0.hasPrefix(value) }
    }

    public func frequency(of value: String) -> UInt32 {
        frequencies[value] ?? 0
    }

    public func firstSyllables() -> [String] {
        frequencies.keys.sorted()
    }
}

public enum StandardPinyinSyllables {
    public static let all: [String] = """
    a ai an ang ao
    ba bai ban bang bao bei ben beng bi bian biang biao bie bin bing bo bu
    ca cai can cang cao ce cen ceng cha chai chan chang chao che chen cheng chi chong chou chu chua chuai chuan chuang chui chun chuo ci cong cou cu cuan cui cun cuo
    da dai dan dang dao de dei den deng di dia dian diao die ding diu dong dou du duan dui dun duo
    e ei en eng er
    fa fan fang fei fen feng fo fou fu
    ga gai gan gang gao ge gei gen geng gong gou gu gua guai guan guang gui gun guo
    ha hai han hang hao he hei hen heng hong hou hu hua huai huan huang hui hun huo
    ji jia jian jiang jiao jie jin jing jiong jiu ju juan jue jun
    ka kai kan kang kao ke ken keng kong kou ku kua kuai kuan kuang kui kun kuo
    la lai lan lang lao le lei leng li lia lian liang liao lie lin ling liu lo long lou lu lv lve luan luo
    ma mai man mang mao me mei men meng mi mian miao mie min ming miu mo mou mu
    na nai nan nang nao ne nei nen neng ni nian niang niao nie nin ning niu nong nou nu nv nve nuan nuo
    o ou
    pa pai pan pang pao pei pen peng pi pian piao pie pin ping po pou pu
    qi qia qian qiang qiao qie qin qing qiong qiu qu quan que qun
    ran rang rao re ren reng ri rong rou ru rua ruan rui run ruo
    sa sai san sang sao se sen seng sha shai shan shang shao she shei shen sheng shi shou shu shua shuai shuan shuang shui shun shuo si song sou su suan sui sun suo
    ta tai tan tang tao te teng ti tian tiao tie ting tong tou tu tuan tui tun tuo
    wa wai wan wang wei wen weng wo wu
    xi xia xian xiang xiao xie xin xing xiong xiu xu xuan xue xun
    ya yan yang yao ye yi yin ying yo yong you yu yuan yue yun
    za zai zan zang zao ze zei zen zeng zha zhai zhan zhang zhao zhe zhen zheng zhi zhong zhou zhu zhua zhuai zhuan zhuang zhui zhun zhuo zi zong zou zu zuan zui zun zuo
    """.split(whereSeparator: \.isWhitespace).map(String.init)

    public static let frequencies: [String: UInt32] = {
        Dictionary(uniqueKeysWithValues: all.map { ($0, 1) })
    }()
}

public enum PinyinBinaryWriter {
    public static func write(frequencies: [String: UInt32], to url: URL) throws {
        let items = frequencies
            .map { (PinyinText.normalizeSyllable($0.key), $0.value) }
            .filter { !$0.0.isEmpty }
            .sorted { $0.0 < $1.0 }
        var pool = StringPoolBuilder()
        var prepared: [(UInt32, UInt32)] = []
        for (syllable, frequency) in items {
            prepared.append((pool.offset(for: syllable), frequency))
        }
        let tableOffset = 40
        let poolOffset = tableOffset + prepared.count * 8
        var writer = BinaryWriter()
        writer.append("PKPINY01")
        writer.append(uint32: 1)
        writer.append(uint32: UInt32(prepared.count))
        writer.append(uint64: UInt64(tableOffset))
        writer.append(uint64: UInt64(poolOffset))
        writer.append(uint64: UInt64(pool.data.count))
        for (offset, frequency) in prepared {
            writer.append(uint32: offset)
            writer.append(uint32: frequency)
        }
        writer.append(contentsOf: pool.data)
        try writer.write(to: url)
    }
}
