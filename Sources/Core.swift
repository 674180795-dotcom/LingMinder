import Foundation
import SQLite3

enum ItemKind: String, Codable, CaseIterable { case reminder, task }
enum ItemState: String, Codable { case running, due, completed, cancelled, dismissed }

struct ReminderItem: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: ItemKind
    var title: String
    var createdAt: Date
    var deadline: Date
    var duration: TimeInterval
    var state: ItemState = .running
    var completedAt: Date?
    var revision: Int = 0
    var deliveredRevision: Int = -1
    var appleID: String?
    var presentedAt: Date?
    var notificationID: String { "\(id.uuidString).\(revision)" }
    func remaining(at now: Date) -> TimeInterval { max(0, deadline.timeIntervalSince(now)) }
    func progress(at now: Date) -> Double { min(1, max(0, remaining(at: now) / max(1, duration))) }
    var isActive: Bool { state == .running || state == .due }
}

enum CoreError: LocalizedError {
    case invalidTime, invalidMinutes, missingItem, database(String)
    var errorDescription: String? {
        switch self {
        case .invalidTime: return "请输入 1–999 分钟或有效时刻（例如 14:30）。"
        case .invalidMinutes: return "时长必须在 1–999 分钟之间。"
        case .missingItem: return "这个计时已不存在。"
        case .database(let message): return "无法保存数据：\(message)"
        }
    }
}

struct TimeInput {
    static func minutes(_ text: String, now: Date, calendar: Calendar = .current) throws -> Double {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "：", with: ":")
        if let number = Double(input), number.isFinite, number >= 1, number <= 999 { return number }
        let normalized = input.lowercased().replacingOccurrences(of: " ", with: "")
        let match = normalized.range(of: "^([0-9]{1,2}):([0-9]{2})(am|pm)?$", options: .regularExpression)
        var hour: Int, minute: Int
        if match != nil {
            let pieces = normalized.components(separatedBy: ":")
            hour = Int(pieces[0]) ?? -1
            minute = Int(String(pieces[1].prefix(2))) ?? -1
        } else if normalized.range(of: "^[0-9]{1,2}(am|pm)$", options: .regularExpression) != nil {
            hour = Int(normalized.dropLast(2)) ?? -1; minute = 0
        } else { throw CoreError.invalidTime }
        if normalized.hasSuffix("am") || normalized.hasSuffix("pm") {
            guard (1...12).contains(hour) else { throw CoreError.invalidTime }
            hour %= 12
            if normalized.hasSuffix("pm") { hour += 12 }
        }
        guard (0...23).contains(hour), (0...59).contains(minute),
              let next = calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute, second: 0), matchingPolicy: .nextTime)
        else { throw CoreError.invalidTime }
        // Clock times mean their next occurrence, including tomorrow. The numeric limit applies to intervals.
        return max(1.0 / 60, next.timeIntervalSince(now) / 60)
    }
}

final class ItemRepository {
    private var database: OpaquePointer?
    let url: URL
    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw CoreError.database("无法打开数据库")
        }
        sqlite3_busy_timeout(database, 3000)
        try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL;")
        try execute("CREATE TABLE IF NOT EXISTS items (id TEXT PRIMARY KEY, payload BLOB NOT NULL); PRAGMA user_version=1;")
    }
    deinit { sqlite3_close(database) }
    private func execute(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &message) == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? "未知错误"
            sqlite3_free(message); throw CoreError.database(text)
        }
    }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var result: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &result, nil) == SQLITE_OK, let result else {
            throw CoreError.database(String(cString: sqlite3_errmsg(database)))
        }
        return result
    }
    func all() throws -> [ReminderItem] {
        let query = try statement("SELECT payload FROM items ORDER BY rowid DESC")
        defer { sqlite3_finalize(query) }
        var items: [ReminderItem] = []
        var step = sqlite3_step(query)
        while step == SQLITE_ROW {
            if let bytes = sqlite3_column_blob(query, 0) {
                let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(query, 0)))
                // Corruption is reported, never silently replaced with an empty database.
                items.append(try JSONDecoder().decode(ReminderItem.self, from: data))
            }
            step = sqlite3_step(query)
        }
        guard step == SQLITE_DONE else { throw CoreError.database(String(cString: sqlite3_errmsg(database))) }
        return items
    }
    func save(_ item: ReminderItem) throws {
        let query = try statement("INSERT INTO items(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload")
        defer { sqlite3_finalize(query) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(query, 1, item.id.uuidString, -1, transient)
        let data = try JSONEncoder().encode(item)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(query, 2, $0.baseAddress, Int32(data.count), transient) }
        guard sqlite3_step(query) == SQLITE_DONE else { throw CoreError.database(String(cString: sqlite3_errmsg(database))) }
    }
    func delete(_ id: UUID) throws {
        let query = try statement("DELETE FROM items WHERE id=?")
        defer { sqlite3_finalize(query) }
        sqlite3_bind_text(query, 1, id.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(query) == SQLITE_DONE else { throw CoreError.database(String(cString: sqlite3_errmsg(database))) }
    }
    func clearFinished() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            for item in try all() where !item.isActive { try delete(item.id) }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
}

final class TimerCore {
    let repository: ItemRepository
    private(set) var items: [ReminderItem]
    var now: () -> Date
    init(repository: ItemRepository, now: @escaping () -> Date = Date.init) throws {
        self.repository = repository; self.now = now; self.items = try repository.all()
    }
    var active: [ReminderItem] {
        items.filter(\.isActive).sorted { $0.deadline == $1.deadline ? $0.createdAt < $1.createdAt : $0.deadline < $1.deadline }
    }
    @discardableResult func create(kind: ItemKind, title: String, minutes: Double) throws -> ReminderItem {
        guard minutes.isFinite, minutes > 0, minutes <= 1440 else { throw CoreError.invalidMinutes }
        let date = now()
        let item = ReminderItem(id: UUID(), kind: kind, title: title.trimmingCharacters(in: .whitespacesAndNewlines), createdAt: date, deadline: date.addingTimeInterval(minutes * 60), duration: minutes * 60)
        try repository.save(item); items.insert(item, at: 0); return item
    }
    @discardableResult private func update(_ id: UUID, _ change: (inout ReminderItem) -> Void) throws -> ReminderItem {
        guard let index = items.firstIndex(where: { $0.id == id }) else { throw CoreError.missingItem }
        var item = items[index]; change(&item)
        try repository.save(item); items[index] = item; return item
    }
    func extend(_ id: UUID, minutes: Double) throws -> ReminderItem {
        guard minutes.isFinite, (1...999).contains(minutes) else { throw CoreError.invalidMinutes }
        return try update(id) {
            $0.deadline = max($0.deadline, now()).addingTimeInterval(minutes * 60)
            $0.duration = max(1, $0.deadline.timeIntervalSince($0.createdAt))
            $0.state = .running; $0.completedAt = nil; $0.presentedAt = nil; $0.revision += 1
        }
    }
    func snooze(_ id: UUID, minutes: Double) throws -> ReminderItem {
        guard minutes.isFinite, (1...999).contains(minutes) else { throw CoreError.invalidMinutes }
        return try update(id) {
            $0.deadline = now().addingTimeInterval(minutes * 60); $0.duration = minutes * 60
            $0.state = .running; $0.completedAt = nil; $0.presentedAt = nil; $0.revision += 1
        }
    }
    func finish(_ id: UUID, cancelled: Bool = false) throws -> ReminderItem {
        try update(id) { $0.state = cancelled ? .cancelled : .completed; $0.completedAt = now() }
    }
    func dismiss(_ id: UUID) throws -> ReminderItem {
        try update(id) { $0.state = .dismissed; $0.completedAt = nil }
    }
    func bindApple(_ id: UUID, identifier: String?) throws { _ = try update(id) { $0.appleID = identifier } }
    func markPresented(_ id: UUID, revision: Int) throws {
        _ = try update(id) { if $0.revision == revision { $0.deliveredRevision = revision; $0.presentedAt = now() } }
    }
    func dueItems() throws -> [ReminderItem] {
        for item in active where item.state == .running && item.deadline <= now() {
            _ = try update(item.id) { $0.state = .due }
        }
        return active.filter { $0.deadline <= now() && $0.deliveredRevision < $0.revision }
    }
    func delete(_ id: UUID) throws { try repository.delete(id); items.removeAll { $0.id == id } }
    func clearHistory() throws { try repository.clearFinished(); items.removeAll { !$0.isActive } }
    func reload() throws { items = try repository.all() }
}

struct PullValue {
    let minutes: Int
    let extensionWidth: CGFloat
    init(start: Int, delta: CGFloat) {
        minutes = max(1,min(99,start + Int((delta / 4).rounded())))
        extensionWidth = max(0,min(392,delta))
    }
}
