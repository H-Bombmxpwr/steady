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

    private var results: [WorkoutPreset] { WorkoutLibrary.sorted(plan.presets, matching: query) }
    private var dupes: Set<String> { WorkoutLibrary.duplicateNames(plan.presets) }

    var body: some View {
        List {
            ForEach(results) { p in
                NavigationLink(value: p) {
                    PresetRow(preset: p, showTimestamp: dupes.contains(p.name.lowercased()))
                }
            }
            .onDelete { idx in
                idx.map { results[$0] }.forEach { context.delete($0) }
                try? context.save()
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
