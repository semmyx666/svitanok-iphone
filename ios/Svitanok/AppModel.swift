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
        if !Region.all.indices.contains(prefs.region) { prefs.region = 9 }
        if ![30, 60, 120].contains(prefs.maxDelayMinutes) { prefs.maxDelayMinutes = 60 }
        if !["system", "dawn", "pulse"].contains(prefs.sound) { prefs.sound = "system" }
    }
    var displayedRegionName: String {
        let region = plan?.region ?? prefs.region
        return Region.all.first(where: { $0.id == region })?.name ?? "Неизвестный регион"
    }
    var currentStatus: AlertStatus { snapshot?.status(region: prefs.region, now: .now) ?? .unknown }
    var statusText: String {
        switch currentStatus {
        case .active: "Воздушная тревога"
        case .partial: "Тревога в части области"
        case .clear: "Источник не сообщает тревогу"
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
            let p = Plan(target: target, maxDelayMinutes: prefs.maxDelayMinutes, region: prefs.region,
                         experimental: test ? false : prefs.experimental, sound: prefs.sound)
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
        guard let components = URLComponents(string: prefs.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/",
              let base = components.url else { throw WakeError.invalidURL }
        return base.appendingPathComponent("v1/status")
    }
    func refresh(force: Bool = false) async {
        guard isForeground, UIApplication.shared.applicationState == .active, !busy, !fetching else { return }
        let now = Date.now
        guard force || now.timeIntervalSince(lastAttempt) >= 15 else { return }
        lastAttempt = now
        fetching = true; defer { fetching = false }
        do {
            let url = try endpoint()
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 8)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 16_384 else { throw WakeError.invalidResponse }
            let candidate = try JSONDecoder().decode(Snapshot.self, from: data)
            guard candidate.status(region: prefs.region, now: .now) != .unknown else { throw WakeError.invalidResponse }
            guard isForeground, UIApplication.shared.applicationState == .active else { return }
            snapshot = candidate; networkMessage = "Свежие данные · alerts.in.ua"
            await evaluate()
        } catch {
            snapshot = nil
            networkMessage = "Нет свежих данных — перенос запрещён"
        }
    }
    private func evaluate() async {
        guard !busy, isForeground, UIApplication.shared.applicationState == .active, var p = plan else { return }
        busy = true; defer { busy = false }
        do {
            let ids = try service.ids()
            let status = snapshot?.status(region: p.region, now: .now) ?? .unknown
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
