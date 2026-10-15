import SwiftUI

struct WakeChallengeView:View {
    @Bindable var model:AppModel
    let request:WakeChallenge
    @State private var answer=""
    @FocusState private var focused:Bool
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    Label("ПОРА ПРОСНУТЬСЯ",systemImage:"sunrise.fill")
                        .font(.caption.weight(.bold)).tracking(2).foregroundStyle(Color.peach)
                    Text("Разбуди голову").font(.largeTitle.bold())
                    Text(request.repeatLater ? "Реши пример. Затем выбери: ещё три напоминания или полностью закончить подъём." : "Чтобы отменить всю серию и резерв, введи правильный ответ.")
                        .font(.body).foregroundStyle(Color.muted).fixedSize(horizontal:false,vertical:true)
                    VStack(alignment:.leading,spacing:20) {
                        Text(request.question.text).font(.system(size:58,weight:.semibold,design:.rounded))
                            .minimumScaleFactor(0.6).lineLimit(1).monospacedDigit().accessibilityIdentifier("math-question")
                        TextField("Твой ответ",text:$answer).font(.system(size:32,weight:.semibold,design:.rounded))
                            .keyboardType(.numberPad).textContentType(.none).autocorrectionDisabled()
                            .padding(16).background(Color.night,in:RoundedRectangle(cornerRadius:14))
                            .focused($focused).accessibilityIdentifier("math-answer")
                    }.padding(24).frame(maxWidth:.infinity,alignment:.leading)
                        .background(Color.panel,in:RoundedRectangle(cornerRadius:24))
                    if !model.challengeError.isEmpty {
                        Label(model.challengeError,systemImage:"exclamationmark.circle.fill").foregroundStyle(Color.peach)
                            .fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("math-error")
                    }
                    if request.repeatLater {
                        Button { focused=false;Task{await model.submitChallenge(answer,finishAll:false)} } label: {
                            Label("Ответить · ещё 3 напоминания",systemImage:"repeat")
                                .font(.headline).frame(maxWidth:.infinity).padding(.vertical,16)
                        }.buttonStyle(.borderedProminent).tint(.sky).foregroundStyle(Color.night)
                            .disabled(model.busy).accessibilityIdentifier("math-repeat")
                    }
                    Button { focused=false;Task{await model.submitChallenge(answer,finishAll:true)} } label: {
                        Label("Я встал · выключить всю серию",systemImage:"checkmark.circle.fill")
                            .font(.headline).frame(maxWidth:.infinity).padding(.vertical,16)
                    }.buttonStyle(.bordered).tint(.sky).disabled(model.busy).accessibilityIdentifier("math-finish")
                    Text(model.ringingInApp ? "Звук приложения повторяется до правильного ответа. Системные повторы остаются, даже если остановить один сигнал на экране блокировки." : "Неверный ответ ничего не отключает. Отмена действует только на эту серию Світанка.")
                        .font(.subheadline).foregroundStyle(Color.muted).fixedSize(horizontal:false,vertical:true)
                    if !model.ringingInApp {
                        Button("Назад · серию не отключать") { model.challenge=nil;model.challengeError="" }
                            .padding(.vertical,8).tint(.muted)
                    }
                }.padding(24).padding(.bottom,24)
            }.scrollDismissesKeyboard(.interactively).background(Color.night)
                .navigationTitle("Проверка пробуждения").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItemGroup(placement:.keyboard) { Spacer();Button("Скрыть клавиатуру"){focused=false} } }
        }.tint(.sky).preferredColorScheme(.dark).interactiveDismissDisabled(true)
    }
}
