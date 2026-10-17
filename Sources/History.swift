import SwiftUI
struct HistoryView: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var filter = "all"
    @State private var clear = false
    @State private var extending: ReminderItem?
    @State private var extraMinutes = "5"
    @State private var deleting: ReminderItem?
    private var results: [ReminderItem] { model.items.filter { (filter == "all" || $0.kind.rawValue == filter) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || clockText($0.deadline).contains(query)) }.sorted { $0.createdAt > $1.createdAt } }
    private var days: [Date] { Array(Set(results.map { Calendar.current.startOfDay(for:$0.createdAt) })).sorted(by:>) }
    var body: some View {
        VStack(spacing:0) {
            HStack(alignment:.top) { VStack(alignment:.leading,spacing:5) { Text(model.text("历史记录","History")).font(.system(size:24,weight:.semibold)); Text(model.text("每一段时间，都有迹可循。","A place for the time you have spent.")).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button { clear = true } label: { Image(systemName:"trash").font(.system(size:18)) }.help(model.text("清空已结束历史","Clear finished history")) }.padding(24)
            HStack { Picker("",selection:$filter) { Text(model.text("全部", "All")).tag("all"); Text(model.text("任务", "Tasks")).tag("task"); Text(model.text("提醒", "Reminders")).tag("reminder") }.pickerStyle(.segmented) }.padding(.horizontal,24).padding(.bottom,12)
            TextField(model.text("搜索历史", "Search history"),text:$query).textFieldStyle(.roundedBorder).padding(.horizontal,24).padding(.bottom,12)
            Divider()
            if results.isEmpty { ContentUnavailableView(model.text("暂无项目", "No items"),systemImage:"clock",description:Text(model.text("从桌面加号开始创建提醒。", "Create a reminder with the desktop + button."))).frame(maxHeight:.infinity) }
            else { List { ForEach(days,id:\.self) { day in Section { ForEach(results.filter { Calendar.current.isDate($0.createdAt,inSameDayAs:day) }) { item in
                HStack(spacing:12) {
                    Image(systemName:item.kind == .task ? "checkmark.circle" : "clock").font(.system(size:18)).foregroundStyle(item.isActive ? Color.accentColor : .secondary)
                    VStack(alignment:.leading,spacing:4) { Text(item.title.isEmpty ? model.text("未命名", "Untitled") : item.title).font(.system(size:13,weight:.medium)).lineLimit(2); HStack { Text(clockText(item.deadline)); Text(status(item)) }.font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if item.isActive { Button { extending = item } label: { Image(systemName:"plus.circle") }.help(model.text("任意分钟加时", "Extend by minutes")); if item.state == .due { Menu(model.text("稍后", "Snooze")) { ForEach([1,5,7,10,15,30],id:\.self) { m in Button("\(m) min") { model.snooze(item.id,Double(m)) } } }.menuStyle(.borderlessButton).fixedSize() }; Button { model.finish(item.id) } label: { Image(systemName:"checkmark") }.help(model.text("完成", "Complete")) }
                    Button { deleting = item } label: { Image(systemName:"trash") }.buttonStyle(.borderless)
                }.padding(.vertical,5).accessibilityElement(children:.contain)
            } } header: { Text(day.formatted(date:.abbreviated,time:.omitted)).font(.system(size:11,weight:.semibold)).foregroundStyle(.secondary) } } }.scrollContentBackground(.hidden) }
        }.frame(width:590,height:600).background(MaterialPalette.canvas)
        .alert(model.text("清空已结束历史？", "Clear finished history?"),isPresented:$clear) { Button(model.text("取消", "Cancel"),role:.cancel) {}; Button(model.text("清空", "Clear"),role:.destructive) { model.clearHistory() } } message: { Text(model.text("活动项目会保留。此操作不能撤销。", "Active items are kept. This cannot be undone.")) }
        .sheet(item:$extending) { item in VStack(spacing:16) { Text(model.text("加时", "Extend")); TextField(model.text("1–999 分钟", "1–999 minutes"),text:$extraMinutes); HStack { Button(model.text("取消", "Cancel")) { extending = nil }; Button(model.text("加时", "Extend")) { if let value = Double(extraMinutes), (1...999).contains(value) { model.extend(item.id,value); extending = nil } }.keyboardShortcut(.defaultAction) } }.padding(24).frame(width:260) }
        .alert(model.text("删除项目？", "Delete item?"),isPresented:Binding(get:{ deleting != nil },set:{ if !$0 { deleting = nil } })) { Button(model.text("取消", "Cancel"),role:.cancel) { deleting = nil }; Button(model.text("删除", "Delete"),role:.destructive) { if let item = deleting { model.delete(item.id) }; deleting = nil } }
    }
    func status(_ item: ReminderItem) -> String { switch item.state { case .running: return model.text("进行中", "Running"); case .due: return model.text("已到期", "Due"); case .completed: return model.text("已完成", "Completed"); case .dismissed: return model.text("已提醒 · 已结束", "Dismissed"); case .cancelled: return model.text("已取消", "Cancelled") } }
}
