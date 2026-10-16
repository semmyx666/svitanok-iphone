import Foundation

enum AlertsAPIError: LocalizedError, Equatable {
    case missingToken, invalidToken, unauthorized, forbidden, throttled, server, invalidResponse, network
    case keychain(Int32)
    var errorDescription: String? {
        switch self {
        case .missingToken: "Вставь токен из письма alerts.in.ua в Настройки → API-токен alerts.in.ua и нажми «Сохранить токен»."
        case .invalidToken: "Токен не сохранён: вставь только ключ из письма, без пробелов внутри и без слова Bearer."
        case .keychain(let code): "Не удалось открыть защищённое хранилище iPhone (код \(code)). Разблокируй устройство и попробуй снова."
        case .unauthorized: "alerts.in.ua: токен не принят (401). Проверь ключ и активацию ответом на письмо."
        case .forbidden: "alerts.in.ua запретил доступ (403). Возможна блокировка IP или ограничение по стране."
        case .throttled: "Пауза между запросами alerts.in.ua. Подожди; повторная проверка выполняется автоматически. При 429 пауза увеличивается."
        case .server: "alerts.in.ua временно недоступен. Статус неизвестен, системные сигналы сохранены."
        case .invalidResponse: "Нет свежего подтверждённого ответа alerts.in.ua. Статус неизвестен, системные сигналы сохранены."
        case .network: "Не удалось связаться с alerts.in.ua. Проверь интернет. Системные сигналы сохранены."
        }
    }
}

// Never forward the Authorization header to a redirect target.
private final class NoAlertsRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

actor AlertsAPI {
    static let shared = AlertsAPI()
    private var nextAllowed = Date.distantPast
    private let session: URLSession
    private let tokenProvider: @Sendable () throws -> String?
    init(session: URLSession? = nil, tokenProvider: @escaping @Sendable () throws -> String? = { try TokenStore.read() }) {
        self.tokenProvider = tokenProvider
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = session ?? URLSession(configuration: config, delegate: NoAlertsRedirect(), delegateQueue: nil)
    }
    static func endpoint(uid: Int?) throws -> URL {
        if let uid {
            guard AlertLocation.find(uid) != nil else { throw AlertsAPIError.invalidResponse }
            return URL(string: "https://api.alerts.in.ua/v1/iot/active_air_raid_alerts/\(uid).json")!
        }
        return URL(string: "https://api.alerts.in.ua/v1/iot/active_air_raid_alerts_by_oblast.json")!
    }
    static func request(token: String, uid: Int?) throws -> URLRequest {
        var request = URLRequest(url: try endpoint(uid: uid), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
        request.setValue("Bearer \(try TokenStore.validated(token))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    static func parse(_ data: Data, uid: Int?, serverDate: String?, now: Date) throws -> Snapshot {
        guard data.count <= 4096, let serverDate else { throw AlertsAPIError.invalidResponse }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let received = f.date(from: serverDate), (-5...45).contains(now.timeIntervalSince(received)),
              let text = try? JSONDecoder().decode(String.self, from: data) else { throw AlertsAPIError.invalidResponse }
        func status(_ char: Character) throws -> AlertStatus {
            switch char {
            case "A": return .active
            case "P": return .partial
            case "N": return .clear
            default: throw AlertsAPIError.invalidResponse
            }
        }
        if let uid {
            guard AlertLocation.find(uid) != nil, text.count == 1, let char = text.first else { throw AlertsAPIError.invalidResponse }
            return Snapshot(fetchedAt: received.timeIntervalSince1970, statuses: nil, locationUID: uid,
                            locationStatus: try status(char), source: "alerts.in.ua")
        }
        guard text.count == Region.all.count else { throw AlertsAPIError.invalidResponse }
        return Snapshot(fetchedAt: received.timeIntervalSince1970, statuses: try text.map { try status($0) }, source: "alerts.in.ua")
    }
    func fetch(uid: Int?) async throws -> Snapshot {
        guard Date.now >= nextAllowed else { throw AlertsAPIError.throttled }
        guard let token = try tokenProvider() else { throw AlertsAPIError.missingToken }
        let request = try Self.request(token: token, uid: uid)
        // Shared by foreground, night mode and the manual connection check; force cannot bypass it.
        nextAllowed = Date.now.addingTimeInterval(15)
        let data: Data; let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw AlertsAPIError.network }
        guard let http = response as? HTTPURLResponse, http.url == request.url else { throw AlertsAPIError.invalidResponse }
        switch http.statusCode {
        case 200: return try Self.parse(data, uid: uid, serverDate: http.value(forHTTPHeaderField: "Date"), now: .now)
        case 401: nextAllowed = .now.addingTimeInterval(60); throw AlertsAPIError.unauthorized
        case 403: nextAllowed = .now.addingTimeInterval(300); throw AlertsAPIError.forbidden
        case 429:
            let delay = Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 120
            nextAllowed = .now.addingTimeInterval(min(3600, max(60, delay.isFinite ? delay : 120)))
            throw AlertsAPIError.throttled
        default: nextAllowed = .now.addingTimeInterval(60); throw AlertsAPIError.server
        }
    }
}
