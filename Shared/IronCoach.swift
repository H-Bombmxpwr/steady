import Foundation

/// Lab-aware coaching for iron — the one deficiency that reliably flattens
/// training and is just as reliably missed.
///
/// Ferritin falls long before hemoglobin does, so an athlete can be told
/// their blood count is "normal" while their stores are empty and every
/// session feels like wading. Clinical anemia cut-offs are the wrong tool
/// here: a lab may flag ferritin only below 15 ng/mL, while the sports
/// literature generally treats anything under ~30 as worth acting on and
/// under ~20 as depleted, because performance and adaptation suffer well
/// before a blood count moves.
///
/// Everything below is local and deterministic — nothing is sent anywhere.
/// The advice is dietary: what to eat, what to eat it with, and what to keep
/// away from it. It is not a diagnosis and it does not recommend supplements,
/// because unnecessary iron supplementation is genuinely harmful and the only
/// way to know is the blood test this reads.
enum IronCoach {

    enum Status: String {
        /// Stores empty or near it — the band where symptoms are expected.
        case depleted
        /// Below where most sports-medicine guidance wants an athlete.
        case low
        /// Fine, but low enough in the range to be worth watching.
        case watch
        /// Comfortably stocked.
        case stocked

        var label: String {
            switch self {
            case .depleted: return "Iron stores depleted"
            case .low: return "Iron stores low"
            case .watch: return "Iron on the low side"
            case .stocked: return "Iron stores look fine"
            }
        }

        /// Does this warrant showing up on the dashboard unprompted?
        var isActionable: Bool { self == .depleted || self == .low || self == .watch }

        /// Should the day plan actively steer meals toward iron?
        var steersMeals: Bool { self == .depleted || self == .low }
    }

    /// What the numbers say, and what to do about it at the table.
    struct Finding {
        let status: Status
        let ferritin: Double?
        let hemoglobin: Double?
        let transferrinSaturation: Double?
        let measuredOn: Date
        /// One line for a card header.
        let headline: String
        /// The reasoning — why these numbers mean this.
        let explanation: String
        /// Concrete things to do, in priority order.
        let actions: [String]
        /// A short note to hang on the meal chosen to carry the iron.
        let mealNote: String
        /// How stale the reading is, when it's old enough to matter.
        let staleness: String?

        var isActionable: Bool { status.isActionable }

        /// The bare numbers for an AI prompt — values only, and only sent
        /// when lab-aware coaching is switched on.
        var promptLine: String {
            var parts: [String] = []
            if let ferritin { parts.append("ferritin \(Int(ferritin)) ng/mL") }
            if let hemoglobin {
                parts.append("hemoglobin \(hemoglobin.formatted(.number.precision(.fractionLength(1)))) g/dL")
            }
            if let transferrinSaturation {
                parts.append("transferrin saturation \(Int(transferrinSaturation))%")
            }
            return parts.joined(separator: ", ")
        }
    }

    /// Ferritin bands, ng/mL. Deliberately above the clinical anemia
    /// threshold — the question here is "is this costing you training?",
    /// not "is this a disease?".
    static let ferritinDepleted = 20.0
    static let ferritinLow = 30.0
    static let ferritinWatch = 50.0

    /// Hemoglobin floors, g/dL, by sex (WHO).
    static func hemoglobinFloor(for sex: BiologicalSex) -> Double {
        switch sex {
        case .male: return 13.5
        case .female: return 12.0
        case .unspecified: return 12.0
        }
    }

    /// Daily dietary iron, mg. The RDA, plus the adjustments that actually
    /// apply to the people using this: plants deliver iron far less
    /// efficiently, and endurance training costs iron through foot-strike
    /// hemolysis, sweat, and gut losses.
    static func dailyIronTargetMg(sex: BiologicalSex, age: Int,
                                  isAthlete: Bool, plantBased: Bool = false) -> Double {
        var base: Double
        switch sex {
        case .female: base = age >= 51 ? 8 : 18
        case .male, .unspecified: base = 8
        }
        // Endurance athletes are commonly counselled ~30–70% above the RDA.
        if isAthlete { base *= 1.5 }
        // Non-heme iron absorbs at roughly a third to a half the rate.
        if plantBased { base *= 1.8 }
        return (base * 10).rounded() / 10
    }

    /// Read a lab panel. Returns nil when it says nothing about iron — no
    /// panel, or a lipid panel with the iron fields left blank.
    static func evaluate(labs: LabResult?, sex: BiologicalSex, now: Date = Date()) -> Finding? {
        guard let labs, labs.hasIronMarkers else { return nil }

        let ferritin = labs.ferritin
        let hemoglobin = labs.hemoglobin
        let sat = labs.transferrinSaturation
        let hgbFloor = hemoglobinFloor(for: sex)

        // Ferritin leads, because it's the marker that moves first.
        var status: Status
        switch ferritin {
        case .some(let f) where f < ferritinDepleted: status = .depleted
        case .some(let f) where f < ferritinLow:      status = .low
        case .some(let f) where f < ferritinWatch:    status = .watch
        case .some:                                   status = .stocked
        case nil:                                     status = .stocked
        }

        // A hemoglobin below the floor outranks a reassuring ferritin: stores
        // can read normal when inflammation props them up while the blood
        // count says otherwise.
        if let hemoglobin, hemoglobin < hgbFloor, status != .depleted {
            status = hemoglobin < hgbFloor - 1.0 ? .depleted : .low
        }
        // Saturation under 20% is the classic supporting sign, and it's the
        // tiebreaker when ferritin looks fine but isn't.
        if let sat, sat < 20, status == .stocked || status == .watch {
            status = .low
        }

        let ageDays = Calendar.current.dateComponents([.day], from: labs.date, to: now).day ?? 0
        let staleness: String?
        switch ageDays {
        case ..<180: staleness = nil
        case ..<400: staleness = "This panel is about \(ageDays / 30) months old — iron moves slowly, but it does move."
        default:     staleness = "This panel is over a year old. Worth a fresh draw before leaning on it."
        }

        return Finding(status: status,
                       ferritin: ferritin,
                       hemoglobin: hemoglobin,
                       transferrinSaturation: sat,
                       measuredOn: labs.date,
                       headline: headline(status, ferritin: ferritin),
                       explanation: explanation(status, ferritin: ferritin,
                                                hemoglobin: hemoglobin, sat: sat,
                                                hgbFloor: hgbFloor),
                       actions: actions(for: status),
                       mealNote: mealNote(for: status),
                       staleness: staleness)
    }

    private static func headline(_ status: Status, ferritin: Double?) -> String {
        guard let ferritin else { return status.label }
        return "\(status.label) — ferritin \(Int(ferritin)) ng/mL"
    }

    private static func explanation(_ status: Status, ferritin: Double?,
                                    hemoglobin: Double?, sat: Double?,
                                    hgbFloor: Double) -> String {
        switch status {
        case .depleted:
            return "Ferritin this low means the tank is empty, not just down. This is the range where sessions feel harder than the numbers say they should, recovery drags, and adaptation stalls — and it usually shows up long before a blood count looks wrong. Food helps, but this is the one to take to a doctor."
        case .low:
            var text = "Most sports-medicine guidance wants an athlete above about 30 ng/mL. Below that, the iron is there to carry oxygen day to day but there's nothing left over for building new red cells, which is exactly what training asks for."
            if let hemoglobin, hemoglobin < hgbFloor {
                text += " Hemoglobin is under \(hgbFloor.formatted()) g/dL too, so it's already showing in the blood count."
            }
            if let sat, sat < 20 {
                text += " Transferrin saturation under 20% points the same way."
            }
            return text
        case .watch:
            return "Comfortably out of the deficient range, but not by much. Hard training spends iron — through sweat, foot-strike hemolysis, and gut losses — so this is a number worth keeping an eye on rather than one to act on."
        case .stocked:
            return "Stores are in good shape. Normal eating covers it from here."
        }
    }

    private static func actions(for status: Status) -> [String] {
        switch status {
        case .stocked:
            return []
        case .watch:
            return [
                "Keep a heme source — red meat, and especially liver — in the week a couple of times. Iron from animal foods absorbs several times better than from plants.",
                "Put vitamin C alongside plant iron. Peppers, citrus, tomato, or strawberries with beans, lentils, tofu, or fortified cereal can multiply what you actually absorb.",
                "Re-test before your next big block rather than waiting for it to feel wrong."
            ]
        case .low, .depleted:
            var items = [
                "Take this to a doctor before taking iron. Supplementing without a deficiency causes real harm, and the dose and form should come from someone reading the whole panel — not from an app.",
                "Anchor one meal a day on heme iron: beef, lamb, liver, oysters, mussels, or dark-meat poultry. It absorbs far better than any plant source.",
                "Pair every plant-iron meal with vitamin C — lentils with tomato and peppers, spinach with citrus, fortified oats with strawberries.",
                "Move coffee and tea at least an hour away from iron-rich meals. The polyphenols in both can cut absorption of that meal's iron substantially.",
                "Keep calcium out of the same sitting — the big dairy serving or a calcium supplement works better at a different meal.",
                "Cast iron helps, genuinely: acidic food simmered in a bare cast-iron pan picks up measurable iron."
            ]
            if status == .depleted {
                items.insert("Expect training to feel off until this is fixed, and don't read the extra effort as lost fitness. Iron stores take months to rebuild even once they're being addressed.", at: 1)
            }
            return items
        }
    }

    private static func mealNote(for status: Status) -> String {
        switch status {
        case .depleted, .low:
            return "Your iron meal — heme source if you can, vitamin C alongside, and keep coffee or tea an hour clear of it."
        case .watch:
            return "A good slot for iron: pair it with something rich in vitamin C."
        case .stocked:
            return ""
        }
    }

    /// The one-line caveat that has to travel with all of this.
    static let disclaimer = "Dietary guidance based on the numbers you entered — not a diagnosis, and not a reason to start an iron supplement. That's a conversation for your doctor."

    /// How today's logged food is doing against the iron target, for the
    /// dashboard. Returns nil when nothing logged knows its iron content.
    static func loggedIronProgress(day: DayLog, targetMg: Double) -> (eaten: Double, target: Double)? {
        let eaten = day.totalFacts.ironMg
        guard eaten > 0 else { return nil }
        return (eaten, targetMg)
    }
}
