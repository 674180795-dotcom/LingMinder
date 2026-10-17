import SwiftUI
import Carbon

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var value: HotKey?
    var label: String
    func makeNSView(context: Context) -> RecorderButton { let button = RecorderButton(); button.bezelStyle = .rounded; button.changed = { value = $0 }; return button }
    func updateNSView(_ button: RecorderButton, context: Context) { button.idleTitle = value?.display ?? label; button.title = button.recording ? "…" : button.idleTitle; button.changed = { value = $0 } }
}
final class RecorderButton: NSButton {
    var recording = false
    var idleTitle = ""
    private var monitor: Any?
    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    var changed: ((HotKey?) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) {
        recording = true; title = "…"; window?.makeFirstResponder(self)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
            guard let self, self.recording, self.window?.isKeyWindow == true else { return event }
            self.keyDown(with:event); return nil
        }
    }
    private func endRecording() { recording = false; title = idleTitle; if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }; window?.makeFirstResponder(nil) }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with:event); return }
        if event.keyCode == 53 { endRecording(); return }
        if event.keyCode == 51 || event.keyCode == 117 { changed?(nil); endRecording(); return }
        let flags = event.modifierFlags.intersection([.command,.option,.control,.shift])
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control) else { NSSound.beep(); return }
        var mods: UInt32 = 0, display = ""
        if flags.contains(.control) { mods |= UInt32(controlKey); display += "⌃" }
        if flags.contains(.option) { mods |= UInt32(optionKey); display += "⌥" }
        if flags.contains(.shift) { mods |= UInt32(shiftKey); display += "⇧" }
        if flags.contains(.command) { mods |= UInt32(cmdKey); display += "⌘" }
        display += event.charactersIgnoringModifiers?.uppercased() ?? "\(event.keyCode)"
        changed?(HotKey(keyCode:UInt32(event.keyCode),modifiers:mods,display:display)); endRecording()
    }
}
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var prefs: Preferences
    @State private var tab = 0
    @State private var playing = false
    var onboarding: () -> Void
    private let icons = ["gearshape","bell","headphones","command","info.circle"]
    private var names: [String] { [model.text("通用","General"),model.text("通知","Notifications"),model.text("专注","Focus"),model.text("快捷键","Shortcuts"),model.text("关于","About")] }
    private var subtitles: [String] { [model.text("让提醒融入你的桌面。","Make reminders at home on your desktop."),model.text("选择时间到来时的提醒方式。","Choose how a reminder reaches you."),model.text("为专注留一点声音与空间。","A little sound and space for focus."),model.text("用熟悉的按键，开始下一段时间。","Start your next timer with familiar keys."),model.text("为你的桌面留下一点安静的提醒。","A gentle reminder on your desktop.")] }
    var body: some View {
        HStack(spacing:0) {
            VStack(alignment:.leading,spacing:24) {
                HStack(spacing:10) {
                    Image(nsImage:NSApp.applicationIconImage).resizable().scaledToFit().frame(width:36,height:36)
                    VStack(alignment:.leading,spacing:3) { Text(model.text("灵提醒","LingMinder")).font(.system(size:14,weight:.semibold)); Text(model.text("设置","Settings")).font(.caption).foregroundStyle(.secondary) }
                }.padding(.horizontal,8)
                VStack(spacing:5) {
                    ForEach(0..<5) { i in
                        Button { tab = i; playing = false; model.refresh() } label: {
                            HStack(spacing:12) { Image(systemName:icons[i]).font(.system(size:20,weight:.regular)).frame(width:22); Text(names[i]).font(.system(size:13,weight:tab == i ? .semibold : .regular)).lineLimit(1).minimumScaleFactor(0.9); Spacer(minLength:0) }
                                .foregroundStyle(tab == i ? Color.accentColor : Color.primary)
                                .padding(.horizontal,12).frame(height:42)
                                .background(tab == i ? Color.accentColor.opacity(0.12) : .clear,in:RoundedRectangle(cornerRadius:9))
                                .contentShape(RoundedRectangle(cornerRadius:9))
                        }.buttonStyle(.plain).accessibilityAddTraits(tab == i ? [.isSelected] : [])
                    }
                }
                Spacer()
                Text("LingMinder · \(MaterialPalette.version)").font(.system(size:10)).foregroundStyle(.secondary).padding(.horizontal,9)
            }.padding(16).frame(width:200).frame(maxHeight:.infinity)
                .background { Frost(material:.sidebar,blendingMode:.withinWindow,dark:false) }
            Divider()
            VStack(alignment:.leading,spacing:0) {
                VStack(alignment:.leading,spacing:7) { Text(names[tab]).font(.system(size:24,weight:.semibold)); Text(subtitles[tab]).font(.system(size:12)).foregroundStyle(.secondary) }.padding(24)
                ScrollView {
                    VStack(alignment:.leading,spacing:20) { switch tab { case 0: general; case 1: notifications; case 2: focus; case 3: shortcuts; default: about } }
                        .padding(.horizontal,24).padding(.bottom,24).frame(maxWidth:.infinity,alignment:.leading)
                }
                if let error = model.error {
                    HStack(spacing:9) { Image(systemName:"exclamationmark.circle"); Text(error).font(.caption); Spacer(); Button { model.error = nil } label: { Image(systemName:"xmark").font(.system(size:12)) }.buttonStyle(.plain).help(model.text("关闭提示","Dismiss message")) }.foregroundStyle(.orange).padding(14)
                }
            }.frame(maxWidth:.infinity,maxHeight:.infinity).background(MaterialPalette.canvas)
        }.frame(width:736,height:570).tint(.accentColor).onDisappear { model.refresh() }
        .onChange(of:prefs.config.focusSound) { _, name in if playing { model.audio.previewBackground(name) } }
    }
    private func toggle(_ zh: String, _ en: String, _ value: Binding<Bool>) -> some View {
        HStack { Text(model.text(zh,en)); Spacer(); Toggle(model.text(zh,en),isOn:value).labelsHidden().toggleStyle(.switch).controlSize(.small) }
    }
    private var general: some View {
        Group {
            SettingsSection(title:model.text("浮窗与桌面","WIDGET & DESKTOP")) {
                toggle("桌面常驻","Always on Desktop",$prefs.config.alwaysVisible)
                toggle("全屏时隐藏浮窗","Hide widget in fullscreen",$prefs.config.hideFullscreen)
                Divider()
                Picker(model.text("显示器","Display"),selection:$prefs.config.displayID) {
                    Text(model.text("主显示器","Main display")).tag(UInt32(0))
                    ForEach(NSScreen.screens,id:\.localizedName) { screen in Text(screen.localizedName).tag((screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) }
                }
                Picker(model.text("浮窗位置","Position"),selection:$prefs.config.position) { Text(model.text("顶部","Top")).tag("top"); Text(model.text("底部","Bottom")).tag("bottom"); Text(model.text("自定义（拖动浮窗）","Custom (drag widget)")).tag("custom") }
                VStack(alignment:.leading,spacing:9) {
                    HStack { Text(model.text("尺寸","Size")); Spacer(); Text(String(format:"%.0f%%",prefs.config.scale*100)).monospacedDigit().foregroundStyle(.secondary) }
                    HStack(spacing:10) { Image(systemName:"minus").font(.caption).foregroundStyle(.secondary); Slider(value:$prefs.config.scale,in:0.75...1.4).accessibilityLabel(model.text("浮窗尺寸","Widget size")); Image(systemName:"plus").font(.caption).foregroundStyle(.secondary) }
                    Text(model.text("设置期间浮窗保持显示，可直接查看调整效果。","The widget stays visible while settings are open.")).font(.caption).foregroundStyle(.secondary)
                }
            }
            SettingsSection(title:model.text("系统联动","SYSTEM")) {
                toggle("开机启动","Launch at Login",$prefs.config.launchAtLogin)
                toggle("与 Apple 提醒事项同步","Sync with Apple Reminders",$prefs.config.syncReminders)
            }
            SettingsSection(title:model.text("体验与语言","EXPERIENCE & LANGUAGE")) {
                toggle("菜单栏图标动画","Animate menu bar icon",$prefs.config.animateTray)
                toggle("音效与触感","Audio & haptics",$prefs.config.audioHaptic)
                Divider()
                Picker("Language / 语言",selection:$prefs.config.language) { Text("简体中文").tag("zh-Hans"); Text("English").tag("en") }
            }
        }
    }
    private var notifications: some View {
        Group {
            SettingsSection(title:model.text("提醒方式","PRESENTATION")) {
                HStack(spacing:12) { ForEach(["blur","regular"],id:\.self) { style in
                    Button { prefs.config.notificationStyle = style } label: {
                        VStack(alignment:.leading,spacing:14) {
                            HStack { Image(systemName:style == "blur" ? "rectangle.inset.filled" : "bell.badge").font(.system(size:20)); Spacer(); Image(systemName:prefs.config.notificationStyle == style ? "checkmark.circle.fill" : "circle").font(.system(size:14)) }
                            Text(style == "blur" ? model.text("模糊全屏","Blur Screen") : model.text("系统通知","System Notification")).font(.system(size:12,weight:.medium)).lineLimit(2)
                        }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
                            .background(prefs.config.notificationStyle == style ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:10))
                            .overlay { RoundedRectangle(cornerRadius:10).stroke(prefs.config.notificationStyle == style ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.08),lineWidth:1) }
                            .foregroundStyle(prefs.config.notificationStyle == style ? Color.accentColor : Color.primary)
                    }.buttonStyle(.plain).accessibilityAddTraits(prefs.config.notificationStyle == style ? [.isSelected] : [])
                } }
                HStack { Button(model.text("预览","Preview"),systemImage:"eye") { model.preview() }; Spacer(); Button(model.text("允许系统通知","Allow Notifications")) { model.notifications.request { allowed in if !allowed { model.error = model.text("通知权限未开启；可在系统设置中允许。","Allow notifications in System Settings.") } } } }
            }
            SettingsSection(title:model.text("声音与关闭","SOUND & DISMISSAL")) {
                toggle("提醒声音","Notification sound",$prefs.config.customSound)
                Button(model.text("试听提醒音","Play notification sound"),systemImage:"play") { model.audio.effect("notification",force:true) }
                Divider()
                toggle("10 秒后自动关闭","Auto-close after 10 seconds",$prefs.config.autoClose)
                Text(model.text("关闭后，该次提醒结束并进入历史。只有明确完成，才完成 Apple 提醒事项。","Closing ends the alert locally. Apple Reminders completes only after explicit completion.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
    private var focus: some View {
        Group {
            SettingsSection(title:model.text("专注声音","FOCUS SOUND")) {
                toggle("专注背景声音","Focus sounds",$prefs.config.focusSounds)
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10) {
                    ForEach(Array(zip(["ticking","heart-beat","binaural","relax-music"],[model.text("滴答","Ticking"),model.text("心跳","Heart Beat"),model.text("双耳节拍","Binaural"),model.text("放松音乐","Relax Music")])),id:\.0) { name,label in
                        Button { prefs.config.focusSound = name } label: {
                            HStack(spacing:9) { Image(systemName:name == "ticking" ? "clock" : name == "heart-beat" ? "heart" : name == "binaural" ? "waveform" : "music.note").font(.system(size:18)).frame(width:20); Text(label).font(.system(size:12)); Spacer(minLength:0); if prefs.config.focusSound == name { Image(systemName:"checkmark").font(.system(size:10,weight:.semibold)) } }
                                .padding(12).frame(height:46).background(prefs.config.focusSound == name ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.035),in:RoundedRectangle(cornerRadius:9)).foregroundStyle(prefs.config.focusSound == name ? Color.accentColor : Color.primary)
                        }.buttonStyle(.plain)
                    }
                }
                Button(playing ? model.text("停止试听","Stop preview") : model.text("试听","Preview"),systemImage:playing ? "stop" : "play") { playing.toggle(); if playing { model.audio.previewBackground(prefs.config.focusSound) } else { model.refresh() } }
                Text(model.text("计时运行期间连续循环；多个项目共用一份声音。","Loops while a timer runs. Multiple timers share a single player.")).font(.caption).foregroundStyle(.secondary)
            }
            SettingsSection(title:model.text("任务显示","TASK APPEARANCE")) { toggle("任务在浮窗中显示全文","Display full task text in widget",$prefs.config.fullTaskText) }
        }
    }
    private var shortcuts: some View {
        Group {
            SettingsSection(title:model.text("常用操作","ACTIONS")) {
                shortcutRow("widget",model.text("打开浮窗","Open Widget"))
                shortcutRow("cancel",model.text("取消最近创建的提醒","Cancel Last Reminder"))
                Text(model.text("点击录制，Esc 取消，Delete 清除。组合需包含 ⌘、⌥ 或 ⌃。","Click to record. Esc cancels; Delete clears. Include ⌘, ⌥ or ⌃.")).font(.caption).foregroundStyle(.secondary)
            }
            SettingsSection(title:model.text("快速计时","QUICK TIMERS")) {
                ForEach(0..<4) { i in
                    HStack { Text("\(i+1)").font(.system(size:11,weight:.medium)).foregroundStyle(.secondary).frame(width:22,height:22).background(Color.primary.opacity(0.05),in:Circle()); TextField("min",value:$prefs.config.fastMinutes[i],format:.number).textFieldStyle(.roundedBorder).frame(width:48).onChange(of:prefs.config.fastMinutes[i]) { _, value in prefs.config.fastMinutes[i] = min(999,max(1,value)) }; Text("min").foregroundStyle(.secondary); Spacer(); recorder("quick\(i)") }
                    if i < 3 { Divider() }
                }
            }
        }
    }
    private func shortcutRow(_ key: String, _ label: String) -> some View { HStack { Text(label); Spacer(); recorder(key) } }
    private func recorder(_ key: String) -> some View {
        ShortcutRecorder(value:Binding(get:{ prefs.config.shortcuts[key] },set:{ next in
            if let next, prefs.config.shortcuts.contains(where:{ $0.key != key && $0.value.keyCode == next.keyCode && $0.value.modifiers == next.modifiers }) { model.error = model.text("该快捷键已被另一项使用。","This shortcut is already assigned.") }
            else { prefs.config.shortcuts[key] = next }
        }),label:model.text("录制快捷键","Record Shortcut")).frame(width:150,height:26)
    }
    private var about: some View {
        VStack(spacing:18) {
            Image(nsImage:NSApp.applicationIconImage).resizable().interpolation(.high).scaledToFit().frame(width:112,height:112)
            Text("灵提醒 · LingMinder").font(.system(size:23,weight:.semibold))
            Text("\(MaterialPalette.version) · macOS 14+").font(.system(size:12)).foregroundStyle(.secondary)
            Button(model.text("重新查看引导","Show Onboarding"),action:onboarding)
            Text(model.text("个人使用版。更新时退出应用，用新版本替换即可；计时与历史保存在独立数据目录。","Personal build. Quit and replace the app to update. Timers and history remain in your data folder.")).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth:330)
        }.padding(.vertical,20).frame(maxWidth:.infinity)
    }
}
