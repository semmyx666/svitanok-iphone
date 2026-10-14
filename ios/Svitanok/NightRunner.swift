import Foundation
@preconcurrency import BackgroundTasks
import UIKit
import AVFoundation

@MainActor @Observable
final class NightRunner {
    private var running = false
    var active: Bool { running && (sleepPlayer == nil || sleepPlayer?.isPlaying == true) }
    var status = "Ночной мониторинг не запущен"
    private weak var owner: AppModel?
    private var task: BGContinuedProcessingTask?
    private var loop: Task<Void,Never>?
    private var group: UUID?
    private var requestID: String?
    private var sleepPlayer: AVAudioPlayer?
    func connect(_ owner:AppModel) { self.owner=owner }
    func begin(_ plan:Plan,useSleepAudio:Bool=false) {
        guard !running else { return }
        group=plan.groupID
        if useSleepAudio {
            do {
                guard let url=Bundle.main.url(forResource:"sleep",withExtension:"wav"), let owner else { throw WakeError.invalidResponse }
                let session=AVAudioSession.sharedInstance()
                try session.setCategory(.playback,mode:.default,options:[.mixWithOthers])
                try session.setActive(true)
                let player=try AVAudioPlayer(contentsOf:url)
                player.volume=0.25;player.numberOfLoops = -1;player.prepareToPlay()
                guard player.play(),player.isPlaying else { throw WakeError.invalidResponse }
                sleepPlayer=player;running=true
                status="Ночной звук играет · можно заблокировать экран"
                log("task.started",extra:["method":"audible-sleep-audio"])
                monitor(owner,progress:nil)
            } catch { status="Ночной звук не запущен. Сигнал по времени сохранён.";log("task.rejected",extra:["error":error.localizedDescription]) }
            return
        }
        let identifier=(Bundle.main.bundleIdentifier ?? "ua.semmyx.svitanok")+".night."+plan.groupID.uuidString
        guard identifier.hasPrefix("ua.semmyx.svitanok.") else { status="Программа подписи изменила ID. Сигнал по времени сохранён.";return }
        let registered=BGTaskScheduler.shared.register(forTaskWithIdentifier:identifier,using:.main) { [weak self] task in
            Task { @MainActor in self?.accept(task) }
        }
        guard registered else { status="iOS не зарегистрировала фон. Сигнал по времени сохранён.";log("task.not_registered");return }
        requestID=identifier
        let request=BGContinuedProcessingTaskRequest(identifier:identifier,title:"Світанок · проверка тревоги",subtitle:"До сигнала и отбоя · можно остановить")
        request.strategy = .fail
        do { try BGTaskScheduler.shared.submit(request);status="Запуск фона запрошен. Пока не подтверждён — перенос запрещён.";log("task.requested") }
        catch { status="iOS не разрешила фон. Сигнал по времени сохранён.";log("task.rejected",extra:["error":error.localizedDescription,"domain":(error as NSError).domain,"code":(error as NSError).code]) }
    }
    private func accept(_ raw:BGTask) {
        guard let continued=raw as? BGContinuedProcessingTask, let owner,
              let plan=Persistence.load(Plan.self,key:"plan"),plan.groupID==group,plan.nightMode==true else { raw.setTaskCompleted(success:false);return }
        task=continued;running=true;status="Фон подтверждён · iOS может его остановить";log("task.started",extra:["method":"BGContinuedProcessingTask"])
        continued.progress.totalUnitCount=max(1,Int64(ceil(plan.deadline.timeIntervalSinceNow/15)))
        continued.expirationHandler={ [weak self] in Task { @MainActor in self?.finish(success:false,reason:"iOS остановила фон. Последний резерв остаётся.") } }
        monitor(owner,progress:continued.progress)
    }
    private func monitor(_ owner:AppModel,progress:Progress?) {
        loop=Task { @MainActor [weak self,weak owner] in
            guard let self, let owner else { return }
            while !Task.isCancelled && self.running {
                guard let p=Persistence.load(Plan.self,key:"plan"),p.groupID==self.group else { self.finish(success:true,reason:"Будильник остановлен");return }
                if Date.now>=p.deadline { self.finish(success:true,reason:"Достигнуто предельное время");return }
                if p.released {
                    if owner.releaseAlerting(p) { self.log("release.alerting");self.finish(success:true,reason:"Система сообщает: сигнал после отбоя активен");return }
                    if Date.now.timeIntervalSince(p.target)>240 && p.demoStart != nil { self.finish(success:false,reason:"Тест: сигнал не подтверждён");return }
                } else {
                    if self.sleepPlayer != nil && self.sleepPlayer?.isPlaying != true { self.finish(success:false,reason:"Звук для сна прерван. Последний резерв остаётся.");return }
                    let attempt=owner.lastAttempt
                    await owner.refresh()
                    if owner.lastAttempt != attempt {
                        if let progress { progress.completedUnitCount=min(progress.totalUnitCount,progress.completedUnitCount+1) }
                        self.log("check",extra:["background":UIApplication.shared.applicationState != .active,"audio_playing":self.sleepPlayer?.isPlaying == true])
                    }
                }
                try? await Task.sleep(for:.seconds(3))
            }
        }
    }
    func finish(success:Bool,reason:String) {
        guard running || task != nil || requestID != nil else { return }
        running=false;status=reason;loop?.cancel();loop=nil
        let t=task;task=nil;t?.setTaskCompleted(success:success)
        if let requestID { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier:requestID) };requestID=nil
        if sleepPlayer != nil { sleepPlayer?.stop();sleepPlayer=nil;try? AVAudioSession.sharedInstance().setActive(false,options:.notifyOthersOnDeactivation) }
        log(success ? "task.completed":"task.expired")
        // NEVER cancel AlarmKit reserves here. Force termination may not call this method.
    }
    func log(_ event:String,extra:[String:Any]=[:]) {
        guard Persistence.load(Plan.self,key:"plan")?.demoStart != nil else { return }
        var record=extra;record["event"]=event;record["time"]=Date.now.timeIntervalSince1970
        guard let data=try? JSONSerialization.data(withJSONObject:record,options:[.sortedKeys]),let dir=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first else { return }
        let url=dir.appendingPathComponent("night-probe.jsonl")
        if !FileManager.default.fileExists(atPath:url.path) { FileManager.default.createFile(atPath:url.path,contents:nil) }
        if let handle=try? FileHandle(forWritingTo:url) { defer { try? handle.close() };try? handle.seekToEnd();try? handle.write(contentsOf:data+Data([10])) }
    }
}
