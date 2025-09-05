import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    var state: ChallengeState

    // Share sheet for the JSON backup
    @State private var exportURL: URL?
    @State private var presentShare = false
    @State private var showEraseConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                // --- Challenge basics
                Section("Challenge") {
                    HStack { Text("Start Date"); Spacer(); Text(state.startDate, style: .date).foregroundStyle(.secondary) }
                    Toggle("Allow 1 alcohol use per month",
                           isOn: Binding(get: { state.allowAlcoholMonthly },
                                         set: { state.allowAlcoholMonthly = $0 }))
                }

                // --- Daily goals & input behavior
                Section("Daily Goals & Input") {
                    Stepper(value: Binding(
                        get: { max(1, state.waterStepOunces) },
                        set: { state.waterStepOunces = max(1, min($0, 256)) }
                    ), in: 1...256) {
                        HStack {
                            Text("Water increment step")
                            Spacer()
                            Text("\(state.waterStepOunces) oz").foregroundStyle(.secondary)
                        }
                    }
                    Text("Set this to your bottle size (e.g., 48 oz).")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                // --- Diet
                Section("Diet") {
                    HStack { Text("Name"); Spacer(); Text(state.dietName).foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description").font(.subheadline).foregroundStyle(.secondary)
                        Text(state.dietDescription)
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }

                // --- Security
                Section("Security") {
                    Label("Face ID is required at launch and resume", systemImage: "faceid")
                        .foregroundStyle(.secondary)
                }

                // --- Backup / Export (JSON)
                Section("Backup / Export") {
                    Button("Export Backup (JSON)…") {
                        do {
                            exportURL = try BackupService.exportJSON(state: state)
                            presentShare = (exportURL != nil)
                        } catch {
                            exportURL = nil
                        }
                    }
                    .sheet(isPresented: $presentShare) {
                        if let url = exportURL {
                            ActivityView(activityItems: [url])
                        }
                    }
                }

                // --- Reset
                Section("Reset") {
                    Button(role: .destructive) { showEraseConfirm = true } label: {
                        Text("Erase All Data")
                    }
                    .confirmationDialog("Erase all local data? This cannot be undone.",
                                        isPresented: $showEraseConfirm,
                                        titleVisibility: .visible) {
                        Button("Erase All", role: .destructive) { eraseAll() }
                        Button("Cancel", role: .cancel) {}
                    }
                }

                // --- Build expiry note
                Section("About Build Expiry") {
                    Text("Install via Xcode with a paid Developer account to minimize expiry (typically annual). Rebuild when provisioning expires.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func eraseAll() {
        // Delete SwiftData models
        if let days = try? context.fetch(FetchDescriptor<DayEntry>()) {
            days.forEach { context.delete($0) }
        }
        if let ps = try? context.fetch(FetchDescriptor<WorkoutPreset>()) {
            ps.forEach { context.delete($0) }
        }
        if let st = try? context.fetch(FetchDescriptor<ChallengeState>()) {
            st.forEach { context.delete($0) }
        }
        try? context.save()

        // Delete photos directory
        try? FileManager.default.removeItem(at: photosDir())
    }
}

// Simple share wrapper (unchanged)
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
