import Foundation
@preconcurrency import BackgroundTasks
import UIKit

@MainActor @Observable
final class NightRunner {
    var active = false
    var status = "Ночной мониторинг не запущен"
    private weak var owner: AppModel?
    private var task: BGContinuedProcessingTask?
    private var loop: Task<Void, Never>?
    private var group: UUID?
    private var registered = false
    private let pattern = "ua.semmyx.svitanok.*"
    private var requestID: String?
    func connect(_ owner: AppModel) {
        self.owner = owner
        // Continued tasks register the concrete submitted identifier, not the Info.plist wildcard.
        // Registration is intentionally on the user's Start action, per Apple's continued-task guide.
    }
    func begin(_ plan: Plan) {
        guard !active else { status = "Фон не запущен. Обычный сигнал сохранён."; log("task.not_registered"); return }
        let identifier = (Bundle.main.bundleIdentifier ?? "ua.semmyx.svitanok") + ".night." + plan.groupID.uuidString
        guard identifier.hasPrefix("ua.semmyx.svitanok.") else { status = "Подписывающая программа изменила ID несовместимо с фоном. Сигнал по времени сохранён."; return }
        registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
            Task { @MainActor in self?.accept(task) }
        }
        guard registered else { status = "iOS не зарегистрировала фон. Сигнал по времени сохранён."; log("task.not_registered"); return }
        group = plan.groupID; requestID = identifier
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "Світанок · проверка тревоги", subtitle: "До сигнала и отбоя · можно остановить")
        request.strategy = .fail
        do { try BGTaskScheduler.shared.submit(request); status = "Запуск фона запрошен. Пока не подтверждён — перенос запрещён."; log("task.requested") }
        catch { status = "iOS не разрешила фон: \(error.localizedDescription). Сигнал по времени сохранён."; log("task.rejected",extra:["error":error.localizedDescription,"domain":(error as NSError).domain,"code":(error as NSError).code]) }
    }
    private func accept(_ raw: BGTask) {
        guard let continued = raw as? BGContinuedProcessingTask, let owner,
              let plan = Persistence.load(Plan.self,key:"plan"), plan.groupID == group, plan.nightMode == true else {
            raw.setTaskCompleted(success:false); return
        }
        task = continued; active = true; status = "Фон подтверждён · iOS может его остановить"
        log("task.started")
        continued.progress.totalUnitCount = max(1,Int64(ceil(plan.deadline.timeIntervalSinceNow / 15)))
        continued.expirationHandler = { [weak self] in Task { @MainActor in self?.finish(success:false, reason:"iOS остановила фон. Последний системный резерв остаётся.") } }
        loop = Task { @MainActor [weak self, weak owner] in
            guard let self, let owner else { return }
            while !Task.isCancelled && self.active {
                guard let p = Persistence.load(Plan.self,key:"plan"), p.groupID == self.group else { self.finish(success:true,reason:"Будильник остановлен"); return }
                if Date.now >= p.deadline { self.finish(success:true,reason:"Достигнуто предельное время"); return }
                if p.released {
                    if owner.releaseAlerting(p) {
                        self.log("release.alerting")
                        self.finish(success:true,reason:"Система сообщает: сигнал после отбоя активен"); return
                    }
                    if Date.now.timeIntervalSince(p.target) > 240 && p.demoStart != nil { self.finish(success:false,reason:"Тест: сигнал не подтверждён"); return }
                } else {
                    let attempt = owner.lastAttempt
                    await owner.refresh()
                    if owner.lastAttempt != attempt {
                        continued.progress.completedUnitCount = min(continued.progress.totalUnitCount,continued.progress.completedUnitCount + 1)
                        self.log("check", extra:["background": UIApplication.shared.applicationState != .active])
                    }
                }
                try? await Task.sleep(for:.seconds(3))
            }
        }
    }
    func finish(success: Bool, reason: String) {
        guard active || task != nil || requestID != nil else { return }
        active = false; status = reason; loop?.cancel(); loop = nil
        let t = task; task = nil
        t?.setTaskCompleted(success:success)
        if let requestID { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:requestID) }
        requestID = nil
        log(success ? "task.completed" : "task.expired")
        // NEVER cancel AlarmKit reserves here: a killed task may not get this callback.
    }
    func log(_ event: String, extra: [String:Any] = [:]) {
        guard Persistence.load(Plan.self,key:"plan")?.demoStart != nil else { return }
        var record=extra; record["event"]=event; record["time"]=Date.now.timeIntervalSince1970
        guard let data=try? JSONSerialization.data(withJSONObject:record,options:[.sortedKeys]),
              let dir=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first else { return }
        let url=dir.appendingPathComponent("night-probe.jsonl")
        if !FileManager.default.fileExists(atPath:url.path) { FileManager.default.createFile(atPath:url.path,contents:nil) }
        if let handle=try? FileHandle(forWritingTo:url) { defer { try? handle.close() }; try? handle.seekToEnd(); try? handle.write(contentsOf:data+Data([10])) }
    }
}
