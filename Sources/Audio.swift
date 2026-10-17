import AppKit
import AVFoundation

final class AudioController {
    private let bundle: Bundle
    init(bundle: Bundle = .main) { self.bundle = bundle }
    private var background: AVAudioPlayer?
    private var backgroundName: String?
    private var effects: [AVAudioPlayer] = []
    private var lastDrag = Date.distantPast
    var enabled = true
    private(set) var backgroundStarts = 0
    var activeBackgroundPlayers: Int { background?.isPlaying == true ? 1 : 0 }
    func player(_ name: String) -> AVAudioPlayer? {
        let extensions = ["m4a", "aiff", "mp3"]
        for ext in extensions {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "Audio"),
               let player = try? AVAudioPlayer(contentsOf: url) { player.prepareToPlay(); return player }
        }
        return nil
    }
    func reconcile(running: Bool, configuration: Configuration) {
        enabled = configuration.audioHaptic
        let desired = running && configuration.focusSounds ? configuration.focusSound : nil
        if desired == backgroundName && (desired == nil || background?.isPlaying == true) { return }
        stopBackground()
        if let desired, let player = player(desired) {
            player.numberOfLoops = -1; player.volume = 0.65; player.play()
            background = player; backgroundName = desired; backgroundStarts += 1
        }
    }
    func previewBackground(_ name: String) {
        stopBackground()
        if let player = player(name) { player.numberOfLoops = -1; player.volume = 0.65; player.play(); background = player; backgroundName = name }
    }
    func stopBackground() { background?.stop(); background = nil; backgroundName = nil }
    func effect(_ name: String, force: Bool = false) {
        guard enabled || force else { return }
        if name == "drag-sound" {
            guard Date().timeIntervalSince(lastDrag) > 0.055 else { return }; lastDrag = Date()
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        effects.removeAll { !$0.isPlaying }
        guard effects.count < 8, let player = player(name) else { return }
        player.play(); effects.append(player)
    }
    func stopAll() { stopBackground(); effects.forEach { $0.stop() }; effects.removeAll() }
}
