import SwiftUI
import SwiftData

/// Shared shape for browsing workout presets: alphabetized, searchable,
/// and same-named workouts show when they were built so you can tell
/// them apart. Backs both the Workouts tab library and the Log Workout
/// preset picker.
enum WorkoutLibrary {

    /// Alphabetical (case-insensitive), ties broken oldest-first.
    static func sorted(_ presets: [WorkoutPreset], matching query: String = "") -> [WorkoutPreset] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return presets
            .filter { q.isEmpty || $0.name.lowercased().contains(q)
                      || $0.category.label.lowercased().contains(q) }
            .sorted {
                let l = $0.name.lowercased(), r = $1.name.lowercased()
                return l == r ? $0.createdAt < $1.createdAt : l < r
            }
    }

    /// Names that appear more than once — those rows get a timestamp.
    static func duplicateNames(_ presets: [WorkoutPreset]) -> Set<String> {
        var seen = Set<String>(), dupes = Set<String>()
        for p in presets {
            let key = p.name.lowercased()
            if !seen.insert(key).inserted { dupes.insert(key) }
        }
        return dupes
    }
}

/// One preset row: icon, name, details — created date/time added when
/// another workout shares the name.
struct PresetRow: View {
    let preset: WorkoutPreset
    var showTimestamp = false

    var body: some View {
        HStack {
            Image(systemName: preset.category.icon)
                .foregroundStyle(Theme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name).font(.headline).lineLimit(1)
                HStack(spacing: 0) {
                    Text(preset.category.label)
                    Text(" · \(preset.defaultMinutes) min")
                    if !preset.exercises.isEmpty { Text(" · \(preset.exercises.count) exercises") }
                    if preset.outdoor { Text(" · outdoor") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if showTimestamp {
                    Text("built \(preset.createdAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

/// Workouts tab → All Workouts: the full library, searchable and
/// alphabetized, with swipe-to-delete. Tapping opens the editor.
struct WorkoutLibraryView: View {
    @Environment(\.modelContext) private var context
    var plan: Plan

    @State private var query = ""

    /// Workouts swiped away that still hold weekday slots — held here while
    /// the confirmation is up, because deleting them silently is what left
    /// the schedule talking about a workout that no longer exists.
    @State private var pendingDelete: [WorkoutPreset] = []

    private var results: [WorkoutPreset] { WorkoutLibrary.sorted(plan.presets, matching: query) }
    private var dupes: Set<String> { WorkoutLibrary.duplicateNames(plan.presets) }

    var body: some View {
        List {
            ForEach(results) { p in
                // A direct destination, not `NavigationLink(value:)`.
                //
                // The value form needs a matching `navigationDestination` that
                // is visible from the link, and the one for WorkoutPreset was
                // declared on the Workouts form — which is no longer on screen
                // once this list has been pushed onto the stack. SwiftUI can't
                // resolve the link from here, so the tap pushed a broken
                // screen you had to back out of to see anything.
                NavigationLink {
                    WorkoutDetailView(plan: plan, preset: p)
                } label: {
                    PresetRow(preset: p, showTimestamp: dupes.contains(p.name.lowercased()))
                }
            }
            .onDelete { idx in
                let targets = idx.map { results[$0] }
                // Deleting the workout has to take its weekday slots with it,
                // and that's a bigger deal than deleting a workout nobody
                // scheduled — so say so rather than quietly changing the week.
                if targets.contains(where: { !plan.scheduleEntries(named: $0.name).isEmpty }) {
                    pendingDelete = targets
                } else {
                    delete(targets)
                }
            }
        }
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .themedForm()
        .navigationTitle("All Workouts")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search workouts")
        .confirmationDialog(scheduleWarningTitle,
                            isPresented: Binding(get: { !pendingDelete.isEmpty },
                                                 set: { if !$0 { pendingDelete = [] } }),
                            titleVisibility: .visible) {
            Button("Delete Workout and Schedule", role: .destructive) {
                delete(pendingDelete)
                pendingDelete = []
            }
            Button("Keep", role: .cancel) { pendingDelete = [] }
        } message: {
            Text(scheduleWarningMessage)
        }
    }

    /// "Pickleball is on your week" — named, because the whole point of the
    /// prompt is telling you which days are about to change.
    private var scheduleWarningTitle: String {
        guard let first = pendingDelete.first else { return "On your weekly schedule" }
        return pendingDelete.count == 1
            ? "\(first.name) is on your weekly schedule"
            : "These workouts are on your weekly schedule"
    }

    private var scheduleWarningMessage: String {
        let days = pendingDelete
            .flatMap { plan.scheduleEntries(named: $0.name) }
            .sorted { $0.weekday < $1.weekday }
            .map(\.weekdayName)
        let unique = NSOrderedSet(array: days).array as? [String] ?? days
        let list = ListFormatter.localizedString(byJoining: unique)
        return unique.isEmpty
            ? "Deleting also clears its weekly schedule slots."
            : "Deleting also clears \(list) — otherwise it keeps showing up on those days."
    }

    private func delete(_ presets: [WorkoutPreset]) {
        let entries = presets.flatMap { plan.scheduleEntries(named: $0.name) }
        // Read the calendar identifiers now — the entries are gone by the
        // time the async cleanup gets a turn.
        let eventIDs = entries.compactMap(\.calendarEventID)
        plan.removeScheduleEntries(entries)
        presets.forEach { context.delete($0) }
        try? context.save()
        NotificationManager.rescheduleAll(plan: plan)
        Task { await CalendarSync.removeEvents(ids: eventIDs) }
    }
}

/// Log Workout → preset picker sheet: same alphabetized searchable list,
/// tap one to pre-fill the form.
struct PresetPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var plan: Plan
    let onPick: (WorkoutPreset) -> Void

    @State private var query = ""

    private var results: [WorkoutPreset] { WorkoutLibrary.sorted(plan.presets, matching: query) }
    private var dupes: Set<String> { WorkoutLibrary.duplicateNames(plan.presets) }

    var body: some View {
        NavigationStack {
            List {
                ForEach(results) { p in
                    Button {
                        onPick(p)
                        dismiss()
                    } label: {
                        PresetRow(preset: p, showTimestamp: dupes.contains(p.name.lowercased()))
                    }
                    .buttonStyle(.plain)
                }
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .themedForm()
            .navigationTitle("Choose Workout")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search workouts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .themedRoot()
    }
}
