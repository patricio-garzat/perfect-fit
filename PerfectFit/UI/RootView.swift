import SwiftUI
import WebKit

@main
struct PerfectFitApp: App {
    @State private var app = AppModel()
    init() {
        Sound.shared.start()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-pfIcon"), let l = LevelStore.all().first(where: { $0.id == 4 }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { IconMaker.run(level: l) }
        }
        #endif
    }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var system
    @State private var homeIntro = true

    var body: some View {
        let pal = app.palette(system)
        ZStack {
            pal.background.ignoresSafeArea()
            switch app.screen {
            case .intro:
                StudioIntro { withAnimation(.easeInOut(duration: 0.6)) { app.screen = .home } }
                    .transition(.opacity)
            case .home:
                HomeView(playIntro: homeIntro)
                    .onDisappear { homeIntro = false }
                    .transition(.opacity)
            case .levels:
                LevelsView().transition(.opacity)
            case .game(let id):
                if let l = app.level(id) {
                    GameView(level: l).id(id).transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.45), value: app.screen)
        .environment(\.palette, pal)
        .preferredColorScheme(app.colorScheme)
        .sheet(item: Binding(get: { app.sheet }, set: { app.sheet = $0 })) { s in
            Group {
                switch s {
                case .settings: SettingsView()
                case .howToPlay: HowToPlayView()
                case .records: RecordsView()
                }
            }
            .environment(app)
            .environment(\.palette, pal)
            .preferredColorScheme(app.colorScheme)
            .presentationDetents([.large])
            .presentationCornerRadius(30)
        }
        .statusBarHidden(app.screen == .intro)
    }
}

/// BluBer Games studio intro: the official logo animation (same as every studio game) on white, about 4 s,
/// can't be skipped. Plays two of Perfect Fit's own sounds: a soft wooden thump as the letters rise and a warm
/// marimba as the light sweeps the logo.
struct StudioIntro: View {
    let done: () -> Void
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            IntroWeb(done: done).ignoresSafeArea()
        }
    }
}

private struct IntroWeb: UIViewRepresentable {
    let done: () -> Void

    func makeCoordinator() -> Coord { Coord(done: done) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.userContentController.add(context.coordinator, name: "intro")
        cfg.mediaTypesRequiringUserActionForPlayback = .all
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.isOpaque = false
        web.backgroundColor = .white
        web.scrollView.isScrollEnabled = false
        web.scrollView.bouncesZoom = false
        web.scrollView.minimumZoomScale = 1; web.scrollView.maximumZoomScale = 1
        web.isUserInteractionEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        if let url = Bundle.main.url(forResource: "studio", withExtension: "html", subdirectory: "Intro") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else { DispatchQueue.main.async { done() } }
        context.coordinator.web = web
        // never get stuck on white
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { context.coordinator.finish() }
        return web
    }
    func updateUIView(_ v: WKWebView, context: Context) {}

    final class Coord: NSObject, WKScriptMessageHandler {
        let done: () -> Void
        weak var web: WKWebView?
        private var finished = false
        init(done: @escaping () -> Void) { self.done = done }

        func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
            switch m.body as? String {
            case "ready": web?.evaluateJavaScript("window.startIntro()")
            case "start":
                Sound.shared.start()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.22) {
                    Sound.shared.play(.introThump); Haptics.shared.play(.introDrop)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { Sound.shared.play(.introChime) }
            case "done": finish()
            default: break
            }
        }
        func finish() {
            guard !finished else { return }
            finished = true
            done()
        }
    }
}
