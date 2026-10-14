import SwiftUI
import AlarmKit
import AVFoundation
import UIKit

@MainActor @Observable
final class AppModel {
    var prefs = Persistence.load(Preferences.self, key: "preferences") ?? Preferences()
    var plan = Persistence.load(Plan.self, key: "plan")
    var selectedDate: Date
    var snapshot: Snapshot?
    var message = "Установите будильник и проверьте его коротким тестом."
    var networkMessage = "Сервер ещё не подключён"
    var busy = false
    var setupVerified = false
    var isForeground = false
    var lastAttempt: Date = .distantPast
    private var fetching = false
    private let service = AlarmService()
    private var player: AVAudioPlayer?

    init() {
        let calendar = Calendar.current
        selectedDate = calendar.nextDate(after: .now, matching: DateComponents(hour: 6, minute: 30), matchingPolicy: .nextTime) ?? Date.now.addingTimeInterval(3600)
        if !["public", "proxy"].contains(prefs.dataSource ?? "") { prefs.dataSource = "public" }
        if prefs.dataSource == "public" { networkMessage = "Подключение к UA Siren без API-ключа…" }
        if !Region.all.indices.contains(prefs.region) { prefs.region = 9 }
        if prefs.locationUID != nil && AlertLocation.find(prefs.locationUID) == nil { prefs.locationUID = nil }
        if ![30, 60, 120].contains(prefs.maxDelayMinutes) { prefs.maxDelayMinutes = 60 }
        if !["system", "dawn", "pulse"].contains(prefs.sound) { prefs.sound = "system" }
    }
    var displayedRegionName: String {
        if let location = AlertLocation.find(plan != nil ? plan?.locationUID : prefs.locationUID) { return location.name }
        let region = plan?.region ?? prefs.region
        return Region.all.first(where: { $0.id == region })?.name ?? "Неизвестный регион"
    }
    var usesPublicSource: Bool { (plan != nil ? (plan?.dataSource ?? "proxy") : prefs.dataSource) == "public" }
    var queryLocationUID: Int? {
        let uid = plan != nil ? plan?.locationUID : prefs.locationUID
        return uid ?? (usesPublicSource ? PublicCatalog.oblastUID(for: plan?.region ?? prefs.region) : nil)
    }
    var currentStatus: AlertStatus { snapshot?.status(region: plan?.region ?? prefs.region, uid: queryLocationUID, now: .now) ?? .unknown }
    var statusText: String {
        switch currentStatus {
        case .active: "Воздушная тревога"
        case .partial: "Тревога в части области"
        case .clear: "Источник не сообщает воздушную тревогу"
        case .unknown: "Статус неизвестен"
        }
    }
    func savePreferences() { Persistence.save(prefs, key: "preferences") }
    func updateForeground(_ active: Bool) {
        isForeground = active
        if active { reconcile() }
    }
    func reconcile() {
        guard !busy else { return }
        plan = Persistence.load(Plan.self, key: "plan")
        guard let p = plan else { setupVerified = false; return }
        do {
            let ids = try service.ids()
            let primaryPresent = p.deferred ? ids.contains(p.backupID) || ids.contains(p.releaseID) : ids.contains(p.primaryID)
            setupVerified = primaryPresent && (!p.experimental || ids.contains(p.backupID))
            if p.ids.allSatisfy({ !ids.contains($0) }) {
                plan = nil
                UserDefaults.standard.removeObject(forKey: "plan")
                message = "Активных системных сигналов нет. Установите следующий будильник."
            }
        } catch { setupVerified = false; message = "Не удалось проверить системные сигналы: \(error.localizedDescription)" }
    }
    func arm(test: Bool = false) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            guard plan == nil else {
                message = "Сначала отключите текущий будильник. Изменения настроек не меняют уже установленный сигнал."
                return
            }
            let target = test ? Date.now.addingTimeInterval(120) : selectedDate
            guard target.timeIntervalSinceNow >= 60 else { message = "Выберите время минимум через минуту."; return }
            if prefs.experimental && !test { _ = try endpoint() }
            try await service.authorize()
            var p = Plan(target: target, maxDelayMinutes: prefs.maxDelayMinutes, region: prefs.region,
                         experimental: test ? false : prefs.experimental, sound: prefs.sound)
            p.locationUID = prefs.locationUID ?? (prefs.dataSource == "public" ? PublicCatalog.oblastUID(for: prefs.region) : nil)
            p.dataSource = prefs.dataSource
            // Persist intent identity before any schedule, including partial-failure states.
            Persistence.save(p, key: "plan"); plan = p; setupVerified = false
            do {
                // Backup first. The primary is NEVER canceled without a verified backup.
                if p.experimental { try await service.schedule(id: p.backupID, at: p.deadline, title: "Світанок · предельное время", plan: p) }
                try await service.schedule(id: p.primaryID, at: p.target, title: "Світанок · пора вставать", plan: p)
                guard Persistence.load(Plan.self, key: "plan")?.groupID == p.groupID else {
                    try service.cancel(plan: p)
                    plan = nil; setupVerified = false
                    message = "Будильник был остановлен во время установки."
                    return
                }
                let ids = try service.ids()
                guard ids.contains(p.primaryID), !p.experimental || ids.contains(p.backupID) else { throw WakeError.noBackup }
                setupVerified = true
                message = test ? "Тестовый системный сигнал — через 2 минуты. Заблокируйте экран." : "Системный сигнал установлен. Один раз, в выбранную дату."
            } catch {
                // Keep any successfully scheduled backup; UI explicitly reports incomplete setup.
                message = "Установка неполная: \(error.localizedDescription). Проверьте/отключите оставшиеся сигналы."
                return
            }
        } catch { message = error.localizedDescription }
    }
    func disarm() {
        guard !busy else { return }
        guard let p = plan else { return }
        do {
            try service.cancel(plan: p)
            plan = nil; setupVerified = false; UserDefaults.standard.removeObject(forKey: "plan")
            message = "Будильник и резерв отключены."
        } catch { message = "Отключение не завершено: \(error.localizedDescription). Проверьте разрешение будильников." }
    }
    func endpoint() throws -> URL {
        if usesPublicSource {
            guard let uid = queryLocationUID, PublicCatalog.find(uid) != nil,
                  let url = URL(string: "https://siren.pp.ua/api/v3/alerts/\(uid)") else { throw WakeError.invalidResponse }
            return url
        }
        guard let components = URLComponents(string: prefs.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              let base = components.url else { throw WakeError.invalidURL }
        if let uid = plan != nil ? plan?.locationUID : prefs.locationUID {
            guard AlertLocation.find(uid) != nil else { throw WakeError.invalidResponse }
            var result = URLComponents(url: base.appendingPathComponent("v2/status"), resolvingAgainstBaseURL: false)!
            result.queryItems = [URLQueryItem(name: "uid", value: String(uid))]
            guard let url = result.url else { throw WakeError.invalidURL }
            return url
        }
        return base.appendingPathComponent("v1/status")
    }
    func refresh(force: Bool = false) async {
        guard isForeground, UIApplication.shared.applicationState == .active, !busy, !fetching else { return }
        if ProcessInfo.processInfo.arguments.contains("--offline-ui-test") { networkMessage = "Проверка интерфейса без сети. Тревога и отбой не определены."; return }
        let now = Date.now
        guard force || now.timeIntervalSince(lastAttempt) >= 15 else { return }
        lastAttempt = now
        fetching = true; defer { fetching = false }
        do {
            let url = try endpoint()
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw WakeError.invalidResponse }
            let candidate: Snapshot
            if usesPublicSource {
                guard http.url?.host == "siren.pp.ua", http.url?.scheme == "https", let uid = queryLocationUID else { throw WakeError.invalidResponse }
                candidate = try PublicAlerts.parse(data, uid: uid, serverDate: http.value(forHTTPHeaderField: "Date"), now: .now)
            } else {
                guard data.count < 16_384 else { throw WakeError.invalidResponse }
                candidate = try JSONDecoder().decode(Snapshot.self, from: data)
            }
            guard candidate.source == (usesPublicSource ? "siren.pp.ua" : "alerts.in.ua"),
                  candidate.status(region: plan?.region ?? prefs.region, uid: queryLocationUID, now: .now) != .unknown else { throw WakeError.invalidResponse }
            guard isForeground, UIApplication.shared.applicationState == .active else { return }
            snapshot = candidate; networkMessage = usesPublicSource ? "Ответ UA Siren получен. Без ключа и своего сервера. Это сторонний источник, возможны задержки." : "Ответ alerts.in.ua получен через ваш сервер."
            await evaluate()
        } catch {
            snapshot = nil
            if usesPublicSource { networkMessage = "UA Siren недоступен или ответ не подтверждён. Тревога/отбой неизвестны. Не отключайте резерв."; return }
            networkMessage = prefs.serverURL.isEmpty ? "Источник не подключён. Будильник работает только по времени." : "Нет свежих данных. Для районов нужен сервер версии 0.3. Перенос сейчас недоступен."
        }
    }
    private func evaluate() async {
        guard !busy, isForeground, UIApplication.shared.applicationState == .active, var p = plan else { return }
        busy = true; defer { busy = false }
        do {
            let ids = try service.ids()
            let status = snapshot?.status(region: p.region, uid: queryLocationUID, now: .now) ?? .unknown
            let decision = AlarmPolicy.decide(plan: p, status: status, now: .now,
                                               foreground: isForeground, backupVerified: try service.canDefer(p))
            switch decision {
            case .keep: break
            case .deferAlarm:
                guard ids.contains(p.primaryID) else { return }
                // Fail closed if the foreground check changed before mutation.
                guard isForeground, UIApplication.shared.applicationState == .active,
                      p.target.timeIntervalSinceNow > 3 else { return }
                try service.cancel(id: p.primaryID)
                p.deferred = true
                plan = p; Persistence.save(p, key: "plan")
                message = "Основной сигнал перенесён. Ожидаем отбой; резерв в \(p.deadline.formatted(date: .omitted, time: .shortened))."
            case .release:
                // New system alarm first. The independent deadline backup stays until Stop.
                try await service.schedule(id: p.releaseID, at: .now.addingTimeInterval(5), title: "Світанок · источник сообщает отбой", plan: p)
                guard Persistence.load(Plan.self, key: "plan")?.groupID == p.groupID else {
                    if try service.ids().contains(p.releaseID) { try service.cancel(id: p.releaseID) }
                    plan = nil; setupVerified = false
                    return
                }
                p.released = true
                plan = p; Persistence.save(p, key: "plan")
                message = "Сигнал после отбоя установлен через 5 секунд. «Я проснулся» отключит резерв."
            }
        } catch { message = "Перенос не завершён: \(error.localizedDescription). Системные сигналы не отключены массово." }
    }
    func previewSound() {
        guard prefs.sound != "system", let url = Bundle.main.url(forResource: prefs.sound, withExtension: "wav") else {
            message = "Системный звук проверяется кнопкой «Тест через 2 минуты»."; return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(contentsOf: url); player?.play()
        } catch { message = "Не удалось воспроизвести звук: \(error.localizedDescription)" }
    }
}
