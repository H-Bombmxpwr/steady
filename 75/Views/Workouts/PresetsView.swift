
import SwiftUI
import SwiftData

/// Weekly workout schedule + reusable presets + calendar sync.
struct WorkoutsView: View {
    @Environment(\.modelContext) private var context
    var plan: Plan

    // New schedule entry
    @State private var newWeekday = 2 // Monday
    @State private var newName = ""
    @State private var newMinutes = 45
    @State private var newTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0))!

    // New preset
    @State private var presetName = ""
    @State private var presetMinutes = 45
    @State private var presetOutdoor = false

    // Calendar sync feedback
    @State private var syncMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                // --- Weekly schedule
                Section {
                    if plan.schedule.isEmpty {
                        Text("No workouts scheduled yet.").foregroundStyle(.secondary)
                    }
                    ForEach(plan.schedule.sorted(by: { ($0.weekday, $0.hour) < ($1.weekday, $1.hour) })) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(entry.weekdayName) — \(entry.name)")
                                Text("\(entry.minutes) min at \(entry.timeString)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if entry.calendarEventID != nil {
                                Image(systemName: "calendar.badge.checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .onDelete(perform: deleteScheduleEntries)
                } header: {
                    Text("Weekly Schedule")
                } footer: {
                    Text("Workouts only count against your daily goals on scheduled days — everything else is a rest day.")
                }

                Section("Add to Schedule") {
                    Picker("Day", selection: $newWeekday) {
                        ForEach(1...7, id: \.self) { d in
                            Text(Calendar.current.weekdaySymbols[d - 1]).tag(d)
                        }
                    }
                    TextField("Workout (e.g., Upper body, Run)", text: $newName)
                    Stepper("Minutes: \(newMinutes)", value: $newMinutes, in: 5...300, step: 5)
                    DatePicker("Time", selection: $newTime, displayedComponents: .hourAndMinute)
                    Button("Add") {
                        let comps = Calendar.current.dateComponents([.hour, .minute], from: newTime)
                        plan.schedule.append(WorkoutScheduleEntry(
                            weekday: newWeekday,
                            name: newName.trimmingCharacters(in: .whitespacesAndNewlines),
                            minutes: newMinutes,
                            hour: comps.hour ?? 7,
                            minute: comps.minute ?? 0))
                        try? context.save()
                        NotificationManager.rescheduleAll(plan: plan)
                        newName = ""
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                // --- Calendar sync (local via EventKit — no server involved)
                Section {
                    Button {
                        Task { await syncCalendar() }
                    } label: {
                        Label("Sync Schedule to Calendar", systemImage: "calendar.badge.plus")
                    }
                    .disabled(plan.schedule.isEmpty)
                    if plan.schedule.contains(where: { $0.calendarEventID != nil }) {
                        Button(role: .destructive) {
                            Task { await removeCalendar() }
                        } label: {
                            Label("Remove from Calendar", systemImage: "calendar.badge.minus")
                        }
                    }
                    if let msg = syncMessage {
                        Text(msg).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Calendar")
                } footer: {
                    Text("Adds each scheduled workout to your iPhone calendar as a weekly repeating event. Stored locally in your calendar; re-run after changing the schedule.")
                }

                // --- Presets
                Section("New Preset") {
                    TextField("Name (e.g., Chest Day)", text: $presetName)
                    Stepper("Default minutes: \(presetMinutes)", value: $presetMinutes, in: 5...180, step: 5)
                    Toggle("Outdoors", isOn: $presetOutdoor)
                    Button("Add Preset") {
                        let p = WorkoutPreset(name: presetName, defaultMinutes: presetMinutes, outdoor: presetOutdoor)
                        plan.presets.append(p)
                        try? context.save()
                        presetName = ""; presetMinutes = 45; presetOutdoor = false
                    }.disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("Presets") {
                    if plan.presets.isEmpty { Text("No presets yet.").foregroundStyle(.secondary) }
                    ForEach(plan.presets) { p in
                        VStack(alignment: .leading) {
                            Text(p.name).font(.headline)
                            HStack { Text("\(p.defaultMinutes) min"); if p.outdoor { Text("outdoor") } }
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { idx in
                        idx.map { plan.presets[$0] }.forEach { context.delete($0) }
                        try? context.save()
                    }
                }
            }
            .themedForm()
            .navigationTitle("Workouts")
        }
    }

    private func deleteScheduleEntries(_ idx: IndexSet) {
        let sorted = plan.schedule.sorted(by: { ($0.weekday, $0.hour) < ($1.weekday, $1.hour) })
        idx.map { sorted[$0] }.forEach { context.delete($0) }
        try? context.save()
        NotificationManager.rescheduleAll(plan: plan)
    }

    private func syncCalendar() async {
        do {
            let count = try await CalendarSync.sync(plan: plan)
            try? context.save()
            syncMessage = "Added \(count) weekly event\(count == 1 ? "" : "s") to your calendar."
        } catch {
            syncMessage = error.localizedDescription
        }
    }

    private func removeCalendar() async {
        do {
            try await CalendarSync.removeFromCalendar(plan: plan)
            try? context.save()
            syncMessage = "Removed synced events."
        } catch {
            syncMessage = error.localizedDescription
        }
    }
}
