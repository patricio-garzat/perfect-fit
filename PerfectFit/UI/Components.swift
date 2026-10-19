import SwiftUI
import SceneKit

/// Hosts a SceneController's SCNView.
struct SceneHost: UIViewRepresentable {
    let controller: SceneController
    func makeUIView(context: Context) -> SCNView { controller.view }
    func updateUIView(_ v: SCNView, context: Context) {}
}

/// Round icon button with a light tap, a soft click and a gentle press.
struct IconButton: View {
    let symbol: String
    var size: CGFloat = 44
    var label: String? = nil
    var prominent = false
    var enabled = true
    let action: () -> Void
    @Environment(\.palette) private var pal

    var body: some View {
        Button {
            Sound.shared.play(.button); Haptics.shared.play(.button)
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.4, weight: .regular))
                    .frame(width: size, height: size)
                    .foregroundStyle(prominent ? pal.surface : pal.ink)
                    .background(Circle().fill(prominent ? pal.ink : pal.surface.opacity(0.92)))
                    .overlay(Circle().strokeBorder(pal.line, lineWidth: prominent ? 0 : 1))
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
                if let label {
                    Text(label).font(Typo.label(11)).foregroundStyle(pal.muted)
                }
            }
            .opacity(enabled ? 1 : 0.35)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .accessibilityLabel(label ?? symbol)
    }
}

/// Wide pill button.
struct PillButton: View {
    let title: String
    var symbol: String? = nil
    var primary = true
    let action: () -> Void
    @Environment(\.palette) private var pal

    var body: some View {
        Button {
            Sound.shared.play(.button); Haptics.shared.play(.button)
            action()
        } label: {
            HStack(spacing: 10) {
                if let symbol { Image(systemName: symbol).font(.system(size: 16, weight: .medium)) }
                Text(title).font(Typo.label(17, .semibold)).tracking(0.3)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundStyle(primary ? pal.surface : pal.ink)
            .background(Capsule().fill(primary ? pal.ink : pal.surface.opacity(0.9)))
            .overlay(Capsule().strokeBorder(pal.line, lineWidth: primary ? 0 : 1))
            .shadow(color: .black.opacity(primary ? 0.12 : 0.05), radius: 10, y: 4)
        }
        .buttonStyle(PressStyle())
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Star row (filled up to `count`).
struct Stars: View {
    let count: Int
    var size: CGFloat = 12
    var spacing: CGFloat = 3
    @Environment(\.palette) private var pal
    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < count ? "star.fill" : "star")
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(i < count ? pal.star : pal.starEmpty)
            }
        }
    }
}

/// A sheet's header with a close button.
struct SheetHeader: View {
    let title: String
    let close: () -> Void
    @Environment(\.palette) private var pal
    var body: some View {
        HStack {
            Text(title).font(Typo.title(28)).foregroundStyle(pal.ink)
            Spacer()
            Button { Haptics.shared.play(.button); Sound.shared.play(.button); close() } label: {
                Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(pal.muted)
                    .frame(width: 36, height: 36).background(Circle().fill(pal.line))
            }
        }
        .padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 8)
    }
}
