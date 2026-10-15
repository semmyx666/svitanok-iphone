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
    var challenge: WakeChallenge?
    var challengeError = ""
    var ringingInApp = false
    private var ringPlayer: AVAudioPlayer?
    var busy = false
    var setupVerified = false
    var isForeground = false
    var lastAttempt: Date = .distantPast
    private var fetching = false
    private let service = AlarmService()
    private let night = NightRunner()
    var nightStatus: String { night.status }
    var backgroundRunning: Bool { night.active }
    private var executionAllowed: Bool { night.active || (isForeground && UIApplication.shared.applicationState == .active) }
    private var player: AVAudioPlayer?

    init() {
        let calendar = Calendar.current
        selectedDate = calendar.nextDate(after: .now, matching: DateComponents(hour: 6, minute: 30), matchingPolicy: .nextTime) ?? Date.now.addingTimeInterval(3600)
        if !["public", "proxy"].contains(prefs.dataSource ?? "") { prefs.dataSource = "public" }
        if prefs.dataSource == "public" { networkMessage = "Подключение к UA Siren без API-ключа…" }
        if !Region.all.indices.contains(prefs.region) { prefs.region = 9 }
        if prefs.locationUID != nil && AlertLocation.find(prefs.locationUID) == nil { prefs.locationUID = nil }
        if ![30, 60, 120].contains(prefs.maxDelayMinutes) { prefs.maxDelayMinutes = 60 }
        if !["system", "dawn", "pulse", "wake"].contains(prefs.sound) { prefs.sound = "system" }
        if prefs.wakeProtection == nil { prefs.wakeProtection = true }
        if ![300,600,900].contains(prefs.repeatSeconds ?? 0) { prefs.repeatSeconds = 300 }
        if prefs.sleepAudio == nil { prefs.sleepAudio = true }
        night.connect(self)
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
        if let p=plan, p.wakeProbe == true && !active { WakeProbeLog.write("app.background",plan:p) }
        if active { reconcile() }
    }
    func reconcile() {
        guard !busy else { return }
        plan = Persistence.load(Plan.self, key: "plan")
        guard let p = plan else { setupVerified = false; return }
        do {
            let ids = try service.ids()
            let primaryPresent = p.wakePhase == true ? (p.wakeSlots ?? []).contains { ids.contains($0.id) } : (p.deferred ? ids.contains(p.backupID) || ids.contains(p.releaseID) : ids.contains(p.primaryID))
            setupVerified = primaryPresent && (p.wakePhase == true || !p.experimental || ids.contains(p.backupID))
            if p.wakeProtection == true && challenge == nil && isForeground && !busy {
                let requested = UserDefaults.standard.string(forKey:"wake-request-group") == p.groupID.uuidString
                let alerting=try service.anyAlerting(p)
                if requested || alerting {
                    UserDefaults.standard.removeObject(forKey:"wake-request-group")
                    if (try? service.anyAlerting(p)) == true { WakeProbeLog.write(p.wakePhase == true ? "repeat.alerting":"first.alerting",plan:p) }
                    requestChallenge(repeatLater:true)
                }
            }
            if p.ids.allSatisfy({ !ids.contains($0) }) {
                plan = nil
                UserDefaults.standard.removeObject(forKey: "plan")
                message = "Активных системных сигналов нет. Установите следующий будильник."
            }
        } catch { setupVerified = false; message = "Не удалось проверить системные сигналы: \(error.localizedDescription)" }
    }
    func arm(test: Bool = false, nightDemo: Bool = false, wakeProbe: Bool = false) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            guard plan == nil else {
                message = "Сначала отключите текущий будильник. Изменения настроек не меняют уже установленный сигнал."
                return
            }
            let isWakeProbe = wakeProbe && ProcessInfo.processInfo.arguments.contains("--wake-probe")
            let target = isWakeProbe ? Date.now.addingTimeInterval(70) : (nightDemo ? Date.now.addingTimeInterval(90) : (test ? Date.now.addingTimeInterval(120) : selectedDate))
            guard target.timeIntervalSinceNow >= 60 else { message = "Выберите время минимум через минуту."; return }
            if prefs.experimental && !test && !nightDemo { _ = try endpoint() }
            if prefs.experimental && target.timeIntervalSinceNow > 12 * 3600 { message = "Ночной режим: время не дальше 12 часов. Для другого дня используйте обычный сигнал."; return }
            try await service.authorize()
            var p = Plan(target: target, maxDelayMinutes: nightDemo ? 5 : prefs.maxDelayMinutes, region: prefs.region,
                         experimental: nightDemo || (!test && !isWakeProbe && prefs.experimental), sound: prefs.sound)
            p.nightMode = p.experimental
            p.wakeProtection = prefs.wakeProtection != false
            p.repeatSeconds = isWakeProbe ? 15 : (prefs.repeatSeconds ?? 300)
            p.wakeProbe = isWakeProbe
            p.sleepAudio = p.experimental && (nightDemo || prefs.sleepAudio == true)
            if nightDemo { p.demoStart = .now }
            p.locationUID = prefs.locationUID ?? (prefs.dataSource == "public" ? PublicCatalog.oblastUID(for: prefs.region) : nil)
            p.dataSource = nightDemo ? "public" : prefs.dataSource
            if nightDemo { p.locationUID = prefs.locationUID ?? PublicCatalog.oblastUID(for:prefs.region) }
            guard WakeSerial.acquire(p.groupID) else { return }
            defer { WakeSerial.release(p.groupID) }
            // Persist intent identity before any schedule, including partial-failure states.
            Persistence.save(p, key: "plan"); plan = p; setupVerified = false
            do {
                // Backup first. The primary is NEVER canceled without a verified backup.
                if p.experimental { try await service.schedule(id: p.backupID, at: p.deadline, title: "Світанок · предельное время", plan: p) }
                try await service.schedule(id: p.primaryID, at: p.target, title: "Світанок · пора вставать", plan: p)
                if p.wakeProtection == true {
                    let base=p.target
                    let slots=try await WakeSeries.prepare(&p,base:base,count:2)
                    try WakeSeries.commit(&p,slots:slots)
                    plan=p
                }
                guard Persistence.load(Plan.self, key: "plan")?.groupID == p.groupID else {
                    try service.cancel(plan: p)
                    plan = nil; setupVerified = false
                    message = "Будильник был остановлен во время установки."
                    return
                }
                let ids = try service.ids()
                guard ids.contains(p.primaryID), !p.experimental || ids.contains(p.backupID) else { throw WakeError.noBackup }
                setupVerified = true
                WakeProbeLog.write("armed",plan:p,extra:["series_count":p.wakeProtection == true ? 3:1])
                if p.nightMode == true { night.begin(p, useSleepAudio: p.sleepAudio == true) }
                message = nightDemo ? "ТЕСТ: искусственная тревога до 2-й минуты, затем искусственный отбой. Это не настоящие данные." : (test ? "Тестовый системный сигнал — через 2 минуты. Заблокируйте экран." : "Системный сигнал установлен. Один раз, в выбранную дату.")
            } catch {
                plan=Persistence.load(Plan.self,key:"plan")
                // Keep any successfully scheduled backup; UI explicitly reports incomplete setup.
                message = "Установка неполная: \(error.localizedDescription). Проверьте/отключите оставшиеся сигналы."
                return
            }
        } catch { message = error.localizedDescription }
    }
    func disarm() {
        guard !busy else { return }
        guard let p = Persistence.load(Plan.self,key:"plan") else { return }
        if p.wakeProtection == true { requestChallenge(repeatLater:false); return }
        do {
            try service.cancel(plan: p)
            night.finish(success:true,reason:"Будильник отключён")
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
        guard executionAllowed, !busy, !fetching else { return }
        if let p = plan, p.demoStart != nil {
            let now = Date.now
            guard now.timeIntervalSince(lastAttempt) >= 15 else { return }
            lastAttempt = now
            let uid = queryLocationUID
            snapshot = Snapshot(fetchedAt: now.timeIntervalSince1970, statuses:nil, locationUID:uid,
                                locationStatus:now < p.target.addingTimeInterval(30) ? .active : .clear,source:"siren.pp.ua")
            networkMessage = "ТЕСТ. Искусственные статусы, не настоящая тревога."
            await evaluate(); return
        }
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
            guard executionAllowed else { return }
            snapshot = candidate; networkMessage = usesPublicSource ? "Ответ UA Siren получен. Без ключа и своего сервера. Это сторонний источник, возможны задержки." : "Ответ alerts.in.ua получен через ваш сервер."
            await evaluate()
        } catch {
            snapshot = nil
            if usesPublicSource { networkMessage = "UA Siren недоступен или ответ не подтверждён. Тревога/отбой неизвестны. Не отключайте резерв."; return }
            networkMessage = prefs.serverURL.isEmpty ? "Источник не подключён. Будильник работает только по времени." : "Нет свежих данных. Для районов нужен сервер версии 0.3. Перенос сейчас недоступен."
        }
    }
    private func evaluate() async {
        guard !busy, executionAllowed, var p = plan else { return }
        guard WakeSerial.acquire(p.groupID) else { return }
        defer { WakeSerial.release(p.groupID) }
        busy = true; defer { busy = false }
        do {
            let ids = try service.ids()
            let status = snapshot?.status(region: p.region, uid: queryLocationUID, now: .now) ?? .unknown
            if p.nightMode == true {
                try await evaluateNight(&p, status:status)
                return
            }
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
        } catch { night.log("mutation.failed",extra:["error":error.localizedDescription,"domain":(error as NSError).domain,"code":(error as NSError).code]); plan=Persistence.load(Plan.self,key:"plan"); message = "Перенос не завершён: \(error.localizedDescription). Системные сигналы не отключены массово." }
    }
    func releaseAlerting(_ p: Plan) -> Bool { (try? service.alerting(p.releaseID)) == true }
    private func evaluateNight(_ p: inout Plan, status: AlertStatus) async throws {
        let action = NightPolicy.decide(plan:p,status:status,now:.now,running:night.active,verified:try service.leaseVerified(p))
        night.log("decision",extra:["status":status.rawValue,"action":String(describing:action),"deferred":p.deferred,"released":p.released,"wake_phase":p.wakePhase==true])
        switch action {
        case .keep: return
        case .extendLease:
            let oldID = p.deferred ? p.currentLeaseID : p.primaryID
            let oldDue = p.deferred ? p.currentLeaseDue : p.target
            guard let oldID, let oldDue else { return }
            let id = UUID(); let due = Date.now.addingTimeInterval(60)
            p.leaseIDs = (p.leaseIDs ?? []) + [id]
            Persistence.save(p,key:"plan"); plan = p
            // Replacement FIRST, cancellation LAST. Crash/rejection leaves an older system alarm.
            try await service.schedule(id:id,at:due,title:"Світанок · проверка прервалась",plan:p)
            guard Persistence.load(Plan.self,key:"plan")?.groupID == p.groupID else { try service.cancel(id:id); return }
            guard night.active, try service.scheduled(id), try service.scheduled(p.backupID), oldDue.timeIntervalSinceNow > 3 else {
                try service.cancel(id:id); return
            }
            if p.wakeProtection == true {
                let slots=try await WakeSeries.prepare(&p,base:due,count:2)
                guard night.active, oldDue.timeIntervalSinceNow > 3 else { return }
                try WakeSeries.commit(&p,slots:slots)
            }
            p.currentLeaseID = id; p.currentLeaseDue = due; p.deferred = true
            Persistence.save(p,key:"plan"); plan = p
            try service.cancel(id:oldID)
            night.log("lease.extended",extra:["due":due.timeIntervalSince1970])
            message = "Тревога: сигнал отложен. Если проверки оборвутся, последний резерв прозвучит примерно в течение минуты."
        case .release:
            // Do not let follow-up preparation turn an already confirmed release into a retry
            // with the same AlarmKit ID. Alerting is also a valid confirmed system state.
            let due=Date.now.addingTimeInterval(5)
            if !(try service.scheduled(p.releaseID)) && !(try service.alerting(p.releaseID)) {
                try await service.schedule(id:p.releaseID,at:due,title:"Світанок · источник сообщает отбой",plan:p)
            }
            guard Persistence.load(Plan.self,key:"plan")?.groupID == p.groupID else { try service.cancel(id:p.releaseID); return }
            let releaseScheduled=try service.scheduled(p.releaseID)
            let releaseAlerting=try service.alerting(p.releaseID)
            guard releaseScheduled || releaseAlerting else { throw WakeError.invalidResponse }
            p.released=true;Persistence.save(p,key:"plan");plan=p
            night.log("release.scheduled")
            if let id=p.currentLeaseID, try service.scheduled(id) { try service.cancel(id:id) }
            if p.wakeProtection == true {
                do {
                    let slots=try await WakeSeries.prepare(&p,base:due,count:2)
                    try WakeSeries.commit(&p,slots:slots)
                    plan=p
                } catch {
                    plan=Persistence.load(Plan.self,key:"plan")
                    night.log("release.followups_not_moved",extra:["error":error.localizedDescription])
                    // The confirmed release and old independent follow-ups remain.
                }
            }
            message = "Источник сообщил отбой. Системный сигнал подтверждён; серия повторов сохранена."
        }
    }
    func probeSystemStop() async {
        guard !busy,ProcessInfo.processInfo.arguments.contains("--wake-probe"),let p=plan,p.wakeProbe==true else {return}
        busy=true;defer{busy=false}
        do {
            _ = try await WakeStopIntent(groupID:p.groupID.uuidString).perform()
            UserDefaults.standard.removeObject(forKey:"wake-request-group")
            busy=false;reconcile()
        } catch { message="Тест обработчика остановки не выполнен." }
    }
    var wakeSummary:String {
        guard let p=plan,p.wakeProtection==true else { return "" }
        let names=(p.wakeSlots ?? []).map { ClockText.format($0.due) }.joined(separator:" · ")
        return p.wakePhase==true ? "Ещё 3 сигнала: \(names)" : "3 сигнала: \(ClockText.format(p.target)) · \(names)"
    }
    func requestChallenge(repeatLater:Bool) {
        guard !busy,challenge==nil,let p=Persistence.load(Plan.self,key:"plan"),p.wakeProtection==true else { return }
        let question=p.wakeProbe==true ? MathQuestion(left:108,right:63):MathQuestion.random()
        challengeError="";challenge=WakeChallenge(groupID:p.groupID,question:question,repeatLater:repeatLater)
        if repeatLater || (try? service.anyAlerting(p))==true {
            night.finish(success:true,reason:"Пробуждение: реши пример")
            startWakeRinging()
        }
    }
    func submitChallenge(_ answer:String,finishAll:Bool) async {
        guard !busy,let request=challenge,let loaded=Persistence.load(Plan.self,key:"plan"),loaded.groupID==request.groupID else { return }
        guard request.question.accepts(answer) else {
            challengeError="Пока неверно. Попробуй ещё раз — сигналы не отключены."
            WakeProbeLog.write("math.rejected",plan:loaded);return
        }
        guard WakeSerial.acquire(loaded.groupID) else { challengeError="Подожди, система обновляет сигналы.";return }
        defer{WakeSerial.release(loaded.groupID)}
        busy=true;defer{busy=false}
        var p=loaded
        do {
            if finishAll {
                try service.cancel(plan:p)
                guard try service.ids().isDisjoint(with:Set(p.ids)) else { throw WakeError.noBackup }
                WakeProbeLog.write("math.finish",plan:p,extra:["remaining_system_ids":0])
                UserDefaults.standard.removeObject(forKey:"plan");plan=nil;setupVerified=false
                message="Пример решён. Вся серия и резерв отключены. Доброе утро!"
            } else {
                let oldIDs=Set(p.ids)
                let slots=try await WakeSeries.prepare(&p,base:.now,count:3)
                p.wakeSlots=slots;p.wakePhase=true
                Persistence.save(p,key:"plan");plan=p
                try service.cancelIDs(oldIDs.subtracting(Set(slots.map(\.id))))
                setupVerified=true
                WakeProbeLog.write("math.repeat",plan:p,extra:["verified_followups":3])
                message="Пример решён. Ещё 3 сигнала через \(Int(RepeatPolicy.interval(p)/60)), \(Int(RepeatPolicy.interval(p)*2/60)) и \(Int(RepeatPolicy.interval(p)*3/60)) минут. Уже встал — отключи всю серию новым примером."
            }
            night.finish(success:true,reason:"Математическое подтверждение получено")
            stopWakeRinging();challenge=nil;challengeError=""
            UserDefaults.standard.removeObject(forKey:"wake-request-group")
        } catch {
            plan=Persistence.load(Plan.self,key:"plan")
            challengeError="Не удалось завершить действие. Оставшиеся сигналы сохранены: \(error.localizedDescription)"
        }
    }
    private func startWakeRinging() {
        guard !ringingInApp,let url=Bundle.main.url(forResource:"wake",withExtension:"wav") else{return}
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback,mode:.default,options:[.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let p=try AVAudioPlayer(contentsOf:url);p.numberOfLoops = -1;p.volume=1;p.prepareToPlay()
            guard p.play() else{throw WakeError.invalidResponse};ringPlayer=p;ringingInApp=true
        } catch { challengeError="Звук приложения не запущен. Не отключай системные сигналы." }
    }
    private func stopWakeRinging() {
        ringPlayer?.stop();ringPlayer=nil;ringingInApp=false
        if !night.active { try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation) }
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
