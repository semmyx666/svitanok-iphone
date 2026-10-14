import XCTest
@testable import Svitanok

final class PolicyTests: XCTestCase {
    private let target = Date(timeIntervalSince1970: 1_800_000_000)
    private func plan(deferred: Bool = false, experimental: Bool = true) -> Plan {
        var p = Plan(target: target, maxDelayMinutes: 60, region: 9, experimental: experimental, sound: "system")
        p.deferred = deferred
        return p
    }
    private func decide(_ p: Plan, _ s: AlertStatus, _ seconds: Double, _ foreground: Bool = true, _ backup: Bool = true) -> Decision {
        AlarmPolicy.decide(plan: p, status: s, now: target.addingTimeInterval(seconds), foreground: foreground, backupVerified: backup)
    }
    func testActiveDefersBeforeAlarm() { XCTAssertEqual(decide(plan(), .active, -15), .deferAlarm) }
    func testPartialDefersConservatively() { XCTAssertEqual(decide(plan(), .partial, -15), .deferAlarm) }
    func testClearKeepsOriginal() { XCTAssertEqual(decide(plan(), .clear, -15), .keep) }
    func testUnknownKeepsOriginal() { XCTAssertEqual(decide(plan(), .unknown, -15), .keep) }
    func testBackgroundNeverDefers() { XCTAssertEqual(decide(plan(), .active, -15, false), .keep) }
    func testNoBackupNeverDefers() { XCTAssertEqual(decide(plan(), .active, -15, true, false), .keep) }
    func testDisabledNeverDefers() { XCTAssertEqual(decide(plan(experimental: false), .active, -15), .keep) }
    func testBeforeWindowKeepsOriginal() { XCTAssertEqual(decide(plan(), .active, -31), .keep) }
    func testWindowBoundaryDefers() { XCTAssertEqual(decide(plan(), .active, -30), .deferAlarm) }
    func testNearDeadlineDoesNotRace() { XCTAssertEqual(decide(plan(), .active, -3), .keep) }
    func testAfterOriginalCannotCancel() { XCTAssertEqual(decide(plan(), .active, 1), .keep) }
    func testAtOriginalCannotCancel() { XCTAssertEqual(decide(plan(), .active, 0), .keep) }
    func testDeferredWaitsWhileActive() { XCTAssertEqual(decide(plan(deferred: true), .active, 60), .keep) }
    func testDeferredWaitsWhilePartial() { XCTAssertEqual(decide(plan(deferred: true), .partial, 60), .keep) }
    func testDeferredUnknownDoesNotRelease() { XCTAssertEqual(decide(plan(deferred: true), .unknown, 60), .keep) }
    func testClearReleasesAfterTarget() { XCTAssertEqual(decide(plan(deferred: true), .clear, 60), .release) }
    func testClearDoesNotWakeBeforeTarget() { XCTAssertEqual(decide(plan(deferred: true), .clear, -5), .keep) }
    func testClearAtTargetReleases() { XCTAssertEqual(decide(plan(deferred: true), .clear, 0), .release) }
    func testReleaseRequiresForeground() { XCTAssertEqual(decide(plan(deferred: true), .clear, 60, false), .keep) }
    func testAtHardDeadlinePreservesBackup() { XCTAssertEqual(decide(plan(deferred: true), .clear, 3600), .keep) }
    func testAfterHardDeadlineKeeps() { XCTAssertEqual(decide(plan(deferred: true), .clear, 3601), .keep) }
    func testReleasedIsIdempotent() {
        var p = plan(deferred: true); p.released = true
        XCTAssertEqual(decide(p, .clear, 60), .keep)
    }
    func testFreshSnapshot() {
        let s = Snapshot(fetchedAt: target.timeIntervalSince1970, statuses: Array(repeating: .clear, count: 27), source: "alerts.in.ua")
        XCTAssertEqual(s.status(region: 9, now: target), .clear)
    }
    func testStaleSnapshotUnknown() {
        let s = Snapshot(fetchedAt: target.timeIntervalSince1970 - 46, statuses: Array(repeating: .clear, count: 27), source: "alerts.in.ua")
        XCTAssertEqual(s.status(region: 9, now: target), .unknown)
    }
    func testSnapshotAgeBoundary() {
        let s = Snapshot(fetchedAt: target.timeIntervalSince1970 - 45, statuses: Array(repeating: .partial, count: 27), source: "alerts.in.ua")
        XCTAssertEqual(s.status(region: 9, now: target), .partial)
    }
    func testFutureClockSkewUnknown() {
        let s = Snapshot(fetchedAt: target.timeIntervalSince1970 + 6, statuses: Array(repeating: .clear, count: 27), source: "alerts.in.ua")
        XCTAssertEqual(s.status(region: 9, now: target), .unknown)
    }
    func testNaNTimestampUnknown() {
        let s = Snapshot(fetchedAt: .nan, statuses: Array(repeating: .clear, count: 27), source: "alerts.in.ua")
        XCTAssertEqual(s.status(region: 9, now: target), .unknown)
    }
    func testWrongRegionCountUnknown() {
        let s = Snapshot(fetchedAt: target.timeIntervalSince1970, statuses: [.clear], source: "alerts.in.ua")
        XCTAssertEqual(s.status(region: 0, now: target), .unknown)
    }
    func testNegativeRegionUnknown() {
        let s = Snapshot(fetchedAt: target.timeIntervalSince1970, statuses: Array(repeating: .clear, count: 27), source: "alerts.in.ua")
        XCTAssertEqual(s.status(region: -1, now: target), .unknown)
    }
    func testRegionOutOfBoundsUnknown() {
        let s = Snapshot(fetchedAt: target.timeIntervalSince1970, statuses: Array(repeating: .clear, count: 27), source: "alerts.in.ua")
        XCTAssertEqual(s.status(region: 27, now: target), .unknown)
    }
    func testWrongSourceUnknown() {
        let s = Snapshot(fetchedAt: target.timeIntervalSince1970, statuses: Array(repeating: .clear, count: 27), source: "untrusted")
        XCTAssertEqual(s.status(region: 9, now: target), .unknown)
    }
    func testKyivIsNotKyivOblast() {
        XCTAssertEqual(Region.all[9].name, "м. Київ")
        XCTAssertEqual(Region.all[10].name, "Київська область")
    }
    func testSeparateIDsForSafety() { XCTAssertEqual(Set(plan().ids).count, 3) }
    func testPersistenceRoundtrip() throws {
        let p = plan(deferred: true)
        let decoded = try JSONDecoder().decode(Plan.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded.primaryID, p.primaryID)
        XCTAssertEqual(decoded.deferred, true)
        XCTAssertEqual(decoded.deadline, p.deadline)
    }
    func testExhaustiveSafetyMatrix() {
        // 40,000+ deterministic combinations; checks actual Swift policy, not a port.
        for status in [AlertStatus.active, .partial, .clear, .unknown] {
            for seconds in stride(from: -120.0, through: 3720.0, by: 3.0) {
                for foreground in [false, true] {
                    for backup in [false, true] {
                        for deferred in [false, true] {
                            let result = decide(plan(deferred: deferred), status, seconds, foreground, backup)
                            if result == .deferAlarm {
                                XCTAssertTrue(foreground && backup && !deferred)
                                XCTAssertTrue(status == .active || status == .partial)
                                XCTAssertTrue(seconds >= -30 && seconds < -3)
                            }
                            if result == .release {
                                XCTAssertTrue(foreground && deferred && status == .clear)
                                XCTAssertTrue(seconds >= 0 && seconds < 3600)
                            }
                        }
                    }
                }
            }
        }
    }
}
