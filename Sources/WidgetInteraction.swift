import AppKit
import SwiftUI

enum WidgetPhase { case idle, primed, pulling, editing, moving }
final class WidgetInteraction: ObservableObject {
    @Published var phase: WidgetPhase = .idle
    @Published private(set) var moveOrigin: WidgetPhase?
    var contentPhase: WidgetPhase { phase == .moving ? (moveOrigin ?? .idle) : phase }
    func beginMoving() { guard phase != .moving else { return }; moveOrigin = phase; phase = .moving }
    func endMoving() { let origin = moveOrigin ?? .idle; phase = origin; moveOrigin = nil }
    @Published var entryVisible = true
    @Published var hovered: UUID?
    var menuOpen = false
    var holdPrimeForUITest = false
    var entry = HoverGeometry()
    var group = HoverGeometry()
    var rings: [UUID:HoverGeometry] = [:]
    weak var model: AppModel?
    private var timer: Timer?
    private var outsideSince: Date?
    private var ringOutsideSince: Date?
    init(model: AppModel) {
        self.model = model
        timer = Timer.scheduledTimer(withTimeInterval:0.03,repeats:true) { [weak self] _ in self?.poll() }
        if let timer { RunLoop.main.add(timer,forMode:.common) }
    }
    deinit { timer?.invalidate() }
    private func poll() {
        guard let model else { return }
        let point = NSEvent.mouseLocation
        if let panel = group.view?.window as? WidgetPanel {
            panel.ignoresMouseEvents = !panel.hasMouseCapture && !menuOpen && !model.widgetMenuOpen && !panel.logicalFrame.contains(point)
        }
        let entryRect = entry.screenRect
        let active = Set(model.active.map(\.id)); rings = rings.filter { active.contains($0.key) }
        let ring = rings.first { $0.value.screenRect?.insetBy(dx:-5,dy:-5).contains(point) == true }
        if let ring, !menuOpen, phase != .moving, phase != .pulling {
            ringOutsideSince = nil
            if hovered != ring.key { hovered = ring.key; if let item = model.active.first(where:{$0.id == ring.key}), let rect = ring.value.screenRect { model.hoverItem?(item,rect) } }
        } else if hovered != nil {
            if ringOutsideSince == nil { ringOutsideSince = Date() }
            if Date().timeIntervalSince(ringOutsideSince!) >= 0.12 { hovered = nil; model.hoverItem?(nil,nil) }
        }
        let nearEntry = entryRect.map { $0.insetBy(dx:-60,dy:-60).contains(point) } ?? false
        let inside = nearEntry || ring != nil || group.screenRect?.contains(point) == true
        if model.settingsOpen || inside || menuOpen || model.widgetMenuOpen || (widgetUITestProfile && holdPrimeForUITest) || phase == .editing || phase == .pulling || phase == .moving {
            outsideSince = nil
            model.proximityChanged?(true)
            if !entryVisible { entryVisible = true }
            if phase == .idle && nearEntry { phase = .primed }
        } else {
            if outsideSince == nil { outsideSince = Date() }
            if Date().timeIntervalSince(outsideSince!) >= 0.8 {
                model.proximityChanged?(false)
                if phase == .primed { phase = .idle }
                if entryVisible { entryVisible = false }
            }
        }
    }
}
// The same fixed native hit surface owns click and drag, including the protruding badge.
struct WidgetSurface: NSViewRepresentable {
    let model: AppModel
    let interaction: WidgetInteraction
    let geometry: HoverGeometry
    var label: String = ""
    var click: (NSPoint,NSRect) -> Void
    func makeNSView(context: Context) -> WidgetSurfaceView { let v = WidgetSurfaceView(); updateNSView(v,context:context); return v }
    func updateNSView(_ v: WidgetSurfaceView, context: Context) { geometry.view = v; v.model = model; v.interaction = interaction; v.click = click; v.setAccessibilityLabel(label) }
}
final class WidgetSurfaceView: HoverAnchorView {
    weak var model: AppModel?
    weak var interaction: WidgetInteraction?
    var click: ((NSPoint,NSRect)->Void)?
    private var down: NSPoint?
    private var original: NSRect = .zero
    private weak var originalResponder: NSResponder?
    private var dragged = false
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityPerformPress() -> Bool { guard let window else { return false }; click?(NSPoint(x:bounds.midX,y:bounds.midY),window.convertToScreen(convert(bounds,to:nil))); return true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }; down = window.convertPoint(toScreen:event.locationInWindow); original = (window as? WidgetPanel)?.logicalFrame ?? window.frame; dragged = false; originalResponder = window.firstResponder
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down, let window, let interaction, interaction.contentPhase != .pulling else { return }
        let p = window.convertPoint(toScreen:event.locationInWindow), dx = p.x-down.x, dy = p.y-down.y
        if !dragged && hypot(dx,dy) <= 4 { return }
        dragged = true; interaction.beginMoving()
        model?.hoverItem?(nil,nil)
        let limits = (NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main)?.visibleFrame ?? original
        let point = WidgetCanvas.clampedOrigin(NSPoint(x:original.minX+dx,y:original.minY+dy),size:original.size,within:limits)
        window.setFrameOrigin(NSPoint(x:point.x-((window as? WidgetPanel)?.drawingInset ?? 0),y:point.y))
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, down != nil { down = nil; if dragged { interaction?.endMoving() }; dragged = false }
        super.viewWillMove(toWindow:newWindow)
    }
    override func mouseUp(with event: NSEvent) {
        guard down != nil, let window, let model, let interaction else { return }; down = nil
        if dragged {
            let logical = (window as? WidgetPanel)?.logicalFrame ?? window.frame
            let screen = (NSScreen.screens.first { $0.frame.contains(NSPoint(x:logical.midX,y:logical.midY)) } ?? NSScreen.main)!
            let normalized = WidgetCanvas.normalizedOrigin(logical,within:screen.visibleFrame)
            var config = model.preferences.config
            config.customX = Double(normalized.x); config.customY = Double(normalized.y); config.position = "custom"
            config.displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            interaction.endMoving(); model.preferences.config = config
            if let originalResponder { window.makeFirstResponder(originalResponder) }
        } else { click?(convert(event.locationInWindow,from:nil),window.convertToScreen(convert(bounds,to:nil))) }
    }
}
