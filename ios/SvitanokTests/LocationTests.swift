import XCTest
@testable import Svitanok

final class LocationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func snapshot(uid: Int = 36, status: AlertStatus = .clear, age: Double = 0) -> Snapshot {
        Snapshot(fetchedAt: now.timeIntervalSince1970 - age, statuses: nil,
                 locationUID: uid, locationStatus: status, source: "alerts.in.ua")
    }
    func testCatalogHas1622UniqueUIDs() {
        XCTAssertEqual(AlertLocation.all.count, 1622)
        XCTAssertEqual(Set(AlertLocation.all.map(\.id)).count, 1622)
    }
    func testVinnytsiaDistrictUID() { XCTAssertEqual(AlertLocation.find(36)?.name, "Вінницький район") }
    func testGaisynDistrictUID() { XCTAssertEqual(AlertLocation.find(37)?.name, "Гайсинський район") }
    func testVinnytsiaCommunityUID() { XCTAssertEqual(AlertLocation.find(155)?.name, "м. Вінниця та Вінницька територіальна громада") }
    func testMatchingUIDClear() { XCTAssertEqual(snapshot().status(region: 2, uid: 36, now: now), .clear) }
    func testMatchingUIDActive() { XCTAssertEqual(snapshot(status: .active).status(region: 2, uid: 36, now: now), .active) }
    func testOtherDistrictCannotRelease() { XCTAssertEqual(snapshot(uid: 37).status(region: 2, uid: 36, now: now), .unknown) }
    func testDistrictDataCannotBeUsedAsOblast() { XCTAssertEqual(snapshot().status(region: 2, now: now), .unknown) }
    func testLegacyOblastCannotBecomeDistrictClear() {
        let s = Snapshot(fetchedAt: now.timeIntervalSince1970, statuses: Array(repeating: .clear,count: 27),source: "alerts.in.ua")
        XCTAssertEqual(s.status(region: 2, uid: 36, now: now), .unknown)
    }
    func testStaleDistrictCannotRelease() { XCTAssertEqual(snapshot(age: 46).status(region: 2, uid: 36, now: now), .unknown) }
    func testUnknownDistrictCannotRelease() { XCTAssertEqual(snapshot(status: .unknown).status(region: 2, uid: 36, now: now), .unknown) }
    func testFutureTimestampCannotRelease() { XCTAssertEqual(snapshot(age: -6).status(region: 2, uid: 36, now: now), .unknown) }
    func testInvalidCatalogUIDCannotRelease() { XCTAssertEqual(snapshot(uid: 9999).status(region: 2, uid: 9999, now: now), .unknown) }
    func testMissingStatusCannotRelease() {
        let s = Snapshot(fetchedAt: now.timeIntervalSince1970,statuses:nil,locationUID:36,source:"alerts.in.ua")
        XCTAssertEqual(s.status(region:2,uid:36,now:now),.unknown)
    }
    func testOldPreferencesMigration() throws {
        let d=Data(#"{"region":2,"experimental":false,"maxDelayMinutes":60,"sound":"system","serverURL":""}"#.utf8)
        let p=try JSONDecoder().decode(Preferences.self,from:d)
        XCTAssertNil(p.locationUID);XCTAssertEqual(p.region,2)
    }
    func testOldPlanMigration() throws {
        let p=Plan(target:now,maxDelayMinutes:60,region:2,experimental:true,sound:"system")
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(p)) as? [String:Any])
        json.removeValue(forKey:"locationUID")
        let migrated=try JSONDecoder().decode(Plan.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertNil(migrated.locationUID);XCTAssertEqual(migrated.primaryID,p.primaryID)
    }
    func testNewPlanKeepsLocationOnRoundTrip() throws {
        var p=Plan(target:now,maxDelayMinutes:60,region:2,experimental:true,sound:"system")
        p.locationUID=36
        let decoded=try JSONDecoder().decode(Plan.self,from:JSONEncoder().encode(p))
        XCTAssertEqual(decoded.locationUID,36)
    }
}
