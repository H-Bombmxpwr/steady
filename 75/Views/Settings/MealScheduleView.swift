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

    /// Read straight off the plan rather than into a `@State` snapshot taken
    /// on appear: the snapshot held the same objects, so edits did land, but
    /// nothing about the array ever changed and anything watching this screen
    /// for "the schedule moved" had no way to notice.
    ///
    /// Sorted by the meal's own position in the day, not by its clock time,
    /// so moving breakfast to the evening doesn't make the row you're editing
    /// jump to the bottom of the list under your thumb.
    private var slots: [MealSlot] {
        plan.mealSlots.sorted { ($0.orderIndex, $0.minutesOfDay) < ($1.orderIndex, $1.minutesOfDay) }
    }

    var body: some View {
        Form {
            // One section per meal. The controls for a meal used to be stacked
            // inside a single row, which left the toggle sharing its hit area
            // with a date picker and a segmented control — tapping it was a
            // coin flip. A section per meal gives each control its own row and
            // its own touch target, which is the whole reason Form has rows.
            ForEach(slots) { slot in
                Section {
                    MealSlotRows(slot: slot) { save() }
                } header: {
                    Text(slot.label)
                }
            }

            Section {
                Button {
                    Haptics.tap()
                    resetToDefaults()
                } label: {
                    Label("Reset to the standard day", systemImage: "arrow.uturn.backward")
                }
            } header: {
                Text("Start Over")
            } footer: {
                Text("Breakfast, lunch, and dinner, with snacks off. Switch a meal off and it disappears from the plan; its food is shared out across the rest. The size dial is relative — a lunch set to \"Large\" next to two \"Regular\" meals just means lunch gets more, not that it hits a particular number.")
            }
        }
        .themedForm()
        .navigationTitle("Meal Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { plan.ensureMealSchedule() }
    }

    private func save() {
        try? context.save()
    }

    private func resetToDefaults() {
        // Out of the relationship first, then out of the store. Deleting a
        // child while the parent still holds it leaves the plan handing out a
        // slot that no longer exists.
        let old = plan.mealSlots
        plan.mealSlots.removeAll()
        old.forEach { context.delete($0) }
        plan.ensureMealSchedule()
        save()
    }
}

/// One meal's rows: on/off, time, and how big it usually is.
private struct MealSlotRows: View {
    @Bindable var slot: MealSlot
    let onChange: () -> Void

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

    /// Derived from the slot on every pass rather than mirrored into `@State`.
    /// A mirror only syncs when the row appears, so a row that got reused for
    /// a different meal showed the wrong time until you left and came back.
    private var time: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: slot.hour, minute: slot.minute,
                                      second: 0, of: Date()) ?? Date()
            },
            set: { newValue in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                slot.hour = c.hour ?? slot.hour
                slot.minute = c.minute ?? 0
                onChange()
            }
        )
    }

    var body: some View {
        // `$slot.enabled` rather than a hand-rolled get/set pair: the binding
        // the @Bindable macro generates is the one SwiftUI's observation
        // actually tracks through, so the row redraws the moment it flips.
        Toggle(isOn: $slot.enabled) {
            Label(slot.enabled ? "On" : "Off", systemImage: slot.meal.icon)
                .foregroundStyle(slot.enabled ? .primary : .secondary)
        }
        .onChange(of: slot.enabled) { _, _ in
            Haptics.tap()
            onChange()
        }

        if slot.enabled {
            // The compact picker, not `.datePickerStyle(.wheel)`.
            //
            // An inline wheel is a scroll view of its own, and it wins every
            // vertical drag that starts anywhere inside it. With one per meal
            // the form was almost entirely covered in them: dragging up the
            // page just spun whichever meal's clock you happened to touch,
            // and the only way to actually scroll was the narrow strip of
            // margin down the side. Tapping this opens the same wheel in a
            // popover, where it's the only thing that can claim the gesture.
            DatePicker("Time", selection: time, displayedComponents: .hourAndMinute)

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
}
