import SwiftUI

/// Full local history — private habit log, no accounts.
struct SessionHistorySheet: View {
    let sessions: [SessionRecord]
    /// Required wipe callback — parent owns UserDefaults suite (no silent no-op clear).
    var onCleared: () -> Void
    /// Delete one session by id. The parent owns the store.
    var onDelete: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

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
                                stat(title: "Sessions", value: "\(weekCompleted)")
                                Spacer()
                                stat(title: "Minutes", value: "\(weekMinutes)")
                                Spacer()
                                stat(title: "Day streak", value: streak > 0 ? "\(streak)" : "—")
                            }
                            .padding(.horizontal, Theme.spaceS)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("This week: \(weekCompleted) sessions, \(weekMinutes) minutes. Streak: \(streak) days.")
                        } header: {
                            Text("This week")
                        }

                        Section("History") {
                            ForEach(sessions) { record in
                                historyRow(record)
                            }
                            .onDelete { offsets in
                                offsets.map { sessions[$0].id }.forEach(onDelete)
                            }
                        }
                    }
                }
            }
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
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func historyRow(_ record: SessionRecord) -> some View {
        HStack(spacing: 12) {
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
                Text(record.durationText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                if let outcome = record.outcomeLabel {
                    Text(outcome)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
