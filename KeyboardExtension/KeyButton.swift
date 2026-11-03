import PrivateKeyboardCore
import UIKit

final class KeyButton: UIControl {
    let action: KeyAction
    private let label = UILabel()
    private let style: KeyStyle
    private let weight: CGFloat

    var onPress: (() -> Void)?

    init(spec: KeySpec) {
        self.action = spec.action
        self.style = spec.style
        self.weight = max(0.1, spec.weight)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 5
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = spec.label
        accessibilityIdentifier = "key-\(spec.label)"

        label.text = spec.label
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.65
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        applyStyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: max(28, 42 * weight), height: 44)
    }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted ? KeyboardTheme.pressedKey : normalBackground
        }
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        onPress?()
        return super.beginTracking(touch, with: event)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: layer.cornerRadius).cgPath
    }

    private var normalBackground: UIColor {
        switch style {
        case .letter:
            return KeyboardTheme.key
        case .function, .emoji:
            return KeyboardTheme.functionKey
        case .accent:
            return KeyboardTheme.accent
        }
    }

    private func applyStyle() {
        backgroundColor = normalBackground
        switch style {
        case .letter:
            label.textColor = KeyboardTheme.keyText
            label.font = label.text?.count == 1 ? KeyboardTheme.keyFont : KeyboardTheme.functionFont
        case .function:
            label.textColor = KeyboardTheme.keyText
            label.font = KeyboardTheme.functionFont
        case .accent:
            label.textColor = .white
            label.font = KeyboardTheme.functionFont
        case .emoji:
            label.textColor = KeyboardTheme.keyText
            label.font = UIFont.systemFont(ofSize: 25)
        }
    }
}
