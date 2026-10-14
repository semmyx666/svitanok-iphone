import XCTest
@testable import Svitanok
final class NightPolicyTests: XCTestCase {
    let target = Date(timeIntervalSince1970: 2000000000)
    func p(_ deferred:Bool = false) -> Plan {
        var p=Plan(target:target,maxDelayMinutes:60,region:9,experimental:true,sound:"system")
        p.nightMode=true; p.deferred=deferred
        if deferred { p.currentLeaseID=UUID(); p.currentLeaseDue=target.addingTimeInterval(60) }
        return p
    }
    func decision(_ p:Plan,_ status:AlertStatus,_ seconds:Double,_ running:Bool=true,_ verified:Bool=true)->NightDecision {
        NightPolicy.decide(plan:p,status:status,now:target.addingTimeInterval(seconds),running:running,verified:verified)
    }
    func testRequiresActualBackgroundHandler() { XCTAssertEqual(decision(p(),.active,-20,false),.keep) }
    func testRequiresVerifiedReserves() { XCTAssertEqual(decision(p(),.active,-20,true,false),.keep) }
    func testUnknownNeverExtends() { XCTAssertEqual(decision(p(true),.unknown,40),.keep) }
    func testExtendsOriginalBeforeTarget() { XCTAssertEqual(decision(p(),.active,-20),.extendLease) }
    func testExtendsLeaseBeforeExpiry() { XCTAssertEqual(decision(p(true),.partial,40),.extendLease) }
    func testNoLateCancellation() { XCTAssertEqual(decision(p(),.active,-3),.keep); XCTAssertEqual(decision(p(true),.active,60),.keep) }
    func testReleaseAfterTargetOnly() { XCTAssertEqual(decision(p(true),.clear,1),.release); XCTAssertEqual(decision(p(true),.clear,-1),.keep) }
    func testHardDeadlineRemains() { XCTAssertEqual(decision(p(true),.clear,3600),.keep); XCTAssertEqual(decision(p(true),.active,3580),.keep) }
    func testReleasedIdempotent() { var v=p(true); v.released=true; XCTAssertEqual(decision(v,.clear,1),.keep) }
    func testLegacyHasNoNightCapability() { var v=p(); v.nightMode=nil; XCTAssertEqual(decision(v,.active,-20),.keep) }
    func testLeaseIDsPersistForCleanup() throws {
        var v=p(true); v.leaseIDs=[v.currentLeaseID!]
        let w=try JSONDecoder().decode(Plan.self,from:JSONEncoder().encode(v))
        XCTAssertTrue(w.ids.contains(v.currentLeaseID!)); XCTAssertEqual(w.nightMode,true)
    }
}
