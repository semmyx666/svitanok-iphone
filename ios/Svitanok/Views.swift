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
    @State private var editingTime = false
    @State private var choosingLocation = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("СВІТАНОК").font(.caption.weight(.bold)).tracking(4).foregroundStyle(Color.sky)
                        Text("Твоё утро").font(.title.bold())
                    }
                    Spacer()
                    Image(systemName: "sunrise.fill").font(.system(size: 32)).foregroundStyle(Color.peach)
                }
                Button { editingTime = true } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label(model.plan == nil ? "ВЫБЕРИ ВРЕМЯ" : "БУДИЛЬНИК", systemImage: "alarm.fill")
                                .font(.caption.weight(.bold)).tracking(1)
                            Spacer()
                            if model.plan == nil { Image(systemName: "pencil.circle.fill").font(.title2) }
                        }.foregroundStyle(Color.sky)
                        Text(ClockText.format(model.plan?.target ?? model.selectedDate))
                            .font(.system(size: 92, weight: .semibold, design: .rounded)).monospacedDigit()
                            .minimumScaleFactor(0.55).lineLimit(1).foregroundStyle(.white)
                        Text((model.plan?.target ?? model.selectedDate).formatted(date: .abbreviated, time: .omitted))
                            .font(.headline).foregroundStyle(Color.muted)
                        if model.plan == nil {
                            Label("Нажми здесь, чтобы изменить", systemImage: "hand.tap")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(Color.sky)
                        } else {
                            Label(model.setupVerified ? "Сигнал подтверждён системой" : "Установка требует проверки", systemImage: model.setupVerified ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.subheadline).foregroundStyle(Color.peach)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                        .background(Color.panel, in: RoundedRectangle(cornerRadius: 24))
                        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.sky.opacity(0.5), lineWidth: 1))
                }.buttonStyle(.plain).disabled(model.plan != nil).accessibilityIdentifier("choose-time")
                Button { choosingLocation = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "location.circle.fill").font(.title).foregroundStyle(Color.sky)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Моя местность").font(.caption).foregroundStyle(Color.muted)
                            Text(model.displayedRegionName).font(.headline).foregroundStyle(.white)
                        }
                        Spacer()
                        if model.plan == nil { Image(systemName: "chevron.right").foregroundStyle(Color.sky) }
                    }.padding(18).background(Color.panel, in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).disabled(model.plan != nil).accessibilityIdentifier("choose-location-home")
                if model.plan == nil {
                    Text("С закрытым экраном — только сигнал по времени.").font(.subheadline).foregroundStyle(Color.peach)
                    Button { Task { await model.arm() } } label: {
                        Label(model.busy ? "Устанавливаю…" : "Включить будильник", systemImage: "alarm.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
                    }.buttonStyle(.borderedProminent).tint(.sky).foregroundStyle(Color.night)
                        .disabled(model.busy).accessibilityIdentifier("arm-alarm")
                    Button { Task { await model.arm(test: true) } } label: {
                        Label("Проверить звук через 2 минуты", systemImage: "speaker.wave.2.fill")
                            .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }.buttonStyle(.bordered).tint(.peach).disabled(model.busy)
                    Text("Срабатывает один раз. Для следующего утра поставь новый сигнал.")
                        .font(.subheadline).foregroundStyle(Color.muted)
                } else {
                    Button(role: .destructive) { model.disarm() } label: {
                        Text("Отключить будильник и резерв").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }.buttonStyle(.bordered).disabled(model.busy)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label(model.statusText, systemImage: statusIcon).font(.headline).foregroundStyle(statusColor)
                    Text(model.networkMessage).font(.subheadline).foregroundStyle(Color.muted)
                    Button("Проверить связь") { Task { await model.refresh(force: true) } }
                        .buttonStyle(.bordered).tint(.sky).disabled(model.busy)
                }.padding(18).background(Color.panel, in: RoundedRectangle(cornerRadius: 18))
                VStack(alignment: .leading, spacing: 8) {
                    Label("С заблокированным экраном", systemImage: "lock.fill").font(.headline)
                    Text("Работает обычный сигнал по времени. Автоматическое ожидание отбоя в фоне в этой версии НЕ работает.")
                        .font(.subheadline).foregroundStyle(Color.peach)
                    if let plan = model.plan, plan.experimental {
                        Text("Резерв: \(plan.deadline.formatted(date: .omitted, time: .shortened)). Он может прозвучать даже во время тревоги.")
                            .font(.subheadline).foregroundStyle(Color.peach)
                    }
                }.padding(18).background(Color.peach.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                if !model.message.isEmpty { Text(model.message).font(.subheadline).foregroundStyle(Color.muted) }
                Label("Версия 0.4 · не заменяет оповещения о тревоге", systemImage: "exclamationmark.shield")
                    .font(.subheadline).foregroundStyle(Color.peach)
            }.padding(20)
        }.background(Color.night)
            .sheet(isPresented: $editingTime) { TimeEditor(date: $model.selectedDate) }
            .sheet(isPresented: $choosingLocation) { LocationPicker(model: model) }
    }
    private var statusIcon: String {
        switch model.currentStatus { case .active, .partial: "exclamationmark.triangle.fill"; case .clear: "checkmark.circle"; case .unknown: "questionmark.circle" }
    }
    private var statusColor: Color {
        switch model.currentStatus { case .active, .partial: .peach; case .clear: .sky; case .unknown: .muted }
    }
}

struct TimeEditor: View {
    @Binding var date: Date
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Во сколько разбудить") {
                    DatePicker("Время сигнала", selection: $date, displayedComponents: [.hourAndMinute])
                        .datePickerStyle(.wheel).labelsHidden().frame(maxWidth: .infinity)
                        .accessibilityIdentifier("time-wheel")
                }
                Section("В какой день") {
                    DatePicker("Дата", selection: $date, in: Date.now..., displayedComponents: [.date])
                        .datePickerStyle(.graphical)
                    Text("Время по настройкам iPhone. Выбери будущую дату: минимум через минуту.")
                        .font(.subheadline).foregroundStyle(Color.muted)
                }
            }.scrollContentBackground(.hidden).background(Color.night)
                .navigationTitle("Время будильника").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }.tint(.sky).environment(\.locale, Locale(identifier: "ru_RU"))
    }
}

struct LocationPicker: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss
    private var locations: [AlertLocation] {
        let matching = AlertLocation.all.filter { (model.prefs.dataSource != "public" || PublicCatalog.find($0.id) != nil) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || String($0.id) == query) }
        return matching.sorted { a, b in
            let priorities = [36, 155, 37]
            let ai = priorities.firstIndex(of: a.id) ?? 10, bi = priorities.firstIndex(of: b.id) ?? 10
            if ai != bi { return ai < bi }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Выбери район или громаду. Область целиком и отдельный район — разные пункты. Здесь только местности из справочника источника, не все населённые пункты.")
                        .font(.subheadline).foregroundStyle(Color.muted)
                }
                Section("Районы, громады и области") {
                    ForEach(locations) { location in
                        Button {
                            model.prefs.locationUID = location.id
                            model.snapshot = nil
                            model.savePreferences()
                            model.lastAttempt = .distantPast
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(location.name).foregroundStyle(.white)
                                    Text("\(location.kind) · UID \(location.id)").font(.caption).foregroundStyle(Color.muted)
                                }
                                Spacer()
                                if model.prefs.locationUID == location.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.sky) }
                            }.padding(.vertical, 5)
                        }.accessibilityIdentifier("location-\(location.id)")
                    }
                }
                if locations.isEmpty { Text("Не найдено. Попробуй название на украинском, например «Вінницький».") }
            }.scrollContentBackground(.hidden).background(Color.night)
                .searchable(text: $query, prompt: "Например: Вінницький")
                .navigationTitle("Выбери местность").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
        }.tint(.sky)
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var choosingLocation = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Где проверять тревогу") {
                    Button { choosingLocation = true } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Выбрать район или громаду").font(.headline)
                            Text(AlertLocation.find(model.prefs.locationUID)?.name ?? Region.all[model.prefs.region].name)
                                .foregroundStyle(Color.muted)
                        }.padding(.vertical, 6)
                    }.accessibilityIdentifier("choose-location-settings")
                    Text("Например: Вінницький район — отдельно от Гайсинського. Если тревогу объявили для всей области, следуй официальным оповещениям независимо от выбранного района.")
                        .font(.subheadline).foregroundStyle(Color.muted)
                }
                Section("Как работает будильник") {
                    Label("Обычный сигнал работает с закрытым экраном", systemImage: "lock.fill")
                    Toggle("Ждать отбоя при открытом приложении", isOn: $model.prefs.experimental)
                    Text("Эксперимент. НЕ работает автоматически при заблокированном экране или закрытом приложении. Если нужен обычный будильник — оставь переключатель выключенным.")
                        .font(.subheadline).foregroundStyle(Color.peach)
                    if model.prefs.experimental {
                        Picker("Разбудить не позднее чем через", selection: $model.prefs.maxDelayMinutes) {
                            Text("30 минут").tag(30); Text("1 час").tag(60); Text("2 часа").tag(120)
                        }
                        Text("Пример: сигнал 06:30, предел 1 час → резерв 07:30, даже если тревога продолжается. Отбой после 06:30 → новый сигнал через 5 секунд после получения свежих данных.")
                            .font(.subheadline).foregroundStyle(Color.muted)
                    }
                }
                Section("Звук") {
                    Picker("Мелодия", selection: $model.prefs.sound) {
                        Text("Системная").tag("system"); Text("Рассвет").tag("dawn"); Text("Импульс").tag("pulse")
                    }
                    Button("Послушать выбранный звук") { model.previewSound() }
                    Text("Громкость меняется средствами iPhone. Перед первым использованием проверь сигнал кнопкой «через 2 минуты» и заблокируй экран.")
                        .font(.subheadline).foregroundStyle(Color.muted)
                }
                Section("Откуда брать данные тревог") {
                    Picker("Источник", selection: $model.prefs.dataSource) {
                        Text("Без ключа · UA Siren").tag(Optional("public"))
                        Text("Мой сервер · alerts.in.ua").tag(Optional("proxy"))
                    }.accessibilityIdentifier("source-picker")
                    Text("UA Siren — публичный сторонний сервис. Ключ и свой сервер не нужны. Нужен интернет. Данные проверяются примерно каждые 15 секунд только при открытом приложении.")
                        .font(.subheadline).foregroundStyle(Color.muted)
                    if model.prefs.dataSource == "proxy" {
                    TextField("HTTPS-адрес сервера", text: $model.prefs.serverURL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    Text("Пока сервер не настроен, приложение НЕ получает тревоги и отбои. Для районов нужен сервер 0.3 из нового архива. Токен alerts.in.ua хранится на сервере, не здесь.")
                        .font(.subheadline).foregroundStyle(Color.muted)
                    }
                    Button("Проверить подключение") { Task { await model.refresh(force: true) } }
                    Text(model.networkMessage).font(.subheadline).foregroundStyle(Color.peach)
                    if model.prefs.dataSource == "proxy" { Link("Запросить API-токен у источника", destination: URL(string: "https://alerts.in.ua/api-request")!) }
                    Link("О публичном источнике UA Siren", destination: URL(string: "https://siren.pp.ua/")!)
                }
                Section("Важно знать") {
                    Text("Настройки относятся к следующему сигналу. Текущий отключи и установи заново, чтобы применить изменения.")
                    Text("Это не приложение гражданской защиты. «Нет тревоги» не подтверждает безопасность. Не отключай официальные оповещения и резерв в «Часах».")
                    Text("Версия 0.4: проверяется в симуляторе. Ночные испытания на реальном iPhone ещё не выполнены.")
                }
            }.scrollContentBackground(.hidden).background(Color.night).navigationTitle("Настройки")
                .sheet(isPresented: $choosingLocation) { LocationPicker(model: model) }
        }.onChange(of: model.prefs.region) { _, _ in model.savePreferences() }
            .onChange(of: model.prefs.sound) { _, _ in model.savePreferences() }
            .onChange(of: model.prefs.experimental) { _, _ in model.savePreferences() }
            .onChange(of: model.prefs.maxDelayMinutes) { _, _ in model.savePreferences() }
            .onChange(of: model.prefs.dataSource) { _, _ in model.snapshot = nil; model.lastAttempt = .distantPast; model.savePreferences() }
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
