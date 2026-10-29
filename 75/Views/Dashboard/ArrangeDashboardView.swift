import SwiftUI

/// The dashboard's cards below the buddy, which the user can put in any
/// order. The buddy stays on top: it's the dashboard's voice.
enum DashboardCard: String, CaseIterable, Identifiable {
    case weight, tour, today, fuel, cycle, health, fasting, streak, milestones, insight

    static let orderKey = "dashboard.cardOrder"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: return "Weight"
        case .tour: return "Tour"
        case .today: return "Today"
        case .fuel: return "Fueling"
        case .cycle: return "Cycle"
        case .health: return "General health"
        case .fasting: return "Fasting"
        case .streak: return "Streak & projection"
        case .milestones: return "Milestones"
        case .insight: return "Weekly insight"
        }
    }

    var icon: String {
        switch self {
        case .weight: return "scalemass"
        case .tour: return "music.note.list"
        case .today: return "fork.knife"
        case .fuel: return "bolt.heart"
        case .cycle: return "circle.dotted"
        case .health: return "heart.text.square"
        case .fasting: return "timer"
        case .streak: return "flame"
        case .milestones: return "rosette"
        case .insight: return "lightbulb"
        }
    }

    /// Cards that only show up some of the time, and when.
    var note: String? {
        switch self {
        case .fuel: return "On training days"
        case .cycle: return "With cycle tracking on"
        case .health: return "With general health on"
        case .fasting: return "With the fasting timer on"
        default: return nil
        }
    }

    /// The saved order, with any card it doesn't mention (one added in an
    /// update) slotted in at the end rather than lost.
    static func order(from raw: String) -> [DashboardCard] {
        var seen = Set<DashboardCard>()
        let saved = raw.split(separator: ",").compactMap { DashboardCard(rawValue: String($0)) }
            .filter { seen.insert($0).inserted }
        return saved + allCases.filter { !seen.contains($0) }
    }

    static func raw(_ order: [DashboardCard]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }
}

struct ArrangeDashboardView: View {
    @Binding var orderRaw: String
    @Environment(\.dismiss) private var dismiss

    private var order: [DashboardCard] { DashboardCard.order(from: orderRaw) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order) { card in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.title)
                                if let note = card.note {
                                    Text(note).font(.caption).foregroundStyle(Theme.textDim)
                                }
                            }
                        } icon: {
                            Image(systemName: card.icon).foregroundStyle(Theme.accent)
                        }
                    }
                    .onMove { from, to in
                        var cards = order
                        cards.move(fromOffsets: from, toOffset: to)
                        orderRaw = DashboardCard.raw(cards)
                    }
                } footer: {
                    Text("Drag to reorder. Your buddy stays at the top.")
                }

                Section {
                    Button("Reset to default order") { orderRaw = "" }
                        .disabled(orderRaw.isEmpty)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Arrange Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
