import Foundation

public enum KeyboardPage: Equatable, Sendable {
    case letters
    case numbers
    case symbols
    case punctuation
}

public enum KeyAction: Equatable, Sendable {
    case character(String)
    case backspace
    case shift
    case space
    case returnKey
    case nextKeyboard
    case toggleLanguage
    case selectPinyin
    case page(KeyboardPage)
}

public enum KeyStyle: Equatable, Sendable {
    case letter
    case function
    case accent
}

public struct KeySpec: Equatable, Sendable {
    public let label: String
    public let action: KeyAction
    public let style: KeyStyle
    public let weight: CGFloat

    public init(_ label: String, _ action: KeyAction, style: KeyStyle = .letter, weight: CGFloat = 1) {
        self.label = label
        self.action = action
        self.style = style
        self.weight = weight
    }
}

public struct NineKeyCell: Equatable, Sendable {
    public let spec: KeySpec
    public let row: Int
    public let column: Int
    public let rowSpan: Int
    public let columnSpan: Int

    public init(_ spec: KeySpec, row: Int, column: Int, rowSpan: Int = 1, columnSpan: Int = 1) {
        self.spec = spec
        self.row = row
        self.column = column
        self.rowSpan = rowSpan
        self.columnSpan = columnSpan
    }
}

public enum KeyboardLayout {
    public static func rows(
        page: KeyboardPage,
        language: InputLanguage,
        shifted: Bool,
        capsLocked: Bool = false,
        returnKeyLabel: String = "换行"
    ) -> [[KeySpec]] {
        switch page {
        case .letters:
            return letterRows(language: language, shifted: shifted, capsLocked: capsLocked, returnKeyLabel: returnKeyLabel)
        case .numbers:
            return numberRows(language: language, returnKeyLabel: returnKeyLabel)
        case .symbols:
            return symbolRows(language: language, returnKeyLabel: returnKeyLabel)
        case .punctuation:
            return punctuationRows(language: language, returnKeyLabel: returnKeyLabel)
        }
    }

    public static func nineKeyGrid(returnKeyLabel: String) -> [NineKeyCell] {
        [
            NineKeyCell(KeySpec("123", .page(.numbers), style: .function), row: 0, column: 0),
            NineKeyCell(KeySpec("，", .character("，"), style: .function), row: 0, column: 1),
            NineKeyCell(KeySpec("ABC", .character("2")), row: 0, column: 2),
            NineKeyCell(KeySpec("DEF", .character("3")), row: 0, column: 3),
            NineKeyCell(KeySpec("⌫", .backspace, style: .function, weight: 1.0), row: 0, column: 4),

            NineKeyCell(KeySpec("#+=", .page(.symbols), style: .function), row: 1, column: 0),
            NineKeyCell(KeySpec("GHI", .character("4")), row: 1, column: 1),
            NineKeyCell(KeySpec("JKL", .character("5")), row: 1, column: 2),
            NineKeyCell(KeySpec("MNO", .character("6")), row: 1, column: 3),
            NineKeyCell(KeySpec("标点", .page(.punctuation), style: .function), row: 1, column: 4),

            NineKeyCell(KeySpec("中", .toggleLanguage, style: .function), row: 2, column: 0),
            NineKeyCell(KeySpec("PQRS", .character("7")), row: 2, column: 1),
            NineKeyCell(KeySpec("TUV", .character("8")), row: 2, column: 2),
            NineKeyCell(KeySpec("WXYZ", .character("9")), row: 2, column: 3),
            NineKeyCell(KeySpec(returnKeyLabel, .returnKey, style: .accent), row: 2, column: 4, rowSpan: 2),

            NineKeyCell(KeySpec("。", .character("。"), style: .function), row: 3, column: 0),
            NineKeyCell(KeySpec("选拼音", .selectPinyin, style: .function), row: 3, column: 1),
            NineKeyCell(KeySpec("空格", .space, style: .letter), row: 3, column: 2, columnSpan: 2)
        ]
    }

    private static func letterRows(language: InputLanguage, shifted: Bool, capsLocked: Bool, returnKeyLabel: String) -> [[KeySpec]] {
        func key(_ character: Character) -> KeySpec {
            let text = shifted ? String(character).uppercased() : String(character)
            return KeySpec(text, .character(text))
        }
        let first = Array("qwertyuiop").map(key)
        let second = Array("asdfghjkl").map(key)
        let third = Array("zxcvbnm").map(key)
        let shiftLabel = capsLocked ? "⇪" : (shifted ? "⬆︎" : "⇧")
        let row3: [KeySpec] = [
            KeySpec(shiftLabel, .shift, style: .function, weight: 1.35)
        ] + third + [
            KeySpec("⌫", .backspace, style: .function, weight: 1.35)
        ]
        return [first, second, row3, bottomRow(page: .letters, language: language, returnKeyLabel: returnKeyLabel)]
    }

    private static func numberRows(language: InputLanguage, returnKeyLabel: String) -> [[KeySpec]] {
        let digits = Array("1234567890").map { KeySpec(String($0), .character(String($0))) }
        let symbols = Array("-/:;()¥@\"").map { KeySpec(String($0), .character(String($0))) }
        let third: [KeySpec] = [
            KeySpec("#+=", .page(.symbols), style: .function),
            KeySpec(".", .character(".")),
            KeySpec(",", .character(",")),
            KeySpec("?", .character("?")),
            KeySpec("!", .character("!")),
            KeySpec("'", .character("'")),
            KeySpec("⌫", .backspace, style: .function, weight: 1.3)
        ]
        return [digits, symbols, third, bottomRow(page: .numbers, language: language, returnKeyLabel: returnKeyLabel)]
    }

    private static func symbolRows(language: InputLanguage, returnKeyLabel: String) -> [[KeySpec]] {
        let first = Array("[]{}#%^*+=").map { KeySpec(String($0), .character(String($0))) }
        let second = Array("_\\|~<>€£·•").map { KeySpec(String($0), .character(String($0))) }
        let third: [KeySpec] = [
            KeySpec("123", .page(.numbers), style: .function),
            KeySpec(".", .character(".")),
            KeySpec(",", .character(",")),
            KeySpec("?", .character("?")),
            KeySpec("!", .character("!")),
            KeySpec("，。？", .page(.punctuation), style: .function, weight: 1.2),
            KeySpec("⌫", .backspace, style: .function, weight: 1.3)
        ]
        return [first, second, third, bottomRow(page: .symbols, language: language, returnKeyLabel: returnKeyLabel)]
    }

    private static func punctuationRows(language: InputLanguage, returnKeyLabel: String) -> [[KeySpec]] {
        let first = ["，", "。", "？", "！", "、", "；", "：", "（", "）"].map { KeySpec($0, .character($0)) } + [
            KeySpec("⌫", .backspace, style: .function, weight: 1.3)
        ]
        let second = ["“", "”", "‘", "’", "《", "》", "【", "】", "…", "—"].map { KeySpec($0, .character($0)) }
        let third = [
            KeySpec("#+=", .page(.symbols), style: .function),
            KeySpec("～", .character("～")),
            KeySpec("·", .character("·")),
            KeySpec("￥", .character("￥")),
            KeySpec("$", .character("$")),
            KeySpec("€", .character("€")),
            KeySpec("£", .character("£")),
            KeySpec("%", .character("%")),
            KeySpec("‰", .character("‰")),
            KeySpec("@", .character("@"))
        ]
        return [first, second, third, bottomRow(page: .punctuation, language: language, returnKeyLabel: returnKeyLabel)]
    }

    private static func bottomRow(
        page: KeyboardPage,
        language: InputLanguage,
        returnKeyLabel: String
    ) -> [KeySpec] {
        let left: KeySpec
        switch page {
        case .letters:
            left = KeySpec("123", .page(.numbers), style: .function)
        case .numbers, .symbols, .punctuation:
            left = KeySpec("ABC", .page(.letters), style: .function)
        }
        var keys: [KeySpec] = [left]
        keys.append(KeySpec(language == .chinese ? "中" : "EN", .toggleLanguage, style: .function, weight: 1.05))
        keys.append(KeySpec("空格", .space, style: .letter, weight: 4.4))
        keys.append(KeySpec(returnKeyLabel, .returnKey, style: .accent, weight: 1.8))
        return keys
    }
}
