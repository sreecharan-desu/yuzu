import AppKit
import AVFoundation

/// Original synthesized feedback sounds plus trackpad haptics.
@MainActor
final class Feedback {
    static let shared = Feedback()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private lazy var tickBuffer = makeBuffer(duration: 0.05) { t in
        let env = exp(-t * 95) * min(1, t * 2500)
        return 0.32 * env * (0.62 * sin(2 * .pi * 2350 * t) + 0.26 * sin(2 * .pi * 3520 * t) + 0.12 * sin(2 * .pi * 1180 * t))
    }
    private lazy var bloomBuffer = makeBuffer(duration: 0.11) { t in
        let f = 520 + 900 * t / 0.11
        let env = exp(-t * 32) * min(1, t * 900)
        return 0.18 * env * sin(2 * .pi * f * t)
    }
    private lazy var dropBuffer = makeBuffer(duration: 0.14) { t in
        let env = exp(-t * 30) * min(1, t * 1500)
        return 0.24 * env * (0.6 * sin(2 * .pi * 880 * t) + 0.4 * sin(2 * .pi * 1320 * t))
    }
    private var idleStop: DispatchWorkItem?

    private init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    private func makeBuffer(duration: Double, _ f: (Double) -> Double) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(format.sampleRate * duration)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let ch = buf.floatChannelData![0]
        for i in 0..<Int(frames) { ch[i] = Float(f(Double(i) / format.sampleRate)) }
        return buf
    }

    func warmUp() {
        guard Prefs.sound else { return }
        if !engine.isRunning { try? engine.start() }
        scheduleIdleStop()
    }

    private func play(_ buffer: AVAudioPCMBuffer) {
        guard Prefs.sound else { return }
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
        scheduleIdleStop()
    }

    private func scheduleIdleStop() {
        idleStop?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.player.stop()
                self?.engine.stop()
            }
        }
        idleStop = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: item)
    }

    private func haptic(_ p: NSHapticFeedbackManager.FeedbackPattern) {
        guard Prefs.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(p, performanceTime: .now)
    }

    func bloom() { play(bloomBuffer); haptic(.generic) }
    func tick() { play(tickBuffer); haptic(.alignment) }
    func drop() { play(dropBuffer); haptic(.levelChange) }
}
