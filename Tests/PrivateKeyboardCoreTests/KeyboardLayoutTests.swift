import XCTest
@testable import PrivateKeyboardCore

final class KeyboardLayoutTests: XCTestCase {
    func testLetterLayoutContains26KeysAndControls() {
        let rows = KeyboardLayout.rows(page: .letters, language: .chinese, shifted: false)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0].count, 10)
        XCTAssertEqual(rows[1].count, 9)
        XCTAssertEqual(rows[2].count, 9)

        let letters = rows.flatMap { $0 }.compactMap { key -> Character? in
            guard case .character(let value) = key.action, value.count == 1,
                  value.first?.isLetter == true
            else { return nil }
            return value.first
        }
        XCTAssertEqual(letters.count, 26)
        XCTAssertEqual(Set(letters), Set("qwertyuiopasdfghjklzxcvbnm"))

        XCTAssertTrue(rows[2].contains { $0.action == .shift })
        XCTAssertTrue(rows[2].contains { $0.action == .backspace })
        let bottom = rows[3]
        XCTAssertTrue(bottom.contains { $0.action == .space })
        XCTAssertTrue(bottom.contains { $0.action == .returnKey })
        XCTAssertTrue(bottom.contains { $0.action == .toggleLanguage })
        XCTAssertTrue(bottom.contains { $0.action == .page(.numbers) })
    }

    func testShiftedLabels() {
        let lower = KeyboardLayout.rows(page: .letters, language: .english, shifted: false)
        let upper = KeyboardLayout.rows(page: .letters, language: .english, shifted: true)
        XCTAssertEqual(lower[0].first?.label, "q")
        XCTAssertEqual(upper[0].first?.label, "Q")
        XCTAssertTrue(upper[2].contains { $0.action == .shift && $0.label == "⬆︎" })
    }

    func testPunctuationPage() {
        let rows = KeyboardLayout.rows(page: .punctuation, language: .chinese, shifted: false)
        XCTAssertEqual(rows.count, 4)
        let labels = rows.flatMap { $0 }.map(\.label)
        for punctuation in ["，", "。", "？", "！", "、", "；", "：", "（", "）", "“", "”", "《", "》", "…", "—", "￥"] {
            XCTAssertTrue(labels.contains(punctuation), "missing punctuation \(punctuation)")
        }
    }

    func testCapsLockAndDynamicReturnLabel() {
        let rows = KeyboardLayout.rows(
            page: .letters,
            language: .english,
            shifted: true,
            capsLocked: true,
            returnKeyLabel: "搜索"
        )
        XCTAssertTrue(rows.flatMap { $0 }.contains { $0.action == .shift && $0.label == "⇪" })
        XCTAssertTrue(rows.last?.contains { $0.action == .returnKey && $0.label == "搜索" } == true)
    }

    func testNumbersAndSymbols() {
        let numbers = KeyboardLayout.rows(page: .numbers, language: .chinese, shifted: false)
        XCTAssertEqual(numbers[0].count, 10)
        XCTAssertTrue(numbers.flatMap { $0 }.contains { $0.action == .page(.symbols) })
        XCTAssertTrue(numbers[3].contains { $0.action == .page(.letters) })

        let symbols = KeyboardLayout.rows(page: .symbols, language: .english, shifted: false)
        XCTAssertEqual(symbols[0].count, 10)
        XCTAssertEqual(symbols[1].count, 10)
        XCTAssertTrue(symbols.flatMap { $0 }.contains { $0.action == .page(.numbers) })
    }


}
