import PrivateKeyboardCore
import UIKit

final class KeyboardView: UIView {
    var onAction: ((KeyAction) -> Void)?
    var onFeedback: (() -> Void)?

    private let candidateBar = CandidateBarView()
    private let rowsStack = UIStackView()
    private var currentPage: KeyboardPage = .letters
    private var currentLanguage: InputLanguage = .chinese
    private var isShifted = false
    private var deleteTimer: Timer?
    private var lastLongPressDeleteEnd: TimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = KeyboardTheme.background
        translatesAutoresizingMaskIntoConstraints = false

        addSubview(candidateBar)
        rowsStack.axis = .vertical
        rowsStack.alignment = .fill
        rowsStack.distribution = .fillEqually
        rowsStack.spacing = 7
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowsStack)

        NSLayoutConstraint.activate([
            candidateBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            candidateBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            candidateBar.topAnchor.constraint(equalTo: topAnchor),
            candidateBar.heightAnchor.constraint(equalToConstant: KeyboardTheme.candidateBarHeight),

            rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: KeyboardTheme.horizontalMargin),
            rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -KeyboardTheme.horizontalMargin),
            rowsStack.topAnchor.constraint(equalTo: candidateBar.bottomAnchor, constant: 4),
            rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4)
        ])
        candidateBar.onSelect = { [weak self] candidate in
            self?.onSelectCandidate?(candidate)
        }
        rebuildKeys()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var onSelectCandidate: ((InputCandidate) -> Void)?

    func update(candidates: [InputCandidate]) {
        candidateBar.update(candidates: candidates)
    }

    func configure(page: KeyboardPage, language: InputLanguage, shifted: Bool, force: Bool = false) {
        guard force || page != currentPage || language != currentLanguage || shifted != isShifted else { return }
        currentPage = page
        currentLanguage = language
        isShifted = shifted
        rebuildKeys()
    }

    deinit {
        deleteTimer?.invalidate()
    }

    private func rebuildKeys() {
        deleteTimer?.invalidate()
        deleteTimer = nil
        for view in rowsStack.arrangedSubviews {
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let rows = KeyboardLayout.rows(page: currentPage, language: currentLanguage, shifted: isShifted)
        for specs in rows {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .fill
            row.spacing = KeyboardTheme.keySpacing
            let weights = specs.map(\.weight)
            let allEqual = weights.dropFirst().allSatisfy { abs($0 - (weights.first ?? 1)) < 0.001 }
            row.distribution = allEqual ? .fillEqually : .fillProportionally
            for spec in specs {
                let button = KeyButton(spec: spec)
                button.onPress = { [weak self] in self?.onFeedback?() }
                button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
                if spec.action == .backspace {
                    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(deleteLongPressed(_:)))
                    longPress.minimumPressDuration = 0.45
                    button.addGestureRecognizer(longPress)
                }
                row.addArrangedSubview(button)
            }
            rowsStack.addArrangedSubview(row)
        }
    }

    @objc private func keyTapped(_ sender: KeyButton) {
        if sender.action == .backspace,
           Date().timeIntervalSinceReferenceDate - lastLongPressDeleteEnd < 0.15 {
            return
        }
        onAction?(sender.action)
    }

    @objc private func deleteLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            onAction?(.backspace)
            onFeedback?()
            deleteTimer?.invalidate()
            let timer = Timer(timeInterval: 0.09, repeats: true) { [weak self] _ in
                self?.onAction?(.backspace)
                self?.onFeedback?()
            }
            RunLoop.main.add(timer, forMode: .common)
            deleteTimer = timer
        case .ended, .cancelled, .failed:
            deleteTimer?.invalidate()
            deleteTimer = nil
            lastLongPressDeleteEnd = Date().timeIntervalSinceReferenceDate
        default:
            break
        }
    }
}
