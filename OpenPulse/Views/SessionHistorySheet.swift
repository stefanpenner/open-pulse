import SwiftUI

/// Full local history — private habit log, no accounts.
struct SessionHistorySheet: View {
    let sessions: [SessionRecord]
    /// Required wipe callback — parent owns UserDefaults suite (no silent no-op clear).
    var onCleared: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    private var totalCompleted: Int {
        sessions.filter(\.completed).count
    }

    private var totalMinutes: Int {
        sessions.reduce(0) { $0 + max(0, $1.durationSeconds) } / 60
    }

    private var weekCompleted: Int {
        SessionHistory.completedThisWeek(from: sessions)
    }

    private var weekMinutes: Int {
        SessionHistory.minutesThisWeek(from: sessions)
    }

    private var streak: Int {
        SessionHistory.streak(from: sessions)
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView {
                        Label("No sessions yet", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Finish a session and it will show up here — stored only on this device, never in the cloud.")
                    }
                } else {
                    List {
                        Section {
                            HStack {
                                stat(title: "Sessions", value: "\(sessions.count)")
                                Spacer()
                                stat(title: "Completed", value: "\(totalCompleted)")
                                Spacer()
                                stat(title: "Minutes", value: "\(totalMinutes)")
                            }
                            .listRowBackground(Color.clear)

                            HStack {
                                stat(title: "This week", value: "\(weekCompleted)")
                                Spacer()
                                stat(title: "Week min", value: "\(weekMinutes)")
                                Spacer()
                                stat(title: "Streak", value: streak > 0 ? "\(streak)d" : "—")
                            }
                            .listRowBackground(Color.clear)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("This week \(weekCompleted) completed, \(weekMinutes) minutes, streak \(streak) days")
                        }

                        Section("History") {
                            ForEach(sessions) { record in
                                historyRow(record)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Your sessions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !sessions.isEmpty {
                        Button("Clear", role: .destructive) {
                            confirmClear = true
                        }
                        .accessibilityLabel("Clear session history")
                        .accessibilityHint("Removes all sessions stored on this device")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Clear session history?",
                isPresented: $confirmClear,
                titleVisibility: .visible
            ) {
                Button("Clear all", role: .destructive) {
                    // VM owns wipe (correct UserDefaults suite)
                    onCleared()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the local session log on this device. Nothing is stored in the cloud.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func stat(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private func historyRow(_ record: SessionRecord) -> some View {
        let mins = max(0, record.durationSeconds / 60)
        let secs = max(0, record.durationSeconds % 60)
        let timeText = mins > 0 ? "\(mins)m \(secs)s" : "\(secs)s"
        return HStack(spacing: 12) {
            Image(systemName: StimulationMode(rawValue: record.modeRaw)?.icon ?? "circle")
                .foregroundStyle(StimulationMode(rawValue: record.modeRaw)?.accentColor ?? Theme.textSecondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.modeName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(record.endedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(timeText)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                Text(record.completed ? "Done" : "Stopped")
                    .font(.caption2)
                    .foregroundStyle(record.completed ? Theme.connectedGreen : Theme.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .listRowBackground(Color.white.opacity(0.04))
    }
}
