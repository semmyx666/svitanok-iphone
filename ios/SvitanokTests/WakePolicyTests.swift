import XCTest
@testable import Svitanok
final class WakePolicyTests:XCTestCase {
    let base=Date(timeIntervalSince1970:2000000000)
    func plan()->Plan { Plan(target:base,maxDelayMinutes:60,region:9,experimental:false,sound:"system") }
    func testExample108Plus63(){let q=MathQuestion(left:108,right:63);XCTAssertEqual(q.answer,171);XCTAssertTrue(q.accepts("171"))}
    func testWrongAnswerRejected(){XCTAssertFalse(MathQuestion(left:108,right:63).accepts("170"))}
    func testEmptyAnswerRejected(){XCTAssertFalse(MathQuestion(left:108,right:63).accepts(""))}
    func testNonIntegerRejected(){let q=MathQuestion(left:108,right:63);for s in ["171.0","1e2","abc","-171","999999999999999999999999999999999999"]{XCTAssertFalse(q.accepts(s))}}
    func testWhitespaceAccepted(){XCTAssertTrue(MathQuestion(left:108,right:63).accepts(" 171\n"))}
    func testRandomQuestionsHaveOnlyOneAcceptedSum(){for _ in 0..<1000 {let q=MathQuestion.random();XCTAssertTrue((20...150).contains(q.left));XCTAssertTrue((10...99).contains(q.right));XCTAssertTrue(q.accepts(String(q.answer)));XCTAssertFalse(q.accepts(String(q.answer+1)))}}
    func testInitialThreeAtZeroFiveTen(){let dates=[base]+RepeatPolicy.dates(base:base,count:2,interval:300);XCTAssertEqual(dates.map{$0.timeIntervalSince(base)},[0,300,600])}
    func testAfterAnswerThreeAtFiveTenFifteen(){XCTAssertEqual(RepeatPolicy.dates(base:base,count:3,interval:300).map{$0.timeIntervalSince(base)},[300,600,900])}
    func testInvalidCountRejected(){XCTAssertEqual(RepeatPolicy.dates(base:base,count:100,interval:300),[])}
    func testInvalidIntervalRejected(){XCTAssertEqual(RepeatPolicy.dates(base:base,count:3,interval:-1),[])}
    func testProductionIntervalNeverBelowFiveMinutes(){for value in [-1,0,1,15,300,600,900,100000]{var p=plan();p.repeatSeconds=value;XCTAssertGreaterThanOrEqual(RepeatPolicy.interval(p),300)}}
    func testProbeIntervalIsExplicit(){var p=plan();p.wakeProbe=true;XCTAssertEqual(RepeatPolicy.interval(p),15)}
    func testAllSeriesIDsIncludedForCleanup(){var p=plan();let slot=WakeSlot(due:base);let extra=UUID();p.wakeSlots=[slot];p.extraWakeIDs=[extra];XCTAssertTrue(p.ids.contains(slot.id));XCTAssertTrue(p.ids.contains(extra))}
    func testOldPlanHasNoImplicitProtection()throws{var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(plan())) as! [String:Any];for key in ["wakeProtection","wakePhase","wakeSlots","extraWakeIDs","repeatSeconds","wakeProbe"]{object.removeValue(forKey:key)};let p=try JSONDecoder().decode(Plan.self,from:JSONSerialization.data(withJSONObject:object));XCTAssertNil(p.wakeProtection);XCTAssertEqual(p.ids.count,3)}
    func testWakePhasePreventsRaidLeaseChanges(){var p=plan();p.experimental=true;p.nightMode=true;p.wakePhase=true;p.deferred=true;XCTAssertEqual(NightPolicy.decide(plan:p,status:.clear,now:base,running:true,verified:true),.keep)}
}
