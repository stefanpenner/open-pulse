import Foundation

/// Pure policy for optional calming ticks (local synth only — no streaming).
/// Off by default. Audio never required for stim. Audio stop ≠ session stop.
enum AmbientAudioPolicy {
    /// Target tick level (0…1) after fade-in. Click loudness lives in BilateralTicks.volume.
    static let targetVolume: Float = 1.0

    /// Fade durations (seconds).
    static let fadeInSeconds: TimeInterval = 2.5
    static let fadeOutSeconds: TimeInterval = 1.8

    /// Whether ambience may play for this session state.
    static func shouldPlay(
        enabled: Bool,
        isRunning: Bool,
        isPaused: Bool,
        isInBackground: Bool
    ) -> Bool {
        // v1: stop in background (no `audio` UIBackgroundMode)
        guard enabled, isRunning, !isPaused, !isInBackground else { return false }
        return true
    }
}
