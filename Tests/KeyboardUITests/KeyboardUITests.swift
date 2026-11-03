import XCTest

/// End-to-end simulator test for the custom keyboard.
///
/// This scheme is not part of CI. Enable PrivateKeyboard once in
/// Settings → General → Keyboard → Keyboards → Add New Keyboard, then run:
///
///   xcodebuild -project PrivateKeyboard.xcodeproj \
///     -scheme PrivateKeyboardUITests \
///     -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
///     -derivedDataPath /tmp/PrivateKeyboardUITestData \
///     CODE_SIGNING_ALLOWED=NO test
///
/// Third-party keyboards run out of process, so the extension's keys are not
/// exposed through the host app's `keys` query; this test selects the
/// extension with the globe key and drives it by screen coordinates.
final class KeyboardUITests: XCTestCase {
    func testCoordinateTyping() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-KeyboardTestMode"]
        app.launch()

        let field = app.textFields["keyboardTestField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15), "keyboard test field missing")
        field.tap()
        sleep(1)

        let globePoint = app.coordinate(withNormalizedOffset: CGVector(dx: 0.107, dy: 0.958))
        var selected = false
        for _ in 0..<7 {
            let globe = app.buttons["下一个键盘"].firstMatch
            guard globe.exists else { break }
            let next = globe.value as? String
            globePoint.tap()
            sleep(1)
            if next == "PrivateKeyboard" {
                selected = true
                break
            }
        }
        try XCTSkipUnless(selected, "Enable PrivateKeyboard in Settings before running this test")

        let taps: [(CGFloat, CGFloat)] = [
            (0.704, 0.795), // n
            (0.746, 0.665), // i
            (0.609, 0.730), // h
            (0.062, 0.730), // a
            (0.845, 0.665), // o
        ]
        for (x, y) in taps {
            app.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
        }
        XCTAssertEqual(field.value as? String, "nihao", "pinyin keys did not reach the document")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.13, dy: 0.615)).tap()
        XCTAssertEqual(field.value as? String, "你好", "candidate commit failed")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "PrivateKeyboard-nihao-commit"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}


extension KeyboardUITests {
    func testDumpSystemKeyboard() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-KeyboardTestMode"]
        app.launch()
        let field = app.textFields["keyboardTestField"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.tap()
        sleep(2)
        print("SYSTEM KEYBOARD HIERARCHY\n\(app.keyboards.firstMatch.debugDescription)")
    }
}
