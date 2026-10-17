import AppKit
import UserNotifications
import EventKit
import ServiceManagement
import Carbon

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    let center = UNUserNotificationCenter.current()
    var action: ((UUID, String) -> Void)?
    var failure: ((String) -> Void)?
    private var scheduled: Set<String> = []
    private var ready = false
    private var waiting: [() -> Void] = []
    private var generation: [UUID:Int] = [:]
    private var flights: [String:[(Bool) -> Void]] = [:]
    override init() {
        super.init(); center.delegate = self
        let snoozes = [1,5,7,10,15,30].map { UNNotificationAction(identifier: "snooze.\($0)", title: "\($0) min", options: []) }
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "reminder", actions: Array(snoozes.prefix(3)) + [UNNotificationAction(identifier: "done", title: "✓", options: [])], intentIdentifiers: []),
            UNNotificationCategory(identifier: "task", actions: [UNNotificationAction(identifier: "done", title: "✓", options: [])], intentIdentifiers: [])
        ])
        let loading = DispatchGroup()
        loading.enter(); center.getPendingNotificationRequests { requests in DispatchQueue.main.async { self.scheduled.formUnion(requests.map(\.identifier)); loading.leave() } }
        loading.enter(); center.getDeliveredNotifications { notifications in DispatchQueue.main.async { self.scheduled.formUnion(notifications.map { $0.request.identifier }); loading.leave() } }
        loading.notify(queue: .main) { self.ready = true; let work = self.waiting; self.waiting.removeAll(); work.forEach { $0() } }
    }
    func request(_ completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { allowed, error in
            DispatchQueue.main.async { if let error { self.failure?(error.localizedDescription) }; completion(allowed) }
        }
    }
    func schedule(_ item: ReminderItem, sound: Bool, completion: @escaping (Bool) -> Void = { _ in }) {
        guard ready else { waiting.append { [weak self] in self?.schedule(item,sound:sound,completion:completion) }; return }
        guard !scheduled.contains(item.notificationID) else { completion(true); return }
        if flights[item.notificationID] != nil { flights[item.notificationID]?.append(completion); return }
        flights[item.notificationID] = [completion]
        let epoch = generation[item.id,default:0]; generation[item.id] = epoch
        func resolve(_ success: Bool) { let callbacks = self.flights.removeValue(forKey:item.notificationID) ?? []; callbacks.forEach { $0(success) } }
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                DispatchQueue.main.async { resolve(false) }; return
            }
            let content = UNMutableNotificationContent()
            content.title = item.kind == .task ? "灵提醒 · 任务 / Task" : "灵提醒 · 提醒 / Reminder"
            content.body = item.title.isEmpty ? (item.kind == .task ? "专注时间结束 / Focus finished" : "时间到了 / Time is up") : item.title
            content.categoryIdentifier = item.kind.rawValue
            content.userInfo = ["id": item.id.uuidString, "revision": item.revision]
            if sound { content.sound = UNNotificationSound(named: UNNotificationSoundName("notification.caf")) }
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, item.deadline.timeIntervalSinceNow), repeats: false)
            self.center.add(UNNotificationRequest(identifier: item.notificationID, content: content, trigger: trigger)) { error in
                DispatchQueue.main.async {
                    if self.generation[item.id,default:0] != epoch { self.center.removePendingNotificationRequests(withIdentifiers:[item.notificationID]); resolve(false) }
                    else if let error { self.failure?(error.localizedDescription); resolve(false) }
                    else { self.scheduled.insert(item.notificationID); resolve(true) }
                }
            }
        }
    }
    func remove(_ item: ReminderItem) {
        guard ready else { waiting.append { [weak self] in self?.remove(item) }; return }
        generation[item.id,default:0] += 1
        let prefix = item.id.uuidString + "."
        let ids = scheduled.filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: Array(ids))
        center.removeDeliveredNotifications(withIdentifiers: Array(ids) + [item.notificationID])
        scheduled.subtract(ids)
    }
    func cancelPending() { guard ready else { waiting.append { [weak self] in self?.cancelPending() }; return }; for id in Array(generation.keys) { generation[id,default:0] += 1 }; waiting.removeAll(); center.removeAllPendingNotificationRequests(); scheduled.removeAll() }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let text = response.notification.request.content.userInfo["id"] as? String, let id = UUID(uuidString: text) {
            DispatchQueue.main.async { self.action?(id, response.actionIdentifier) }
        }
        completionHandler()
    }
}

final class ReminderBridge {
    private let store = EKEventStore()
    var failure: ((String) -> Void)?
    var externalCompletion: ((String) -> Void)?
    private var permitted = false
    private var writing = false
    private var observer: NSObjectProtocol?
    init() {
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in self?.checkOwned() }
    }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    private var owned: Set<String> = []
    func request(_ completion: @escaping (Bool) -> Void) {
        store.requestFullAccessToReminders { allowed, error in DispatchQueue.main.async {
            self.permitted = allowed
            if let error { self.failure?(error.localizedDescription) }
            completion(allowed)
        } }
    }
    private func calendar() throws -> EKCalendar {
        if let result = store.calendars(for: .reminder).first(where: { $0.title == "灵提醒" && $0.allowsContentModifications }) { return result }
        let result = EKCalendar(for: .reminder, eventStore: store); result.title = "灵提醒"
        guard let source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first(where: { $0.sourceType == .local || $0.sourceType == .calDAV }) else {
            throw NSError(domain: "LingMinder", code: 1, userInfo: [NSLocalizedDescriptionKey: "没有可写入的提醒事项账户。"])
        }
        result.source = source; try store.saveCalendar(result, commit: true); return result
    }
    func sync(_ item: ReminderItem) throws -> String? {
        guard permitted else { return nil }
        writing = true; defer { writing = false }
        let existing = item.appleID.flatMap { store.calendarItem(withIdentifier: $0) as? EKReminder }
        if item.state == .cancelled {
            if let existing { try store.remove(existing, commit: true) }; return nil
        }
        let reminder = existing ?? EKReminder(eventStore: store)
        if existing == nil { reminder.calendar = try calendar() }
        reminder.title = item.title.isEmpty ? (item.kind == .task ? "专注任务" : "提醒") : item.title
        reminder.notes = "Created by LingMinder · \(item.id.uuidString)"
        reminder.dueDateComponents = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second,.timeZone], from: item.deadline)
        reminder.isCompleted = item.state == .completed
        reminder.completionDate = item.state == .completed ? item.completedAt : nil
        try store.save(reminder, commit: true)
        owned.insert(reminder.calendarItemIdentifier)
        return reminder.calendarItemIdentifier
    }
    func track(_ identifiers: [String]) { owned.formUnion(identifiers) }
    private func checkOwned() {
        guard permitted, !writing else { return }
        for id in owned {
            if let reminder = store.calendarItem(withIdentifier: id) as? EKReminder, reminder.isCompleted { externalCompletion?(id) }
        }
    }
}

final class GlobalShortcuts {
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var action: ((UInt32) -> Void)?
    var failure: ((String) -> Void)?
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            if result == noErr { Unmanaged<GlobalShortcuts>.fromOpaque(context).takeUnretainedValue().action?(id.id) }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    deinit { references.forEach { UnregisterEventHotKey($0) }; if let handler { RemoveEventHandler(handler) } }
    func register(_ keys: [String: HotKey]) {
        references.forEach { UnregisterEventHotKey($0) }; references.removeAll()
        for (index, name) in ["widget", "cancel", "quick0", "quick1", "quick2", "quick3"].enumerated() {
            guard let key = keys[name] else { continue }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(key.keyCode, key.modifiers, EventHotKeyID(signature: 0x4c4d4e44, id: UInt32(index)), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { references.append(ref) }
            else { failure?("快捷键 \(key.display) 无法注册（\(status)），请换一个组合。") }
        }
    }
}
