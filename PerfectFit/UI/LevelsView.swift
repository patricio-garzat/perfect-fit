import SwiftUI
import PerfectFitCore

struct LevelsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var pal
    private var S: Strings { app.strings }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                IconButton(symbol: "chevron.left", size: 42) { app.screen = .home }
                Spacer()
                Text(S.levels).font(Typo.title(28)).foregroundStyle(pal.ink)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "star.fill").font(.system(size: 13)).foregroundStyle(pal.star)
                    Text("\(app.progress.totalStars)/\(app.levels.count * 3)").font(Typo.label(14, .semibold)).foregroundStyle(pal.ink)
                }
                .frame(width: 70, alignment: .trailing)
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 14)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(app.levels) { l in card(l) }
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .background(LinearGradient(colors: [pal.background, pal.backgroundDeep], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private func card(_ l: Level) -> some View {
        let unlocked = app.progress.isUnlocked(l.id)
        let stars = app.progress.stars[l.id] ?? 0
        return Button {
            guard unlocked else { Sound.shared.play(.invalid); Haptics.shared.play(.error); return }
            Sound.shared.play(.button); Haptics.shared.play(.button)
            app.screen = .game(l.id)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(l.id)").font(Typo.title(26)).foregroundStyle(unlocked ? pal.ink : pal.muted)
                    Spacer()
                    if unlocked { Stars(count: stars, size: 11) } else {
                        Image(systemName: "lock").font(.system(size: 13)).foregroundStyle(pal.muted)
                    }
                }
                PlanThumb(level: l, dim: !unlocked)
                    .frame(height: 74)
                Text(l.name.text(app.settings.lang.rawValue))
                    .font(Typo.label(13, .medium)).foregroundStyle(unlocked ? pal.ink : pal.muted).lineLimit(1)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(pal.surface.opacity(unlocked ? 0.95 : 0.55)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(pal.line))
        }
        .buttonStyle(PressStyle())
    }
}

/// The room's plan, drawn like an architect's sketch: floor, walls, door arcs and windows.
struct PlanThumb: View {
    let level: Level
    var dim = false
    @Environment(\.palette) private var pal

    var body: some View {
        Canvas { ctx, size in
            let room = Room(level)
            let s = min(size.width / CGFloat(room.width + 1), size.height / CGFloat(room.height + 1))
            let ox = (size.width - CGFloat(room.width) * s) / 2, oy = (size.height - CGFloat(room.height) * s) / 2
            func rect(_ c: Cell) -> CGRect { CGRect(x: ox + CGFloat(c.x) * s, y: oy + CGFloat(c.y) * s, width: s, height: s) }
            for c in room.floor { ctx.fill(Path(rect(c).insetBy(dx: -0.3, dy: -0.3)), with: .color(pal.accent.opacity(dim ? 0.08 : 0.16))) }
            for c in room.columns { ctx.fill(Path(rect(c)), with: .color(pal.ink.opacity(0.5))) }
            var walls = Path()
            for c in room.floor {
                let r = rect(c)
                if !room.floor.contains(Cell(c.x, c.y - 1)) { walls.move(to: CGPoint(x: r.minX, y: r.minY)); walls.addLine(to: CGPoint(x: r.maxX, y: r.minY)) }
                if !room.floor.contains(Cell(c.x, c.y + 1)) { walls.move(to: CGPoint(x: r.minX, y: r.maxY)); walls.addLine(to: CGPoint(x: r.maxX, y: r.maxY)) }
                if !room.floor.contains(Cell(c.x - 1, c.y)) { walls.move(to: CGPoint(x: r.minX, y: r.minY)); walls.addLine(to: CGPoint(x: r.minX, y: r.maxY)) }
                if !room.floor.contains(Cell(c.x + 1, c.y)) { walls.move(to: CGPoint(x: r.maxX, y: r.minY)); walls.addLine(to: CGPoint(x: r.maxX, y: r.maxY)) }
            }
            ctx.stroke(walls, with: .color(pal.ink.opacity(dim ? 0.3 : 0.75)), style: StrokeStyle(lineWidth: 2.2, lineCap: .square))
            // windows: light double line
            for w in room.windows {
                for c in w.cells {
                    let r = rect(c)
                    var p = Path()
                    switch w.side {
                    case .north: p.move(to: CGPoint(x: r.minX + 1, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX - 1, y: r.minY))
                    case .south: p.move(to: CGPoint(x: r.minX + 1, y: r.maxY)); p.addLine(to: CGPoint(x: r.maxX - 1, y: r.maxY))
                    case .west: p.move(to: CGPoint(x: r.minX, y: r.minY + 1)); p.addLine(to: CGPoint(x: r.minX, y: r.maxY - 1))
                    case .east: p.move(to: CGPoint(x: r.maxX, y: r.minY + 1)); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 1))
                    }
                    ctx.stroke(p, with: .color(Color(hex: 0x9FC3D6)), lineWidth: 3)
                }
            }
            // doors: gap + quarter arc
            for d in room.doors {
                let a = rect(d.cells[0]), b = rect(d.cells[d.cells.count - 1])
                let span = a.union(b)
                var gap = Path(), arc = Path()
                let len = CGFloat(d.width) * s
                switch d.side {
                case .north:
                    gap.move(to: CGPoint(x: span.minX, y: span.minY)); gap.addLine(to: CGPoint(x: span.maxX, y: span.minY))
                    arc.move(to: CGPoint(x: span.minX, y: span.minY + len)); arc.addArc(center: CGPoint(x: span.minX, y: span.minY), radius: len, startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
                case .south:
                    gap.move(to: CGPoint(x: span.minX, y: span.maxY)); gap.addLine(to: CGPoint(x: span.maxX, y: span.maxY))
                    arc.move(to: CGPoint(x: span.minX, y: span.maxY - len)); arc.addArc(center: CGPoint(x: span.minX, y: span.maxY), radius: len, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
                case .west:
                    gap.move(to: CGPoint(x: span.minX, y: span.minY)); gap.addLine(to: CGPoint(x: span.minX, y: span.maxY))
                    arc.move(to: CGPoint(x: span.minX + len, y: span.minY)); arc.addArc(center: CGPoint(x: span.minX, y: span.minY), radius: len, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
                case .east:
                    gap.move(to: CGPoint(x: span.maxX, y: span.minY)); gap.addLine(to: CGPoint(x: span.maxX, y: span.maxY))
                    arc.move(to: CGPoint(x: span.maxX - len, y: span.minY)); arc.addArc(center: CGPoint(x: span.maxX, y: span.minY), radius: len, startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
                }
                ctx.stroke(gap, with: .color(pal.surface), lineWidth: 3.4)
                ctx.stroke(arc, with: .color(pal.ink.opacity(0.35)), lineWidth: 0.8)
            }
        }
    }
}
