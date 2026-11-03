import Foundation

public enum KeyboardPage: Equatable {
    case letters
    case numbers
    case symbols
    case emoji
}

public enum KeyAction: Equatable {
    case character(String)
    case backspace
    case shift
    case space
    case returnKey
    case nextKeyboard
    case toggleLanguage
    case page(KeyboardPage)
    case emoji(String)
}

public enum KeyStyle: Equatable {
    case letter
    case function
    case accent
    case emoji
}

public struct KeySpec: Equatable {
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

public enum KeyboardLayout {
    private static let emojiRows: [[String]] = [
        ["😀", "😄", "😁", "😂", "🥹", "😊", "😍", "🥰"],
        ["😎", "🤔", "😅", "😭", "😡", "👍", "👏", "🙏"],
        ["❤️", "🔥", "✨", "🎉", "💯", "👌", "🤝", "💪"],
        ["🍜", "☕️", "🌧️", "🌙", "🚗", "🏠", "📱", "💻"]
    ]

    public static func rows(page: KeyboardPage, language: InputLanguage, shifted: Bool) -> [[KeySpec]] {
        switch page {
        case .letters:
            return letterRows(language: language, shifted: shifted)
        case .numbers:
            return numberRows(language: language)
        case .symbols:
            return symbolRows(language: language)
        case .emoji:
            return emojiRows.map { row in row.map { KeySpec($0, .emoji($0), style: .emoji) } }
                + [bottomRow(page: page, language: language)]
        }
    }

    private static func letterRows(language: InputLanguage, shifted: Bool) -> [[KeySpec]] {
        func key(_ character: Character) -> KeySpec {
            let text = shifted ? String(character).uppercased() : String(character)
            return KeySpec(text, .character(text))
        }
        let first = Array("qwertyuiop").map(key)
        let second = Array("asdfghjkl").map(key)
        let third = Array("zxcvbnm").map(key)
        let row3: [KeySpec] = [
            KeySpec(shifted ? "⬆︎" : "⇧", .shift, style: .function, weight: 1.35)
        ] + third + [
            KeySpec("⌫", .backspace, style: .function, weight: 1.35)
        ]
        return [first, second, row3, bottomRow(page: .letters, language: language)]
    }

    private static func numberRows(language: InputLanguage) -> [[KeySpec]] {
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
        return [digits, symbols, third, bottomRow(page: .numbers, language: language)]
    }

    private static func symbolRows(language: InputLanguage) -> [[KeySpec]] {
        let first = Array("[]{}#%^*+=").map { KeySpec(String($0), .character(String($0))) }
        let second = Array("_\\|~<>€£·•").map { KeySpec(String($0), .character(String($0))) }
        let third: [KeySpec] = [
            KeySpec("123", .page(.numbers), style: .function),
            KeySpec(".", .character(".")),
            KeySpec(",", .character(",")),
            KeySpec("?", .character("?")),
            KeySpec("!", .character("!")),
            KeySpec("'", .character("'")),
            KeySpec("⌫", .backspace, style: .function, weight: 1.3)
        ]
        return [first, second, third, bottomRow(page: .symbols, language: language)]
    }

    private static func bottomRow(page: KeyboardPage, language: InputLanguage) -> [KeySpec] {
        let left: KeySpec
        switch page {
        case .letters:
            left = KeySpec("123", .page(.numbers), style: .function)
        case .numbers, .symbols, .emoji:
            left = KeySpec("ABC", .page(.letters), style: .function)
        }
        var keys: [KeySpec] = [
            left,
            KeySpec("🌐", .nextKeyboard, style: .function, weight: 1.0),
            KeySpec("😊", .page(.emoji), style: .function, weight: 0.9)
        ]
        if page == .emoji {
            keys.removeLast()
        }
        keys.append(KeySpec(language == .chinese ? "中" : "EN", .toggleLanguage, style: .function, weight: 1.05))
        keys.append(KeySpec("空格", .space, style: .letter, weight: 4.4))
        keys.append(KeySpec("换行", .returnKey, style: .accent, weight: 1.8))
        return keys
    }
}
