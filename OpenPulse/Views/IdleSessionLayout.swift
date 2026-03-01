import SwiftUI

struct IdleSessionLayout: View {
    @ObservedObject var vm: SessionViewModel
    @State private var infoMode: StimulationMode? = nil

    var body: some View {
        VStack(spacing: 12) {
            StatusBarView(vm: vm)

            Spacer()

            Text("I feel...")
                .font(.title2.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            ExpandedModePicker(vm: vm) { mode in
                infoMode = mode
            }

            Spacer()

            ActionButtonView(vm: vm)
        }
        .sheet(item: $infoMode) { mode in
            ModeInfoSheet(mode: mode)
                .presentationDetents([.medium])
                .preferredColorScheme(.dark)
        }
    }
}

private struct ModeInfoSheet: View {
    let mode: StimulationMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    HStack(spacing: 12) {
                        Image(systemName: mode.icon)
                            .font(.title2)
                            .foregroundStyle(mode.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.name)
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)

                            if !mode.evidenceLevel.isEmpty {
                                Text("Evidence: \(mode.evidenceLevel)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(mode.accentColor.opacity(0.8))
                            }
                        }
                    }

                    // Description
                    Text(mode.summary)
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)

                    // Research links
                    if !mode.researchLinks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RESEARCH")
                                .font(Theme.sectionLabel)
                                .foregroundStyle(Theme.textTertiary)
                                .tracking(1.5)

                            ForEach(mode.researchLinks, id: \.url) { link in
                                if let url = URL(string: link.url) {
                                    Link(destination: url) {
                                        HStack {
                                            Text(link.label)
                                                .font(.callout)
                                                .foregroundStyle(Theme.accentBlue)
                                                .multilineTextAlignment(.leading)

                                            Spacer()

                                            Image(systemName: "arrow.up.right")
                                                .font(.caption)
                                                .foregroundStyle(Theme.accentBlue.opacity(0.6))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle(mode.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
