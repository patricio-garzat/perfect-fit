import SwiftUI
import PerfectFitCore

/// Home: a furnished room slowly turning behind the title. The first time after the intros, its pieces fall
/// into place one by one (the game's own intro).
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal
    @Environment(\.colorScheme) private var scheme
    @State private var showcase: SceneController?
    @State private var titleIn = false
    @State private var buttonsIn = false
    var playIntro: Bool

    private var S: Strings { app.strings }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [pal.background, pal.backgroundDeep], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                if let showcase {
                    SceneHost(controller: showcase)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        Text("PERFECT FIT")
                            .font(Typo.title(44)).tracking(6)
                            .foregroundStyle(pal.ink)
                            .minimumScaleFactor(0.6).lineLimit(1)
                        HStack(spacing: 10) {
                            Rectangle().fill(pal.accent.opacity(0.5)).frame(width: 26, height: 1)
                            Text(S.byStudio).font(Typo.label(13)).tracking(1.2).foregroundStyle(pal.muted)
                            Rectangle().fill(pal.accent.opacity(0.5)).frame(width: 26, height: 1)
                        }
                    }
                    .padding(.top, geo.safeAreaInsets.top + 34)
                    .opacity(titleIn ? 1 : 0)
                    .offset(y: titleIn ? 0 : 8)
                    Spacer()
                    VStack(spacing: 12) {
                        PillButton(title: playTitle, symbol: "play.fill") { app.screen = .game(nextLevel) }
                        HStack(spacing: 12) {
                            PillButton(title: S.levels, symbol: "square.grid.2x2", primary: false) { app.screen = .levels }
                            PillButton(title: S.settings, symbol: "slider.horizontal.3", primary: false) { app.sheet = .settings }
                        }
                        HStack(spacing: 28) {
                            smallLink(S.howToPlay, "questionmark.circle") { app.sheet = .howToPlay }
                            smallLink(S.records, "chart.bar") { app.sheet = .records }
                        }
                        .padding(.top, 6)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, geo.safeAreaInsets.bottom + 18)
                    .opacity(buttonsIn ? 1 : 0)
                    .offset(y: buttonsIn ? 0 : 12)
                }
            }
            .onAppear { setup(geo) }
            .onChange(of: app.isDark(scheme)) { _, d in showcase?.dark = d }
        }
    }

    private var nextLevel: Int {
        let p = app.progress
        if let first = app.levels.first(where: { (p.stars[$0.id] ?? 0) == 0 && p.isUnlocked($0.id) }) { return first.id }
        return min(p.lastLevel, app.levels.count)
    }
    private var playTitle: String { app.progress.totalStars == 0 ? S.play : "\(S.play) · \(nextLevel)" }

    private func smallLink(_ t: String, _ sym: String, _ action: @escaping () -> Void) -> some View {
        Button { Sound.shared.play(.button); Haptics.shared.play(.button); action() } label: {
            Label(t, systemImage: sym).font(Typo.label(14)).foregroundStyle(pal.muted)
        }
    }

    private func setup(_ geo: GeometryProxy) {
        guard showcase == nil, let level = app.level(4) else { return }
        let session = GameSession(level: level)
        let c = SceneController(session: session)
        c.dark = app.isDark(scheme)
        c.interactive = false
        c.insets = UIEdgeInsets(top: geo.safeAreaInsets.top + 150, left: 0, bottom: geo.safeAreaInsets.bottom + 230, right: 0)
        // a 3-star layout of the "Snug" bedroom
        DispatchQueue.global(qos: .userInitiated).async {
            let layout = Solver(level: level).find(stars: 3, deadline: Date().addingTimeInterval(2))
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.8)) { showcase = c }
                if let layout { c.dropIn(layout, start: playIntro ? 0.5 : 0, interval: playIntro ? 0.34 : 0, feedback: playIntro) }
                c.drift()
                let titleDelay = playIntro ? 0.5 + Double(layout?.count ?? 0) * 0.34 + 0.2 : 0.1
                withAnimation(.easeOut(duration: 0.9).delay(titleDelay)) { titleIn = true }
                withAnimation(.easeOut(duration: 0.8).delay(titleDelay + 0.35)) { buttonsIn = true }
            }
        }
    }
}
