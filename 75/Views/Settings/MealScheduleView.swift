import SwiftUI
import SwiftData

/// The shape of a normal day: which meals happen, when, and roughly how big.
///
/// Three meals with dinner as the largest is the default because it's what
/// most people do. The reason it's editable at all is that plenty of people
/// don't — shift workers, people who train at five in the morning, and
/// anyone whose carb target is high enough that three sittings genuinely
/// can't hold it. Sizes are relative rather than percentages, so switching a
/// snack on doesn't require re-balancing everything else.
struct MealScheduleView: View {
    @Environment(\.modelContext) private var context
    var plan: Plan

    @State private var slots: [MealSlot] = []

    var body: some View {
        Form {
            Section {
                ForEach(slots) { slot in
                    MealSlotRow(slot: slot) { save() }
                }
            } header: {
                Text("Meals")
            } footer: {
                Text("Switch a meal off and it disappears from the plan; its food is shared out across the rest. The size dial is relative — a lunch set to \"Large\" next to two \"Regular\" meals just means lunch gets more, not that it hits a particular number.")
            }

            Section {
                Button {
                    Haptics.tap()
                    resetToDefaults()
                } label: {
                    Label("Reset to the standard day", systemImage: "arrow.uturn.backward")
                }
            } footer: {
                Text("Breakfast, lunch, and dinner, with snacks off.")
            }
        }
        .themedForm()
        .navigationTitle("Meal Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { slots = plan.ensureMealSchedule() }
    }

    private func save() {
        try? context.save()
    }

    private func resetToDefaults() {
        slots.forEach { context.delete($0) }
        plan.mealSlots.removeAll()
        slots = plan.ensureMealSchedule()
    }
}

/// One row: on/off, time, name, and how big it usually is.
private struct MealSlotRow: View {
    @Bindable var slot: MealSlot
    let onChange: () -> Void

    @State private var time: Date = Date()

    /// Relative sizes, worded rather than numbered — nobody knows what 1.4
    /// means, and everybody knows what "my biggest meal" means.
    private static let sizes: [(label: String, share: Double)] = [
        ("Small", 0.4), ("Light", 0.7), ("Regular", 1.0),
        ("Large", 1.4), ("Biggest", 1.8)
    ]

    private var sizeIndex: Int {
        let best = Self.sizes.enumerated().min {
            abs($0.element.share - slot.share) < abs($1.element.share - slot.share)
        }
        return best?.offset ?? 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { slot.enabled },
                set: { slot.enabled = $0; Haptics.tap(); onChange() }
            )) {
                Label(slot.label, systemImage: slot.meal.icon)
                    .foregroundStyle(slot.enabled ? .primary : .secondary)
            }

            if slot.enabled {
                DatePicker("Time", selection: Binding(
                    get: { time },
                    set: { newValue in
                        time = newValue
                        let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                        slot.hour = c.hour ?? slot.hour
                        slot.minute = c.minute ?? 0
                        onChange()
                    }
                ), displayedComponents: .hourAndMinute)
                .font(.subheadline)

                Picker("Size", selection: Binding(
                    get: { sizeIndex },
                    set: { slot.share = Self.sizes[$0].share; Haptics.selection(); onChange() }
                )) {
                    ForEach(Array(Self.sizes.enumerated()), id: \.offset) { index, size in
                        Text(size.label).tag(index)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.vertical, 2)
        .onAppear {
            let comps = DateComponents(hour: slot.hour, minute: slot.minute)
            time = Calendar.current.date(from: comps) ?? Date()
        }
    }
}
