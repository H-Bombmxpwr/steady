import SwiftUI
import SwiftData
import WidgetKit

/// The weigh-in, on its own: one number, one button. Opened from the home
/// screen widget's Weight door so stepping off the scale and logging it is a
/// single tap away.
struct QuickWeightView: View {
    let plan: Plan
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var value: Double? {
        Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }
    private var valid: Bool { (value ?? 0) > 50 && (value ?? 0) < 800 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Sprite(BuddyStore.shared.state.species.asset, size: 64)
                Text("\(BuddyStore.shared.state.name) is by the scale")
                    .font(.headline)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    TextField("0.0", text: $text)
                        .keyboardType(.decimalPad)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .frame(maxWidth: 180)
                    Text("lb").foregroundStyle(Theme.textDim)
                }
                Text("Only the trend pays out, so a heavy morning costs nothing. Weighing in is +\(Int(IdleEngine.minutes(for: .weighIn))) minutes of studio output.")
                    .font(.caption)
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                Button("Log weight", action: save)
                    .buttonStyle(.primaryAction)
                    .disabled(!valid)
            }
            .padding()
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } } }
            .onAppear {
                if let today = ensureDay(plan: plan, date: Date()).weight {
                    text = String(format: "%.1f", today)
                }
                focused = true
            }
        }
    }

    private func save() {
        guard let value, valid else { return }
        let day = ensureDay(plan: plan, date: Date())
        day.weight = (value * 10).rounded() / 10
        try? context.save()
        WidgetSnapshot.refreshTotals(from: day)
        Haptics.success()
        dismiss()
    }
}
