import Foundation

/// Soft left/right "tick, tock" for calming music, like bilateral tappers.
/// Pure: renders one stereo loop (tick left, then tock right). Local synth — no asset.
enum BilateralTicks {
    enum Side { case left, right }

    /// Time from one side to the other. Tappers sit near one tap per second.
    static let beatSeconds: TimeInterval = 0.8
    /// Peak click level (0…1).
    static let volume: Float = 0.3

    private static let tickHz = 1_200.0
    private static let tockHz = 800.0
    private static let clickSeconds = 0.06
    private static let attackSeconds = 0.002
    private static let decaySeconds = 0.012

    struct HapticTap: Equatable {
        let time: TimeInterval
        let side: Side
        let intensity: Float
        let sharpness: Float
    }

    static var loopSeconds: TimeInterval { beatSeconds * 2 }

    /// A phone has one haptic motor, so the sides differ by feel: a sharp tick, then a soft tock.
    static let hapticTaps: [HapticTap] = [
        HapticTap(time: 0, side: .left, intensity: 0.6, sharpness: 0.8),
        HapticTap(time: beatSeconds, side: .right, intensity: 0.5, sharpness: 0.2),
    ]

    /// The taps for the given sides only, on the same beat times as the full loop.
    static func hapticTaps(for sides: Set<Side>) -> [HapticTap] {
        hapticTaps.filter { sides.contains($0.side) }
    }

    static func side(beat: Int) -> Side {
        beat.isMultiple(of: 2) ? .left : .right
    }

    static func renderLoop(sampleRate: Double) -> (left: [Float], right: [Float]) {
        let beatFrames = Int(sampleRate * beatSeconds)
        let silence = [Float](repeating: 0, count: beatFrames)
        let tick = click(hz: tickHz, frames: beatFrames, sampleRate: sampleRate)
        let tock = click(hz: tockHz, frames: beatFrames, sampleRate: sampleRate)
        return (left: tick + silence, right: silence + tock)
    }

    /// A short sine with a 2 ms ramp in and a fast decay out, padded to one beat.
    private static func click(hz: Double, frames: Int, sampleRate: Double) -> [Float] {
        let clickFrames = min(frames, Int(sampleRate * clickSeconds))
        var out = [Float](repeating: 0, count: frames)
        for i in 0..<clickFrames {
            let t = Double(i) / sampleRate
            let attack = min(1, t / attackSeconds)
            let decay = exp(-t / decaySeconds)
            out[i] = volume * Float(attack * decay * sin(2 * .pi * hz * t))
        }
        return out
    }
}
