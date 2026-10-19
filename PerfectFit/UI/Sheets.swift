import SwiftUI
import PerfectFitCore

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal
    @State private var confirmErase = false
    private var S: Strings { app.strings }

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            SheetHeader(title: S.settings) { app.sheet = nil }
            ScrollView {
                VStack(spacing: 14) {
                    group {
                        toggle(S.sound, "speaker.wave.2", $app.settings.sound)
                        divider
                        toggle(S.vibration, "iphone.radiowaves.left.and.right", $app.settings.haptics)
                    }
                    group {
                        row(S.theme, "circle.lefthalf.filled") {
                            segmented([(ThemeMode.auto, S.auto), (.light, S.light), (.dark, S.dark)], $app.settings.theme)
                        }
                        divider
                        row(S.language, "globe") {
                            segmented([(Lang.en, "English"), (.es, "Español")], $app.settings.lang)
                        }
                    }
                    group {
                        Button { Haptics.shared.play(.button); confirmErase = true } label: {
                            HStack { Label(S.resetData, systemImage: "trash").foregroundStyle(pal.terracotta); Spacer() }
                                .font(Typo.label(15)).padding(.vertical, 14)
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(S.about.uppercased()).font(Typo.label(11, .semibold)).tracking(1.4).foregroundStyle(pal.muted).padding(.leading, 6).padding(.bottom, 6)
                        group {
                            info(S.version, AppInfo.version)
                            divider
                            link(S.website, "blubergames.com", "https://blubergames.com")
                            divider
                            link(S.support, "blubergames.com/support", "https://blubergames.com/support/")
                        }
                        Text(S.assets).font(Typo.label(11)).foregroundStyle(pal.muted).padding(.top, 10).padding(.leading, 6)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 30)
            }
        }
        .background(pal.background.ignoresSafeArea())
        .confirmationDialog(S.resetConfirm, isPresented: $confirmErase, titleVisibility: .visible) {
            Button(S.erase, role: .destructive) { app.eraseProgress() }
            Button(S.cancel, role: .cancel) {}
        }
    }

    private var divider: some View { Rectangle().fill(pal.line).frame(height: 1) }

    private func group<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 0) { c() }
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(pal.surface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(pal.line))
    }

    private func toggle(_ t: String, _ sym: String, _ b: Binding<Bool>) -> some View {
        Toggle(isOn: Binding(get: { b.wrappedValue }, set: { b.wrappedValue = $0; Haptics.shared.play(.button); Sound.shared.play(.button) })) {
            Label(t, systemImage: sym).font(Typo.label(15)).foregroundStyle(pal.ink)
        }
        .tint(pal.sage)
        .padding(.vertical, 10)
    }

    private func row<C: View>(_ t: String, _ sym: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(t, systemImage: sym).font(Typo.label(15)).foregroundStyle(pal.ink)
            c()
        }
        .padding(.vertical, 12)
    }

    private func segmented<T: Hashable>(_ options: [(T, String)], _ b: Binding<T>) -> some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { o in
                Button {
                    b.wrappedValue = o.0
                    Haptics.shared.play(.button); Sound.shared.play(.button)
                } label: {
                    Text(o.1).font(Typo.label(13, b.wrappedValue == o.0 ? .semibold : .regular))
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .foregroundStyle(b.wrappedValue == o.0 ? pal.surface : pal.ink)
                        .background(Capsule().fill(b.wrappedValue == o.0 ? pal.ink : Color.clear))
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(pal.line))
    }

    private func info(_ t: String, _ v: String) -> some View {
        HStack { Text(t).foregroundStyle(pal.ink); Spacer(); Text(v).foregroundStyle(pal.muted) }.font(Typo.label(15)).padding(.vertical, 14)
    }

    private func link(_ t: String, _ v: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack { Text(t).foregroundStyle(pal.ink); Spacer(); Text(v).foregroundStyle(pal.muted); Image(systemName: "arrow.up.right").font(.system(size: 11)).foregroundStyle(pal.muted) }
                .font(Typo.label(15)).padding(.vertical, 14)
        }
    }
}

struct HowToPlayView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal
    var body: some View {
        let S = app.strings
        VStack(spacing: 0) {
            SheetHeader(title: S.howToPlay) { app.sheet = nil }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(S.howSteps.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .top, spacing: 16) {
                            Image(systemName: step.1).font(.system(size: 20, weight: .light)).foregroundStyle(pal.accent)
                                .frame(width: 46, height: 46).background(Circle().fill(pal.surface)).overlay(Circle().strokeBorder(pal.line))
                            Text(step.0).font(Typo.label(15)).foregroundStyle(pal.ink).fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 4)
                        }
                    }
                }
                .padding(24)
            }
        }
        .background(pal.background.ignoresSafeArea())
    }
}

struct RecordsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal
    var body: some View {
        let S = app.strings, p = app.progress
        VStack(spacing: 0) {
            SheetHeader(title: S.records) { app.sheet = nil }
            ScrollView {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        tile("\(p.totalStars)", S.stars, "star")
                        tile("\(p.stars.values.filter { $0 > 0 }.count)/\(app.levels.count)", S.roomsDone, "house")
                    }
                    HStack(spacing: 12) {
                        tile("\(p.stars.values.filter { $0 == 3 }.count)", S.perfectRooms, "sparkle")
                        tile("\(p.hints)", S.hintsLeft, "lightbulb")
                    }
                    VStack(spacing: 0) {
                        ForEach(app.levels) { l in
                            HStack {
                                Text("\(l.id)").font(Typo.title(17)).foregroundStyle(pal.muted).frame(width: 28, alignment: .leading)
                                Text(l.name.text(app.settings.lang.rawValue)).font(Typo.label(15)).foregroundStyle(pal.ink)
                                Spacer()
                                Stars(count: p.stars[l.id] ?? 0, size: 12)
                            }
                            .padding(.vertical, 11)
                            if l.id != app.levels.last?.id { Rectangle().fill(pal.line).frame(height: 1) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(pal.surface))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(pal.line))
                }
                .padding(20)
            }
        }
        .background(pal.background.ignoresSafeArea())
    }

    private func tile(_ v: String, _ t: String, _ sym: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: sym).font(.system(size: 16, weight: .light)).foregroundStyle(pal.accent)
            Text(v).font(Typo.title(30)).foregroundStyle(pal.ink)
            Text(t).font(Typo.label(12)).foregroundStyle(pal.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(pal.surface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(pal.line))
    }
}
