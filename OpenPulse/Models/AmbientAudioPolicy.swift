import Foundation

/// Pure policy for optional session ambience (local only — no streaming).
/// Off by default. Audio never required for stim. Audio stop ≠ session stop.
enum AmbientAudioPolicy {
    /// Bundle resource name (without extension).
    static let resourceName = "AmbientCalm"
    static let resourceExtension = "m4a"

    /// Target playback volume (0…1) after fade-in.
    static let targetVolume: Float = 0.55

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
