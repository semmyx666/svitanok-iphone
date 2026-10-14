import SwiftUI
import WebKit
import SafariServices

extension Color {
    static let night = Color(red: 0.055, green: 0.082, blue: 0.14)
    static let panel = Color(red: 0.09, green: 0.13, blue: 0.21)
    static let sky = Color(red: 0.48, green: 0.79, blue: 0.94)
    static let peach = Color(red: 1, green: 0.76, blue: 0.58)
    static let muted = Color(red: 0.68, green: 0.75, blue: 0.84)
}

struct HomeView: View {
    @Bindable var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("СВІТАНОК").font(.caption.weight(.bold)).tracking(4).foregroundStyle(Color.sky)
                        Text("Утро без спешки").font(.title2.weight(.semibold))
                    }
                    Spacer()
                    Image(systemName: "sunrise.fill").font(.system(size: 30)).foregroundStyle(Color.peach)
                }
                VStack(alignment: .leading, spacing: 14) {
                    Label(model.plan == nil ? "Ближайший будильник" : (model.setupVerified ? "Системный сигнал установлен" : "Проверьте системные сигналы"), systemImage: "alarm.fill")
                        .font(.subheadline).foregroundStyle(Color.muted)
                    Text((model.plan?.target ?? model.selectedDate).formatted(.dateTime.hour().minute()))
                        .font(.system(size: 70, weight: .light, design: .rounded)).monospacedDigit()
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text((model.plan?.target ?? model.selectedDate).formatted(date: .abbreviated, time: .omitted))
                        .foregroundStyle(Color.muted)
                    Divider().overlay(Color.white.opacity(0.12))
                    Label(model.displayedRegionName, systemImage: "location.fill")
                        .foregroundStyle(Color.sky)
                    Text(model.plan?.experimental == true ? "Перенос экспериментальный · только при открытом приложении" : "По времени · даже без интернета")
                        .font(.subheadline).foregroundStyle(Color.muted)
                    if let p = model.plan, p.experimental {
                        Text("Предельный сигнал: \(p.deadline.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Color.peach)
                    }
                }.padding(24).background(Color.panel, in: RoundedRectangle(cornerRadius: 20))
                VStack(alignment: .leading, spacing: 10) {
                    Label(model.statusText, systemImage: statusIcon)
                        .foregroundStyle(statusColor).font(.headline)
                    Text(model.networkMessage).font(.subheadline).foregroundStyle(Color.muted)
                    Text("Статус выбранной области, не подтверждение безопасности. Официальные оповещения имеют приоритет.")
                        .font(.subheadline).foregroundStyle(Color.muted)
                    Button("Обновить статус") { Task { await model.refresh(force: true) } }
                        .buttonStyle(.bordered).tint(.sky).disabled(model.busy)
                }.padding(20).background(Color.panel, in: RoundedRectangle(cornerRadius: 16))
                if model.plan == nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Когда разбудить").font(.headline)
                        DatePicker("Дата и время", selection: $model.selectedDate, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                            .datePickerStyle(.compact).tint(.sky)
                        Text("Одно срабатывание. После него установите следующее. Время — в часовом поясе iPhone.")
                            .font(.subheadline).foregroundStyle(Color.muted)
                    }
                    Button { Task { await model.arm() } } label: {
                        Label(model.busy ? "Устанавливаю…" : "Установить будильник", systemImage: "alarm")
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                    }.buttonStyle(.borderedProminent).tint(.sky).foregroundStyle(Color.night).disabled(model.busy)
                    Button("Тест через 2 минуты") { Task { await model.arm(test: true) } }
                        .buttonStyle(.bordered).tint(.peach).disabled(model.busy)
                } else {
                    Button(role: .destructive) { model.disarm() } label: {
                        Text("Отключить будильник и резерв").frame(maxWidth: .infinity).padding(.vertical, 10)
                    }.buttonStyle(.bordered).disabled(model.busy)
                }
                Text(model.message).font(.subheadline).foregroundStyle(Color.muted)
                    .accessibilityLabel("Состояние: \(model.message)")
                Label("Прототип 0.2 · не заменяет сирены", systemImage: "exclamationmark.shield")
                    .font(.subheadline).foregroundStyle(Color.peach)
            }.padding(24)
        }.background(Color.night)
    }
    private var statusIcon: String {
        switch model.currentStatus { case .active, .partial: "exclamationmark.triangle.fill"; case .clear: "checkmark.circle"; case .unknown: "questionmark.circle" }
    }
    private var statusColor: Color {
        switch model.currentStatus { case .active, .partial: .peach; case .clear: .sky; case .unknown: .muted }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    var body: some View {
        NavigationStack {
            Form {
                Section("Регион") {
                    Picker("Область или город", selection: $model.prefs.region) {
                        ForEach(Region.all) { Text($0.name).tag($0.id) }
                    }
                    Text("Киев и Киевская область — разные регионы. Частичная тревога считается активной для всей выбранной области.")
                        .foregroundStyle(Color.muted)
                }
                Section("Звук") {
                    Picker("Мелодия", selection: $model.prefs.sound) {
                        Text("Системная").tag("system")
                        Text("Рассвет").tag("dawn")
                        Text("Импульс").tag("pulse")
                    }
                    Button("Послушать мелодию") { model.previewSound() }
                    Text("Громкость регулируется средствами iPhone. Проверяйте звук на устройстве; приложение не обещает менять системную громкость.")
                        .foregroundStyle(Color.muted)
                }
                Section("Ожидание отбоя · эксперимент") {
                    Toggle("Перенос при подтверждённой тревоге", isOn: $model.prefs.experimental)
                    Picker("Максимальное ожидание", selection: $model.prefs.maxDelayMinutes) {
                        Text("30 минут").tag(30); Text("1 час").tag(60); Text("2 часа").tag(120)
                    }
                    Text("Проверка за 30–3 секунды до сигнала, только пока приложение открыто и активно. Если экран заблокирован, интернет пропал или данные устарели — сигнал по времени. После переноса резерв прозвучит в предельное время даже при продолжающейся тревоге.")
                        .foregroundStyle(Color.peach)
                    Text("Будильник не сообщает, что можно выходить из укрытия. Следуйте официальным рекомендациям.")
                        .foregroundStyle(Color.muted)
                }
                Section("Источник данных") {
                    TextField("https://ваш-сервер.example", text: $model.prefs.serverURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Text("Адрес вашего HTTPS-прокси. API-токен хранится только на сервере, не в приложении. Без сервера обычный будильник работает, перенос — нет.")
                        .foregroundStyle(Color.muted)
                    Link("Запросить токен alerts.in.ua", destination: URL(string: "https://alerts.in.ua/api-request")!)
                }
                Section("Важно") {
                    Text("Настройки применяются к следующему установленному сигналу. Чтобы изменить текущий, отключите его и установите заново.")
                    Text("Не используйте прототип как единственный будильник перед школой. Оставьте отдельный резерв в приложении «Часы».")
                }
            }.scrollContentBackground(.hidden).background(Color.night)
                .navigationTitle("Настройки")
        }.onChange(of: model.prefs.region) { _, _ in model.savePreferences() }
            .onChange(of: model.prefs.sound) { _, _ in model.savePreferences() }
            .onChange(of: model.prefs.experimental) { _, _ in model.savePreferences() }
            .onChange(of: model.prefs.maxDelayMinutes) { _, _ in model.savePreferences() }
            .onChange(of: model.prefs.serverURL) { _, _ in model.savePreferences() }
    }
}

struct MapView: View {
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Карта тревог").font(.title2.bold()).padding(.horizontal, 20)
            Text("Веб-карта alerts.in.ua · интернет обязателен. Точные позиции дронов эта версия не предоставляет.")
                .font(.subheadline).foregroundStyle(Color.muted).padding(.horizontal, 20)
            if let error {
                Text(error).foregroundStyle(Color.peach).padding(.horizontal, 20)
            }
            AlertWebView(error: $error)
            Link("Открыть источник в Safari", destination: URL(string: "https://alerts.in.ua/")!)
                .padding(.horizontal, 20).padding(.bottom, 12)
        }.padding(.top, 20).background(Color.night)
    }
}

struct AlertWebView: UIViewRepresentable {
    @Binding var error: String?
    func makeCoordinator() -> Coordinator { Coordinator(error: $error) }
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.navigationDelegate = context.coordinator
        view.isOpaque = false; view.backgroundColor = .clear
        view.load(URLRequest(url: URL(string: "https://alerts.in.ua/")!))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    final class Coordinator: NSObject, WKNavigationDelegate {
        let error: Binding<String?>
        init(error: Binding<String?>) { self.error = error }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            self.error.wrappedValue = "Карта недоступна. Проверьте интернет или откройте источник в Safari."
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { error.wrappedValue = nil }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if action.targetFrame?.isMainFrame == true || action.targetFrame == nil {
                guard url.scheme == "https", let host = url.host,
                      host == "alerts.in.ua" || host.hasSuffix(".alerts.in.ua") else {
                    decisionHandler(.cancel); return
                }
            }
            decisionHandler(.allow)
        }
    }
}
