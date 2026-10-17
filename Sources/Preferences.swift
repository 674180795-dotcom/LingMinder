import AppKit
import Combine

// Only a deliberately marked QA bundle uses this profile. Release builds omit
// the plist key, so native UI checks cannot touch the user's timers or settings.
let widgetUITestProfile = Bundle.main.object(forInfoDictionaryKey:"LingMinderTestProfile") as? String == "ui024"

struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String
}
struct Configuration: Codable {
    var language = "zh-Hans"
    var alwaysVisible = true
    var hideFullscreen = true
    var animateTray = false
    var position = "bottom"
    var displayID: UInt32 = 0
    var scale: Double = 1
    var customX: Double = 0.7
    var customY: Double = 0.8
    var audioHaptic = true
    var notificationStyle = "blur"
    var customSound = true
    var autoClose = true
    var focusSounds = false
    var focusSound = "ticking"
    var fullTaskText = false
    var syncReminders = false
    var launchAtLogin = false
    var fastMinutes = [5, 10, 15, 25]
    var shortcuts: [String: HotKey] = [:]
    var onboardingDone = false
}
final class Preferences: ObservableObject {
    let defaults: UserDefaults
    var onChange: (() -> Void)?
    @Published var config: Configuration { didSet {
        if let data = try? JSONEncoder().encode(config) { defaults.set(data, forKey: "configuration.v1") }
        onChange?()
    } }
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? ProcessInfo.processInfo.environment["LINGMINDER_PREFERENCES_SUITE"].flatMap { UserDefaults(suiteName:$0) } ?? (widgetUITestProfile ? UserDefaults(suiteName:"local.ling99.LingMinder.ui024")! : .standard)
        if let data = self.defaults.data(forKey: "configuration.v1"), let saved = try? JSONDecoder().decode(Configuration.self, from: data) { config = saved }
        else { config = Configuration(); if widgetUITestProfile { config.onboardingDone = true; config.audioHaptic = false } }
    }
    func text(_ chinese: String, _ english: String) -> String { config.language == "en" ? english : chinese }
}

func clockText(_ date: Date) -> String {
    let formatter = DateFormatter(); formatter.dateStyle = .none; formatter.timeStyle = .short
    return formatter.string(from: date)
}
