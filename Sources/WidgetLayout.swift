import AppKit
import Combine

// The logical footprint retains the old position convention. Canvas padding is
// exclusively for drawing and never contributes to saved coordinates or hit tests.
final class WidgetCanvas: ObservableObject {
    static let margin: CGFloat = 64
    @Published private(set) var width: CGFloat = 100
    @Published private(set) var drawingWidth: CGFloat = 100
    private(set) var settlement: UUID?
    var changed: (() -> Void)?
    func update(_ value: CGFloat) {
        let next = max(76,value)
        guard width != next else { return }
        width = next
        drawingWidth = settlement == nil ? next : max(drawingWidth,next)
        changed?()
    }
    @discardableResult func hold(for target: CGFloat) -> UUID {
        let token = UUID(); settlement = token
        drawingWidth = max(drawingWidth,width,target)
        changed?(); return token
    }
    func complete(_ token: UUID) {
        guard settlement == token else { return }
        settlement = nil; drawingWidth = width; changed?()
    }
    func cancelSettlement() {
        settlement = nil; drawingWidth = width; changed?()
    }
    static func normalizedOrigin(_ rect: NSRect, within screen: NSRect) -> NSPoint {
        NSPoint(x:min(1,max(0,(rect.minX-screen.minX)/max(1,screen.width-rect.width))),
                y:min(1,max(0,(rect.minY-screen.minY)/max(1,screen.height-rect.height))))
    }
    static func clampedOrigin(_ origin: NSPoint, size: NSSize, within screen: NSRect) -> NSPoint {
        NSPoint(x:min(max(screen.minX,screen.maxX-size.width),max(screen.minX,origin.x)),
                y:min(max(screen.minY,screen.maxY-size.height),max(screen.minY,origin.y)))
    }
}
