import SwiftUI
import SwiftData

/// "Today isn't a normal day."
///
/// Most days follow the schedule, and this screen never opens. The ones that
/// don't tend to go wrong in three specific ways — the day started late, one
/// meal is the whole point of it, or a meal just didn't happen — and each of
/// those has a right answer that isn't "eat the same amount anyway." Setting
/// them here re-plans everything still ahead.
struct DayShapeSheet: View {
    @Environment(\.dismiss) private var dismiss
    var plan: Plan
    var day: DayLog

    @State private var lateStart: Bool
    @State private var wakeTime: Date

    init(plan: Plan, day: DayLog) {
        self.plan = plan
        self.day = day
        let minutes = day.wakeMinutesOfDay
        _lateStart = State(initialValue: minutes != nil)
        let comps = DateComponents(hour: (minutes ?? 7 * 60) / 60, minute: (minutes ?? 0) % 60)
        _wakeTime = State(initialValue: Calendar.current.date(from: comps) ?? Date())
    }

    private var slots: [MealSlot] { plan.activeMealSlots }

    var body: some View {
        NavigationStack {
            Form {
                // --- A late start
                Section {
                    Toggle("The day started late", isOn: $lateStart.animation())
                    if lateStart {
                        DatePicker("Up at", selection: $wakeTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("When today began")
                } footer: {
                    Text("Meals before this time come out of the plan entirely — they aren't meals you skipped, they're meals that were never going to happen. Their food gets spread across the hours you've actually got, rather than sitting there as a deficit you're supposed to make up.")
                }

                // --- The meal you're planning around
                Section {
                    ForEach(slots) { slot in
                        Button {
                            Haptics.selection()
                            day.setBigMeal(day.bigMeal == slot.meal ? nil : slot.meal)
                        } label: {
                            HStack {
                                Label(slot.label, systemImage: slot.meal.icon)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(slot.timeString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if day.bigMeal == slot.meal {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                    }
                } header: {
                    Text("Planning around a big meal")
                } footer: {
                    Text("A dinner out doesn't blow the day — it just means the meals around it should be smaller. Pick one and everything else shrinks to make room. Tap it again to clear it.")
                }

                // --- Skipped meals
                Section {
                    ForEach(slots) { slot in
                        Toggle(isOn: Binding(
                            get: { day.isSkipped(slot.meal) },
                            set: { day.setSkipped(slot.meal, $0); Haptics.tap() }
                        )) {
                            HStack {
                                Label(slot.label, systemImage: slot.meal.icon)
                                Spacer()
                                Text(slot.timeString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Skipped today")
                } footer: {
                    Text("Marking a meal skipped hands its calories and macros to the meals still ahead of you. If it genuinely won't fit in what's left, the plan says so instead of printing a dinner nobody could eat.")
                }

                if day.hasDayShapeChanges {
                    Section {
                        Button(role: .destructive) {
                            Haptics.tap()
                            lateStart = false
                            day.resetDayShape()
                        } label: {
                            Label("Back to the normal day", systemImage: "arrow.uturn.backward")
                        }
                    }
                }

                Section {
                    NavigationLink {
                        MealScheduleView(plan: plan)
                    } label: {
                        Label("Edit my usual meal times", systemImage: "clock")
                    }
                } footer: {
                    Text("Changing the schedule changes every day. Everything above is just today.")
                }
            }
            .themedForm()
            .navigationTitle("Adjust Today")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: lateStart) { _, on in
                applyWake(enabled: on, time: wakeTime)
            }
            .onChange(of: wakeTime) { _, time in
                applyWake(enabled: lateStart, time: time)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func applyWake(enabled: Bool, time: Date) {
        guard enabled else {
            day.setWake(hour: nil, minute: nil)
            return
        }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: time)
        day.setWake(hour: comps.hour, minute: comps.minute)
    }
}
