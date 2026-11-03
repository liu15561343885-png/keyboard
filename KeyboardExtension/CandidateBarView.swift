import PrivateKeyboardCore
import UIKit

final class CandidateBarView: UIView {
    var onSelect: ((InputCandidate) -> Void)?
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private let emptyLabel = UILabel()
    private let separator = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = KeyboardTheme.candidateBackground
        translatesAutoresizingMaskIntoConstraints = false

        separator.backgroundColor = KeyboardTheme.separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
        addSubview(scrollView)

        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        emptyLabel.text = "本地候选"
        emptyLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        emptyLabel.textColor = KeyboardTheme.secondaryText
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),

            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            emptyLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(candidates: [InputCandidate]) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        emptyLabel.isHidden = !candidates.isEmpty
        for candidate in candidates {
            let cell = CandidateCell(candidate: candidate)
            cell.addTarget(self, action: #selector(cellTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(cell)
        }
        scrollView.setContentOffset(.zero, animated: false)
        accessibilityLabel = candidates.isEmpty ? "本地候选栏，无候选" : "候选栏，\(candidates.count) 个候选"
    }

    @objc private func cellTapped(_ sender: UIControl) {
        guard let cell = sender as? CandidateCell else { return }
        onSelect?(cell.candidate)
    }
}

private final class CandidateCell: UIControl {
    let candidate: InputCandidate
    private let firstLine = UILabel()
    private let secondLine = UILabel()

    init(candidate: InputCandidate) {
        self.candidate = candidate
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        layer.cornerRadius = 5
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "\(candidate.text)，\(candidate.detail)"
        accessibilityIdentifier = "candidate-\(candidate.text)"

        firstLine.text = candidate.text
        firstLine.font = KeyboardTheme.candidateFont
        firstLine.textColor = KeyboardTheme.keyText
        firstLine.lineBreakMode = .byTruncatingTail
        firstLine.translatesAutoresizingMaskIntoConstraints = false

        secondLine.text = candidate.detail.isEmpty ? " " : candidate.detail
        secondLine.font = KeyboardTheme.candidateDetailFont
        secondLine.textColor = KeyboardTheme.secondaryText
        secondLine.lineBreakMode = .byTruncatingTail
        secondLine.translatesAutoresizingMaskIntoConstraints = false

        addSubview(firstLine)
        addSubview(secondLine)

        let width = min(172, max(88, max(firstLine.intrinsicContentSize.width, secondLine.intrinsicContentSize.width) + 20))
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: width),
            firstLine.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            firstLine.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            firstLine.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            secondLine.leadingAnchor.constraint(equalTo: firstLine.leadingAnchor),
            secondLine.trailingAnchor.constraint(equalTo: firstLine.trailingAnchor),
            secondLine.topAnchor.constraint(equalTo: firstLine.bottomAnchor, constant: 0),
            secondLine.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -5)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? KeyboardTheme.key.withAlphaComponent(0.5) : .clear }
    }
}
