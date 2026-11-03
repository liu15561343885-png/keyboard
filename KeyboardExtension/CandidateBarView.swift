import PrivateKeyboardCore
import UIKit

final class CandidateBarView: UIView {
    var onSelect: ((InputCandidate) -> Void)?
    var onToggleExpand: (() -> Void)?

    private let capsuleView = UIView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let expandButton = UIButton(type: .system)
    private let separator = UIView()
    private var expanded = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        translatesAutoresizingMaskIntoConstraints = false

        separator.backgroundColor = KeyboardTheme.separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.isHidden = true
        addSubview(separator)

        capsuleView.translatesAutoresizingMaskIntoConstraints = false
        capsuleView.backgroundColor = KeyboardTheme.candidateCapsule
        capsuleView.layer.cornerRadius = 18
        capsuleView.layer.cornerCurve = .continuous
        capsuleView.layer.borderWidth = 0.5
        capsuleView.layer.borderColor = KeyboardTheme.separator.withAlphaComponent(0.5).cgColor
        capsuleView.isUserInteractionEnabled = false
        addSubview(capsuleView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 4)
        addSubview(scrollView)

        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        expandButton.translatesAutoresizingMaskIntoConstraints = false
        expandButton.tintColor = KeyboardTheme.secondaryText
        expandButton.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        expandButton.accessibilityIdentifier = "candidate-expand"
        expandButton.accessibilityLabel = "展开候选"
        expandButton.addTarget(self, action: #selector(toggleTapped), for: .touchUpInside)
        expandButton.isHidden = true
        addSubview(expandButton)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            capsuleView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            capsuleView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            capsuleView.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            capsuleView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),

            expandButton.trailingAnchor.constraint(equalTo: capsuleView.trailingAnchor, constant: -4),
            expandButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            expandButton.widthAnchor.constraint(equalToConstant: 30),
            expandButton.heightAnchor.constraint(equalToConstant: 40),

            scrollView.leadingAnchor.constraint(equalTo: capsuleView.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: expandButton.leadingAnchor, constant: -2),
            scrollView.topAnchor.constraint(equalTo: capsuleView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: capsuleView.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(candidates: [InputCandidate]) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for candidate in candidates {
            let cell = CandidateCell(candidate: candidate)
            cell.addTarget(self, action: #selector(cellTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(cell)
        }
        expandButton.isHidden = candidates.isEmpty
        if candidates.isEmpty, expanded {
            setExpanded(false)
        }
        scrollView.setContentOffset(.zero, animated: false)
        accessibilityLabel = candidates.isEmpty ? "候选栏" : "候选栏，\(candidates.count) 个候选"
    }

    func setExpanded(_ value: Bool) {
        expanded = value
        expandButton.setImage(UIImage(systemName: value ? "chevron.up" : "chevron.down"), for: .normal)
        expandButton.accessibilityLabel = value ? "收起候选" : "展开候选"
    }

    @objc private func toggleTapped() {
        onToggleExpand?()
    }

    @objc private func cellTapped(_ sender: UIControl) {
        guard let cell = sender as? CandidateCell else { return }
        onSelect?(cell.candidate)
    }
}

final class CandidateCell: UIControl {
    let candidate: InputCandidate
    private let firstLine = UILabel()
    private let secondLine = UILabel()

    init(candidate: InputCandidate) {
        self.candidate = candidate
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 7
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "\(candidate.text)，\(candidate.detail)"
        accessibilityIdentifier = "candidate-\(candidate.text)"

        firstLine.text = candidate.text
        firstLine.font = UIFont.systemFont(ofSize: 18, weight: .regular)
        firstLine.textColor = KeyboardTheme.keyText
        firstLine.lineBreakMode = .byTruncatingTail
        firstLine.translatesAutoresizingMaskIntoConstraints = false

        secondLine.text = candidate.detail.isEmpty ? " " : candidate.detail
        secondLine.font = KeyboardTheme.candidateDetailFont
        secondLine.textColor = KeyboardTheme.secondaryText
        secondLine.lineBreakMode = .byTruncatingTail
        secondLine.translatesAutoresizingMaskIntoConstraints = false
        secondLine.isHidden = true

        addSubview(firstLine)
        addSubview(secondLine)

        let width = min(140, max(54, firstLine.intrinsicContentSize.width + 18))
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            firstLine.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            firstLine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            firstLine.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? KeyboardTheme.key.withAlphaComponent(0.5) : .clear }
    }
}

final class CandidatePanelView: UIView {
    var onSelect: ((InputCandidate) -> Void)?
    private let capsuleView = UIView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceVertical = true
        scrollView.contentInset = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        addSubview(scrollView)

        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -16)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(candidates: [InputCandidate]) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        var index = 0
        while index < candidates.count {
            let row = UIStackView()
            row.axis = .horizontal
            row.distribution = .fillEqually
            row.spacing = 6
            for candidate in candidates[index..<min(index + 3, candidates.count)] {
                let cell = CandidatePanelCell(candidate: candidate)
                cell.addTarget(self, action: #selector(cellTapped(_:)), for: .touchUpInside)
                row.addArrangedSubview(cell)
            }
            stack.addArrangedSubview(row)
            index += 3
        }
        scrollView.setContentOffset(.zero, animated: false)
    }

    @objc private func cellTapped(_ sender: UIControl) {
        guard let cell = sender as? CandidatePanelCell else { return }
        onSelect?(cell.candidate)
    }
}

final class CandidatePanelCell: UIControl {
    let candidate: InputCandidate
    private let firstLine = UILabel()
    private let secondLine = UILabel()

    init(candidate: InputCandidate) {
        self.candidate = candidate
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = KeyboardTheme.key
        layer.cornerRadius = 9
        layer.cornerCurve = .continuous
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityIdentifier = "panel-candidate-\(candidate.text)"
        accessibilityLabel = candidate.detail.isEmpty ? candidate.text : "\(candidate.text)，\(candidate.detail)"

        firstLine.text = candidate.text
        firstLine.font = UIFont.systemFont(ofSize: 18, weight: .regular)
        firstLine.textColor = KeyboardTheme.keyText
        firstLine.lineBreakMode = .byTruncatingTail
        firstLine.translatesAutoresizingMaskIntoConstraints = false

        secondLine.text = candidate.detail.isEmpty ? " " : candidate.detail
        secondLine.font = KeyboardTheme.candidateDetailFont
        secondLine.textColor = KeyboardTheme.secondaryText
        secondLine.lineBreakMode = .byTruncatingTail
        secondLine.translatesAutoresizingMaskIntoConstraints = false
        secondLine.isHidden = true

        addSubview(firstLine)
        addSubview(secondLine)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 46),
            firstLine.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            firstLine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            firstLine.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            secondLine.leadingAnchor.constraint(equalTo: firstLine.leadingAnchor),
            secondLine.trailingAnchor.constraint(equalTo: firstLine.trailingAnchor),
            secondLine.topAnchor.constraint(equalTo: firstLine.bottomAnchor, constant: 0),
            secondLine.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? KeyboardTheme.pressedKey : KeyboardTheme.key }
    }
}
