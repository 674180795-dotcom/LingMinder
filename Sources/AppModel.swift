import AppKit
import Combine
import ServiceManagement

final class AppModel: ObservableObject {
    let preferences = Preferences()
    let core: TimerCore
    let audio = AudioController()
    let notifications = NotificationService()
    let reminders = ReminderBridge()
    let shortcuts = GlobalShortcuts()
    @Published var items: [ReminderItem] = []
    @Published var now = Date()
    @Published var error: String?
    @Published var draftOpen = false
    @Published var widgetMenuOpen = false
    @Published var settingsOpen = false
    var proximityChanged: ((Bool)->Void)?
    var showWidget: (() -> Void)?
    var configurationChanged: (() -> Void)?
    var present: ((ReminderItem, Bool) -> Void)?
    var dismissAlert: ((UUID) -> Void)?
    var hoverItem: ((ReminderItem?, NSRect?) -> Void)?
    var pullingChanged: ((Bool) -> Void)?
    var preparePullTest: (() -> Void)?
    var acquireKeyboardFocus: (() -> Void)?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var syncEnabled = false
    private var previous: Configuration
    private var pending: Set<String> = []
    init() throws {
        if !preferences.defaults.bool(forKey:"compactRevision2Applied") {
            preferences.config.scale = 1
            preferences.defaults.set(true,forKey:"compactRevision2Applied")
        }
        previous = preferences.config
        let root = ProcessInfo.processInfo.environment["LINGMINDER_DATA"].map { URL(fileURLWithPath: $0) }
            ?? (widgetUITestProfile ? URL(fileURLWithPath:"/private/tmp/LingMinder-ui024") : nil)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LingMinder")
        core = try TimerCore(repository: ItemRepository(url: root.appendingPathComponent("items.sqlite")))
        items = core.items
        preferences.onChange = { [weak self] in self?.applyConfiguration() }
        notifications.failure = { [weak self] in self?.error = $0 }
        notifications.action = { [weak self] id, action in
            if action == "done" { self?.finish(id) }
            else if action.hasPrefix("snooze."), let minutes = Double(action.dropFirst(7)) { self?.snooze(id, minutes) }
            else { self?.showWidget?() }
        }
        reminders.failure = { [weak self] in self?.error = $0 }
        reminders.externalCompletion = { [weak self] appleID in
            guard let self, self.syncEnabled, let item = self.items.first(where: { $0.appleID == appleID && $0.isActive }) else { return }
            self.finish(item.id)
        }
        shortcuts.failure = { [weak self] in self?.error = $0 }
        shortcuts.action = { [weak self] index in
            guard let self else { return }
            if index == 0 { self.showWidget?(); self.draftOpen = true }
            else if index == 1 { self.cancelLast() }
            else { self.create(kind: .reminder, title: "", text: String(self.preferences.config.fastMinutes[Int(index)-2])) }
        }
        shortcuts.register(preferences.config.shortcuts)
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.tick() })
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name("NSSystemClockDidChangeNotification"), object: nil, queue: .main) { [weak self] _ in self?.tick() })
        if preferences.config.syncReminders { enableSync() }
    }
    var active: [ReminderItem] { items.filter(\.isActive).sorted { $0.deadline < $1.deadline } }
    func text(_ chinese: String, _ english: String) -> String { preferences.text(chinese, english) }
    private func perform(_ work: () throws -> Void) { do { try work(); refresh() } catch { self.error = error.localizedDescription } }
    func refresh() {
        items = core.items
        audio.reconcile(running: active.contains { $0.state == .running }, configuration: preferences.config)
    }
    func create(kind: ItemKind, title: String, text: String) {
        perform {
            let minutes = try TimeInput.minutes(text, now: Date())
            let item = try core.create(kind: kind, title: title, minutes: minutes)
            audio.effect("funky"); schedule(item); sync(item); draftOpen = false
        }
    }
    func extend(_ id: UUID, _ minutes: Double) {
        perform { if let old = items.first(where: { $0.id == id }) { notifications.remove(old) }; let item = try core.extend(id, minutes: minutes); pending = pending.filter { !$0.hasPrefix(id.uuidString) }; dismissAlert?(id); schedule(item); sync(item) }
    }
    func snooze(_ id: UUID, _ minutes: Double) {
        perform { if let old = items.first(where: { $0.id == id }) { notifications.remove(old) }; let item = try core.snooze(id, minutes: minutes); pending = pending.filter { !$0.hasPrefix(id.uuidString) }; dismissAlert?(id); schedule(item); sync(item) }
    }
    func finish(_ id: UUID, cancelled: Bool = false) {
        perform { let item = try core.finish(id, cancelled: cancelled); notifications.remove(item); dismissAlert?(id); sync(item); audio.effect("pong") }
    }
    func dismissItem(_ id: UUID) {
        perform { let item = try core.dismiss(id); notifications.remove(item); dismissAlert?(id); sync(item) }
    }
    func presentationConfirmed(_ item: ReminderItem) {
        perform { try core.markPresented(item.id,revision:item.revision) }
    }
    func presentationFailed(_ item: ReminderItem) {
        DispatchQueue.main.asyncAfter(deadline:.now()+2) { [weak self] in self?.pending.remove(item.notificationID) }
    }
    func cancelLast() { if let item = active.max(by: { $0.createdAt < $1.createdAt }) { finish(item.id, cancelled: true) } }
    func delete(_ id: UUID) { perform { if let item = items.first(where: { $0.id == id }), item.isActive { notifications.remove(item); sync(try core.finish(id, cancelled: true)) }; dismissAlert?(id); try core.delete(id) } }
    func clearHistory() { perform { try core.clearHistory() } }
    private func schedule(_ item: ReminderItem) {
        if preferences.config.notificationStyle == "regular" {
            notifications.schedule(item, sound: preferences.config.customSound)
        }
    }
    func tick() {
        now = Date()
        do {
            let due = try core.dueItems()
            if items != core.items { refresh() }
            for item in due where !pending.contains(item.notificationID) {
                pending.insert(item.notificationID)
                if preferences.config.notificationStyle == "regular" {
                    notifications.schedule(item, sound: preferences.config.customSound) { [weak self] allowed in
                        guard let self, let current = self.core.items.first(where: { $0.id == item.id }), current.isActive, current.revision == item.revision else { return }
                        if allowed { try? self.core.markPresented(item.id, revision: item.revision); self.refresh() }
                        else { self.present?(item, false); self.error = self.text("系统通知未获授权，已在应用中显示到期提醒。", "Notifications are unavailable; the reminder is shown in the app."); self.refresh() }
                    }
                } else { present?(item, false); refresh() }
            }
        } catch { self.error = error.localizedDescription }
    }
    func preview() {
        let item = ReminderItem(id:UUID(),kind:.reminder,title:text("这是提醒预览", "This is a reminder preview"),createdAt:now,deadline:now,duration:60)
        if preferences.config.notificationStyle == "regular" { notifications.schedule(item,sound:preferences.config.customSound) { [weak self] allowed in if !allowed { self?.error = self?.text("请先允许系统通知。", "Please allow notifications first.") } } }
        else { present?(item,true) }
    }
    private func sync(_ item: ReminderItem) {
        guard syncEnabled else { return }
        do { let id = try reminders.sync(item); if id != item.appleID { try core.bindApple(item.id, identifier: id) } }
        catch { self.error = text("Apple 提醒事项同步失败；本地计时仍保留：", "Apple Reminders sync failed; your local timer is saved: ") + error.localizedDescription }
    }
    func enableSync() {
        reminders.request { [weak self] allowed in
            guard let self else { return }; self.syncEnabled = allowed && self.preferences.config.syncReminders
            if !allowed { self.error = self.text("请在系统设置 → 隐私与安全性 → 提醒事项中允许灵提醒。", "Allow LingMinder in System Settings → Privacy & Security → Reminders.") }
            if self.syncEnabled { self.reminders.track(self.items.compactMap(\.appleID)); self.items.forEach { self.sync($0) }; self.refresh() }
        }
    }
    private func applyConfiguration() {
        let config = preferences.config
        if previous.shortcuts != config.shortcuts { shortcuts.register(config.shortcuts) }
        if previous.launchAtLogin != config.launchAtLogin {
            do { if config.launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
            catch { self.error = error.localizedDescription }
        }
        if previous.syncReminders != config.syncReminders { if config.syncReminders { enableSync() } else { syncEnabled = false } }
        if previous.notificationStyle != config.notificationStyle || previous.customSound != config.customSound {
            notifications.cancelPending(); active.filter { $0.state == .running }.forEach(schedule)
        }
        previous = config; refresh(); configurationChanged?()
    }
}
