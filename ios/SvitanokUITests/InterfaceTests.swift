import XCTest

final class InterfaceTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--offline-ui-test"]
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
        let limit = app.staticTexts["Обычный сигнал работает с закрытым экраном"]
        for _ in 0..<10 { if limit.exists && limit.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(limit.exists)
        capture("05-settings-iPhone")
    }
    func testPublicSourceNeedsNoServerField() {
        app.tabBars.buttons["Настройки"].tap()
        let picker = app.descendants(matching: .any).matching(identifier: "source-picker").firstMatch
        for _ in 0..<12 {
            if picker.exists && picker.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(picker.exists)
        XCTAssertTrue(picker.isHittable)
        XCTAssertFalse(app.textFields["HTTPS-адрес сервера"].exists)
        capture("06-public-source-settings-iPhone")
    }

    func testTokenFieldSavePersistsAndDelete() {
        app.tabBars.buttons["Настройки"].tap()
        let field=app.secureTextFields["alerts-api-token"]
        XCTAssertTrue(field.waitForExistence(timeout:10))
        field.tap();field.typeText("ui-test-not-a-real-token")
        app.buttons["save-api-token"].tap()
        XCTAssertTrue(app.staticTexts["Токен сохранён на iPhone"].waitForExistence(timeout:5))
        capture("15-api-token-saved")
        app.terminate();app.launch();app.tabBars.buttons["Настройки"].tap()
        XCTAssertTrue(app.staticTexts["Токен сохранён на iPhone"].waitForExistence(timeout:10))
        XCTAssertFalse(app.staticTexts["ui-test-not-a-real-token"].exists)
        app.buttons["delete-api-token"].tap()
        XCTAssertTrue(app.staticTexts["Токен ещё не сохранён"].waitForExistence(timeout:5))
        capture("16-api-token-deleted")
    }

}
