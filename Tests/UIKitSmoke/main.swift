import UIKit
import PrivateKeyboardCore

func allSubviews(_ view: UIView) -> [UIView] {
    [view] + view.subviews.flatMap(allSubviews)
}

let keyboard = KeyboardView(frame: CGRect(x: 0, y: 0, width: 375, height: 288))
keyboard.layoutIfNeeded()
let letterKeys = allSubviews(keyboard).filter { $0 is KeyButton }.count
print("letter page keys:", letterKeys)
precondition(letterKeys == 34, "expected 34 key controls, got \(letterKeys)")

keyboard.configure(page: .numbers, language: .chinese, shifted: false, force: true)
keyboard.layoutIfNeeded()
let numberKeys = allSubviews(keyboard).filter { $0 is KeyButton }.count
print("number page keys:", numberKeys)
precondition(numberKeys == 32, "expected 32 key controls, got \(numberKeys)")

keyboard.configure(page: .emoji, language: .chinese, shifted: false, force: true)
keyboard.layoutIfNeeded()
let emojiKeys = allSubviews(keyboard).filter { $0 is KeyButton }.count
print("emoji page keys:", emojiKeys)
precondition(emojiKeys == 37, "expected 37 key controls, got \(emojiKeys)")

keyboard.configure(page: .letters, language: .chinese, shifted: false, force: true)
keyboard.layoutIfNeeded()
let labelsBefore = allSubviews(keyboard).compactMap { ($0 as? UILabel)?.text }
for expected in ["q", "123", "空格", "换行"] {
    precondition(labelsBefore.contains(expected), "missing key label \(expected)")
}

let lightBackground = KeyboardTheme.background.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
let darkBackground = KeyboardTheme.background.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
precondition(!lightBackground.isEqual(darkBackground), "dark mode background did not resolve differently")

let candidate = InputCandidate(
    id: "test",
    text: "你好",
    detail: "phr. hello",
    kind: .chinese,
    pinyin: "ni hao",
    matchScore: 1,
    entryID: 1,
    baseFrequency: 100,
    glosses: []
)
keyboard.update(candidates: [candidate, candidate, candidate])
keyboard.layoutIfNeeded()
let candidateCells = allSubviews(keyboard).filter { String(describing: type(of: $0)) == "CandidateCell" }
print("candidate cells:", candidateCells.count)
precondition(candidateCells.count == 3, "expected 3 candidate cells, got \(candidateCells.count)")
let candidateLabels = candidateCells.flatMap { allSubviews($0) }.compactMap { ($0 as? UILabel)?.text }
precondition(candidateLabels.contains("你好"), "missing candidate first line")
precondition(candidateLabels.contains("phr. hello"), "missing candidate second line")
if let bar = allSubviews(keyboard).compactMap({ $0 as? CandidateBarView }).first {
    print("candidate bar height:", bar.bounds.height)
    precondition(abs(bar.bounds.height - KeyboardTheme.candidateBarHeight) < 0.5, "unexpected candidate bar height")
} else {
    preconditionFailure("candidate bar not found")
}
print("dark background: \(lightBackground) vs \(darkBackground)")
print("CATALYST KEYBOARD VIEW SMOKE PASSED")
