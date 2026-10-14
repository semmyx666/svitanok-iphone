import XCTest

final class InterfaceTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func testHomeHasLargeTimeControl() {
        XCTAssertTrue(app.buttons["choose-time"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["choose-location-home"].exists)
        XCTAssertTrue(app.buttons["arm-alarm"].isHittable)
        capture("01-home-iPhone")
    }
    func testTimeWheelOpensAndCloses() {
        app.buttons["choose-time"].tap()
        XCTAssertTrue(app.navigationBars["Время будильника"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.pickerWheels.firstMatch.exists)
        capture("02-time-picker-iPhone")
        app.buttons["Готово"].tap()
        XCTAssertTrue(app.buttons["choose-time"].exists)
    }
    func testSelectVinnytsiaDistrict() {
        app.buttons["choose-location-home"].tap()
        let district = app.buttons["location-36"]
        XCTAssertTrue(district.waitForExistence(timeout: 10))
        capture("03-location-picker-iPhone")
        district.tap()
        XCTAssertTrue(app.staticTexts["Вінницький район"].waitForExistence(timeout: 5))
        capture("04-district-selected-iPhone")
    }
    func testSettingsExplainLockedScreenLimit() {
        app.tabBars.buttons["Настройки"].tap()
        XCTAssertTrue(app.buttons["choose-location-settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Обычный сигнал работает с закрытым экраном"].exists)
        capture("05-settings-iPhone")
    }
}
