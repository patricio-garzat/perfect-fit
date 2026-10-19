import SwiftUI
import PerfectFitCore

/// Calm victory: the stars arrive one by one with a marimba note each. No confetti.
struct VictoryView: View {
    let level: Level
    let info: GameView.VictoryInfo
    let hasNext: Bool
    let next: () -> Void
    let replay: () -> Void
    let levels: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal
    @State private var shown = 0
    @State private var appear = false

    private var S: Strings { app.strings }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 18) {
                Text(S.perfectFit.uppercased())
                    .font(Typo.label(12, .semibold)).tracking(3).foregroundStyle(pal.muted)
                Text(level.name.text(app.settings.lang.rawValue))
                    .font(Typo.title(30)).foregroundStyle(pal.ink)
                HStack(spacing: 18) {
                    ForEach(0..<3, id: \.self) { i in
                        Image(systemName: i < min(shown, info.stars) ? "star.fill" : "star")
                            .font(.system(size: i == 1 ? 40 : 32, weight: .light))
                            .foregroundStyle(i < min(shown, info.stars) ? pal.star : pal.starEmpty)
                            .scaleEffect(i < shown ? 1 : 0.85)
                            .opacity(i < shown ? 1 : 0.5)
                            .offset(y: i == 1 ? -6 : 0)
                    }
                }
                .padding(.vertical, 6)
                VStack(alignment: .leading, spacing: 10) {
                    row(true, S.starFit, nil)
                    row(info.harmony.0 == info.harmony.1, S.starHarmony, S.harmonyDetail(info.harmony.0, info.harmony.1))
                    row(info.flow, S.starFlow, S.flowDetail(info.flow))
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(pal.background.opacity(0.7)))
                if info.earnedHint {
                    Label(S.hintEarned, systemImage: "lightbulb").font(Typo.label(13, .semibold)).foregroundStyle(pal.accent)
                }
                if !hasNext && app.progress.totalStars >= 30 {
                    Text(S.finale).font(Typo.title(17)).foregroundStyle(pal.ink).multilineTextAlignment(.center)
                }
                VStack(spacing: 10) {
                    if hasNext { PillButton(title: S.nextLevel, symbol: "arrow.right") { next() } }
                    HStack(spacing: 10) {
                        PillButton(title: S.replay, symbol: "arrow.counterclockwise", primary: !hasNext) { replay() }
                        PillButton(title: S.levels, symbol: "square.grid.2x2", primary: false) { levels() }
                    }
                }
                .padding(.top, 4)
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(pal.surface.opacity(0.95)))
            .shadow(color: .black.opacity(0.1), radius: 24, y: 8)
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
            .offset(y: appear ? 0 : 30)
            .opacity(appear ? 1 : 0)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) { appear = true }
            for i in 0..<3 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55 + Double(i) * 0.42) {
                    withAnimation(.easeOut(duration: 0.4)) { shown = i + 1 }
                    if i < info.stars {
                        Sound.shared.play([.star1, .star2, .star3][i])
                        Haptics.shared.play(.star)
                    }
                }
            }
        }
    }

    private func row(_ ok: Bool, _ title: String, _ detail: String?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 17)).foregroundStyle(ok ? pal.sage : pal.muted.opacity(0.6))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.label(14, .semibold)).foregroundStyle(pal.ink)
                if let detail { Text(detail).font(Typo.label(12)).foregroundStyle(pal.muted) }
            }
            Spacer(minLength: 0)
        }
    }
}
