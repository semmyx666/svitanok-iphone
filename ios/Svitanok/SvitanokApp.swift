import SwiftUI

@main
struct SvitanokApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            TabView {
                HomeView(model: model).tabItem { Label("Будильник", systemImage: "alarm") }
                MapView().tabItem { Label("Карта", systemImage: "map") }
                SettingsView(model: model).tabItem { Label("Настройки", systemImage: "slider.horizontal.3") }
            }.tint(.sky).preferredColorScheme(.dark)
                .sheet(item:$model.challenge) { request in WakeChallengeView(model:model,request:request) }
                .onChange(of: phase, initial: true) { _, phase in
                    model.updateForeground(phase == .active)
                }
                .task {
                    while !Task.isCancelled {
                        if model.isForeground { await model.refresh(); model.reconcile() }
                        try? await Task.sleep(for: .seconds(5))
                    }
                }
        }
    }
}
