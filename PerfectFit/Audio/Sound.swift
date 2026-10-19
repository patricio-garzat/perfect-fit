import AVFoundation

/// Every sound is synthesized here when the app starts (no audio files): warm, ASMR-like wood and soft clicks.
/// Moves only make a soft thump; melodies (marimba) are kept for rewards. Studio rule: "ambient" session, so the
/// app follows the silent switch and never shows up in the Dynamic Island.
final class Sound {
    static let shared = Sound()

    enum Cue: CaseIterable {
        case pick, place, placeHeavy, rotate, tick, invalid, button, toTray, valid, star1, star2, star3, victory, introThump, introChime
    }

    var enabled = true { didSet { if !enabled { slide.volume = 0 } } }

    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    private let mixer = AVAudioMixerNode()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private let slide = AVAudioPlayerNode()
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var started = false

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
        engine.attach(mixer)
        engine.attach(reverb)
        reverb.loadFactoryPreset(.smallRoom)
        reverb.wetDryMix = 14
        engine.connect(mixer, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9
        for _ in 0..<10 {
            let p = AVAudioPlayerNode()
            engine.attach(p); engine.connect(p, to: mixer, format: format)
            players.append(p)
        }
        engine.attach(slide); engine.connect(slide, to: mixer, format: format)
        for c in Cue.allCases { buffers[c] = Synth.make(c, format) }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            if type == .ended { self?.started = false; self?.start() }
        }
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.started = false; self?.start()
        }
    }

    func start() {
        guard !started || !engine.isRunning else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning { try engine.start() }
            players.forEach { $0.play() }
            if let loop = Synth.slideLoop(format) {
                slide.stop()
                slide.scheduleBuffer(loop, at: nil, options: .loops)
                slide.volume = 0
                slide.play()
            }
            started = true
        } catch { started = false }
    }

    func play(_ cue: Cue, volume: Float = 1, pitch: Float = 1) {
        guard enabled, let b = buffers[cue] else { return }
        if !engine.isRunning { started = false; start() }
        let p = players[next]; next = (next + 1) % players.count
        p.volume = volume
        p.stop()
        p.scheduleBuffer(b, at: nil, options: [])
        p.play()
        _ = pitch
    }

    /// Soft felt-on-wood slide while dragging; level follows the finger's speed.
    func setSlide(speed: Double) {
        guard enabled else { slide.volume = 0; return }
        let target = Float(min(1, speed / 900)) * 0.22
        slide.volume = slide.volume * 0.6 + target * 0.4
    }
}

/// Offline synthesis of every cue into a buffer.
enum Synth {
    static let sr = 44_100.0

    static func buffer(_ f: AVAudioFormat, seconds: Double, _ fill: (Int, Double) -> Double) -> AVAudioPCMBuffer {
        let n = Int(seconds * sr)
        let b = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(n))!
        b.frameLength = AVAudioFrameCount(n)
        let d = b.floatChannelData![0]
        for i in 0..<n { d[i] = Float(fill(i, Double(i) / sr)) }
        // gentle fade at the end, no clicks
        let fade = min(n, Int(0.01 * sr))
        for k in 0..<fade { d[n - 1 - k] *= Float(k) / Float(fade) }
        return b
    }

    /// Deterministic noise.
    struct Noise { var s: UInt32 = 0x12345; mutating func next() -> Double { s ^= s << 13; s ^= s >> 17; s ^= s << 5; return Double(s) / Double(UInt32.max) * 2 - 1 } }

    /// One-pole low-pass state.
    struct LP { var y = 0.0; let a: Double; init(_ hz: Double) { a = 1 - exp(-2 * .pi * hz / sr) }; mutating func run(_ x: Double) -> Double { y += a * (x - y); return y } }

    /// Wooden thump: a low body that drops slightly in pitch, a warm knock and a short felt click. Never sharp.
    static func thump(_ f: AVAudioFormat, body: Double, weight: Double, gain: Double) -> AVAudioPCMBuffer {
        var noise = Noise(), lp = LP(900), lp2 = LP(2400)
        var phase = 0.0, phase2 = 0.0
        return buffer(f, seconds: 0.45) { _, t in
            let freq = body * (1 + 0.35 * exp(-t * 40))
            phase += 2 * .pi * freq / sr
            phase2 += 2 * .pi * freq * 2.71 / sr
            let env = exp(-t * (14 - weight * 5)) * (1 - exp(-t * 900))
            let bodyS = sin(phase) * env + 0.18 * sin(phase2) * exp(-t * 30)
            let click = lp2.run(lp.run(noise.next())) * exp(-t * 120) * 0.9
            return (bodyS * 0.8 + click) * gain
        }
    }

    /// Warm marimba note (fundamental + the 4th partial a marimba bar has, soft mallet).
    static func marimba(_ f: AVAudioFormat, notes: [(Double, Double)], seconds: Double, gain: Double) -> AVAudioPCMBuffer {
        var noise = Noise(), lp = LP(1500)
        return buffer(f, seconds: seconds) { _, t in
            var s = 0.0
            for (hz, at) in notes where t >= at {
                let u = t - at
                let env = exp(-u * 3.2) * (1 - exp(-u * 600))
                s += (sin(2 * .pi * hz * u) * 0.8 + sin(2 * .pi * hz * 3.93 * u) * 0.12 * exp(-u * 14) + sin(2 * .pi * hz * 2 * u) * 0.08 * exp(-u * 6)) * env
                if u < 0.02 { s += lp.run(noise.next()) * (1 - u / 0.02) * 0.08 }
            }
            return s * gain
        }
    }

    static func make(_ c: Sound.Cue, _ f: AVAudioFormat) -> AVAudioPCMBuffer {
        switch c {
        case .pick:
            // light lift: a small airy tok
            var noise = Noise(), lp = LP(1800)
            var ph = 0.0
            return buffer(f, seconds: 0.18) { _, t in
                ph += 2 * .pi * 320 * (1 + 0.2 * exp(-t * 60)) / sr
                return (sin(ph) * exp(-t * 45) * 0.35 + lp.run(noise.next()) * exp(-t * 70) * 0.35) * 0.55
            }
        case .place: return thump(f, body: 96, weight: 0.4, gain: 0.85)
        case .placeHeavy: return thump(f, body: 74, weight: 1, gain: 0.95)
        case .introThump: return thump(f, body: 84, weight: 0.7, gain: 0.7)
        case .rotate:
            // two soft wooden clicks, like a ratchet in felt
            var noise = Noise(), lp = LP(2200)
            return buffer(f, seconds: 0.2) { _, t in
                var s = 0.0
                for at in [0.0, 0.07] where t >= at { let u = t - at; s += sin(2 * .pi * 520 * u) * exp(-u * 90) * 0.4 + lp.run(noise.next()) * exp(-u * 160) * 0.5 }
                return s * 0.45
            }
        case .tick:
            var noise = Noise(), lp = LP(1600)
            return buffer(f, seconds: 0.05) { _, t in lp.run(noise.next()) * exp(-t * 200) * 0.22 }
        case .invalid:
            // muted low double knock
            var ph = 0.0
            return buffer(f, seconds: 0.32) { _, t in
                var s = 0.0
                for (at, hz) in [(0.0, 165.0), (0.11, 140.0)] where t >= at { let u = t - at; ph = 2 * .pi * hz * u; s += sin(ph) * exp(-u * 26) * (1 - exp(-u * 500)) }
                return s * 0.42
            }
        case .button:
            var ph = 0.0
            return buffer(f, seconds: 0.08) { _, t in ph += 2 * .pi * 760 / sr; return sin(ph) * exp(-t * 90) * 0.16 }
        case .toTray:
            var noise = Noise(), lp = LP(700)
            return buffer(f, seconds: 0.3) { _, t in lp.run(noise.next()) * sin(.pi * min(1, t / 0.3)) * 0.35 }
        case .valid:
            return marimba(f, notes: [(523.25, 0), (783.99, 0.12)], seconds: 1.4, gain: 0.32)       // C5 G5
        case .star1: return marimba(f, notes: [(587.33, 0)], seconds: 1.2, gain: 0.32)             // D5
        case .star2: return marimba(f, notes: [(659.25, 0)], seconds: 1.2, gain: 0.32)             // E5
        case .star3: return marimba(f, notes: [(783.99, 0)], seconds: 1.4, gain: 0.32)             // G5
        case .victory:
            // pentatonic arpeggio, slow and warm
            return marimba(f, notes: [(392.0, 0), (440.0, 0.14), (523.25, 0.28), (659.25, 0.42), (783.99, 0.6)], seconds: 2.6, gain: 0.3)
        case .introChime:
            return marimba(f, notes: [(523.25, 0), (659.25, 0.09)], seconds: 1.8, gain: 0.22)
        }
    }

    /// Seamless brown-ish noise loop for sliding furniture.
    static func slideLoop(_ f: AVAudioFormat) -> AVAudioPCMBuffer? {
        var noise = Noise(), lp = LP(420), lp2 = LP(900)
        var brown = 0.0
        let b = buffer(f, seconds: 2) { _, _ in
            brown = (brown + noise.next() * 0.08) * 0.985
            return lp2.run(lp.run(brown * 3 + noise.next() * 0.05))
        }
        // crossfade the ends so the loop never clicks
        let d = b.floatChannelData![0], n = Int(b.frameLength), x = 2000
        for k in 0..<x { let a = Float(k) / Float(x); d[k] = d[k] * a + d[n - x + k] * (1 - a) }
        b.frameLength = AVAudioFrameCount(n - x)
        return b
    }
}
