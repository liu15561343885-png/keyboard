import PrivateKeyboardCore
import UIKit

final class KeyboardView: UIView {
    var onAction: ((KeyAction) -> Void)?
    var onFeedback: ((KeyAction) -> Void)?
    var onCursorMove: ((Int) -> Void)?
    var onPunctuationLongPress: (([String]) -> Void)?

    private let blurView: UIVisualEffectView
    private let tintView = UIView()
    private let candidateBar = CandidateBarView()
    private let candidatePanel = CandidatePanelView()
    private let rowsStack = UIStackView()
    private var rowsLeadingConstraint: NSLayoutConstraint?
    private var rowsTrailingConstraint: NSLayoutConstraint?
    private var candidatesExpanded = false
    private var currentPage: KeyboardPage = .letters
    private var currentLanguage: InputLanguage = .chinese
    private var isShifted = false
    private var capsLocked = false
    private var returnKeyLabel = "换行"
    private var nineKey = false
    private var nineGrid: UIView?
    private var deleteTimer: Timer?
    private var lastLongPressDeleteEnd: TimeInterval = 0
    private var lastCursorMoveEnd: TimeInterval = 0
    private var cursorAnchorX: CGFloat = 0
    private var cursorRemainder: CGFloat = 0

    override init(frame: CGRect) {
        blurView = UIVisualEffectView(effect: Self.glassEffect())
        super.init(frame: frame)
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = KeyboardTheme.backgroundCornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true

        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        tintView.translatesAutoresizingMaskIntoConstraints = false
        tintView.backgroundColor = KeyboardTheme.background
        tintView.alpha = KeyboardTheme.backgroundOpacity
        tintView.isUserInteractionEnabled = false
        addSubview(tintView)
        addSubview(candidateBar)
        addSubview(candidatePanel)
        candidatePanel.isHidden = true
        rowsStack.axis = .vertical
        rowsStack.alignment = .fill
        rowsStack.distribution = .fillEqually
        rowsStack.spacing = 8
        rowsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowsStack)

        let rowsLeading = rowsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: KeyboardTheme.horizontalMargin)
        let rowsTrailing = rowsStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -KeyboardTheme.horizontalMargin)
        rowsLeadingConstraint = rowsLeading
        rowsTrailingConstraint = rowsTrailing
        NSLayoutConstraint.activate([
            rowsLeading,
            rowsTrailing,
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            tintView.leadingAnchor.constraint(equalTo: leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: trailingAnchor),
            tintView.topAnchor.constraint(equalTo: topAnchor),
            tintView.bottomAnchor.constraint(equalTo: bottomAnchor),

            candidateBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            candidateBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            candidateBar.topAnchor.constraint(equalTo: topAnchor),
            candidateBar.heightAnchor.constraint(equalToConstant: KeyboardTheme.candidateBarHeight),

            rowsStack.topAnchor.constraint(equalTo: candidateBar.bottomAnchor, constant: 4),
            rowsStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),

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

    func applyAppearance() {
        layer.cornerRadius = KeyboardTheme.backgroundCornerRadius
        tintView.alpha = KeyboardTheme.backgroundOpacity
        rowsStack.spacing = 8
        rowsLeadingConstraint?.constant = KeyboardTheme.horizontalMargin
        rowsTrailingConstraint?.constant = -KeyboardTheme.horizontalMargin
        rebuildKeys()
    }

    func update(candidates: [InputCandidate]) {
        candidateBar.update(candidates: candidates)
        candidatePanel.update(candidates: candidates)
        if candidates.isEmpty {
            collapseCandidates()
        }
    }

    private static func glassEffect() -> UIVisualEffect {
        // Built with the iOS 18 SDK, but runs on iOS 26/27. Resolve the native
        // Liquid Glass effect at runtime and fall back to material on older OS.
        if let glassType = NSClassFromString("UIGlassEffect") as? NSObject.Type,
           let effect = glassType.init() as? UIVisualEffect {
            return effect
        }
        return UIBlurEffect(style: .systemUltraThinMaterial)
    }

    func expandCandidates() {
        guard !candidatesExpanded else { return }
        toggleCandidates()
    }

    private func toggleCandidates() {
        guard !candidateBar.isHidden else { return }
        candidatesExpanded.toggle()
        candidateBar.setExpanded(candidatesExpanded)
        candidatePanel.isHidden = !candidatesExpanded
        rowsStack.isHidden = candidatesExpanded
        nineGrid?.isHidden = candidatesExpanded
        onFeedback?(.page(.letters))
    }

    private func collapseCandidates() {
        guard candidatesExpanded else { return }
        candidatesExpanded = false
        candidateBar.setExpanded(false)
        candidatePanel.isHidden = true
        if nineKey, currentPage == .letters, currentLanguage == .chinese {
            rowsStack.isHidden = true
            nineGrid?.isHidden = false
        } else {
            rowsStack.isHidden = false
        }
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
        nineGrid?.removeFromSuperview()
        nineGrid = nil
        for view in rowsStack.arrangedSubviews {
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if nineKey, currentPage == .letters, currentLanguage == .chinese {
            rowsStack.isHidden = true
            buildNineKeyGrid()
            return
        }
        rowsStack.isHidden = false
        let rows = KeyboardLayout.rows(
            page: currentPage,
            language: currentLanguage,
            shifted: isShifted,
            capsLocked: capsLocked,
            returnKeyLabel: returnKeyLabel
        )
        for specs in rows {
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .fill
            row.spacing = KeyboardTheme.keySpacing
            if specs.count == 9, specs.allSatisfy({
                if case .character = $0.action { return true }
                return false
            }) {
                row.isLayoutMarginsRelativeArrangement = true
                row.layoutMargins = UIEdgeInsets(top: 0, left: 19.3, bottom: 0, right: 19.3)
            }
            let weights = specs.map(\.weight)
            let allEqual = weights.dropFirst().allSatisfy { abs($0 - (weights.first ?? 1)) < 0.001 }
            row.distribution = allEqual ? .fillEqually : .fillProportionally
            for spec in specs {
                let button = KeyButton(spec: spec)
                button.onPress = { [weak self] in self?.onFeedback?(spec.action) }
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

    private func buildNineKeyGrid() {
        let grid = UIView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(grid, belowSubview: candidatePanel)
        nineGrid = grid
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor, constant: KeyboardTheme.horizontalMargin),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -KeyboardTheme.horizontalMargin),
            grid.topAnchor.constraint(equalTo: candidateBar.bottomAnchor),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20)
        ])

        var columns: [UILayoutGuide] = []
        for _ in 0..<5 {
            let guide = UILayoutGuide()
            grid.addLayoutGuide(guide)
            columns.append(guide)
        }
        var rows: [UILayoutGuide] = []
        for _ in 0..<4 {
            let guide = UILayoutGuide()
            grid.addLayoutGuide(guide)
            rows.append(guide)
        }
        columns[0].leadingAnchor.constraint(equalTo: grid.leadingAnchor).isActive = true
        rows[0].topAnchor.constraint(equalTo: grid.topAnchor).isActive = true
        for index in 1..<columns.count {
            columns[index].leadingAnchor.constraint(equalTo: columns[index - 1].trailingAnchor).isActive = true
            columns[index].widthAnchor.constraint(equalTo: columns[0].widthAnchor).isActive = true
        }
        for index in 1..<rows.count {
            rows[index].topAnchor.constraint(equalTo: rows[index - 1].bottomAnchor).isActive = true
            rows[index].heightAnchor.constraint(equalTo: rows[0].heightAnchor).isActive = true
        }
        columns.last?.trailingAnchor.constraint(equalTo: grid.trailingAnchor).isActive = true
        rows.last?.bottomAnchor.constraint(equalTo: grid.bottomAnchor).isActive = true

        for cell in KeyboardLayout.nineKeyGrid(returnKeyLabel: returnKeyLabel) {
            let button = KeyButton(spec: cell.spec)
            button.onPress = { [weak self] in self?.onFeedback?(cell.spec.action) }
            let variants = Self.punctuationVariants[cell.spec.label] ?? []
            button.variants = variants
            let event: UIControl.Event = (cell.spec.action == .space || !variants.isEmpty) ? .touchUpInside : .touchDown
            button.addTarget(self, action: #selector(keyTapped(_:)), for: event)
            if !variants.isEmpty {
                let longPress = UILongPressGestureRecognizer(target: self, action: #selector(punctuationLongPressed(_:)))
                longPress.minimumPressDuration = 0.35
                button.addGestureRecognizer(longPress)
            }
            if cell.spec.action == .backspace {
                let longPress = UILongPressGestureRecognizer(target: self, action: #selector(deleteLongPressed(_:)))
                longPress.minimumPressDuration = 0.45
                button.addGestureRecognizer(longPress)
            } else if cell.spec.action == .space {
                let longPress = UILongPressGestureRecognizer(target: self, action: #selector(spaceLongPressed(_:)))
                longPress.minimumPressDuration = 0.3
                button.addGestureRecognizer(longPress)
            }
            grid.addSubview(button)
            let lastColumn = min(columns.count - 1, cell.column + cell.columnSpan - 1)
            let lastRow = min(rows.count - 1, cell.row + cell.rowSpan - 1)
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: columns[cell.column].leadingAnchor),
                button.trailingAnchor.constraint(equalTo: columns[lastColumn].trailingAnchor),
                button.topAnchor.constraint(equalTo: rows[cell.row].topAnchor),
                button.bottomAnchor.constraint(equalTo: rows[lastRow].bottomAnchor)
            ])
        }
    }

    private static let punctuationVariants: [String: [String]] = [
        "，": ["，", "、", "。", "？", "！", "；", "："],
        "。": ["。", "，", "、", "？", "！", "…"],
        "？": ["？", "！", "，", "。"],
        "！": ["！", "？", "，", "。"],
        "-": ["-", "—", "–", "_"],
        ".": [".", "…", "。", "·"],
        ",": [",", "，", "、", "；"]
    ]

    @objc private func punctuationLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let button = gesture.view as? KeyButton, !button.variants.isEmpty else { return }
        onPunctuationLongPress?(button.variants)
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
            onFeedback?(.space)
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
            onFeedback?(.backspace)
            deleteTimer?.invalidate()
            let timer = Timer(timeInterval: 0.09, repeats: true) { [weak self] _ in
                self?.onAction?(.backspace)
                self?.onFeedback?(.backspace)
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
