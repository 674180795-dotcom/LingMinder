import SwiftUI
import AppKit

// macOS 14/15 material backing. NSVisualEffectView is not Liquid Glass.
struct Frost: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var dark = true
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { configure(view) }
    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.appearance = dark ? NSAppearance(named:.vibrantDark) : nil
    }
}

enum MaterialPalette {
    static let edge = LinearGradient(colors:[.white.opacity(0.46),.white.opacity(0.12)],startPoint:.topLeading,endPoint:.bottomTrailing)
    static let canvas = Color(nsColor:.windowBackgroundColor)
    static let card = Color(nsColor:.controlBackgroundColor)
    static var version: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "—" }
}

struct Glass: View {
    @Environment(\.accessibilityReduceTransparency) private var reduced
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        ZStack {
            if reduced {
                Color(red:0.17,green:0.23,blue:0.27)
            } else {
                Frost(material:.hudWindow)
                LinearGradient(colors:[.white.opacity(0.055),Color(red:0.22,green:0.42,blue:0.48).opacity(0.045)],startPoint:.topLeading,endPoint:.bottomTrailing)
            }
            if contrast == .increased { Color.black.opacity(0.18) }
        }
    }
}

struct AlertBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduced
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        ZStack {
            if reduced { Color(red:0.12,green:0.16,blue:0.19) }
            else { Frost(material:.fullScreenUI) }
            LinearGradient(colors:[.black.opacity(0.12),.black.opacity(contrast == .increased ? 0.55 : 0.34)],startPoint:.top,endPoint:.bottom)
        }
    }
}

// Content stays on a readable standard surface; only floating chrome uses Frost.
struct SettingsSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Text(title).font(.system(size:11,weight:.semibold)).foregroundStyle(.secondary).padding(.leading,4)
            VStack(alignment:.leading,spacing:14) { content }
                .frame(maxWidth:.infinity,alignment:.leading).padding(16)
                .background(MaterialPalette.card,in:RoundedRectangle(cornerRadius:12))
                .overlay { RoundedRectangle(cornerRadius:12).stroke(Color.primary.opacity(contrast == .increased ? 0.3 : 0.06),lineWidth:1) }
        }
    }
}
