import XCTest
@testable import Svitanok

final class AlertsAPITests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func header(age: Double = 0) -> String {
        let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.timeZone=TimeZone(secondsFromGMT:0)
        f.dateFormat="EEE, dd MMM yyyy HH:mm:ss zzz"; return f.string(from:now.addingTimeInterval(-age))
    }
    private func parse(_ text: String, uid: Int? = 36, age: Double = 0) throws -> Snapshot {
        try AlertsAPI.parse(Data(text.utf8), uid: uid, serverDate: header(age:age), now:now)
    }
    func testSelectedDistrictActive() throws { XCTAssertEqual(try parse(#""A""#).locationStatus,.active) }
    func testPartialIsNotClear() throws { XCTAssertEqual(try parse(#""P""#).locationStatus,.partial) }
    func testNoReportedAirRaid() throws { XCTAssertEqual(try parse(#""N""#).locationStatus,.clear) }
    func testNoUnknownCharacterClear() {
        for value in [#"" ""#, #""X""#, #""R""#, #""""#, #""NN""#] { XCTAssertThrowsError(try parse(value)) }
    }
    func testErrorOrMissingResponseCannotBeClear() {
        for value in ["null", "{}", "[]", #"{"message":"error"}"#, "N"] { XCTAssertThrowsError(try parse(value)) }
    }
    func testMissingDate() { XCTAssertThrowsError(try AlertsAPI.parse(Data(#""N""#.utf8), uid:36, serverDate:nil,now:now)) }
    func testStaleDateNotClear() { XCTAssertThrowsError(try parse(#""N""#,age:46)) }
    func testFutureDateNotClear() { XCTAssertThrowsError(try parse(#""N""#,age:-6)) }
    func testValidAgeBoundary() throws { XCTAssertEqual(try parse(#""N""#,age:45).locationStatus,.clear) }
    func testOversizedRejected() { XCTAssertThrowsError(try AlertsAPI.parse(Data(repeating:32,count:4097),uid:36,serverDate:header(),now:now)) }
    func testUnknownUIDRejected() { XCTAssertThrowsError(try parse(#""N""#,uid:99999)) }
    func testAllOblastOrderAndKyiv() throws {
        let chars = Array(repeating: "N",count:9) + ["A","P"] + Array(repeating:"N",count:16)
        let data = try JSONEncoder().encode(chars.joined())
        let s = try AlertsAPI.parse(data,uid:nil,serverDate:header(),now:now)
        XCTAssertEqual(s.status(region:9,now:now),.active);XCTAssertEqual(s.status(region:10,now:now),.partial)
        XCTAssertEqual(s.status(region:0,now:now),.clear)
    }
    func testShortOblastResponseNotClear() { XCTAssertThrowsError(try parse(#""NNN""#,uid:nil)) }
    func testLongOblastResponseNotClear() { XCTAssertThrowsError(try parse("\""+String(repeating:"N",count:28)+"\"",uid:nil)) }
    func testUIDAndSourcePreserved() throws {
        let s=try parse(#""N""#);XCTAssertEqual(s.source,"alerts.in.ua");XCTAssertEqual(s.locationUID,36)
        XCTAssertEqual(s.status(region:2,uid:37,now:now),.unknown)
    }
    func testTokenOnlyInHeaderNotURL() throws {
        let request=try AlertsAPI.request(token:"unit-test-not-a-real-key",uid:36)
        XCTAssertEqual(request.url?.absoluteString,"https://api.alerts.in.ua/v1/iot/active_air_raid_alerts/36.json")
        XCTAssertNil(request.url?.query);XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer unit-test-not-a-real-key")
    }
    func testOblastEndpoint() throws { XCTAssertTrue(try AlertsAPI.endpoint(uid:nil).path.hasSuffix("active_air_raid_alerts_by_oblast.json")) }
    func testInvalidUIDNoRequest() { XCTAssertThrowsError(try AlertsAPI.request(token:"unit-test-not-a-real-key",uid:-1)) }
    func testWhitespaceTrimmed() throws { XCTAssertEqual(try TokenStore.validated("  unit-test-only\n"),"unit-test-only") }
    func testHeaderInjectionAndEmptyRejected() {
        for value in ["", "short", "unit-test\r\nAuthorization: secret", "Bearer key-value",String(repeating:"x",count:513)] {
            XCTAssertThrowsError(try TokenStore.validated(value))
        }
    }
    func testKeychainSaveReplaceReadDelete() throws {
        let account="unit-test-"+UUID().uuidString
        defer { try? TokenStore.delete(account:account) }
        XCTAssertNil(try TokenStore.read(account:account))
        try TokenStore.save("unit-test-only-first",account:account)
        XCTAssertEqual(try TokenStore.read(account:account),"unit-test-only-first")
        try TokenStore.save("unit-test-only-second",account:account)
        XCTAssertEqual(try TokenStore.read(account:account),"unit-test-only-second")
        try TokenStore.delete(account:account);XCTAssertNil(try TokenStore.read(account:account))
    }
    func testPreferencesDoNotContainToken() throws {
        let p=Preferences();let text=String(data:try JSONEncoder().encode(p),encoding:.utf8)!
        XCTAssertFalse(text.lowercased().contains("token"))
    }
    func testMissingCredentialDoesNotSendRequest() async {
        let client=AlertsAPI(tokenProvider:{nil})
        do { _=try await client.fetch(uid:36);XCTFail("Missing token accepted") }
        catch { XCTAssertEqual(error as? AlertsAPIError,.missingToken) }
    }
}
