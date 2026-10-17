import SwiftUI
import AppKit

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
final class WidgetPanel: FloatingPanel {
    var drawingInset: CGFloat = 64
    var logicalSize = NSSize(width:100,height:118)
    var hasMouseCapture = false
    var logicalFrame: NSRect { NSRect(x:frame.minX+drawingInset,y:frame.minY,width:logicalSize.width,height:logicalSize.height) }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class AlertClock: ObservableObject {
    @Published var visibleAt: Date?
}
struct DueView: View {
    let item: ReminderItem
    @ObservedObject var model: AppModel
    @ObservedObject var clock: AlertClock
    var preview: Bool
    var dismiss: () -> Void
    @State private var snoozeOpen = false
    var body: some View {
        VStack(spacing:28) {
            Text(item.kind == .task ? "TASK" : "REMINDER").font(.system(size:13,weight:.bold)).tracking(5).foregroundStyle(.white.opacity(0.65))
            Text(item.title.isEmpty ? model.text("时间到了", "Time is up") : item.title).font(.system(size:52,weight:.semibold,design:.rounded)).multilineTextAlignment(.center).frame(maxWidth:760).padding(.bottom,14)
            HStack(spacing:16) {
                Button(action:dismiss) {
                    HStack(spacing:10) {
                        ZStack { Circle().stroke(.white.opacity(0.3),lineWidth:2); Circle().trim(from:0,to:remaining).stroke(.white,lineWidth:2).rotationEffect(.degrees(-90)) }.frame(width:22,height:22)
                        Text(model.text("关闭", "Close"))
                    }.frame(width:150,height:50).background(.white.opacity(0.16),in:RoundedRectangle(cornerRadius:14))
                }.keyboardShortcut(.defaultAction)
                Button { snoozeOpen = true } label: {
                    Label(model.text("稍后提醒", "Snooze Reminder"),systemImage:"clock.arrow.circlepath").frame(width:190,height:50).overlay(RoundedRectangle(cornerRadius:14).stroke(.white.opacity(0.35),lineWidth:1))
                }.popover(isPresented:$snoozeOpen) {
                    VStack(spacing:0) { ForEach([1,5,7,10,15,30],id:\.self) { m in Button("\(m) min") { snoozeOpen = false; if !preview { model.snooze(item.id,Double(m)) }; dismiss() }.buttonStyle(.plain).frame(width:140,height:34) } }.padding(8)
                }
            }.font(.system(size:17,weight:.semibold))
            if item.kind == .task { Button { if !preview { model.finish(item.id) }; dismiss() } label: { Label(model.text("完成任务", "Complete Task"),systemImage:"checkmark.circle").font(.system(size:18)) } }
        }.buttonStyle(.plain).foregroundStyle(.white).environment(\.colorScheme,.dark).padding(50).frame(maxWidth:.infinity,maxHeight:.infinity)
        .background { AlertBackdrop() }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }
    private var remaining: Double { guard model.preferences.config.autoClose, let start = clock.visibleAt else { return 1 }; return max(0,1-model.now.timeIntervalSince(start)/10) }
}
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var model: AppModel!
    var panel: WidgetPanel!
    var status: NSStatusItem!
    lazy var statusArtwork: NSImage? = {
        guard let url = Bundle.main.url(forResource:"StatusIcon",withExtension:"png"), let image = NSImage(contentsOf:url) else { return nil }
        image.size = NSSize(width:18,height:18); image.isTemplate = true
        return image
    }()
    var windows: [String:NSWindow] = [:]
    var alerts: [(ReminderItem,Bool)] = []
    var alertPanels: [NSPanel] = []
    var currentAlert: UUID?
    var alertClock = AlertClock()
    var widgetMonitor: Any?
    var closeTimer: Timer?
    var subscriptions: [AnyObject] = []
    let canvas = WidgetCanvas()
    var temporary = false
    var moving = false
    let tooltip = ItemTooltip()
    var pullAnchor: CGFloat?
    func applicationDidFinishLaunching(_ notification: Notification) {
        do { model = try AppModel() } catch { let alert = NSAlert(); alert.messageText = "灵提醒无法打开数据库"; alert.informativeText = error.localizedDescription; alert.runModal(); NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        if let url = Bundle.main.url(forResource:"IconArtwork",withExtension:"png"), let image = NSImage(contentsOf:url) { NSApp.applicationIconImage = image }
        panel = WidgetPanel(contentRect:NSRect(x:0,y:0,width:100,height:118),styleMask:[.borderless],backing:.buffered,defer:false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false; panel.delegate = self
        panel.isFloatingPanel = true; panel.becomesKeyOnlyIfNeeded = false
        model.acquireKeyboardFocus = { [weak self] in self?.focusWidget() }
        canvas.changed = { [weak self] in self?.resize() }
        panel.contentView = NSHostingView(rootView:ScaledWidget(model:model,preferences:model.preferences,canvas:canvas))
        status = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        if let button = status.button { button.target = self; button.action = #selector(statusClicked); button.sendAction(on:[.leftMouseUp,.rightMouseUp]) }
        model.proximityChanged = { [weak self] near in guard let self, !self.model.preferences.config.alwaysVisible else { return }; self.temporary = near; self.visibility() }
        model.showWidget = { [weak self] in self?.reveal() }
        model.configurationChanged = { [weak self] in guard self?.moving == false else { return }; self?.pullAnchor = nil; self?.lastVisibility = .distantPast; self?.position(); self?.updateTray() }
        model.present = { [weak self] item, preview in self?.enqueue(item,preview:preview) }
        model.dismissAlert = { [weak self] id in self?.dismiss(id) }
        model.hoverItem = { [weak self] item, rect in
            guard let self else { return }
            if let item, let rect { self.tooltip.show(item,anchor:rect,title:item.title.isEmpty ? self.model.text(item.kind == .task ? "任务" : "提醒",item.kind.rawValue.capitalized) : item.title) }
            else { self.tooltip.hide(after:0.08) }
        }
        model.pullingChanged = { [weak self] pulling in
            guard let self else { return }
            if pulling { self.pullAnchor = self.panel.logicalFrame.minX }
        }
        let token = model.$now.sink { [weak self] _ in self?.updateTray(); self?.visibility() }; subscriptions.append(token)
        NotificationCenter.default.addObserver(self,selector:#selector(screensChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(screensChanged),name:NSWorkspace.activeSpaceDidChangeNotification,object:nil)
        widgetMonitor = NSEvent.addLocalMonitorForEvents(matching:[.rightMouseDown,.leftMouseDown,.leftMouseUp]) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if event.type == .leftMouseDown {
                self.panel.hasMouseCapture = true
                if self.model.draftOpen { self.focusWidget() }
                return event
            }
            if event.type == .leftMouseUp { self.panel.hasMouseCapture = false; return event }
            guard self.panel.logicalFrame.contains(self.panel.convertPoint(toScreen:event.locationInWindow)) else { return nil }
            self.tooltip.hide(); self.temporary = true; self.model.widgetMenuOpen = true
            defer { self.model.widgetMenuOpen = false }
            NSMenu.popUpContextMenu(self.widgetMenu(),with:event,for:self.panel.contentView!)
            return nil
        }
        position(); updateTray(); model.tick()
        if !model.preferences.config.onboardingDone { openOnboarding() }
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") { DispatchQueue.main.asyncAfter(deadline:.now()+2) { self.openSettings() } }
    }
    func applicationWillTerminate(_ notification: Notification) { model?.audio.stopAll() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func focusWidget() {
        panel.ignoresMouseEvents = false
        NSApp.activate(ignoringOtherApps:true)
        panel.makeKeyAndOrderFront(nil)
    }
    func resize() {
        guard panel != nil else { return }
        if panel.isVisible { pullAnchor = panel.logicalFrame.minX }
        position()
    }
    var screen: NSScreen {
        NSScreen.screens.first { (($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0) == model.preferences.config.displayID } ?? NSScreen.main ?? NSScreen.screens[0]
    }
    func position() {
        guard let panel else { return }
        moving = true; defer { moving = false }
        let config = model.preferences.config, frame = screen.visibleFrame
        let scale = config.scale
        let width = canvas.width*scale, height: CGFloat = 118*scale
        let x: CGFloat, y: CGFloat
        if config.position == "custom" { x = pullAnchor.map { min(frame.maxX-width,max(frame.minX,$0)) } ?? (frame.minX + CGFloat(config.customX)*max(1,frame.width-width)); y = frame.minY + CGFloat(config.customY)*max(1,frame.height-height) }
        else { x = pullAnchor.map { min(frame.maxX-width,max(frame.minX,$0)) } ?? (frame.midX-width/2); y = config.position == "top" ? frame.maxY-height+16 : frame.minY+72-height/2 }
        panel.isMovableByWindowBackground = false
        let logicalOrigin = WidgetCanvas.clampedOrigin(NSPoint(x:x,y:y),size:NSSize(width:width,height:height),within:frame)
        panel.drawingInset = WidgetCanvas.margin*scale
        panel.logicalSize = NSSize(width:width,height:height)
        let target = NSRect(x:logicalOrigin.x-panel.drawingInset,y:logicalOrigin.y,width:(canvas.drawingWidth+WidgetCanvas.margin*2)*scale,height:height)
        panel.setFrame(target,display:true,animate:false)
        visibility()
    }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === windows["settings"] {
            model.settingsOpen = false
            model.refresh(); lastVisibility = .distantPast; visibility()
        }
    }
    func fullscreen() -> Bool {
        // Public on-screen window metadata: no screen recording or pixel capture.
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] else { return false }
        let target = screen.frame
        let top = NSScreen.screens.first?.frame.maxY ?? target.maxY
        let quartzTarget = CGRect(x:target.minX,y:top-target.maxY,width:target.width,height:target.height)
        return info.contains { row in
            guard let pid = row[kCGWindowOwnerPID as String] as? Int, pid != ProcessInfo.processInfo.processIdentifier,
                  let layer = row[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = row[kCGWindowBounds as String] as? [String:CGFloat], let rect = CGRect(dictionaryRepresentation:bounds as CFDictionary) else { return false }
            return abs(rect.width-target.width)<3 && abs(rect.height-target.height)<3 && rect.intersection(quartzTarget).width > target.width-3 && rect.intersection(quartzTarget).height > target.height-3
        }
    }
    private var lastVisibility = Date.distantPast
    func visibility() {
        guard panel != nil, Date().timeIntervalSince(lastVisibility)>0.7 else { return }; lastVisibility = Date()
        let hide = !model.settingsOpen && model.preferences.config.hideFullscreen && fullscreen()
        if currentAlert == nil && (model.settingsOpen || model.preferences.config.alwaysVisible || temporary || model.draftOpen) && !hide { panel.orderFrontRegardless() } else { panel.orderOut(nil); tooltip.hide() }
    }
    func reveal() { temporary = true; lastVisibility = .distantPast; visibility(); NSApp.activate(ignoringOtherApps:true); panel.makeKeyAndOrderFront(nil) }
    @objc func screensChanged() { position(); model.tick() }
    @objc func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { status.menu = menu(); status.button?.performClick(nil); status.menu = nil }
        else { if panel.isVisible && !model.preferences.config.alwaysVisible && !model.settingsOpen { temporary = false; panel.orderOut(nil) } else { reveal(); model.draftOpen.toggle() } }
    }
    func menu() -> NSMenu {
        let menu = NSMenu()
        for (title,selector) in [(model.text("新提醒", "New Reminder"),#selector(newReminder)),(model.text("历史", "History"),#selector(openHistory)),(model.text("设置", "Settings"),#selector(openSettings)),(model.text("使用引导", "Onboarding"),#selector(openOnboarding)),(model.text("取消最近创建的提醒", "Cancel Last Reminder"),#selector(cancelLast))] { let item = NSMenuItem(title:title,action:selector,keyEquivalent:""); item.target = self; menu.addItem(item) }
        menu.addItem(.separator()); let quit = NSMenuItem(title:model.text("退出灵提醒", "Quit LingMinder"),action:#selector(quit),keyEquivalent:"q"); quit.target = self; menu.addItem(quit); return menu
    }
    func updateTray() {
        guard let button = status?.button else { return }
        if let item = model.active.first { button.title = " \(item.state == .due ? "!" : String(max(1,Int(ceil(item.remaining(at:Date())/60)))))m"; button.toolTip = (item.title.isEmpty ? item.kind.rawValue.capitalized : item.title) + " · " + clockText(item.deadline) }
        else { button.title = ""; button.toolTip = "灵提醒 · LingMinder" }
        button.image = statusArtwork; button.imagePosition = .imageLeading
        button.alphaValue = model.preferences.config.animateTray && Int(Date().timeIntervalSince1970)%2 == 0 && !model.active.isEmpty ? 0.65 : 1
    }
    func show<V:View>(_ key: String, title: String, view: V) {
        if let window = windows[key] { NSApp.activate(ignoringOtherApps:true); window.makeKeyAndOrderFront(nil); return }
        let host = NSHostingController(rootView:view)
        let window = NSWindow(contentViewController:host); window.title = title
        window.styleMask = [.titled,.closable,.miniaturizable]; window.isReleasedWhenClosed = false; window.delegate = self; window.center(); windows[key] = window
        NSApp.activate(ignoringOtherApps:true); window.makeKeyAndOrderFront(nil)
    }
    @objc func openSettings() {
        model.settingsOpen = true
        lastVisibility = .distantPast; visibility()
        show("settings",title:model.text("灵提醒设置", "LingMinder Settings"),view:SettingsView(model:model,prefs:model.preferences,onboarding:{ self.openOnboarding() }))
    }
    @objc func openHistory() { show("history",title:model.text("历史", "History"),view:HistoryView(model:model)) }
    @objc func openOnboarding() { windows["onboarding"]?.close(); windows["onboarding"] = nil; show("onboarding",title:model.text("使用引导", "Onboarding"),view:OnboardingView(model:model,prefs:model.preferences,finish:{ self.windows["onboarding"]?.close(); self.reveal() })) }
    @objc func newReminder() { reveal(); model.draftOpen = true }
    @objc func cancelLast() { model.cancelLast() }
    @objc func quit() { NSApp.terminate(nil) }
    func widgetMenu() -> NSMenu {
        let menu = NSMenu()
        for (title,selector) in [(model.text("设置", "Settings"),#selector(openSettings)),(model.text("历史", "History"),#selector(openHistory))] { let item = NSMenuItem(title:title,action:selector,keyEquivalent:""); item.target = self; menu.addItem(item) }
        menu.addItem(.separator())
        let desktop = NSMenuItem(title:model.text("桌面常驻", "Always on Desktop"),action:#selector(toggleDesktop),keyEquivalent:""); desktop.target = self; desktop.state = model.preferences.config.alwaysVisible ? .on : .off; menu.addItem(desktop)
        menu.addItem(.separator()); let quitItem = NSMenuItem(title:model.text("退出", "Quit"),action:#selector(quit),keyEquivalent:"q"); quitItem.target = self; menu.addItem(quitItem)
        return menu
    }
    @objc func toggleDesktop() { temporary = false; model.preferences.config.alwaysVisible.toggle() }
    func enqueue(_ item: ReminderItem, preview: Bool) {
        guard currentAlert != item.id, !alerts.contains(where:{$0.0.notificationID == item.notificationID}) else { return }
        alerts.append((item,preview)); alerts.sort { $0.0.deadline < $1.0.deadline }; showNext()
    }
    func showNext() {
        guard currentAlert == nil, !alerts.isEmpty else { return }
        let (item,preview) = alerts.removeFirst()
        guard preview || model.core.items.contains(where:{$0.id == item.id && $0.isActive && $0.revision == item.revision}) else { showNext(); return }
        currentAlert = item.id; tooltip.hide(); panel.orderOut(nil); alertClock = AlertClock()
        for screen in NSScreen.screens {
            let window = FloatingPanel(contentRect:screen.frame,styleMask:[.borderless],backing:.buffered,defer:false)
            window.title = "灵提醒 · 到期提醒"
            window.level = .screenSaver; window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; window.isOpaque = false; window.backgroundColor = .clear; window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.contentView = NSHostingView(rootView:DueView(item:item,model:model,clock:alertClock,preview:preview,dismiss:{ [weak self] in self?.closePresented(item,preview:preview) }))
            window.setFrame(screen.frame,display:true); window.orderFrontRegardless(); alertPanels.append(window)
        }
        NSApp.activate(ignoringOtherApps:true); alertPanels.first?.makeKeyAndOrderFront(nil)
        confirmVisible(item,preview:preview,attempt:0)
    }
    func confirmVisible(_ item: ReminderItem, preview: Bool, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline:.now()+0.05) { [weak self] in
            guard let self, self.currentAlert == item.id else { return }
            if !self.alertPanels.isEmpty && self.alertPanels.allSatisfy({$0.isVisible && $0.occlusionState.contains(.visible)}) {
                if !preview { self.model.presentationConfirmed(item) }
                self.alertClock.visibleAt = Date()
                if self.model.preferences.config.customSound { self.model.audio.effect("notification",force:true) }
                if self.model.preferences.config.autoClose { self.closeTimer = Timer.scheduledTimer(withTimeInterval:10,repeats:false) { [weak self] _ in self?.closePresented(item,preview:preview) }; if let timer = self.closeTimer { RunLoop.main.add(timer,forMode:.common) } }
            } else if attempt < 10 { self.alertPanels.forEach{$0.orderFrontRegardless()}; self.confirmVisible(item,preview:preview,attempt:attempt+1) }
            else { self.dismiss(item.id); if !preview { self.model.presentationFailed(item) } }
        }
    }
    func closePresented(_ item: ReminderItem, preview: Bool) {
        guard currentAlert == item.id else { return }
        if preview { dismiss(item.id) }
        else { model.dismissItem(item.id) }
    }
    func dismiss(_ id: UUID) {
        alerts.removeAll { $0.0.id == id }
        guard currentAlert == id else { return }
        closeTimer?.invalidate(); closeTimer = nil; alertPanels.forEach { $0.close() }; alertPanels.removeAll(); currentAlert = nil
        lastVisibility = .distantPast; visibility()
        DispatchQueue.main.async { self.showNext() }
    }
}
@main struct LingMinderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        Settings { EmptyView() }.commands {
            CommandGroup(replacing: .appSettings) { Button("设置 / Settings") { delegate.openSettings() }.keyboardShortcut(",",modifiers:.command) }
            CommandMenu("灵提醒") {
                Button("新提醒 / New Reminder") { delegate.newReminder() }.keyboardShortcut("n",modifiers:.command)
                Button("历史 / History") { delegate.openHistory() }.keyboardShortcut("h",modifiers:[.command,.shift])
                Button("使用引导 / Onboarding") { delegate.openOnboarding() }
                if widgetUITestProfile { Button("QA: 准备拉伸") { delegate.reveal(); delegate.model.preparePullTest?() }.keyboardShortcut("p",modifiers:[.command,.shift]) }
            }
        }
    }
}
