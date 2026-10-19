import SwiftUI
import Observation
import PerfectFitCore

enum ThemeMode: String, Codable, CaseIterable { case auto, light, dark }

struct Settings: Codable, Equatable {
    var sound = true
    var haptics = true
    var theme: ThemeMode = .auto
    var lang: Lang = .en
}

struct Progress: Codable, Equatable {
    var stars: [Int: Int] = [:]      // level id → best stars
    var hints = 3
    var hintsUsed = 0
    var lastLevel = 1
    var seenFinale = false

    func isUnlocked(_ id: Int) -> Bool { id == 1 || (stars[id - 1] ?? 0) > 0 }
    var totalStars: Int { stars.values.reduce(0, +) }
}

enum Screen: Equatable { case intro, home, levels, game(Int) }

/// App-wide state: navigation, settings, progress. Saved as JSON in UserDefaults (local only, no accounts).
@Observable
final class AppModel {
    var screen: Screen = .intro
    var settings: Settings { didSet { save(settings, "pf.settings"); applySettings() } }
    var progress: Progress { didSet { save(progress, "pf.progress") } }
    var sheet: Sheet? = nil
    let levels: [Level]

    enum Sheet: String, Identifiable { case settings, howToPlay, records; var id: String { rawValue } }

    init() {
        settings = Self.load("pf.settings") ?? Settings()
        progress = Self.load("pf.progress") ?? Progress()
        levels = LevelStore.all()
        applySettings()
        // development shortcuts:  -pfLevel N  opens a level,  -pfHome  skips the intro
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-pfLevel"), i + 1 < args.count, let n = Int(args[i + 1]) { screen = .game(n) }
        if args.contains("-pfHome") { screen = .home }
        if let i = args.firstIndex(of: "-pfTheme"), i + 1 < args.count, let t = ThemeMode(rawValue: args[i + 1]) { settings.theme = t }
    }

    var strings: Strings { Strings(lang: settings.lang) }

    func palette(_ scheme: ColorScheme) -> Palette { isDark(scheme) ? .dark : .light }
    func isDark(_ system: ColorScheme) -> Bool {
        switch settings.theme { case .auto: return system == .dark; case .light: return false; case .dark: return true }
    }
    var colorScheme: ColorScheme? {
        switch settings.theme { case .auto: return nil; case .light: return .light; case .dark: return .dark }
    }

    func level(_ id: Int) -> Level? { levels.first { $0.id == id } }

    /// Records a finished level. Returns true when it earned a hint (first time at 3 stars).
    @discardableResult
    func complete(level id: Int, stars: Int) -> Bool {
        let before = progress.stars[id] ?? 0
        var p = progress
        p.stars[id] = max(before, stars)
        var earned = false
        if stars == 3 && before < 3 { p.hints += 1; earned = true }
        if let next = level(id + 1)?.id { p.lastLevel = next } else { p.lastLevel = id }
        progress = p
        return earned
    }

    func eraseProgress() { progress = Progress() }

    private func applySettings() {
        Sound.shared.enabled = settings.sound
        Haptics.shared.enabled = settings.haptics
    }

    private func save<T: Encodable>(_ v: T, _ key: String) {
        if let d = try? JSONEncoder().encode(v) { UserDefaults.standard.set(d, forKey: key) }
    }
    private static func load<T: Decodable>(_ key: String) -> T? {
        guard let d = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }
}

enum LevelStore {
    static func all() -> [Level] {
        guard let dir = Bundle.main.url(forResource: "Levels", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? Level.load($0) }
    }
}

enum AppInfo {
    static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }
}
