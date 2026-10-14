import XCTest
final class NightProbeTests:XCTestCase {
    func testControlledAllClearWhileLocked() throws {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["--offline-ui-test"]
        app.launch()
        let button=app.buttons["night-demo"]
        for _ in 0..<5 { if button.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout:10)); button.tap()
        let spring=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        for _ in 0..<15 {
            let allow=spring.buttons.matching(NSPredicate(format:"label == %@ OR label == %@", "Allow","Разрешить")).firstMatch
            if allow.exists { allow.tap() }
            Thread.sleep(forTimeInterval:1)
        }
        let ready=XCTAttachment(screenshot:app.screenshot());ready.name="07a-before-lock-night-state";ready.lifetime = .keepAlways;add(ready)
        // External driver presses a real simulated LOCK hardware button, not just Home.
        // It independently verifies task launch, background checks, lease, release and alerting.
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval:155)
        let shot=XCTAttachment(screenshot:spring.screenshot())
        shot.name="07-controlled-locked-all-clear";shot.lifetime = .keepAlways;add(shot)
    }
}
