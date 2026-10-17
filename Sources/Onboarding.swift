import SwiftUI
struct OnboardingView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @State private var step = 0
    @State private var allowed = false
    var finish: () -> Void
    var body: some View {
        VStack(spacing:22) {
            HStack { ForEach(0..<5) { i in Capsule().fill(i == step ? Color.accentColor : Color.secondary.opacity(0.15)).frame(width:i == step ? 26 : 9,height:5) } }
            Group {
                switch step {
                case 0:
                    Image(systemName:"bell.badge").font(.system(size:80)).foregroundStyle(Color.accentColor).frame(height:180)
                    Text(model.text("允许通知", "Allow Notifications")).font(.largeTitle.bold())
                    Text(model.text("即使浮窗隐藏，也能及时看到到期提醒。", "Receive reminders even when the widget is hidden."))
                    Button(allowed ? model.text("已允许", "Allowed") : model.text("允许系统通知", "Allow Notifications")) { model.notifications.request { allowed = $0 } }.buttonStyle(.borderedProminent)
                case 1:
                    CreationDemo(task:false).frame(height:180)
                    Text(model.text("欢迎使用灵提醒", "Welcome to LingMinder")).font(.largeTitle.bold())
                    Text(model.text("点击加号，拉伸设置 1–99 分钟。手动输入支持 999 分钟或具体时刻；填写内容后按回车。", "Click + and stretch for 1–99 minutes. Type up to 999 minutes or a clock time, add an optional title, then press Return."))
                case 2:
                    CreationDemo(task:true).frame(height:180)
                    Text(model.text("提醒与任务", "Reminders and Tasks")).font(.largeTitle.bold())
                    Text(model.text("点击图标或按 ↑ ↓ 切换。提醒让你记住一件事；任务陪你专注一段时间。任务可开启滴答背景音。", "Click the icon or press ↑ ↓ to switch. Reminders help you remember; tasks help you focus. Enable ticking in Focus settings."))
                case 3:
                    VStack(alignment:.leading,spacing:13) { Text(model.text("今天", "Today")).font(.caption).foregroundStyle(.secondary); Label(model.text("读书 · 进行中", "Read · Running"),systemImage:"checkmark.circle"); Divider(); Label(model.text("伸展 · 已完成", "Stretch · Completed"),systemImage:"clock") }.padding(25).frame(width:320,height:180).background(.quaternary.opacity(0.5),in:RoundedRectangle(cornerRadius:20))
                    Text(model.text("历史记录", "History")).font(.largeTitle.bold())
                    Text(model.text("按日期查看，搜索任务与提醒。到期不会自动完成；你可以加时、稍后提醒或标记完成。", "Browse by date and search. Due items stay available to extend, snooze or complete."))
                default:
                    HStack(spacing:18) { Image(systemName:"bell"); Text("10m").monospacedDigit(); Text(model.text("专注阅读 · 14:30", "Read · 14:30")).font(.caption).padding(12).background(.ultraThinMaterial,in:Capsule()) }.frame(height:180)
                    Text(model.text("菜单栏模式", "Menu Bar Mode")).font(.largeTitle.bold())
                    Text(model.text("菜单栏显示最近到期的项目。左键唤出浮窗，右键打开历史、设置与引导。", "The menu bar shows your next timer. Click to toggle the widget; right-click for History, Settings and Onboarding."))
                    Toggle(model.text("开机启动", "Launch at Login"),isOn:$prefs.config.launchAtLogin).frame(width:180)
                }
            }
            .multilineTextAlignment(.center)
            Spacer(minLength:0)
            HStack { if step > 0 { Button(model.text("上一步", "Back")) { step -= 1 } }; Spacer(); Button(step == 4 ? model.text("开始使用", "Get Started") : model.text("继续", "Continue")) { if step == 4 { prefs.config.onboardingDone = true; finish() } else { withAnimation(.easeInOut(duration:0.2)) { step += 1 } } }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(35).frame(width:590,height:470).background(MaterialPalette.canvas)
    }
}
struct CreationDemo: View {
    var task: Bool
    @State private var phase = 0
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    let pulse = Timer.publish(every:1.3,on:.main,in:.common).autoconnect()
    var body: some View {
        HStack(spacing:10) {
            if phase >= 4 { ZStack { Circle().stroke(.white,lineWidth:3); Text("35").font(.system(size:13,design:.rounded)) }.frame(width:38,height:38).transition(.scale); Image(systemName:"plus").padding(13).background(Glass().clipShape(RoundedRectangle(cornerRadius:14))) }
            else if phase == 0 { Image(systemName:"plus").font(.title2).padding(12).background(Glass().clipShape(RoundedRectangle(cornerRadius:14))) }
            else { HStack(spacing:12) { Image(systemName:"xmark").font(.caption); Image(systemName: task && phase % 2 == 0 ? "checkmark.circle" : "clock").contentTransition(.symbolEffect(.replace)); Text(phase == 1 ? "5" : "35").monospacedDigit(); if phase >= 3 { Text(task ? "专注阅读 / Read" : "给 Alex 打电话 / Call Alex").font(.system(size:12)).transition(.opacity) }; Image(systemName:phase >= 3 ? "arrow.up" : "line.3.vertical") }.padding(.horizontal,15).frame(width:phase == 1 ? 145 : phase == 2 ? 280 : 350,height:42).background(Frost().clipShape(StretchShape(tension: phase == 2 ? 8 : 0))).overlay(StretchShape(tension:phase == 2 ? 8 : 0).stroke(.white.opacity(0.3))).shadow(radius:8,y:4) }
        }.foregroundStyle(.white).environment(\.colorScheme,.dark).animation(reducedMotion ? nil : .spring(response:0.4,dampingFraction:0.64),value:phase).onReceive(pulse) { _ in if !reducedMotion { phase = (phase+1)%6 } }.onAppear { if reducedMotion { phase = 3 } }.accessibilityLabel(task ? "任务模式演示" : "创建计时演示")
    }
}
