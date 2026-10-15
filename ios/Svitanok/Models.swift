import Foundation

struct Region: Identifiable, Sendable {
    let id: Int
    let name: String
    static let all: [Region] = [
        "Автономна Республіка Крим", "Волинська область", "Вінницька область",
        "Дніпропетровська область", "Донецька область", "Житомирська область",
        "Закарпатська область", "Запорізька область", "Івано-Франківська область",
        "м. Київ", "Київська область", "Кіровоградська область", "Луганська область",
        "Львівська область", "Миколаївська область", "Одеська область",
        "Полтавська область", "Рівненська область", "м. Севастополь", "Сумська область",
        "Тернопільська область", "Харківська область", "Херсонська область",
        "Хмельницька область", "Черкаська область", "Чернівецька область", "Чернігівська область"
    ].enumerated().map { Region(id: $0.offset, name: $0.element) }
}

struct AlertLocation: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let kind: String
    static let all: [AlertLocation] = {
        guard let url = Bundle.main.url(forResource: "locations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([AlertLocation].self, from: data),
              Set(rows.map(\.id)).count == rows.count else { return [] }
        return rows
    }()
    static func find(_ uid: Int?) -> AlertLocation? {
        guard let uid else { return nil }
        return all.first { $0.id == uid }
    }
}

enum AlertStatus: String, Codable, Sendable { case active, partial, clear, unknown }
struct Snapshot: Codable, Sendable {
    let fetchedAt: Double
    let statuses: [AlertStatus]?
    var locationUID: Int? = nil
    var locationStatus: AlertStatus? = nil
    let source: String
    func status(region: Int, uid: Int? = nil, now: Date) -> AlertStatus {
        let age = now.timeIntervalSince1970 - fetchedAt
        guard fetchedAt.isFinite, age >= -5, age <= 45, ["alerts.in.ua", "siren.pp.ua"].contains(source) else { return .unknown }
        if let uid {
            guard locationUID == uid, AlertLocation.find(uid) != nil else { return .unknown }
            return locationStatus ?? .unknown
        }
        guard locationUID == nil, let statuses, statuses.count == 27,
              statuses.indices.contains(region) else { return .unknown }
        return statuses[region]
    }
}

struct Plan: Codable, Sendable {
    var groupID: UUID = UUID()
    var primaryID: UUID = UUID()
    var backupID: UUID = UUID()
    var releaseID: UUID = UUID()
    var target: Date
    var maxDelayMinutes: Int
    var region: Int
    var locationUID: Int? = nil
    var dataSource: String? = nil
    var experimental: Bool
    var nightMode: Bool? = nil
    var wakeProtection: Bool? = nil
    var wakePhase: Bool? = nil
    var wakeSlots: [WakeSlot]? = nil
    var extraWakeIDs: [UUID]? = nil
    var repeatSeconds: Int? = nil
    var wakeProbe: Bool? = nil
    var sleepAudio: Bool? = nil
    var demoStart: Date? = nil
    var leaseIDs: [UUID]? = nil
    var currentLeaseID: UUID? = nil
    var currentLeaseDue: Date? = nil
    var sound: String
    var deferred = false
    var released = false
    var deadline: Date { target.addingTimeInterval(Double(maxDelayMinutes) * 60) }
    var ids: [UUID] { [primaryID, backupID, releaseID] + (leaseIDs ?? []) + (wakeSlots ?? []).map(\.id) + (extraWakeIDs ?? []) }
}

/// Pure policy. Any unknown status preserves the system alarm.
/// We never defer at or after the scheduled time: the primary may already be ringing.
enum Decision: Equatable { case keep, deferAlarm, release }
enum AlarmPolicy {
    static func decide(plan: Plan, status: AlertStatus, now: Date, foreground: Bool,
                       backupVerified: Bool) -> Decision {
        guard plan.experimental, foreground, !plan.released, now < plan.deadline else { return .keep }
        if plan.deferred {
            return status == .clear && now >= plan.target ? .release : .keep
        }
        let remaining = plan.target.timeIntervalSince(now)
        guard backupVerified, remaining > 3, remaining <= 30,
              status == .active || status == .partial else { return .keep }
        return .deferAlarm
    }
}

struct Preferences: Codable, Sendable {
    var region = 9
    var locationUID: Int? = nil
    var dataSource: String? = nil
    var experimental = false
    var wakeProtection: Bool? = nil
    var repeatSeconds: Int? = nil
    var sleepAudio: Bool? = nil
    var maxDelayMinutes = 60
    var sound = "system"
    var serverURL = ""
}

enum Persistence {
    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// Explicit 24-hour display; the device timezone is unchanged.
enum ClockText {
    static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// A short system lease remains even if iOS kills monitoring without an expiration callback.
enum NightDecision: Equatable { case keep, extendLease, release }
enum NightPolicy {
    static func decide(plan: Plan, status: AlertStatus, now: Date, running: Bool, verified: Bool) -> NightDecision {
        guard plan.nightMode == true, plan.experimental, plan.wakePhase != true, running, !plan.released, now < plan.deadline else { return .keep }
        if plan.deferred && status == .clear && now >= plan.target { return .release }
        guard verified, status == .active || status == .partial else { return .keep }
        let due = plan.deferred ? plan.currentLeaseDue : plan.target
        guard let due, due.timeIntervalSince(now) > 3, due.timeIntervalSince(now) <= 30,
              now.addingTimeInterval(60) < plan.deadline else { return .keep }
        return .extendLease
    }
}
