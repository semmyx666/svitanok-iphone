import XCTest
final class WakeProbeTests:XCTestCase {
    func capture(_ app:XCUIApplication,_ name:String){let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)}
    func reveal(_ element:XCUIElement,in app:XCUIApplication){for _ in 0..<8{if element.exists && element.isHittable{return};app.swipeUp()}}
    func testMathAndNextAlarmWhileLocked()throws{
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["--offline-ui-test","--wake-probe"];app.launch()
        let start=app.buttons["wake-probe"];reveal(start,in:app);XCTAssertTrue(start.waitForExistence(timeout:10));start.tap()
        let spring=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        for _ in 0..<15 {
            let allow=spring.buttons.matching(NSPredicate(format:"label == %@ OR label == %@","Allow","Разрешить")).firstMatch
            if allow.exists{allow.tap()};Thread.sleep(forTimeInterval:1)
        }
        XCTAssertTrue(app.staticTexts["wake-series-summary"].waitForExistence(timeout:10))
        capture(app,"08-three-system-alarms")
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval:58)
        capture(spring,"09-first-alarm-locked")
        app.activate()
        XCTAssertTrue(app.textFields["math-answer"].waitForExistence(timeout:15))
        capture(app,"10-math-question")
        app.textFields["math-answer"].tap();app.textFields["math-answer"].typeText("0")
        let repeatButton=app.buttons["math-repeat"];reveal(repeatButton,in:app);repeatButton.tap()
        XCTAssertTrue(app.staticTexts["math-error"].waitForExistence(timeout:5));capture(app,"11-wrong-answer-keeps-alarms")
        let field=app.textFields["math-answer"];field.tap();field.typeText(XCUIKeyboardKey.delete.rawValue+"171")
        reveal(repeatButton,in:app);repeatButton.tap()
        XCTAssertTrue(app.staticTexts["wake-series-summary"].waitForExistence(timeout:10))
        capture(app,"12-three-more-system-alarms")
        let stop=app.buttons["probe-system-stop"];reveal(stop,in:app);stop.tap()
        Thread.sleep(forTimeInterval:2)
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval:22)
        capture(spring,"13-repeat-alarm-locked")
        app.activate()
        XCTAssertTrue(app.textFields["math-answer"].waitForExistence(timeout:15))
        app.textFields["math-answer"].tap();app.textFields["math-answer"].typeText("171")
        let finish=app.buttons["math-finish"];reveal(finish,in:app);finish.tap()
        XCTAssertTrue(app.buttons["arm-alarm"].waitForExistence(timeout:10))
        capture(app,"14-all-series-cancelled")
    }
}
