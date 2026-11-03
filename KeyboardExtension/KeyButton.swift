import PrivateKeyboardCore
import UIKit

final class KeyButton: UIControl {
    let action: KeyAction
    private let label = UILabel()
    private let icon = UIImageView()
    private let style: KeyStyle
    private let weight: CGFloat

    var onPress: (() -> Void)?

    init(spec: KeySpec) {
        self.action = spec.action
        self.style = spec.style
        self.weight = max(0.1, spec.weight)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = KeyboardTheme.cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = Self.identifier(for: spec)
        accessibilityLabel = Self.accessibilityLabel(for: spec)

        if let iconName = Self.iconName(for: spec) {
            label.isHidden = true
            icon.image = UIImage(systemName: iconName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular))
            icon.contentMode = .scaleAspectFit
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.isUserInteractionEnabled = false
            addSubview(icon)
            NSLayoutConstraint.activate([
                icon.centerXAnchor.constraint(equalTo: centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 24),
                icon.heightAnchor.constraint(equalToConstant: 24)
            ])
        } else {
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
        }
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
            UIView.animate(withDuration: 0.08) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.96, y: 0.96)
                    : .identity
                self.alpha = self.isHighlighted ? 0.82 : 1
            }
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -KeyboardTheme.hitExpansion, dy: -KeyboardTheme.hitExpansion).contains(point)
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
        case .function:
            return KeyboardTheme.functionKey
        case .accent:
            return KeyboardTheme.functionKey
        }
    }

    private static func iconName(for spec: KeySpec) -> String? {
        switch spec.action {
        case .nextKeyboard: return "globe"
        default: return nil
        }
    }

    private static func identifier(for spec: KeySpec) -> String {
        switch spec.action {
        case .nextKeyboard: return "key-nextKeyboard"
        default: return "key-\(spec.label)"
        }
    }

    private static func accessibilityLabel(for spec: KeySpec) -> String {
        switch spec.action {
        case .nextKeyboard: return "下一个键盘"
        default: return spec.label
        }
    }

    private func applyStyle() {
        backgroundColor = normalBackground
        layer.borderWidth = KeyboardTheme.borderOpacity > 0 ? 0.5 : 0
        layer.borderColor = KeyboardTheme.separator.withAlphaComponent(KeyboardTheme.borderOpacity).cgColor
        icon.tintColor = KeyboardTheme.keyText
        switch style {
        case .letter:
            label.textColor = KeyboardTheme.keyText
            label.font = label.text?.count == 1 ? KeyboardTheme.keyFont : KeyboardTheme.functionFont
        case .function:
            label.textColor = KeyboardTheme.keyText
            label.font = KeyboardTheme.functionFont
        case .accent:
            label.textColor = KeyboardTheme.keyText
            label.font = KeyboardTheme.functionFont
        }
    }
}
