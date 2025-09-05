import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @State private var startDate = Date()
    @State private var dietName = ""
    @State private var dietDescription = ""
    @State private var startingWeightText = ""   // free text, convert to Double later

    // Focus for dismissing keyboards
    @FocusState private var descFocused: Bool
    @FocusState private var startWeightFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Start") {
                    DatePicker("Challenge Start Date",
                               selection: $startDate,
                               in: ...Date(),                       // no future starts
                               displayedComponents: .date)
                }

                Section("Starting Weight (optional)") {
                    TextField("Weight (lb)", text: $startingWeightText)
                        .keyboardType(.decimalPad)
                        .focused($startWeightFocused)
                }

                Section("Diet Plan") {
                    TextField("Diet name (e.g., Keto, Paleo)", text: $dietName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description / rules")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $dietDescription)
                            .frame(minHeight: 120)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                            .focused($descFocused)
                    }
                }

                Section(footer: Text("Diet name and description lock after setup. Use Reset to start over.")) {
                    Button("Create Challenge") {
                        let startW = Double(startingWeightText.trimmingCharacters(in: .whitespaces))
                        let s = ChallengeState(
                            startDate: startDate,
                            dietName: dietName.trimmingCharacters(in: .whitespacesAndNewlines),
                            dietDescription: dietDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                            startingWeight: startW
                        )
                        // preseed 75 days
                        for i in 0..<s.totalDays {
                            let d = Calendar.current.date(byAdding: .day, value: i, to: s.startDate)!
                            s.days.append(DayEntry(date: d))
                        }
                        context.insert(s)
                        try? context.save()
                    }
                    .disabled(dietName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              dietDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("75 Hard Setup")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        // Dismiss whichever input is active
                        descFocused = false
                        startWeightFocused = false
                    }
                }
            }
        }
    }
}
