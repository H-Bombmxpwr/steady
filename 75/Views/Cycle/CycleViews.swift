import SwiftUI
import SwiftData

// MARK: - Dashboard card

/// Cycle status on the dashboard, behind the same Face ID / PIN gate as the
/// progress photos.
///
/// The locked state deliberately says nothing except that something is here —
/// a card reading "Day 3 · Menstrual" over the lock would defeat the point of
/// locking it.
struct CycleCard: View {
    @EnvironmentObject private var appLock: AppLockManager
    let plan: Plan

    private var status: CycleStatus? { CycleEngine.status(entries: plan.cycles) }

    var body: some View {
        Card(title: "Cycle", icon: "drop.fill", tint: Theme.photoTint) {
            if appLock.isUnlocked(.cycle) {
                unlockedContent
            } else {
                lockedContent
            }
        }
    }

    @ViewBuilder
    private var lockedContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title3)
                .foregroundStyle(Theme.textDim)
            Text("Locked")
                .font(.subheadline)
                .foregroundStyle(Theme.textDim)
            Spacer()
            Button {
                appLock.unlock(.cycle)
            } label: {
                Label("Unlock", systemImage: "faceid")
                    .font(.caption.bold())
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
        }
    }

    @ViewBuilder
    private var unlockedContent: some View {
        if let status {
            NavigationLink {
                CycleLogView(plan: plan)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: status.phase.icon)
                            .foregroundStyle(Theme.photoTint)
                        Text(status.phase.label)
                            .font(.system(.title3, design: .rounded).bold())
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text("Day \(status.dayOfCycle)")
                                .font(.subheadline.weight(.semibold))
                            if let days = status.daysUntilNext, days >= 0 {
                                Text(days == 0 ? "due today" : "next in \(days)d")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textDim)
                            }
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(Theme.textDim)
                    }
                    Text(status.phase.shortNote)
                        .font(.footnote)
                        .foregroundStyle(Theme.textDim)
                    if status.isEstimate {
                        Text("Based on a 28-day default — a couple more logged cycles and this gets personal.")
                            .font(.caption2)
                            .foregroundStyle(Theme.textDim)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                CycleLogView(plan: plan)
            } label: {
                HStack {
                    Text("Log a period to start tracking phases.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textDim)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2).foregroundStyle(Theme.textDim)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Log

/// The full cycle log: current status, history, and logging. Locked as a
/// whole — reaching it through a deep link or a stale navigation stack still
/// hits the gate.
struct CycleLogView: View {
    @EnvironmentObject private var appLock: AppLockManager
    @Environment(\.modelContext) private var context
    let plan: Plan

    @State private var showAdd = false
    @State private var editing: CycleEntry?

    private var entries: [CycleEntry] {
        plan.cycles.sorted { $0.startDate > $1.startDate }
    }
    private var status: CycleStatus? { CycleEngine.status(entries: plan.cycles) }

    var body: some View {
        Group {
            if appLock.isUnlocked(.cycle) {
                form
            } else {
                LockGate(area: .cycle)
                    .frame(maxHeight: .infinity)
                    .brandBackground()
            }
        }
        .navigationTitle("Cycle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if appLock.isUnlocked(.cycle) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            CycleEntrySheet(plan: plan, entry: nil)
        }
        .sheet(item: $editing) { entry in
            CycleEntrySheet(plan: plan, entry: entry)
        }
    }

    private var form: some View {
        Form {
            if let status {
                Section {
                    HStack(spacing: 12) {
                        SectionIcon(systemImage: status.phase.icon, size: 34, tint: Theme.photoTint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status.phase.label).font(.headline)
                            Text("Day \(status.dayOfCycle) of a \(status.cycleLength)-day cycle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    Text(status.phase.note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let next = status.predictedNextStart {
                        HStack {
                            Text("Next period")
                            Spacer()
                            Text(next.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    SectionHeader(icon: "calendar", title: "Right now", tint: Theme.photoTint)
                } footer: {
                    Text(status.isEstimate
                         ? "Predictions use a 28-day default until there are two or three logged cycles to learn from."
                         : "Learned from your last \(min(6, max(1, status.loggedCycles - 1))) cycles. Predictions are estimates — bodies aren't calendars.")
                }
            }

            if let ongoing = entries.first(where: \.isOngoing) {
                Section {
                    Button {
                        ongoing.endDate = Calendar.current.startOfDay(for: Date())
                        try? context.save()
                        Haptics.success()
                    } label: {
                        Label("End period today", systemImage: "checkmark.circle")
                    }
                } footer: {
                    Text("Started \(ongoing.startDate.formatted(.dateTime.month(.abbreviated).day())) and still open.")
                }
            }

            Section {
                Button {
                    showAdd = true
                } label: {
                    Label("Log a period", systemImage: "plus.circle.fill")
                }
                if entries.isEmpty {
                    Text("Nothing logged yet. Add the first day of your last period and phases start showing up.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !entries.isEmpty {
                Section {
                    ForEach(entries) { entry in
                        Button { editing = entry } label: { row(entry) }
                            .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                } header: {
                    SectionHeader(icon: "list.bullet", title: "History", tint: Theme.photoTint)
                }
            }

            Section {
                Label("Stored only on this device", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Cycle data never leaves this phone, never goes to Apple Health, and is never part of anything sent for a nutrition estimate. It's locked behind Face ID with the rest of your private data, and you can switch tracking off — and erase all of it — in Settings.")
            }
        }
        .themedForm()
    }

    private func row(_ entry: CycleEntry) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.startDate.formatted(.dateTime.month(.abbreviated).day().year()))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(entry.flow.label)
                    if let length = entry.periodLength {
                        Text("· \(length) day\(length == 1 ? "" : "s")")
                    } else {
                        Text("· ongoing")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if !entry.symptoms.isEmpty {
                Text(entry.symptoms.count == 1 ? entry.symptoms[0] : "\(entry.symptoms.count) symptoms")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func delete(_ offsets: IndexSet) {
        let doomed = offsets.map { entries[$0] }
        let ids = Set(doomed.map(\.persistentModelID))
        plan.cycles.removeAll { ids.contains($0.persistentModelID) }
        doomed.forEach { context.delete($0) }
        try? context.save()
    }
}

// MARK: - Entry sheet

struct CycleEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let plan: Plan
    /// nil = logging a new period.
    let entry: CycleEntry?

    @State private var startDate = Date()
    @State private var hasEnded = false
    @State private var endDate = Date()
    @State private var flow: CycleFlow = .medium
    @State private var symptoms: Set<String> = []
    @State private var notes = ""

    private var isValid: Bool { !hasEnded || endDate >= startDate }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("First day", selection: $startDate,
                               in: ...Date(), displayedComponents: .date)
                    Toggle("It's finished", isOn: $hasEnded.animation())
                    if hasEnded {
                        DatePicker("Last day", selection: $endDate,
                                   in: startDate...Date(), displayedComponents: .date)
                    }
                } footer: {
                    if !isValid {
                        Text("The last day can't come before the first.")
                            .foregroundStyle(Theme.danger)
                    } else if !hasEnded {
                        Text("Leave this off while it's still going — you can close it out later from the cycle log.")
                    }
                }

                Section("Flow") {
                    Picker("Flow", selection: $flow) {
                        ForEach(CycleFlow.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section("Symptoms") {
                    FlowChips(options: CycleSymptom.all, selection: $symptoms)
                }

                Section("Notes") {
                    TextField("Anything worth remembering", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if entry != nil {
                    Section {
                        Button(role: .destructive) { deleteEntry() } label: {
                            Label("Delete this entry", systemImage: "trash")
                        }
                    }
                }
            }
            .themedForm()
            .navigationTitle(entry == nil ? "Log a Period" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
        }
        .themedRoot()
        .onAppear(perform: load)
    }

    private func load() {
        guard let entry else { return }
        startDate = entry.startDate
        if let end = entry.endDate {
            hasEnded = true
            endDate = end
        }
        flow = entry.flow
        symptoms = Set(entry.symptoms)
        notes = entry.notes ?? ""
    }

    private func save() {
        let target = entry ?? {
            let new = CycleEntry(startDate: startDate)
            plan.cycles.append(new)
            return new
        }()
        target.startDate = Calendar.current.startOfDay(for: startDate)
        target.endDate = hasEnded ? Calendar.current.startOfDay(for: endDate) : nil
        target.flow = flow
        target.symptoms = symptoms.sorted()
        target.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : notes
        try? context.save()
        Haptics.success()
        dismiss()
    }

    private func deleteEntry() {
        guard let entry else { return }
        plan.cycles.removeAll { $0.persistentModelID == entry.persistentModelID }
        context.delete(entry)
        try? context.save()
        dismiss()
    }
}

// MARK: - Chips

/// Wrapping multi-select chips — used for symptoms.
struct FlowChips: View {
    let options: [String]
    @Binding var selection: Set<String>

    var body: some View {
        FlexibleHStack(options, spacing: 8) { option in
            let on = selection.contains(option)
            Button {
                if on { selection.remove(option) } else { selection.insert(option) }
                Haptics.selection()
            } label: {
                Text(option)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(on ? Theme.accent.opacity(0.25) : Theme.surface2))
                    .foregroundStyle(on ? Theme.accent : .secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

/// A minimal wrapping layout, so chips flow onto as many lines as they need.
struct FlexibleHStack<Data: RandomAccessCollection, Content: View>: View
where Data.Element: Hashable {
    let data: Data
    let spacing: CGFloat
    let content: (Data.Element) -> Content

    init(_ data: Data, spacing: CGFloat = 8,
         @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        ChipLayout(spacing: spacing) {
            ForEach(Array(data), id: \.self) { content($0) }
        }
    }
}

private struct ChipLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? x, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
