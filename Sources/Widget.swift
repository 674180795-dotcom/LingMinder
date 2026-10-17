import SwiftUI
import AppKit

struct StretchShape: Shape {
    var tension: CGFloat
    var animatableData: CGFloat { get { tension } set { tension = newValue } }
    func path(in r: CGRect) -> Path {
        let radius: CGFloat = min(r.height / 2, 20), bend = min(10, tension)
        var p = Path(); p.move(to: CGPoint(x: radius,y: 0))
        p.addQuadCurve(to: CGPoint(x:r.width-radius,y:0), control: CGPoint(x:r.midX,y:bend))
        p.addQuadCurve(to: CGPoint(x:r.width,y:radius), control: CGPoint(x:r.width,y:0))
        p.addLine(to: CGPoint(x:r.width,y:r.height-radius)); p.addQuadCurve(to: CGPoint(x:r.width-radius,y:r.height), control: CGPoint(x:r.width,y:r.height))
        p.addQuadCurve(to: CGPoint(x:radius,y:r.height), control: CGPoint(x:r.midX,y:r.height-bend))
        p.addQuadCurve(to: CGPoint(x:0,y:r.height-radius), control: CGPoint(x:0,y:r.height)); p.addLine(to: CGPoint(x:0,y:radius)); p.addQuadCurve(to: CGPoint(x:radius,y:0), control: .zero); return p
    }
}
struct WidgetView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @StateObject private var interaction: WidgetInteraction
    @State private var minutes = "1"
    @State private var title = ""
    @State private var kind: ItemKind = .reminder
    @State private var stretch: CGFloat = 0
    @State private var visualWidth: CGFloat = 126
    @State private var visualTension: CGFloat = 0
    @State private var settlementToken = UUID()
    @State private var topEdge = HoverGeometry()
    @State private var bottomEdge = HoverGeometry()
    
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @FocusState private var focus: Int?
    let canvas: WidgetCanvas
    init(model:AppModel,preferences:Preferences,canvas:WidgetCanvas) {
        self.model = model; self.preferences = preferences; self.canvas = canvas
        _interaction = StateObject(wrappedValue:WidgetInteraction(model:model))
    }
    private var editing: Bool { interaction.contentPhase == .editing }
    private var pulling: Bool { interaction.contentPhase == .pulling }
    private var expanded: Bool { editing || pulling || interaction.contentPhase == .primed }
    private var barWidth: CGFloat { editing ? 270 : 126 + stretch }
    var body: some View {
        HStack(spacing:9) {
            entryButton
            if !model.active.isEmpty { ScrollView(.horizontal,showsIndicators:false) {
                HStack(spacing:9) { ForEach(model.active) { item in RingItem(item:item,model:model,interaction:interaction,full:preferences.config.fullTaskText) } }
            }.scrollClipDisabled().frame(width:activeWidth,height:44) }
            if expanded { creationBar.transition(.identity) }
        }.textFieldStyle(.plain).buttonStyle(.plain).foregroundStyle(.white).environment(\.colorScheme,.dark).padding(18).frame(height:118)
        .shadow(color:.black.opacity(0.16),radius:6,y:3)
        .background(WidgetSurface(model:model,interaction:interaction,geometry:interaction.group,click:{_,_ in}))
        .onChange(of:model.draftOpen) { _,open in
            if open { if interaction.contentPhase != .pulling && interaction.contentPhase != .editing {
                settlementToken = UUID(); canvas.cancelSettlement(); visualWidth = 270; visualTension = 0
                interaction.phase = .editing; focus = 0
            } }
            else { interaction.phase = .idle }
            if open { model.acquireKeyboardFocus?() }
            updateSize()
        }
         .onChange(of:interaction.contentPhase) { old,next in
            if next == .primed && old != .pulling { resetPull() }
            updateSize()
        }
        .onChange(of:stretch) { _,_ in updateSize() }
        .onChange(of:model.active.map(\.id)) { _,_ in updateSize() }
        .onChange(of:preferences.config.fullTaskText) { _,_ in updateSize() }
        .onAppear {
            updateSize()
            if widgetUITestProfile { model.preparePullTest = {
                close()
                DispatchQueue.main.async { resetPull(); interaction.holdPrimeForUITest = true; interaction.phase = .primed; interaction.entryVisible = true }
            } }
        }
    }
    private var entryButton: some View {
            ZStack {
                Glass().clipShape(RoundedRectangle(cornerRadius:15)).overlay(RoundedRectangle(cornerRadius:15).stroke(MaterialPalette.edge,lineWidth:0.75)).opacity(interaction.entryVisible ? 1 : 0)
                Image(systemName: editing || pulling ? "xmark" : "plus").font(.system(size:18,weight:.medium)).opacity(interaction.entryVisible ? (interaction.phase == .moving ? 0.35 : 1) : 0)
                WidgetSurface(model:model,interaction:interaction,geometry:interaction.entry) { _,_ in
                    if editing || pulling { close() } else { model.draftOpen = true }
                }
            }.frame(width:40,height:34).accessibilityLabel(model.text("创建提醒", "Create reminder"))
    }
    private var creationBar: some View {
                HStack(spacing:8) {
                    WidgetGlyphButton(model:model,interaction:interaction,symbol:kind == .task ? "checkmark.circle" : "clock",label:model.text("切换提醒／任务", "Switch Reminder / Task")) { kind = kind == .task ? .reminder : .task }.help(model.text("切换提醒／任务（↑ ↓）", "Switch Reminder / Task (↑ ↓)"))
                    if editing {
                        TextField("1",text:$minutes).frame(width:48).focused($focus,equals:0).multilineTextAlignment(.center)
                        TextField(kind == .task ? model.text("任务内容", "Task") : model.text("提醒内容", "Reminder"),text:$title).focused($focus,equals:1)
                        WidgetGlyphButton(model:model,interaction:interaction,symbol:"arrow.up",label:model.text("创建", "Create"),action:submit).help(model.text("创建", "Create"))
                    } else {
                        Text("\(minutes) min").font(.system(size:13,weight:.medium)).monospacedDigit().fixedSize()
                        Spacer(minLength:0)
                        PullHandle(began:{
                            interaction.holdPrimeForUITest = false
                            resetPull(); focus = nil
                            interaction.phase = .pulling; model.pullingChanged?(true); model.hoverItem?(nil,nil)
                        },changed:{ delta in
                            let value = PullValue(start:1,delta:delta/preferences.config.scale); stretch = value.extensionWidth; visualWidth = 126+stretch; visualTension = stretch/28
                            if minutes != String(value.minutes) { minutes = String(value.minutes); model.audio.effect("drag-sound") }
                        },ended:{
                            finishPull()
                        }).frame(width:23,height:34).help(model.text("按住向右拉伸：1–99 分钟", "Stretch: 1–99 minutes"))
                    }
                }.padding(.horizontal,10).frame(width:barWidth,height:34)
                .transaction { $0.animation = nil }
                .background(alignment:.leading) {
                    Glass().clipShape(StretchShape(tension:visualTension))
                        .overlay(StretchShape(tension:visualTension).stroke(MaterialPalette.edge,lineWidth:0.75))
                        .frame(width:visualWidth,height:34)
                }
                .overlay(alignment:.top) { if editing { WidgetSurface(model:model,interaction:interaction,geometry:topEdge,click:{_,_ in}).frame(height:2) } }
                .overlay(alignment:.bottom) { if editing { WidgetSurface(model:model,interaction:interaction,geometry:bottomEdge,click:{_,_ in}).frame(height:2) } }
                .overlay(alignment:.bottom) { if pulling || focus == 0 { Text(endTime).font(.system(size:11)).padding(5).background(Glass().clipShape(Capsule())).offset(y:26) } }
                .onSubmit { submit() }
                .onKeyPress(.tab) { focus = focus == 0 ? 1 : 0; return .handled }
                .onKeyPress(.escape) { close(); return .handled }
                .onKeyPress(.upArrow) { kind = .task; return .handled }
                .onKeyPress(.downArrow) { kind = .reminder; return .handled }
    }
    private var activeWidth: CGFloat {
        let desired = model.active.reduce(CGFloat(0)) { $0 + widgetItemWidth($1,full:preferences.config.fullTaskText) }
        let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == preferences.config.displayID } ?? NSScreen.main
        // Reserve the maximum pull width up front so the bar's left anchor does not
        // shift when a crowded active list gives space back during the rebound.
        return min(desired,max(0,(screen?.visibleFrame.width ?? 1200)/preferences.config.scale-(expanded ? 518+112 : 100)))
    }
    private var endTime: String { if let m = try? TimeInput.minutes(minutes,now:model.now) { return clockText(model.now.addingTimeInterval(m*60)) }; return model.text("1–999 分钟 / HH:mm", "1–999 min / HH:mm") }
    private func updateSize() { canvas.update(logicalWidth) }
    private var logicalWidth: CGFloat { 40+activeWidth+(expanded ? barWidth+9 : 0)+(model.active.isEmpty ? 0 : 9)+36 }
    private func resetPull() {
        settlementToken = UUID(); canvas.cancelSettlement()
        minutes = "1"; stretch = 0; visualWidth = 126; visualTension = 0
    }
    private func finishPull() {
        // Reserve both old and new bounds before atomically changing the controls.
        let target = logicalWidth + 270-barWidth
        let token = canvas.hold(for:target); settlementToken = token
        interaction.phase = .editing; model.draftOpen = true; stretch = 0
        model.acquireKeyboardFocus?(); focus = 1
        updateSize(); model.pullingChanged?(false)
        withAnimation(reducedMotion ? nil : .spring(response:0.38,dampingFraction:0.65),completionCriteria:.removed) {
            visualWidth = 270; visualTension = 0
        } completion: {
            if settlementToken == token { canvas.complete(token) }
        }
    }
    private func submit() {
        withTransaction(Transaction(animation:nil)) {
            model.create(kind:kind,title:title,text:minutes)
            if !model.draftOpen { title = ""; resetPull() }
            updateSize()
        }
    }
    private func close() {
        withTransaction(Transaction(animation:nil)) {
            model.draftOpen = false; interaction.phase = .idle; title = ""; resetPull(); updateSize()
        }
        model.audio.effect("pong")
    }
}
struct RingItem: View {
    let item: ReminderItem
    @ObservedObject var model: AppModel
    @ObservedObject var interaction: WidgetInteraction
    let full: Bool
    @State private var geometry = HoverGeometry()
    @State private var popover = false
    var body: some View {
        ZStack(alignment:.topTrailing) {
            HStack(spacing:7) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.035))
                    Circle().stroke(.white.opacity(0.22),lineWidth:2.5)
                    Circle().trim(from:0,to:item.progress(at:model.now)).stroke(.white,lineWidth:2.5).rotationEffect(.degrees(-90))
                    if item.state == .due { Image(systemName:item.kind == .task ? "checkmark.circle" : "bell").font(.system(size:18)) }
                    else { Text(String(max(1,Int(ceil(item.remaining(at:model.now)/60))))).font(.system(size:12,weight:.semibold,design:.rounded)).monospacedDigit() }
                }.frame(width:34,height:34)
                if full && item.kind == .task && !item.title.isEmpty { Text(item.title.replacingOccurrences(of:"\n",with:" ")).font(.system(size:13)).lineLimit(1).fixedSize() }
            }.background(Glass().clipShape(Capsule())).padding(.top,4).padding(.trailing,4)
            if interaction.hovered == item.id {
                Image(systemName:"xmark").font(.system(size:8,weight:.bold)).frame(width:15,height:15).background(Color(red:0.24,green:0.45,blue:0.51),in:Circle())
            }
            WidgetSurface(model:model,interaction:interaction,geometry:geometry) { point,rect in
                if interaction.hovered == item.id && point.x > rect.width-18 && point.y > rect.height-18 { model.finish(item.id,cancelled:true) }
                else { popover = true; interaction.menuOpen = true; model.hoverItem?(nil,nil) }
            }
        }.frame(width:widgetItemWidth(item,full:full)-9,height:44)
        .onAppear { interaction.rings[item.id] = geometry }
        .popover(isPresented:$popover,arrowEdge:.bottom) {
            VStack(spacing:0) {
                ForEach([1,5,10,15,20,30],id:\.self) { m in
                    Button { model.extend(item.id,Double(m)); popover = false } label: { Text("+\(m) min").font(.system(size:15,weight:.medium)).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,16).padding(.vertical,10) }.buttonStyle(.plain)
                    if m != 30 { Divider().opacity(0.4) }
                }
            }.frame(width:140).padding(2)
        }.onChange(of:popover) { _,open in interaction.menuOpen = open }
    }
}
struct WidgetGlyphButton: View {
    let model: AppModel
    let interaction: WidgetInteraction
    let symbol: String
    let label: String
    var action: ()->Void
    @State private var geometry = HoverGeometry()
    var body: some View {
        Image(systemName:symbol).font(.system(size:18)).frame(width:24,height:30)
            .overlay(WidgetSurface(model:model,interaction:interaction,geometry:geometry,label:label,click:{_,_ in action()}))
            .accessibilityLabel(label)
    }
}
struct ScaledWidget: View {
    @ObservedObject var model: AppModel
    @ObservedObject var preferences: Preferences
    @ObservedObject var canvas: WidgetCanvas
    var body: some View {
        let scale = preferences.config.scale
        WidgetView(model:model,preferences:preferences,canvas:canvas)
            .frame(width:canvas.width,height:118,alignment:.leading)
            .frame(width:canvas.drawingWidth,height:118,alignment:.leading)
            .padding(.horizontal,WidgetCanvas.margin)
            .scaleEffect(scale,anchor:.topLeading)
            .frame(width:(canvas.drawingWidth+WidgetCanvas.margin*2)*scale,height:118*scale,alignment:.topLeading)
    }
}

func widgetItemWidth(_ item: ReminderItem, full: Bool) -> CGFloat {
    guard full, item.kind == .task, !item.title.isEmpty else { return 49 }
    return ceil((item.title.replacingOccurrences(of:"\n",with:" ") as NSString).size(withAttributes:[.font:NSFont.systemFont(ofSize:13)]).width)+56
}
