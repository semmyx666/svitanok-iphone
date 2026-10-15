import Foundation
import AppIntents

struct WakeSlot:Codable,Sendable,Equatable { var id:UUID=UUID();var due:Date }
struct MathQuestion:Sendable {
    let left:Int;let right:Int
    var text:String { "\(left) + \(right)" }
    var answer:Int { left+right }
    func accepts(_ text:String)->Bool { Int(text.trimmingCharacters(in:.whitespacesAndNewlines)) == answer }
    static func random()->MathQuestion { .init(left:Int.random(in:20...150),right:Int.random(in:10...99)) }
}
struct WakeChallenge:Identifiable {
    let id=UUID();let groupID:UUID;let question:MathQuestion;let repeatLater:Bool
}
enum RepeatPolicy {
    static func interval(_ p:Plan)->TimeInterval {
        if p.wakeProbe == true { return 15 }
        return TimeInterval([300,600,900].contains(p.repeatSeconds ?? 0) ? p.repeatSeconds! : 300)
    }
    static func dates(base:Date,count:Int,interval:TimeInterval)->[Date] {
        guard (1...3).contains(count),interval>=1 else { return [] }
        return (1...count).map { base.addingTimeInterval(Double($0)*interval) }
    }
}
@MainActor enum WakeSerial {
    private static var groups=Set<UUID>()
    static func acquire(_ group:UUID)->Bool { groups.insert(group).inserted }
    static func release(_ group:UUID) { groups.remove(group) }
}
@MainActor enum WakeSeries {
    static func prepare(_ p:inout Plan,base:Date,count:Int) async throws->[WakeSlot] {
        let slots=RepeatPolicy.dates(base:base,count:count,interval:RepeatPolicy.interval(p)).map { WakeSlot(due:$0) }
        guard slots.count==count else { throw WakeError.invalidResponse }
        p.extraWakeIDs=(p.extraWakeIDs ?? [])+slots.map(\.id)
        Persistence.save(p,key:"plan") // All intent identities first, including partially scheduled sets.
        let service=AlarmService()
        for (i,s) in slots.enumerated() {
            try await service.schedule(id:s.id,at:s.due,title:"Світанок · повтор \(i+1)/\(count)",plan:p)
        }
        guard Persistence.load(Plan.self,key:"plan")?.groupID==p.groupID,
              try slots.allSatisfy({ try service.scheduled($0.id) }) else { throw WakeError.noBackup }
        return slots
    }
    static func commit(_ p:inout Plan,slots:[WakeSlot]) throws {
        let old=p.wakeSlots ?? []
        p.wakeSlots=slots;Persistence.save(p,key:"plan")
        let service=AlarmService()
        // New system alarms verified before canceling the old FUTURE follow-ups.
        for s in old where !slots.contains(where:{$0.id==s.id}) {
            if try service.scheduled(s.id) { try service.cancel(id:s.id) }
        }
    }
    static func systemStopped(groupID:String) async throws {
        guard let group=UUID(uuidString:groupID) else { return }
        var acquired=false
        for _ in 0..<100 { if WakeSerial.acquire(group) { acquired=true;break };try? await Task.sleep(for:.milliseconds(100)) }
        guard acquired else { return } // Existing follow-ups remain if another mutation is still running.
        defer { WakeSerial.release(group) }
        guard var p=Persistence.load(Plan.self,key:"plan"),p.groupID==group,p.wakeProtection==true else { return }
        UserDefaults.standard.set(groupID,forKey:"wake-request-group")
        let oldIDs=Set(p.ids)
        do {
            let slots=try await prepare(&p,base:.now,count:3)
            p.wakeSlots=slots;p.wakePhase=true
            Persistence.save(p,key:"plan")
            try AlarmService().cancelIDs(oldIDs.subtracting(Set(slots.map(\.id))))
            WakeProbeLog.write("system.stop.rearmed",plan:p,extra:["verified_followups":3])
        } catch {
            // No mass cancellation on a failed re-arm. Existing reserves/follow-ups remain.
            WakeProbeLog.write("system.stop.rearm_failed",plan:p)
        }
    }
}
struct WakeOpenIntent:LiveActivityIntent {
    static let title:LocalizedStringResource="Решить пример"
    static var openAppWhenRun:Bool=true
    @Parameter(title:"Группа") var groupID:String
    init(){groupID=""}
    init(groupID:String){self.groupID=groupID}
    func perform() async throws->some IntentResult {
        let expected=groupID
        await MainActor.run {
            guard let p=Persistence.load(Plan.self,key:"plan"),p.groupID.uuidString==expected,p.wakeProtection==true else { return }
            UserDefaults.standard.set(expected,forKey:"wake-request-group")
        }
        return .result() // Do NOT cancel any alarm here.
    }
}
@MainActor enum WakeProbeLog {
    static func write(_ event:String,plan:Plan,extra:[String:Any]=[:]) {
        guard plan.wakeProbe==true else { return }
        var record=extra;record["event"]=event;record["time"]=Date.now.timeIntervalSince1970
        record["followup_count"]=(plan.wakeSlots ?? []).count
        guard let data=try? JSONSerialization.data(withJSONObject:record,options:[.sortedKeys]),let dir=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first else { return }
        let url=dir.appendingPathComponent("wake-probe.jsonl")
        if !FileManager.default.fileExists(atPath:url.path){FileManager.default.createFile(atPath:url.path,contents:nil)}
        if let h=try? FileHandle(forWritingTo:url){defer{try? h.close()};try? h.seekToEnd();try? h.write(contentsOf:data+Data([10]))}
    }
}
