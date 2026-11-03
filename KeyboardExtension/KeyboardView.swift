import PrivateKeyboardCore
import UIKit

final class KeyboardView: UIView {
    var onAction: ((KeyAction) -> Void)?
    var onFeedback: (() -> Void)?
    var onCursorMove: ((Int) -> Void)?

    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private let candidateBar = CandidateBarView()
    private let candidatePanel = CandidatePanelView()
    private let rowsStack = UIStackView()
    private var candidatesExpanded = false
    private var currentPage: KeyboardPage = .letters
    private var currentLanguage: InputLanguage = .chinese
    private var isShifted = false
    private var capsLocked = false
    private var returnKeyLabel = "换行"
    private var nineKey = false
    private var deleteTimer: Timer?
    private var lastLongPressDeleteEnd: TimeInterval = 0
    private var lastCursorMoveEnd: TimeInterval = 0
    private var cursorAnchorX: CGFloat = 0
    private var cursorRemainder: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.masksToBounds = true

        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        addSubview(candidateBar)
        addSubview(candidatePanel)
        candidatePanel.isHidden = true
        rowsStack.axis = .vertical
        rowsStack.alignment = .fill
        rowsStack.distribution = .fillEqually
        rowsStack.spacing = 7
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowsStack)

        NSLayoutConstraint.activate([
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),

            candidateBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            candidateBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            candidateBar.topAnchor.constraint(equalTo: topAnchor),
            candidateBar.heightAnchor.constraint(equalToConstant: KeyboardTheme.candidateBarHeight),

            rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: KeyboardTheme.horizontalMargin),
            rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -KeyboardTheme.horizontalMargin),
            rowsStack.topAnchor.constraint(equalTo: candidateBar.bottomAnchor, constant: 4),
            rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            candidatePanel.leadingAnchor.constraint(equalTo: leadingAnchor),
            candidatePanel.trailingAnchor.constraint(equalTo: trailingAnchor),
            candidatePanel.topAnchor.constraint(equalTo: candidateBar.bottomAnchor, constant: 4),
            candidatePanel.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        candidateBar.onSelect = { [weak self] candidate in
            self?.collapseCandidates()
            self?.onSelectCandidate?(candidate)
        }
        candidateBar.onToggleExpand = { [weak self] in
            self?.toggleCandidates()
        }
        candidatePanel.onSelect = { [weak self] candidate in
            self?.collapseCandidates()
            self?.onSelectCandidate?(candidate)
        }
        rebuildKeys()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var onSelectCandidate: ((InputCandidate) -> Void)?

    func update(candidates: [InputCandidate]) {
        candidateBar.update(candidates: candidates)
        candidatePanel.update(candidates: candidates)
        if candidates.isEmpty {
            collapseCandidates()
        }
    }

    private func toggleCandidates() {
        guard !candidateBar.isHidden else { return }
        candidatesExpanded.toggle()
        candidateBar.setExpanded(candidatesExpanded)
        candidatePanel.isHidden = !candidatesExpanded
        rowsStack.isHidden = candidatesExpanded
        onFeedback?()
    }

    private func collapseCandidates() {
        guard candidatesExpanded else { return }
        candidatesExpanded = false
        candidateBar.setExpanded(false)
        candidatePanel.isHidden = true
        rowsStack.isHidden = false
    }

    func configure(
        page: KeyboardPage,
        language: InputLanguage,
        shifted: Bool,
        capsLocked: Bool = false,
        returnKeyLabel: String = "换行",
        nineKey: Bool = false,
        force: Bool = false
    ) {
        guard force || page != currentPage || language != currentLanguage || shifted != isShifted
                || capsLocked != self.capsLocked || returnKeyLabel != self.returnKeyLabel
                || nineKey != self.nineKey else { return }
        if page != currentPage || language != currentLanguage {
            collapseCandidates()
        }
        currentPage = page
        currentLanguage = language
        isShifted = shifted
        self.capsLocked = capsLocked
        self.returnKeyLabel = returnKeyLabel
        self.nineKey = nineKey
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
        let rows = KeyboardLayout.rows(
            page: currentPage,
            language: currentLanguage,
            shifted: isShifted,
            capsLocked: capsLocked,
            returnKeyLabel: returnKeyLabel,
            nineKey: nineKey
        )
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
                } else if spec.action == .space {
                    let longPress = UILongPressGestureRecognizer(target: self, action: #selector(spaceLongPressed(_:)))
                    longPress.minimumPressDuration = 0.3
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
        if sender.action == .space,
           Date().timeIntervalSinceReferenceDate - lastCursorMoveEnd < 0.2 {
            return
        }
        onAction?(sender.action)
    }

    @objc private func spaceLongPressed(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            cursorAnchorX = recognizer.location(in: self).x
            cursorRemainder = 0
            onFeedback?()
        case .changed:
            let x = recognizer.location(in: self).x
            let delta = x - cursorAnchorX
            cursorRemainder += delta
            let steps = Int(cursorRemainder / 9)
            if steps != 0 {
                cursorRemainder -= CGFloat(steps * 9)
                onCursorMove?(steps)
            }
            cursorAnchorX = x
        case .ended, .cancelled, .failed:
            lastCursorMoveEnd = Date().timeIntervalSinceReferenceDate
        default:
            break
        }
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
