import SwiftUI

struct SessionSettingsRow: View {
    @ObservedObject var vm: SessionViewModel
    @State private var showSettings = false

    var body: some View {
        Button {
            showSettings = true
        } label: {
            HStack(spacing: 0) {
                // Timer stepper
                HStack(spacing: 6) {
                    Button { vm.decreaseTimer() } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)

                    Text("\(vm.timerMinutes) min")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.default, value: vm.timerMinutes)

                    Button { vm.increaseTimer() } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                // Divider
                Text("·")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 8)

                // Intensity stepper
                HStack(spacing: 6) {
                    Button { vm.setStrength(vm.strength - 1) } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)

                    Text("Intensity \(vm.strength)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.default, value: vm.strength)

                    Button { vm.setStrength(vm.strength + 1) } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Chevron to open full settings
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        TimerCardView(vm: vm)
                        StrengthCardView(vm: vm)
                    }
                    .padding(16)
                }
                .background(Theme.backgroundGradient.ignoresSafeArea())
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showSettings = false }
                    }
                }
            }
            .presentationDetents([.medium])
            .preferredColorScheme(.dark)
        }
    }
}
