import AlarmKit
import ActivityKit
import AppIntents
import SwiftUI

struct WakeMetadata: AlarmMetadata { var groupID: String }

enum WakeError: LocalizedError {
    case permission, invalidURL, invalidResponse, noBackup
    var errorDescription: String? {
        switch self {
        case .permission: "Разрешите будильники в настройках iPhone. Сигнал не установлен."
        case .invalidURL: "Нужен HTTPS-адрес вашего сервера без пароля, параметров и пути."
        case .invalidResponse: "Нет свежих достоверных данных. Будильник остаётся по времени."
        case .noBackup: "Резервный сигнал не подтверждён. Перенос запрещён."
        }
    }
}

@MainActor
final class AlarmService {
    private let manager = AlarmManager.shared
    func authorize() async throws {
        let state = try await manager.requestAuthorization()
        guard state == .authorized else { throw WakeError.permission }
    }
    func ids() throws -> Set<UUID> { Set(try manager.alarms.map(\.id)) }
    func canDefer(_ plan: Plan) throws -> Bool {
        let alarms = try manager.alarms
        return alarms.contains(where: { $0.id == plan.primaryID && $0.state == .scheduled })
            && alarms.contains(where: { $0.id == plan.backupID && $0.state == .scheduled })
    }
    func schedule(id: UUID, at date: Date, title: String, plan: Plan) async throws {
        let stop = AlarmButton(text: "Я проснулся", textColor: .white, systemImageName: "checkmark")
        let presentation = AlarmPresentation(alert: .init(title: LocalizedStringResource(stringLiteral: title), stopButton: stop))
        let attributes = AlarmAttributes(presentation: presentation,
                                         metadata: WakeMetadata(groupID: plan.groupID.uuidString),
                                         tintColor: Color(red: 0.42, green: 0.76, blue: 0.92))
        // Alert-only: no countdown UI, so no required Live Activity widget extension.
        let sound: AlertConfiguration.AlertSound = plan.sound == "system" ? .default : .named(plan.sound + ".wav")
        let configuration = AlarmManager.AlarmConfiguration<WakeMetadata>(
            schedule: .fixed(date), attributes: attributes,
            stopIntent: WakeStopIntent(groupID: plan.groupID.uuidString), sound: sound)
        _ = try await manager.schedule(id: id, configuration: configuration)
    }
    func cancel(id: UUID) throws { try manager.cancel(id: id) }
    func cancel(plan: Plan) throws {
        let current = try manager.alarms
        for alarm in current where plan.ids.contains(alarm.id) {
            if alarm.state == .alerting {
                try manager.stop(id: alarm.id)
                // A one-time stop usually removes the occurrence. Cancel only if still present.
                if try ids().contains(alarm.id) { try manager.cancel(id: alarm.id) }
            } else {
                try manager.cancel(id: alarm.id)
            }
        }
    }
}

struct WakeStopIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Я проснулся"
    static let description = IntentDescription("Останавливает этот будильник и его резервный сигнал.")
    @Parameter(title: "Группа") var groupID: String
    init() { groupID = "" }
    init(groupID: String) { self.groupID = groupID }
    func perform() async throws -> some IntentResult {
        // Resolve persisted IDs, not all alarms: other users' apps are untouched.
        let expectedGroup = groupID
        try await MainActor.run {
            if let plan = Persistence.load(Plan.self, key: "plan"), plan.groupID.uuidString == expectedGroup {
                try AlarmService().cancel(plan: plan)
                UserDefaults.standard.removeObject(forKey: "plan")
            }
        }
        return .result()
    }
}
