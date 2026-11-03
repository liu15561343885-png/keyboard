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
print("CATALYST KEYBOARD VIEW SMOKE PASSED")
