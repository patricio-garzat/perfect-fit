import CoreHaptics
import UIKit

/// Soft, distinct haptics for each moment. Respects the Vibration setting.
final class Haptics {
    static let shared = Haptics()
    var enabled = true

    enum Kind { case button, select, rotate, snap, place, error, valid, victory, star, introDrop }

    private var engine: CHHapticEngine?
    private let light = UIImpactFeedbackGenerator(style: .light)

    private init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        engine = try? CHHapticEngine()
        engine?.isAutoShutdownEnabled = true
        engine?.resetHandler = { [weak self] in try? self?.engine?.start() }
        try? engine?.start()
    }

    private func tap(_ i: Float, _ s: Float, _ t: TimeInterval = 0) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: s)], relativeTime: t)
    }
    private func hum(_ i: Float, _ s: Float, _ t: TimeInterval, _ d: TimeInterval) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticContinuous, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: i),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: s)], relativeTime: t, duration: d)
    }

    func play(_ k: Kind) {
        guard enabled else { return }
        guard let engine else { if k != .snap { light.impactOccurred(intensity: 0.6) }; return }
        let events: [CHHapticEvent]
        switch k {
        case .button: events = [tap(0.45, 0.35)]
        case .select: events = [tap(0.35, 0.25)]
        case .snap: events = [tap(0.18, 0.15)]
        case .rotate: events = [tap(0.35, 0.4), tap(0.25, 0.4, 0.07)]
        case .place: events = [tap(0.75, 0.2), hum(0.22, 0.05, 0.01, 0.07)]
        case .error: events = [tap(0.4, 0.05), tap(0.3, 0.05, 0.11)]
        case .valid: events = [tap(0.5, 0.3), tap(0.4, 0.4, 0.12)]
        case .star: events = [tap(0.6, 0.45)]
        case .introDrop: events = [tap(0.7, 0.15), hum(0.2, 0.05, 0.01, 0.06)]
        case .victory: events = [tap(0.4, 0.3), tap(0.5, 0.35, 0.14), tap(0.6, 0.4, 0.28), hum(0.25, 0.1, 0.4, 0.35)]
        }
        do {
            try engine.start()
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {}
    }
}
