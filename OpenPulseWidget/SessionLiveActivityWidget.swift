import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Lock Screen + Dynamic Island UI for an active Open Pulse session.
/// Glanceable wellness session presence only — no tracking or medical claims.
struct SessionLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SessionActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    // Fixed mode glyph — status chrome lives bottom + compact (no dual signal)
                    Label(context.attributes.modeName, systemImage: "waveform.path.ecg")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)
                        .lineLimit(1)
                        .accessibilityLabel(context.attributes.modeName)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdownText(context.state)
                        .font(.title3.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .accessibilityLabel(timeA11y(context.state))
                }
                DynamicIslandExpandedRegion(.center) {
                    progressView(context)
                        .tint(.teal)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    // Status + one-hand intensity ± + pause/resume/stop
                    HStack(spacing: 8) {
                        Text(statusLine(context.state))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 4)
                        intensityNudgeButtons(for: context.state)
                        controlButton(for: context.state)
                    }
                }
            } compactLeading: {
                // Progress ring + state tint so Island shows session progress at a glance
                compactProgress(context)
                    .accessibilityLabel(compactA11y(context.state))
            } compactTrailing: {
                countdownText(context.state)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .accessibilityLabel(timeA11y(context.state))
                    .frame(minWidth: 36, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            } minimal: {
                // Minimal: tiny progress so competing apps still show we're mid-session
                compactProgress(context, size: 14)
                    .accessibilityLabel(compactA11y(context.state))
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<SessionActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Open Pulse")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(context.attributes.modeName)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(statusLine(context.state))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                countdownText(context.state)
                    .font(.system(.title, design: .monospaced).weight(.light))
                    .accessibilityLabel(timeA11y(context.state))
                progressView(context)
                    .tint(.teal)
                    .frame(width: 90)
                    .accessibilityHidden(true)
                HStack(spacing: 8) {
                    intensityNudgeButtons(for: context.state)
                    controlButton(for: context.state)
                }
            }
        }
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.85))
        .activitySystemActionForegroundColor(.white)
    }

    /// System-driven countdown when running; frozen static time when paused/offline.
    @ViewBuilder
    private func countdownText(_ state: SessionActivityAttributes.ContentState) -> some View {
        if LiveActivityPresentation.usesLiveCountdown(
            endsAt: state.endsAt, isPaused: state.isPaused, isLinkReady: state.isLinkReady
        ), let end = state.endsAt {
            Text(timerInterval: Date.now...end, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } else {
            Text(LiveActivityPresentation.formatTime(state.remainingSeconds))
                .monospacedDigit()
        }
    }

    /// Compact Island progress ring — live timer when running, static when frozen.
    @ViewBuilder
    private func compactProgress(
        _ context: ActivityViewContext<SessionActivityAttributes>,
        size: CGFloat = 18
    ) -> some View {
        let state = context.state
        let total = state.totalSeconds > 0
            ? state.totalSeconds
            : max(1, context.attributes.totalSeconds)
        let isRunning = !state.isPaused && state.remainingSeconds > 0
        let tint: Color = LiveActivityPresentation.claimsPendingOffChrome(
            isRunning: isRunning,
            pendingDeviceOff: state.pendingDeviceOff
        )
            ? .orange
            : (!state.isLinkReady ? .yellow : .teal)
        Group {
            if LiveActivityPresentation.usesLiveCountdown(
                endsAt: state.endsAt, isPaused: state.isPaused, isLinkReady: state.isLinkReady
            ), let end = state.endsAt {
                let start = end.addingTimeInterval(-TimeInterval(max(1, total)))
                ProgressView(timerInterval: start...end, countsDown: true)
                    .progressViewStyle(.circular)
            } else {
                ProgressView(value: LiveActivityPresentation.progress(
                    remainingSeconds: state.remainingSeconds,
                    totalSeconds: total
                ))
                .progressViewStyle(.circular)
            }
        }
        .tint(tint)
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func progressView(_ context: ActivityViewContext<SessionActivityAttributes>) -> some View {
        let state = context.state
        let total = state.totalSeconds > 0
            ? state.totalSeconds
            : max(1, context.attributes.totalSeconds)
        if LiveActivityPresentation.usesLiveCountdown(
            endsAt: state.endsAt, isPaused: state.isPaused, isLinkReady: state.isLinkReady
        ), let end = state.endsAt {
            let start = end.addingTimeInterval(-TimeInterval(max(1, total)))
            ProgressView(timerInterval: start...end, countsDown: true)
        } else {
            ProgressView(value: LiveActivityPresentation.progress(
                remainingSeconds: state.remainingSeconds,
                totalSeconds: total
            ))
        }
    }

    /// One-hand intensity ± on expanded Island / lock-adjacent controls.
    @ViewBuilder
    private func intensityNudgeButtons(for state: SessionActivityAttributes.ContentState) -> some View {
        if StrengthPresentation.showsLiveActivityNudge(
            isPaused: state.isPaused,
            remainingSeconds: state.remainingSeconds
        ) {
            HStack(spacing: 4) {
                Button(intent: DecreaseOpenPulseIntensityIntent()) {
                    Image(systemName: "minus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decrease intensity")

                Button(intent: IncreaseOpenPulseIntensityIntent()) {
                    Image(systemName: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Increase intensity")
            }
        }
    }

    /// Single LA control (HIG) — pause / resume / stop (stop when offline pause).
    @ViewBuilder
    private func controlButton(for state: SessionActivityAttributes.ContentState) -> some View {
        // Complete linger (remaining 0, not paused) must not offer Pause
        let action = LiveActivityPresentation.controlAction(
            isPaused: state.isPaused,
            isRunning: !state.isPaused && state.remainingSeconds > 0,
            pendingDeviceOff: state.pendingDeviceOff,
            isLinkReady: state.isLinkReady
        )
        switch action {
        case .pause:
            Button(intent: PauseOpenPulseSessionIntent()) {
                Label("Pause", systemImage: "pause.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pause session")
        case .resume:
            Button(intent: ResumeOpenPulseSessionIntent()) {
                Label("Resume", systemImage: "play.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.teal)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resume session")
        case .stop:
            Button(intent: StopOpenPulseSessionIntent()) {
                Label("Stop", systemImage: "stop.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop session")
            .accessibilityHint("Ends the session and turns the device off")
        case .none:
            EmptyView()
        }
    }

    /// Prefer VM-computed `statusText` so app + Island stay aligned.
    private func statusLine(_ state: SessionActivityAttributes.ContentState) -> String {
        if !state.statusText.isEmpty {
            return state.statusText
        }
        return LiveActivityPresentation.lockScreenFallback(
            isPaused: state.isPaused,
            isRunning: sessionIsRunning(state),
            pendingDeviceOff: state.pendingDeviceOff,
            isLinkReady: state.isLinkReady
        )
    }

    private func sessionIsRunning(_ state: SessionActivityAttributes.ContentState) -> Bool {
        !state.isPaused && state.remainingSeconds > 0
    }

    private func compactIcon(_ state: SessionActivityAttributes.ContentState) -> String {
        LiveActivityPresentation.compactIconName(
            isPaused: state.isPaused,
            isRunning: sessionIsRunning(state),
            pendingDeviceOff: state.pendingDeviceOff,
            isLinkReady: state.isLinkReady,
            isStimulationActive: state.stimulationActive
        )
    }

    private func compactA11y(_ state: SessionActivityAttributes.ContentState) -> String {
        LiveActivityPresentation.compactAccessibility(
            statusText: state.statusText,
            isPaused: state.isPaused,
            isRunning: sessionIsRunning(state),
            pendingDeviceOff: state.pendingDeviceOff,
            isLinkReady: state.isLinkReady
        )
    }

    private func timeA11y(_ state: SessionActivityAttributes.ContentState) -> String {
        LiveActivityPresentation.timeAccessibility(remainingSeconds: state.remainingSeconds)
    }
}
