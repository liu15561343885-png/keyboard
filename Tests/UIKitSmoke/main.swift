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

func keyButton(withLabel label: String) -> KeyButton? {
    allSubviews(keyboard).compactMap { $0 as? KeyButton }.first { button in
        button.subviews.compactMap { ($0 as? UILabel)?.text }.contains(label)
    }
}

var observedActions: [KeyAction] = []
keyboard.onAction = { observedActions.append($0) }
precondition(keyButton(withLabel: "q") != nil, "q key not found")
if let q = keyButton(withLabel: "q") {
    _ = keyboard.perform(NSSelectorFromString("keyTapped:"), with: q)
}
precondition(observedActions == [.character("q")], "q tap did not emit character action")
let deleteKey = keyButton(withLabel: "⌫")
precondition(deleteKey != nil, "delete key not found")
precondition(deleteKey?.gestureRecognizers?.contains { $0 is UILongPressGestureRecognizer } == true, "delete long-press recognizer missing")
print("delete long-press recognizer: present")
precondition(keyButton(withLabel: "123") != nil, "123 key not found")
if let pageKey = keyButton(withLabel: "123") {
    _ = keyboard.perform(NSSelectorFromString("keyTapped:"), with: pageKey)
}
precondition(observedActions.last == .page(.numbers), "123 tap did not emit page action")

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
var manyCandidates = [candidate]
for index in 1..<24 {
    manyCandidates.append(
        InputCandidate(
            id: "test-\(index)",
            text: "候选\(index)",
            detail: "detail \(index)",
            kind: .chinese,
            pinyin: "hou xuan",
            matchScore: 0.5,
            entryID: nil,
            baseFrequency: 1,
            glosses: []
        )
    )
}
keyboard.update(candidates: manyCandidates)
keyboard.layoutIfNeeded()
let candidateCells = allSubviews(keyboard).filter { String(describing: type(of: $0)) == "CandidateCell" }
print("candidate cells:", candidateCells.count)
precondition(candidateCells.count == 24, "expected 24 candidate cells, got \(candidateCells.count)")
let candidateLabels = candidateCells.flatMap { allSubviews($0) }.compactMap { ($0 as? UILabel)?.text }
precondition(candidateLabels.contains("你好"), "missing candidate first line")
precondition(candidateLabels.contains("phr. hello"), "missing candidate second line")
if let bar = allSubviews(keyboard).compactMap({ $0 as? CandidateBarView }).first {
    print("candidate bar height:", bar.bounds.height)
    precondition(abs(bar.bounds.height - KeyboardTheme.candidateBarHeight) < 0.5, "unexpected candidate bar height")
    if let scroll = allSubviews(bar).compactMap({ $0 as? UIScrollView }).first {
        bar.layoutIfNeeded()
        scroll.layoutIfNeeded()
        print("candidate scroll width:", scroll.contentSize.width, "viewport:", scroll.bounds.width)
        fflush(stdout)
        precondition(scroll.contentSize.width > scroll.bounds.width, "candidate bar is not horizontally scrollable")
    } else {
        preconditionFailure("candidate scroll view not found")
    }
} else {
    preconditionFailure("candidate bar not found")
}
print("dark background: \(lightBackground) vs \(darkBackground)")

var selectedCandidate: InputCandidate?
keyboard.onSelectCandidate = { selectedCandidate = $0 }
let cellControl = candidateCells.compactMap { $0 as? UIControl }.first
precondition(cellControl != nil, "candidate control missing")
if let cellControl, let bar = allSubviews(keyboard).compactMap({ $0 as? CandidateBarView }).first {
    _ = bar.perform(NSSelectorFromString("cellTapped:"), with: cellControl)
}
precondition(selectedCandidate?.text == "你好", "candidate tap did not select the expected candidate")
print("key action wiring: q, 123, candidate tap")

let controller = KeyboardViewController()
controller.loadViewIfNeeded()
controller.view.frame = CGRect(x: 0, y: 0, width: 375, height: 288)
controller.view.layoutIfNeeded()
let controllerKeys = allSubviews(controller.view).filter { $0 is KeyButton }.count
print("controller height:", controller.view.bounds.height, "controller keys:", controllerKeys)
precondition(abs(controller.view.bounds.height - 288) < 0.5, "unexpected controller height")
precondition(controllerKeys == 34, "unexpected controller key count")
final class RecordingTextSink: KeyboardTextSink {
    var text = ""
    func insertText(_ value: String) { text += value }
    func deleteBackward() { if !text.isEmpty { text.removeLast() } }
}

let liveSink = RecordingTextSink()
controller.textSinkOverride = liveSink
let controllerKeyboard = allSubviews(controller.view).compactMap { $0 as? KeyboardView }.first
precondition(controllerKeyboard != nil, "controller keyboard view missing")

func tapControllerKey(_ label: String) {
    guard let keyboardView = controllerKeyboard,
          let key = allSubviews(keyboardView).compactMap({ $0 as? KeyButton }).first(where: { button in
              button.subviews.compactMap { ($0 as? UILabel)?.text }.contains(label)
          })
    else { preconditionFailure("controller key not found: \(label)") }
    _ = keyboardView.perform(NSSelectorFromString("keyTapped:"), with: key)
}

for label in ["q", "w", "e", "r", "t"] {
    tapControllerKey(label)
}
print("typed composition:", liveSink.text)
precondition(liveSink.text == "qwert", "unexpected typed composition")
tapControllerKey("⌫")
precondition(liveSink.text == "qwer", "backspace did not delete composition")
tapControllerKey("空格")
print("after space:", "\(liveSink.text)")
precondition(liveSink.text == "qwer ", "space did not commit/clear composition")
print("CATALYST KEYBOARD VIEW SMOKE PASSED")
