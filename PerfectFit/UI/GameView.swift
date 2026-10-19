import SwiftUI
import PerfectFitCore

struct GameView: View {
    let levelID: Int
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal
    @Environment(\.colorScheme) private var scheme
    @State private var session: GameSession
    @State private var controller: SceneController
    @State private var paused = false
    @State private var victory: VictoryInfo?
    @State private var overTray = false
    @State private var trayDragging: Int?
    @State private var showIntroHint = true
    @State private var hintMessage: String?
    @State private var safeTop: CGFloat = 0
    @State private var safeBottom: CGFloat = 0

    struct VictoryInfo: Equatable { let stars: Int; let harmony: (Int, Int); let flow: Bool; let earnedHint: Bool
        static func == (a: Self, b: Self) -> Bool { a.stars == b.stars && a.flow == b.flow && a.harmony == b.harmony && a.earnedHint == b.earnedHint }
    }

    init(level: Level) {
        levelID = level.id
        let s = GameSession(level: level)
        _session = State(initialValue: s)
        _controller = State(initialValue: SceneController(session: s))
    }

    private var S: Strings { app.strings }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                SceneHost(controller: controller)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    topBar
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                    statusLine
                        .padding(.top, 10)
                    Spacer(minLength: 0)
                    actionRow
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                    tray
                        .background(GeometryReader { g in
                            Color.clear.onAppear { controller.trayTop = g.frame(in: .global).minY }
                                .onChange(of: g.frame(in: .global).minY) { _, y in controller.trayTop = y }
                        })
                }
                .opacity(victory == nil ? 1 : 0)
                .animation(.easeInOut(duration: 0.5), value: victory == nil)

                if paused { pauseMenu.transition(.opacity) }
                if let v = victory {
                    VictoryView(level: session.level, info: v, hasNext: app.level(levelID + 1) != nil,
                                next: { app.screen = .game(levelID + 1) },
                                replay: replay,
                                levels: { app.screen = .levels })
                    .transition(.opacity)
                }
            }
            .onAppear {
                safeTop = geo.safeAreaInsets.top; safeBottom = geo.safeAreaInsets.bottom
                controller.insets = UIEdgeInsets(top: geo.safeAreaInsets.top + 110, left: 0, bottom: geo.safeAreaInsets.bottom + (session.kinds.count > 6 ? 250 : 190), right: 0)
                controller.dark = app.isDark(scheme)
                controller.onTrayHover = { overTray = $0 }
                app.progress.lastLevel = levelID
            }
            .onChange(of: app.isDark(scheme)) { _, d in controller.dark = d }
        }
        .animation(.easeInOut(duration: 0.3), value: paused)
    }

    // MARK: - top

    private var topBar: some View {
        HStack(spacing: 12) {
            IconButton(symbol: "pause", size: 42) { paused = true }
            Spacer()
            VStack(spacing: 2) {
                Text(S.levelN(levelID).uppercased()).font(Typo.label(11, .semibold)).tracking(1.6).foregroundStyle(pal.muted)
                Text(session.level.name.text(app.settings.lang.rawValue)).font(Typo.title(21)).foregroundStyle(pal.ink)
            }
            Spacer()
            IconButton(symbol: "arrow.counterclockwise", size: 42) {
                session.reset(); controller.sync(.all)
            }
            ZStack(alignment: .topTrailing) {
                IconButton(symbol: session.hintBusy ? "ellipsis" : "lightbulb", size: 42, enabled: !session.hintBusy) { useHint() }
                Text("\(app.progress.hints)")
                    .font(Typo.label(10, .bold)).foregroundStyle(pal.surface)
                    .frame(minWidth: 17, minHeight: 17).background(Circle().fill(pal.accent))
                    .offset(x: 4, y: -3)
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        let e = session.eval
        let text: String? = {
            if let hintMessage { return hintMessage }
            if let i = session.selected {
                let k = session.kinds[i]
                var parts = [S.piece(k)]
                if let problem = e.issues.first(where: { $0.piece == i }) { parts = [S.issue(problem, session.kinds)] }
                let needs = S.needs(k, rules: session.level.rules)
                if !needs.isEmpty { parts.append(needs) }
                if let p = k.preference, e.preferenceMet[i] != nil || session.placement(i) == nil { parts.append(S.likes(p)) }
                return parts.joined(separator: "\n")
            }
            if showIntroHint, let h = session.level.hint, session.layout.placedCount == 0 { return h.text(app.settings.lang.rawValue) }
            if let first = e.issues.first(where: { $0.piece != nil }) { return S.issue(first, session.kinds) }
            if case .notPlaced(let n)? = e.issues.first { return S.left(n) }
            if e.valid { return S.allPlaced }
            return nil
        }()
        VStack(spacing: 8) {
            if let text {
                Text(text)
                    .font(Typo.label(13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(pal.ink.opacity(0.85))
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Capsule().fill(pal.surface.opacity(0.88)).overlay(Capsule().strokeBorder(pal.line)))
                    .padding(.horizontal, 24)
                    .id(text)
                    .transition(.opacity)
            }
            if e.valid {
                Stars(count: e.stars, size: 14, spacing: 5)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: text)
        .animation(.easeInOut(duration: 0.25), value: e.stars)
    }

    // MARK: - bottom

    private var actionRow: some View {
        HStack(spacing: 14) {
            IconButton(symbol: "camera.rotate", size: 44, label: nil) { controller.turnCamera() }
            Spacer()
            if session.selected != nil {
                IconButton(symbol: "arrow.clockwise", size: 50, label: S.rotate) {
                    if controller.drag != nil { controller.rotateDrag() } else { session.rotateSelected() }
                }
                if let i = session.selected, session.placement(i) != nil {
                    IconButton(symbol: "tray.and.arrow.down", size: 50, label: S.toTray) { session.remove(i) }
                }
            }
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .frame(height: 74)
        .animation(.easeInOut(duration: 0.2), value: session.selected)
    }

    /// Tray groups: one entry per kind (identical pieces stack with a count), the next unplaced index first.
    private var trayGroups: [[Int]] {
        var order: [String] = [], groups: [String: [Int]] = [:]
        for i in session.trayPieces {
            let id = session.kinds[i].id
            if groups[id] == nil { order.append(id) }
            groups[id, default: []].append(i)
        }
        return order.map { groups[$0]! }
    }

    @ViewBuilder private var tray: some View {
        let groups = trayGroups
        let perRow = 6
        let rows = stride(from: 0, to: groups.count, by: perRow).map { Array(groups[$0..<min($0 + perRow, groups.count)]) }
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(pal.surface.opacity(overTray ? 0.98 : 0.9))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(overTray ? pal.accent.opacity(0.6) : pal.line, lineWidth: overTray ? 1.5 : 1))
                .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
            if groups.isEmpty {
                if session.eval.valid {
                    PillButton(title: S.done, symbol: "checkmark") { finish() }
                        .padding(.horizontal, 22)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    Text(overTray ? S.toTray : S.allPlaced).font(Typo.label(13)).foregroundStyle(pal.muted)
                }
            } else {
                VStack(spacing: 2) {
                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: 2) {
                            ForEach(rows[r], id: \.self) { g in trayItem(g, compact: groups.count > 4) }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }
        }
        .frame(height: rows.count > 1 ? 172 : 104)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .animation(.easeInOut(duration: 0.25), value: groups)
        .animation(.easeInOut(duration: 0.3), value: session.eval.valid)
    }

    private func trayItem(_ group: [Int], compact: Bool) -> some View {
        let i = group[0]
        let k = session.kinds[i]
        let selected = group.contains { session.selected == $0 }
        let side: CGFloat = compact ? 46 : 62
        return VStack(spacing: 1) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: Thumbnails.image(k, style: session.level.style, rotation: session.rotation(i)))
                    .resizable().scaledToFit()
                    .frame(width: side, height: side)
                if group.count > 1 {
                    Text("×\(group.count)").font(Typo.label(10, .bold)).foregroundStyle(pal.surface)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(pal.ink.opacity(0.75)))
                        .offset(x: 4, y: -2)
                }
            }
            Text(S.piece(k)).font(Typo.label(compact ? 9 : 10)).foregroundStyle(pal.muted).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: 84)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 14).fill(selected ? pal.accent.opacity(0.14) : .clear))
        .opacity(trayDragging == i ? 0.25 : 1)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { g in
                    let pt = controller.view.convert(g.location, from: nil)
                    if trayDragging == nil {
                        trayDragging = i
                        showIntroHint = false
                        controller.beginDrag(piece: i, fromTray: true, at: pt)
                    } else { controller.moveDrag(to: pt) }
                }
                .onEnded { _ in
                    controller.endDrag()
                    trayDragging = nil
                }
        )
        .simultaneousGesture(TapGesture().onEnded {
            showIntroHint = false
            if session.selected == i { autoPlace(i) } else {
                session.selected = i
                Haptics.shared.play(.select); Sound.shared.play(.button, volume: 0.6)
            }
        })
    }

    /// Tapping a selected tray piece drops it on the free spot nearest the middle of the room.
    private func autoPlace(_ i: Int) {
        let k = session.kinds[i], r = session.rotation(i), room = session.room
        let (w, h) = k.rotatedSize(r)
        let cx = Double(room.width) / 2, cy = Double(room.height) / 2
        var best: Placement?, bestD = Double.infinity
        for y in 0...max(0, room.height - h) { for x in 0...max(0, room.width - w) {
            let p = Placement(origin: Cell(x, y), rotation: r)
            guard session.canPlace(i, p) else { continue }
            let d = pow(Double(x) + Double(w) / 2 - cx, 2) + pow(Double(y) + Double(h) / 2 - cy, 2)
            if d < bestD { bestD = d; best = p }
        }}
        if let best { session.place(i, best) } else { session.feedbackInvalid() }
    }

    // MARK: - actions

    private func useHint() {
        showIntroHint = false
        guard app.progress.hints > 0 else { flash(S.noHints); return }
        session.hint { ok in
            if ok { app.progress.hints -= 1; app.progress.hintsUsed += 1 } else { flash(S.hintNone) }
        }
    }

    private func flash(_ m: String) {
        hintMessage = m
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { if hintMessage == m { hintMessage = nil } }
    }

    private func finish() {
        let e = session.eval
        guard e.valid else { return }
        let earned = app.complete(level: levelID, stars: e.stars)
        controller.celebrate(room: UIEdgeInsets(top: safeTop + 10, left: 0, bottom: 470 + safeBottom, right: 0))
        Sound.shared.play(.victory)
        Haptics.shared.play(.victory)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            victory = VictoryInfo(stars: e.stars, harmony: (e.harmonyMet, e.harmonyTotal), flow: e.flow, earnedHint: earned)
        }
    }

    private func replay() {
        victory = nil
        session.reset()
        controller.resetMood()
        controller.sync(.all)
    }

    private var pauseMenu: some View {
        ZStack {
            pal.background.opacity(0.75).ignoresSafeArea().onTapGesture { paused = false }
            VStack(spacing: 12) {
                Text(S.paused).font(Typo.title(32)).foregroundStyle(pal.ink).padding(.bottom, 10)
                PillButton(title: S.resume, symbol: "play.fill") { paused = false }
                PillButton(title: S.restart, symbol: "arrow.counterclockwise", primary: false) { paused = false; replay() }
                PillButton(title: S.levels, symbol: "square.grid.2x2", primary: false) { app.screen = .levels }
                PillButton(title: S.settings, symbol: "slider.horizontal.3", primary: false) { app.sheet = .settings }
            }
            .padding(.horizontal, 44)
        }
    }
}
