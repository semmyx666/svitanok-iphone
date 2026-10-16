import XCTest
@testable import Svitanok

private final class AlertsStub: URLProtocol, @unchecked Sendable {
    static var code = 200
    static var calls = 0
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "api.alerts.in.ua" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.calls += 1
        let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.timeZone=TimeZone(secondsFromGMT:0)
        f.dateFormat="EEE, dd MMM yyyy HH:mm:ss zzz"
        let response=HTTPURLResponse(url:request.url!,statusCode:Self.code,httpVersion:"HTTP/1.1",
            headerFields:["Date":f.string(from:.now),"Retry-After":"120"])!
        client?.urlProtocol(self,didReceive:response,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Data(#""N""#.utf8));client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class AlertsTransportTests: XCTestCase {
    private func client(code:Int) -> AlertsAPI {
        AlertsStub.code=code;AlertsStub.calls=0
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[AlertsStub.self]
        return AlertsAPI(session:URLSession(configuration:config),tokenProvider:{"unit-test-not-a-real-token"})
    }
    func testSuccessfulFetchAndManualCannotBypassCooldown() async throws {
        let api=client(code:200)
        let snapshot=try await api.fetch(uid:36);XCTAssertEqual(snapshot.locationStatus,.clear)
        do { _=try await api.fetch(uid:36);XCTFail("Bypassed throttle") }
        catch { XCTAssertEqual(error as? AlertsAPIError,.throttled) }
        XCTAssertEqual(AlertsStub.calls,1)
    }
    func test401NotClearAndBacksOff() async {
        let api=client(code:401)
        do { _=try await api.fetch(uid:36);XCTFail("401 accepted") }
        catch { XCTAssertEqual(error as? AlertsAPIError,.unauthorized) }
        do { _=try await api.fetch(uid:36);XCTFail("Bypassed backoff") }
        catch { XCTAssertEqual(error as? AlertsAPIError,.throttled) }
        XCTAssertEqual(AlertsStub.calls,1)
    }
    func test403NotClear() async {
        let api=client(code:403)
        do { _=try await api.fetch(uid:36);XCTFail("403 accepted") }
        catch { XCTAssertEqual(error as? AlertsAPIError,.forbidden) }
    }
    func test429NotClearAndNoImmediateRetry() async {
        let api=client(code:429)
        for _ in 0..<2 {
            do { _=try await api.fetch(uid:36);XCTFail("429 accepted") }
            catch { XCTAssertEqual(error as? AlertsAPIError,.throttled) }
        }
        XCTAssertEqual(AlertsStub.calls,1)
    }
    func testServerErrorNotClear() async {
        let api=client(code:503)
        do { _=try await api.fetch(uid:36);XCTFail("503 accepted") }
        catch { XCTAssertEqual(error as? AlertsAPIError,.server) }
    }
}
