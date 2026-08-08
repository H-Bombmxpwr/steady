import Foundation
import SwiftData

/// One logged period. Everything about cycle tracking lives in this store,
/// on this device — it is never sent anywhere, never written to Apple Health
/// unless you ask, and never included in anything the AI estimator sees.
@Model
final class CycleEntry {
    /// Day 1 — the first day of real flow.
    var startDate: Date
    /// Last day of flow. `nil` while a period is still in progress.
    var endDate: Date?
    var flowRaw: String = CycleFlow.medium.rawValue
    var symptoms: [String] = []
    var notes: String?
    var createdAt: Date = Date()

    init(startDate: Date, endDate: Date? = nil, flow: CycleFlow = .medium) {
        self.startDate = Calendar.current.startOfDay(for: startDate)
        self.endDate = endDate.map { Calendar.current.startOfDay(for: $0) }
        self.flowRaw = flow.rawValue
        self.createdAt = Date()
    }

    var flow: CycleFlow {
        get { CycleFlow(rawValue: flowRaw) ?? .medium }
        set { flowRaw = newValue.rawValue }
    }

    var isOngoing: Bool { endDate == nil }

    /// Length of the bleed in days, once it's finished.
    var periodLength: Int? {
        endDate.map { startDate.days(to: $0) + 1 }
    }
}

enum CycleFlow: String, Codable, CaseIterable, Identifiable {
    case spotting, light, medium, heavy

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// The symptoms worth offering as taps. Deliberately short — a long checklist
/// stops getting filled in by week two.
enum CycleSymptom {
    static let all = ["Cramps", "Headache", "Bloating", "Fatigue", "Low mood",
                      "Cravings", "Poor sleep", "Sore breasts", "Back pain"]
}

// MARK: - Phases

enum CyclePhase: String, CaseIterable, Identifiable {
    case menstrual, follicular, ovulatory, luteal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .menstrual: return "Menstrual"
        case .follicular: return "Follicular"
        case .ovulatory: return "Ovulatory"
        case .luteal: return "Luteal"
        }
    }

    var icon: String {
        switch self {
        case .menstrual: return "drop.fill"
        case .follicular: return "leaf.fill"
        case .ovulatory: return "sparkles"
        case .luteal: return "moon.fill"
        }
    }

    /// What tends to be true in this phase — hedged on purpose. The research
    /// on cycle phase and performance is genuinely mixed, and individual
    /// variation dwarfs the average effect. This is context for reading your
    /// own data, not a prescription.
    var note: String {
        switch self {
        case .menstrual:
            return "Iron losses are real this week — keep red meat, beans, or lentils in the rotation. Train as you feel; plenty of personal bests happen on day 2."
        case .follicular:
            return "Rising oestrogen, generally good tolerance for hard work. A reasonable window to put the harder sessions if you get to choose."
        case .ovulatory:
            return "Peak oestrogen. Some people notice joints feeling looser — worth a longer warm-up before anything explosive."
        case .luteal:
            return "Core temperature runs a touch higher, so hot sessions feel harder and you'll sweat sooner. Appetite and fluid retention often rise — a scale jump this week is usually water, not fat."
        }
    }

    /// The one-line version for a dashboard card.
    var shortNote: String {
        switch self {
        case .menstrual: return "Iron matters this week. Train as you feel."
        case .follicular: return "Good window for the harder sessions."
        case .ovulatory: return "Warm up thoroughly before anything explosive."
        case .luteal: return "Scale jumps this week are usually water."
        }
    }

    /// Heat tolerance drops slightly in the luteal phase — the one place a
    /// phase genuinely earns a nudge to a number rather than just a note.
    var fluidMultiplier: Double { self == .luteal ? 1.05 : 1.0 }
}

/// Where today sits in the cycle, and what's coming.
struct CycleStatus {
    let phase: CyclePhase
    /// Day of the current cycle, 1-based.
    let dayOfCycle: Int
    let cycleLength: Int
    let predictedNextStart: Date?
    /// Whether the numbers come from enough history to mean anything, or are
    /// still leaning on the 28-day default.
    let isEstimate: Bool
    let loggedCycles: Int

    var daysUntilNext: Int? {
        predictedNextStart.map { Calendar.current.startOfDay(for: Date()).days(to: $0) }
    }
}

enum CycleEngine {
    static let defaultCycleLength = 28
    static let defaultPeriodLength = 5

    /// Average cycle length from logged starts, ignoring gaps that are clearly
    /// a missed log rather than a real cycle (under 21 or over 45 days).
    static func averageCycleLength(_ entries: [CycleEntry]) -> (length: Int, samples: Int) {
        let starts = entries.map(\.startDate).sorted()
        guard starts.count >= 2 else { return (defaultCycleLength, 0) }

        let gaps = zip(starts, starts.dropFirst())
            .map { $0.days(to: $1) }
            .filter { $0 >= 21 && $0 <= 45 }
        guard !gaps.isEmpty else { return (defaultCycleLength, 0) }

        // Recent cycles describe the current body better than year-old ones.
        let recent = Array(gaps.suffix(6))
        let mean = Double(recent.reduce(0, +)) / Double(recent.count)
        return (Int(mean.rounded()), recent.count)
    }

    static func averagePeriodLength(_ entries: [CycleEntry]) -> Int {
        let lengths = entries.compactMap(\.periodLength).filter { $0 >= 1 && $0 <= 12 }
        guard !lengths.isEmpty else { return defaultPeriodLength }
        return Int((Double(lengths.reduce(0, +)) / Double(lengths.count)).rounded())
    }

    /// Where `date` falls. Returns nil until there's at least one logged
    /// period — guessing a phase with no data would be theatre.
    static func status(entries: [CycleEntry], on date: Date = Date()) -> CycleStatus? {
        let day = Calendar.current.startOfDay(for: date)
        let sorted = entries.sorted { $0.startDate < $1.startDate }
        guard let current = sorted.last(where: { $0.startDate <= day }) else { return nil }

        let (cycleLength, samples) = averageCycleLength(sorted)
        let periodLength = current.periodLength ?? averagePeriodLength(sorted)
        let dayOfCycle = current.startDate.days(to: day) + 1

        // Ovulation lands about 14 days before the next period, which makes
        // the luteal phase the stable one and the follicular phase absorb
        // cycle-length variation. That's the direction the biology runs.
        let ovulationDay = max(periodLength + 1, cycleLength - 14)
        let phase: CyclePhase
        switch dayOfCycle {
        case ..<1:                              phase = .menstrual
        case 1...periodLength:                  phase = .menstrual
        case (periodLength + 1)..<(ovulationDay - 1): phase = .follicular
        case (ovulationDay - 1)...(ovulationDay + 1): phase = .ovulatory
        default:                                phase = .luteal
        }

        let next = Calendar.current.date(byAdding: .day, value: cycleLength, to: current.startDate)

        return CycleStatus(phase: phase,
                           dayOfCycle: max(1, dayOfCycle),
                           cycleLength: cycleLength,
                           predictedNextStart: next,
                           isEstimate: samples < 2,
                           loggedCycles: sorted.count)
    }
}
