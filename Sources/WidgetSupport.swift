import AppKit
import SwiftUI

struct PullHandle: NSViewRepresentable {
    var began: () -> Void
    var changed: (CGFloat) -> Void
    var ended: () -> Void
    func makeNSView(context: Context) -> PullHandleView { let view = PullHandleView(); updateNSView(view,context:context); return view }
    func updateNSView(_ view: PullHandleView, context: Context) { view.began = began; view.changed = changed; view.ended = ended }
}
final class PullHandleView: NSView {
    var began: (() -> Void)?
    var changed: ((CGFloat) -> Void)?
    var ended: (() -> Void)?
    private var origin: NSPoint?
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds,cursor:.resizeLeftRight) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.65).setFill()
        for offset in [-5.0,0,5.0] { NSBezierPath(roundedRect:NSRect(x:bounds.midX+offset-1.4,y:bounds.midY-7,width:2.8,height:14),xRadius:1.4,yRadius:1.4).fill() }
    }
    override func mouseDown(with event: NSEvent) { guard let window else { return }; origin = window.convertPoint(toScreen:event.locationInWindow); began?() }
    override func mouseDragged(with event: NSEvent) { guard let origin, let window else { return }; changed?(window.convertPoint(toScreen:event.locationInWindow).x-origin.x) }
    override func mouseUp(with event: NSEvent) { if origin != nil { origin = nil; ended?() } }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil && origin != nil { origin = nil; ended?() } }
}
final class HoverGeometry {
    weak var view: HoverAnchorView?
    var screenRect: NSRect? { guard let view, let window = view.window else { return nil }; return window.convertToScreen(view.convert(view.bounds,to:nil)) }
}
struct HoverAnchor: NSViewRepresentable {
    let geometry: HoverGeometry
    var enter: (NSRect) -> Void
    var leave: () -> Void
    func makeNSView(context: Context) -> HoverAnchorView { let view = HoverAnchorView(); updateNSView(view,context:context); return view }
    func updateNSView(_ view: HoverAnchorView, context: Context) { geometry.view = view; view.enter = enter; view.leave = leave }
}
class HoverAnchorView: NSView {
    var enter: ((NSRect) -> Void)?
    var leave: (() -> Void)?
    private var tracking: NSTrackingArea?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeAlways,.inVisibleRect,.enabledDuringMouseDrag],owner:self,userInfo:nil)
        addTrackingArea(next); tracking = next
    }
    override func mouseEntered(with event: NSEvent) { if let window { enter?(window.convertToScreen(convert(bounds,to:nil))) } }
    override func mouseExited(with event: NSEvent) { leave?() }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { leave?() } }
}
struct TipArrow: Shape {
    func path(in rect: CGRect) -> Path { var p = Path(); p.move(to:CGPoint(x:rect.midX,y:0)); p.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY)); p.addLine(to:CGPoint(x:0,y:rect.maxY)); p.closeSubpath(); return p }
}
struct ItemTipView: View {
    let title: String
    let time: String
    let width: CGFloat
    let arrowOffset: CGFloat
    var body: some View {
        VStack(spacing:0) {
            Frost(material:.toolTip).clipShape(TipArrow()).frame(width:16,height:7).offset(x:arrowOffset)
            (Text(title).fontWeight(.semibold) + Text("  ·  " + time).foregroundColor(.secondary))
                .font(.system(size:13)).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.center)
                .padding(.horizontal,12).padding(.vertical,7).background(Frost(material:.toolTip).clipShape(RoundedRectangle(cornerRadius:8)))
        }.frame(width:width).padding(.bottom,3).environment(\.colorScheme,.dark)
    }
}
final class ItemTooltip {
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    private var shown: UUID?
    func show(_ item: ReminderItem, anchor: NSRect, title: String) {
        hideWork?.cancel()
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x:anchor.midX,y:anchor.midY)) } ?? NSScreen.main!
        let limits = screen.visibleFrame.insetBy(dx:6,dy:4)
        let time = clockText(item.deadline), text = title + "  ·  " + time
        let font = NSFont.systemFont(ofSize:13,weight:.semibold)
        let width = min(420,limits.width,max(120,ceil((text as NSString).size(withAttributes:[.font:font]).width)+24))
        let height = min(limits.height,ceil((text as NSString).boundingRect(with:NSSize(width:width-24,height:10000),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:[.font:font]).height)+24)
        let x = min(limits.maxX-width,max(limits.minX,anchor.midX-width/2))
        let y = max(limits.minY,anchor.minY-height-5)
        let view = ItemTipView(title:title,time:time,width:width,arrowOffset:min(width/2-12,max(-width/2+12,anchor.midX-(x+width/2))))
        if panel == nil {
            let next = NSPanel(contentRect:.zero,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            next.title = "项目提示"; next.isOpaque = false; next.backgroundColor = .clear; next.hasShadow = true; next.level = NSWindow.Level(rawValue:NSWindow.Level.floating.rawValue+1)
            next.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; next.hidesOnDeactivate = false; next.ignoresMouseEvents = true
            panel = next
        }
        panel?.contentView = NSHostingView(rootView:view)
        panel?.setFrame(NSRect(x:x,y:y,width:width,height:height),display:true)
        panel?.orderFrontRegardless(); shown = item.id
    }
    func hide(after delay: TimeInterval = 0) {
        hideWork?.cancel()
        if delay == 0 { panel?.orderOut(nil); shown = nil; return }
        let work = DispatchWorkItem { [weak self] in self?.panel?.orderOut(nil); self?.shown = nil }
        hideWork = work; DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:work)
    }
}
