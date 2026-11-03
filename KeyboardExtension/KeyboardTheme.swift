import UIKit

enum KeyboardTheme {
    static let background = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 0.55)
            : UIColor(red: 0.82, green: 0.83, blue: 0.85, alpha: 0.55)
    }

    static let candidateBackground = UIColor { _ in .clear }

    static var keyOpacity: CGFloat = 0.88
    static var borderOpacity: CGFloat = 0.25
    static var cornerRadius: CGFloat = 9
    static var backgroundCornerRadius: CGFloat = 16
    static var keyboardHeight: CGFloat = 288
    static var horizontalMargin: CGFloat = 0
    static var keySpacing: CGFloat = 0

    static let key = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.30, green: 0.30, blue: 0.32, alpha: keyOpacity)
            : UIColor.white.withAlphaComponent(keyOpacity)
    }

    static let functionKey = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.23, green: 0.23, blue: 0.25, alpha: keyOpacity * 0.78)
            : UIColor(red: 0.68, green: 0.70, blue: 0.73, alpha: keyOpacity * 0.62)
    }

    static let pressedKey = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.42, green: 0.42, blue: 0.45, alpha: 1)
            : UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
    }

    static let keyText = UIColor.label
    static let secondaryText = UIColor.secondaryLabel
    static let separator = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.08)
            : UIColor.black.withAlphaComponent(0.12)
    }
    static let accent = UIColor.systemBlue

    static let keyFont = UIFont.systemFont(ofSize: 22, weight: .regular)
    static let functionFont = UIFont.systemFont(ofSize: 15, weight: .regular)
    static let candidateFont = UIFont.systemFont(ofSize: 16, weight: .regular)
    static let candidateDetailFont = UIFont.systemFont(ofSize: 10.5, weight: .regular)
    static let candidateBarHeight: CGFloat = 56
    static let keyRowHeight: CGFloat = 43
}
