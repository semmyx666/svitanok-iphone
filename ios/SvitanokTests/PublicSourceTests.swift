import XCTest
@testable import Svitanok

final class PublicSourceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func header(age: Double = 0) -> String {
        let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.timeZone=TimeZone(secondsFromGMT:0)
        f.dateFormat="EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.string(from:now.addingTimeInterval(-age))
    }
    private func response(_ uid: Int=36, alerts: [[String:String]]=[], name: String?=nil, type: String?=nil) throws -> Data {
        let location=try XCTUnwrap(PublicCatalog.find(uid))
        return try JSONSerialization.data(withJSONObject:[["regionId":String(uid),"regionName":name ?? location.name,"regionType":type ?? location.type,"activeAlerts":alerts]])
    }
    private func parse(_ data:Data,uid:Int=36,age:Double=0) throws -> Snapshot {
        try PublicAlerts.parse(data,uid:uid,serverDate:header(age:age),now:now)
    }
    private func air(_ uid:Int,_ type:String) -> [String:String] { ["regionId":String(uid),"regionType":type,"type":"AIR"] }
    func test1589VerifiedMappings() { XCTAssertEqual(PublicCatalog.all.count,1589) }
    func testVinnytsiaDistrictMapping() { XCTAssertEqual(PublicCatalog.find(36)?.parents,[4]) }
    func testCommunityParentMapping() { XCTAssertEqual(PublicCatalog.find(155)?.parents,[4,36]) }
    func testLegacyKyivMapping() { XCTAssertEqual(PublicCatalog.oblastUID(for:9),31) }
    func testLegacyKyivOblastDifferent() { XCTAssertNotEqual(PublicCatalog.oblastUID(for:9),PublicCatalog.oblastUID(for:10)) }
    func testNoKeyClearResponse() throws { XCTAssertEqual(try parse(response()).locationStatus,.clear) }
    func testSelectedDistrictAir() throws { XCTAssertEqual(try parse(response(alerts:[air(36,"District")])).locationStatus,.active) }
    func testOblastAirAppliesToDistrict() throws { XCTAssertEqual(try parse(response(alerts:[air(4,"State")])).locationStatus,.active) }
    func testDistrictAirAppliesToCommunity() throws { XCTAssertEqual(try parse(response(155,alerts:[air(36,"District")]),uid:155).locationStatus,.active) }
    func testOblastAirAppliesToCommunity() throws { XCTAssertEqual(try parse(response(155,alerts:[air(4,"State")]),uid:155).locationStatus,.active) }
    func testSiblingCannotBecomeSelectedAirOrClear() throws { XCTAssertThrowsError(try parse(response(alerts:[air(37,"District")]))) }
    func testWrongResponseUIDNotClear() throws { XCTAssertThrowsError(try parse(response(37))) }
    func testEmptyListNotClear() { XCTAssertThrowsError(try parse(Data("[]".utf8))) }
    func testMissingActiveAlertsNotClear() { XCTAssertThrowsError(try parse(Data(#"[{"regionId":"36","regionName":"Вінницький район","regionType":"District"}]"#.utf8))) }
    func testErrorBodyNotClear() { XCTAssertThrowsError(try parse(Data(#"{"error":"unavailable"}"#.utf8))) }
    func testNullNotClear() { XCTAssertThrowsError(try parse(Data("null".utf8))) }
    func testWrongTypeNotClear() throws { XCTAssertThrowsError(try parse(response(type:"State"))) }
    func testWrongNameNotClear() throws { XCTAssertThrowsError(try parse(response(name:"Гайсинський район"))) }
    func testBadParentTypeNotClear() throws { XCTAssertThrowsError(try parse(response(alerts:[air(4,"District")]))) }
    func testUnknownAlertTypeNotClear() throws {
        XCTAssertThrowsError(try parse(response(alerts:[["regionId":"36","regionType":"District","type":"UNRECOGNIZED"]])))
    }
    func testStaleHTTPResponseNotClear() throws { XCTAssertThrowsError(try parse(response(),age:46)) }
    func testFutureHTTPResponseNotClear() throws { XCTAssertThrowsError(try parse(response(),age:-6)) }
    func testMissingDateNotClear() throws { XCTAssertThrowsError(try PublicAlerts.parse(response(),uid:36,serverDate:nil,now:now)) }
    func testOversizeNotClear() { XCTAssertThrowsError(try parse(Data(repeating:32,count:65_537))) }
    func testWrongLocationNotAvailable() { XCTAssertThrowsError(try PublicAlerts.parse(Data("[]".utf8),uid:9999,serverDate:header(),now:now)) }
    func testCorrectPublicSourceLabelAndUID() throws {
        let s=try parse(response());XCTAssertEqual(s.source,"siren.pp.ua");XCTAssertEqual(s.locationUID,36)
        XCTAssertEqual(s.status(region:2,uid:36,now:now),.clear)
        XCTAssertEqual(s.status(region:2,uid:37,now:now),.unknown)
    }
    func testOldPreferencesDecodeWithoutSource() throws {
        let d=Data(#"{"region":2,"experimental":false,"maxDelayMinutes":60,"sound":"system","serverURL":""}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(Preferences.self,from:d).dataSource)
    }
    func testOldPlanDecodeWithoutSource() throws {
        let p=Plan(target:now,maxDelayMinutes:60,region:2,experimental:true,sound:"system")
        XCTAssertNil(try JSONDecoder().decode(Plan.self,from:JSONEncoder().encode(p)).dataSource)
    }
    func testNewPlanPersistsPublicSource() throws {
        var p=Plan(target:now,maxDelayMinutes:60,region:2,experimental:true,sound:"system")
        p.dataSource="public";p.locationUID=36
        let d=try JSONDecoder().decode(Plan.self,from:JSONEncoder().encode(p));XCTAssertEqual(d.dataSource,"public")
    }
}
