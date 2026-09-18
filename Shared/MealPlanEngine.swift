import Foundation

/// Turns a day's worth of targets into a day's worth of *meals*.
///
/// A daily calorie number is a summary, not a plan. It tells you nothing
/// about the two things that actually decide whether the day works: how much
/// to eat at each sitting, and where the training sits among them. Eating
/// 3,200 calories is a different problem when 90 minutes of intervals starts
/// at seven than when it starts at seven in the evening, and the daily number
/// is identical in both cases.
///
/// So this walks the clock. It lays the day's meals and sessions out in the
/// order they happen, carves the workout-adjacent fuel out first because
/// that's the part with a deadline attached, spreads protein evenly because
/// that's how protein works, and lets carbs and fat fill in around them. What
/// comes out is a list of targets with times on them.
///
/// Three things bend the shape, and they're the ones that come up in real
/// days rather than in theory:
///
/// - **A late start.** Slots before you woke up aren't meals you skipped;
///   they're meals that were never going to happen. They come out and the
///   rest of the day absorbs them.
/// - **A meal you're planning around.** A dinner out doesn't mean the day is
///   blown, it means the other meals should be smaller. Marking it says so.
/// - **What you already ate.** On today, any meal that has passed and has
///   food logged against it is locked to what actually went in, and
///   everything still ahead is re-planned around that. This is what makes
///   "I skipped lunch, reallocate" a real answer rather than a shrug — and
///   it works the same when you ate double, just in the other direction.
///
/// When the leftovers genuinely can't fit in what's left of the day, it says
/// so instead of printing a 2,400-calorie dinner and pretending.
enum MealPlanEngine {

    // MARK: - Shape of the output

    /// Why this meal looks the way it does. One per meal, priority-ordered —
    /// a pre-session breakfast that's also the day's big meal reads as
    /// pre-session, because that's the constraint with a clock on it.
    enum MealRole: String {
        case preWorkout
        case recovery
        case normal

        var badge: String? {
            switch self {
            case .preWorkout: return "PRE"
            case .recovery: return "RECOVERY"
            case .normal: return nil
            }
        }
    }

    /// One meal, with a time and a number.
    struct MealTarget: Identifiable, Equatable {
        let id: String
        let meal: Meal
        let label: String
        let minutesOfDay: Int
        let role: MealRole
        let isBig: Bool
        let isIronFocus: Bool
        let skipped: Bool
        /// True when the engine invented this slot to carry workout fuel that
        /// no scheduled meal was close enough to handle.
        let isSynthetic: Bool
        /// True when this meal is in the past and locked to what was eaten.
        let isLocked: Bool
        /// Minutes-of-day this meal sits at on the schedule, when training
        /// moved it somewhere else today.
        let movedFrom: Int?

        let calories: Int
        let carbGrams: Int
        let proteinGrams: Int
        let fatGrams: Int

        /// What's actually been logged against this meal so far.
        let eatenCalories: Int
        let eatenProtein: Int

        /// The one-line reason this meal is sized and timed the way it is.
        let why: String
        /// Extra context worth a second line — the iron note, a fat caution.
        let notes: [String]

        var timeString: String {
            let comps = DateComponents(hour: minutesOfDay / 60, minute: minutesOfDay % 60)
            let date = Calendar.current.date(from: comps) ?? Date()
            return date.formatted(date: .omitted, time: .shortened)
        }

        /// The phrasing the whole feature is built around. Targets are aims,
        /// not quotas, and saying so is the difference between a plan someone
        /// uses and a number someone fails.
        var aim: String {
            if skipped { return "Skipped — spread across the rest of the day" }
            return "Aim to eat about \(calories) cal"
        }

        var macroLine: String {
            "\(carbGrams) g carbs · \(proteinGrams) g protein · \(fatGrams) g fat"
        }

        /// Progress against the aim, 0…1+, for the row's bar.
        var progress: Double {
            guard calories > 0 else { return 0 }
            return Double(eatenCalories) / Double(calories)
        }

        var hasLoggedFood: Bool { eatenCalories > 0 }

        /// "Moved up from 12:30 PM" — said out loud, because a meal that
        /// silently isn't where the schedule says it is looks like a bug.
        var movedNote: String? {
            guard let movedFrom else { return nil }
            let comps = DateComponents(hour: movedFrom / 60, minute: movedFrom % 60)
            let date = Calendar.current.date(from: comps) ?? Date()
            let was = date.formatted(date: .omitted, time: .shortened)
            return movedFrom > minutesOfDay
                ? "Moved up from \(was) so it's cleared before you train."
                : "Pushed back from \(was) — you're training then."
        }
    }

    /// A session on the timeline, with its fueling already worked out.
    struct SessionBlock: Identifiable, Equatable {
        let id: String
        let session: TrainingSession
        let fuel: FuelingPlan
        /// Called off for today. Still drawn — there has to be something to
        /// tap to put it back — but it fuels nothing and costs nothing.
        var isSkipped = false

        static func == (lhs: SessionBlock, rhs: SessionBlock) -> Bool {
            lhs.id == rhs.id && lhs.isSkipped == rhs.isSkipped
        }

        var minutesOfDay: Int { session.hour * 60 + session.minute }
        var endMinutesOfDay: Int { minutesOfDay + session.minutes }

        /// "90 min · Hard · 8:00 AM"
        var subtitle: String { session.subtitle }

        /// What to take in *during* the session, when it runs long enough to
        /// need anything. Empty for everything short.
        var duringLine: String? {
            guard fuel.needsInWorkoutFuel else { return nil }
            return "\(fuel.carbsPerHour) g carbs/hr during — about \(fuel.duringCarbs) g across the session"
        }

        var hydrationLine: String {
            var line = "\(fuel.fluidOzPerHour) oz/hr"
            if fuel.sodiumMgPerHour > 0 { line += " · \(fuel.sodiumMgPerHour) mg sodium/hr" }
            if fuel.fluidIsMeasured { line += " · from your sweat tests" }
            return line
        }
    }

    /// One entry on the day's timeline.
    enum Item: Identifiable {
        case meal(MealTarget)
        case session(SessionBlock)

        var id: String {
            switch self {
            case .meal(let m): return "meal-\(m.id)"
            case .session(let s): return "session-\(s.id)"
            }
        }

        var minutesOfDay: Int {
            switch self {
            case .meal(let m): return m.minutesOfDay
            case .session(let s): return s.minutesOfDay
            }
        }

        /// Meals sort before a session starting at the same minute — you eat,
        /// then you train.
        var sortRank: Int {
            switch self {
            case .meal: return 0
            case .session: return 1
            }
        }
    }

    /// The whole day, ready to render.
    struct DayPlan {
        let date: Date
        let items: [Item]
        let targets: DailyTargets
        let headline: String
        let subhead: String
        /// Things worth saying out loud — a shortfall that can't be made up,
        /// a heat warning off the fueling plans, a stale lab panel.
        let advisories: [String]
        let iron: IronCoach.Finding?
        /// Carbs spoken for mid-session and therefore not in any meal.
        let duringSessionCarbs: Int

        var meals: [MealTarget] {
            items.compactMap { if case .meal(let m) = $0 { return m } else { return nil } }
        }

        var sessions: [SessionBlock] {
            items.compactMap { if case .session(let s) = $0 { return s } else { return nil } }
        }

        var plannedMeals: [MealTarget] { meals.filter { !$0.skipped } }

        /// Everything the meals add up to — should land on the day's budget
        /// once mid-session carbs are added back.
        var plannedCalories: Int { plannedMeals.reduce(0) { $0 + $1.calories } }

        /// The next thing due, for a compact dashboard card.
        func next(after minutesOfDay: Int) -> Item? {
            items.first { $0.minutesOfDay >= minutesOfDay && !isSkippedMeal($0) }
        }

        private func isSkippedMeal(_ item: Item) -> Bool {
            switch item {
            case .meal(let m): return m.skipped
            case .session(let s): return s.isSkipped
            }
        }
    }

    // MARK: - Tuning

    /// The most of a day's macro any one sitting is asked to carry. Past
    /// this, a "reallocated" meal stops being a plan and starts being a dare.
    static let maxShareOfDay = 0.45
    /// The same ceiling for a meal someone deliberately marked as the big one.
    static let maxShareOfDayBig = 0.65
    /// Protein per sitting: below the lower bound the meal doesn't clear the
    /// threshold that actually triggers muscle protein synthesis; above the
    /// upper bound the extra is mostly just fuel.
    static let minProteinPerMeal = 15.0
    static let maxProteinPerMeal = 55.0
    /// How far before a session a meal still counts as the pre-session meal.
    static let preWorkoutWindowMinutes = 180
    /// And how long after it still counts as recovery.
    static let recoveryWindowMinutes = 150
    /// Where a synthetic pre-session top-up lands when no real meal is close.
    static let syntheticPreOffsetMinutes = 75
    /// And a synthetic recovery meal, after the session ends.
    static let syntheticRecoveryOffsetMinutes = 30
    /// Fat is pulled down before a session — it slows gastric emptying, and
    /// the last thing a hard effort needs is food still sitting there.
    static let preWorkoutFatFactor = 0.35
    /// How much extra a meal marked "big" pulls toward itself.
    static let bigMealWeightFactor = 1.9

    // MARK: - Entry point

    /// Build the day.
    ///
    /// `sessions` and `fuels` are parallel: caller-supplied so the weather,
    /// sweat profile, and cycle phase stay a view concern and this stays a
    /// pure function of its inputs.
    static func plan(date: Date,
                     day: DayLog,
                     plan: Plan,
                     profile: UserProfile,
                     targets: DailyTargets,
                     sessions: [TrainingSession],
                     fuels: [FuelingPlan],
                     skipped: [SessionBlock] = [],
                     iron: IronCoach.Finding? = nil,
                     now: Date = Date()) -> DayPlan {

        let calendar = Calendar.current
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let nowMinutes: Int = {
            let c = calendar.dateComponents([.hour, .minute], from: now)
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }()

        // Sessions and their fueling, paired and in clock order. Only the
        // live ones — `blocks` drives every calculation below, so a called-off
        // session simply isn't in it.
        let blocks = zip(sessions, fuels)
            .map { SessionBlock(id: $0.0.id, session: $0.0, fuel: $0.1) }
            .sorted { $0.minutesOfDay < $1.minutesOfDay }
        let skippedBlocks = skipped.map { block -> SessionBlock in
            var copy = block
            copy.isSkipped = true
            return copy
        }

        // Carbs taken in mid-session belong to the session, not to a meal.
        let duringCarbs = blocks.reduce(0) { $0 + $1.fuel.duringCarbs }

        var macros = resolveMacros(targets: targets, bodyweightLbs: plan.currentWeight)
        macros.carbs = max(0, macros.carbs - Double(duringCarbs))
        macros.calories = max(0, macros.calories - Double(duringCarbs) * 4)

        // --- Which slots are in play
        var entries = buildEntries(day: day, plan: plan, blocks: blocks)
        guard !entries.isEmpty else {
            return DayPlan(date: date,
                           items: (blocks + skippedBlocks)
                               .sorted { $0.minutesOfDay < $1.minutesOfDay }
                               .map(Item.session),
                           targets: targets,
                           headline: headline(targets: targets, mealCount: 0, blocks: blocks),
                           subhead: "No meals are switched on. Add some under Settings → Meal Schedule.",
                           advisories: [], iron: iron, duringSessionCarbs: duringCarbs)
        }

        assignRoles(&entries, blocks: blocks, bigMeal: day.bigMeal)

        // --- Lock what already happened, re-plan what hasn't
        var advisories: [String] = []
        if isToday {
            lockPastMeals(&entries, day: day, nowMinutes: nowMinutes)
        }
        for i in entries.indices {
            entries[i].eatenCalories = day.calories(for: entries[i].meal)
            entries[i].eatenProtein = day.protein(for: entries[i].meal)
        }

        let lockedCalories = entries.filter(\.isLocked).reduce(0.0) { $0 + Double($1.eatenCalories) }
        let lockedProtein = entries.filter(\.isLocked).reduce(0.0) { $0 + Double($1.eatenProtein) }
        let lockedFacts = entries.filter(\.isLocked).reduce(into: NutritionFacts()) {
            $0.add(day.facts(for: $1.meal))
        }

        let openIndices = entries.indices.filter { !entries[$0].skipped && !entries[$0].isLocked }
        let remaining = reconciled(Macros(calories: macros.calories - lockedCalories,
                                          carbs: macros.carbs - lockedFacts.carbsGrams,
                                          protein: macros.protein - lockedProtein,
                                          fat: macros.fat - lockedFacts.fatGrams))

        if openIndices.isEmpty {
            advisories.append("Every meal today is either eaten or skipped. Nothing left to plan — the numbers below are what actually went in.")
        } else if remaining.calories <= 0 {
            advisories.append("Today's budget is already spent. What's left of the plan is protein and vegetables — it isn't a failed day, it's just a full one.")
        }

        // --- Allocate
        allocate(&entries, openIndices: openIndices, remaining: remaining,
                 dayTotal: macros, blocks: blocks,
                 normalMealCount: max(1, plan.activeMealSlots.count),
                 advisories: &advisories)

        // --- Iron gets a home
        if let iron, iron.status.steersMeals {
            markIronFocus(&entries, openIndices: openIndices)
        }

        // --- Assemble
        let ironNote = (iron?.status.steersMeals ?? false) ? (iron?.mealNote ?? "") : ""
        let mealTargets = entries.map { $0.finish(day: day, blocks: blocks, ironNote: ironNote) }
        var items: [Item] = mealTargets.map(Item.meal)
            + (blocks + skippedBlocks).map(Item.session)
        items.sort { ($0.minutesOfDay, $0.sortRank) < ($1.minutesOfDay, $1.sortRank) }

        // Anything the fueling engine wanted to say — heat, sweat tests, caps.
        for block in blocks {
            for advisory in block.fuel.advisories where !advisories.contains(advisory) {
                advisories.append(advisory)
            }
        }
        if let staleness = iron?.staleness, iron?.status.isActionable == true {
            advisories.append(staleness)
        }

        return DayPlan(date: date,
                       items: items,
                       targets: targets,
                       headline: headline(targets: targets,
                                          mealCount: mealTargets.filter { !$0.skipped }.count,
                                          blocks: blocks),
                       subhead: subhead(day: day, entries: entries, blocks: blocks),
                       advisories: advisories,
                       iron: iron,
                       duringSessionCarbs: duringCarbs)
    }

    // MARK: - Macros

    struct Macros {
        var calories: Double
        var carbs: Double
        var protein: Double
        var fat: Double
    }

    /// Make the four numbers agree with each other.
    ///
    /// Logged food is where they stop agreeing. A meal recorded as 1,400
    /// calories whose macros only account for 1,260 isn't a bug in the app —
    /// it's a barcode with half a nutrition panel, or a restaurant that
    /// publishes a calorie count and nothing else. The calories are the
    /// reliable half of that, so the remaining carbs and fat are scaled to
    /// fit what's actually left of the budget rather than being subtracted
    /// naively and quietly over-feeding the rest of the day.
    ///
    /// Protein is held fixed: it's the target that shouldn't flex, and it's
    /// the one logged food reports most reliably.
    static func reconciled(_ macros: Macros) -> Macros {
        var m = macros
        m.protein = max(0, m.protein)
        let forCarbsAndFat = m.calories - m.protein * 4
        guard forCarbsAndFat > 0 else {
            m.carbs = 0
            m.fat = 0
            return m
        }
        let current = max(0, m.carbs) * 4 + max(0, m.fat) * 9
        guard current > 0 else {
            m.carbs = forCarbsAndFat / 4
            m.fat = 0
            return m
        }
        let factor = forCarbsAndFat / current
        // Rounding-sized drift isn't worth moving numbers for.
        guard abs(factor - 1) > 0.005 else { return m }
        m.carbs = max(0, m.carbs) * factor
        m.fat = max(0, m.fat) * factor
        return m
    }

    /// Weight-loss and general-health targets carry calories and protein but
    /// no carb/fat split — there's no training load to periodize against. The
    /// plan still needs all four, so the rest is derived: fat at roughly a
    /// quarter of calories with a floor that keeps hormones and fat-soluble
    /// vitamins out of it, and carbs take what's left.
    static func resolveMacros(targets: DailyTargets, bodyweightLbs: Double) -> Macros {
        let calories = Double(targets.calories)
        let protein = Double(targets.proteinGrams)
        if let carbs = targets.carbGrams, let fat = targets.fatGrams {
            return Macros(calories: calories, carbs: Double(carbs),
                          protein: protein, fat: Double(fat))
        }
        let kg = max(30, bodyweightLbs * 0.45359237)
        let fat = max(kg * 0.7, calories * 0.27 / 9)
        let carbs = max(0, (calories - protein * 4 - fat * 9) / 4)
        return Macros(calories: calories, carbs: carbs, protein: protein, fat: fat)
    }

    // MARK: - Entries (the mutable working copy of a slot)

    private struct Entry {
        var id: String
        var meal: Meal
        var label: String
        var minutesOfDay: Int
        var weight: Double
        var skipped: Bool
        var isSynthetic: Bool
        var isLocked = false
        /// Where this meal sat on the schedule before training moved it.
        var shiftedFrom: Int?

        /// How long before a session this meal needs in order to have cleared.
        ///
        /// Scaled by size, because that's what actually decides it: a full
        /// dinner needs two to three hours, a gel or a banana needs twenty
        /// minutes. Training on a stomach that's still working is the single
        /// most common way a planned session falls apart, and it's entirely
        /// avoidable by moving the meal.
        var digestionLeadMinutes: Int {
            switch weight {
            case ..<0.7: return 45     // a snack
            case ..<1.3: return 120    // an ordinary meal
            default:     return 180    // a big one
            }
        }
        var role: MealRole = .normal
        var isBig = false
        var isIronFocus = false

        var carbFloor = 0.0
        var proteinFloor = 0.0

        var carbs = 0.0
        var protein = 0.0
        var fat = 0.0

        var eatenCalories = 0
        var eatenProtein = 0
        /// What a locked meal actually cost. Derived calories would disagree
        /// with it whenever the logged food's macro panel was incomplete, and
        /// the number on the label is the one to trust.
        var lockedCalories: Int?

        var calories: Double {
            if let lockedCalories { return Double(lockedCalories) }
            return carbs * 4 + protein * 4 + fat * 9
        }

        func finish(day: DayLog, blocks: [SessionBlock], ironNote: String) -> MealTarget {
            var notes: [String] = []
            if isIronFocus, !ironNote.isEmpty { notes.append(ironNote) }
            if let shiftedFrom {
                let comps = DateComponents(hour: shiftedFrom / 60, minute: shiftedFrom % 60)
                let date = Calendar.current.date(from: comps) ?? Date()
                notes.append(shiftedFrom > minutesOfDay
                    ? "Normally \(date.formatted(date: .omitted, time: .shortened)) — moved so it has time to clear before training."
                    : "Normally \(date.formatted(date: .omitted, time: .shortened)) — moved because you're training then.")
            }
            if role == .preWorkout {
                notes.append("Keep the fat and fiber low here — both slow the stomach down, and that's the last thing you want at the start line.")
            }
            return MealTarget(id: id,
                              meal: meal,
                              label: label,
                              minutesOfDay: minutesOfDay,
                              role: role,
                              isBig: isBig,
                              isIronFocus: isIronFocus,
                              skipped: skipped,
                              isSynthetic: isSynthetic,
                              isLocked: isLocked,
                              movedFrom: shiftedFrom,
                              calories: Int(calories.rounded()),
                              carbGrams: Int(carbs.rounded()),
                              proteinGrams: Int(protein.rounded()),
                              fatGrams: Int(fat.rounded()),
                              eatenCalories: eatenCalories,
                              eatenProtein: eatenProtein,
                              why: MealPlanEngine.why(for: self, blocks: blocks),
                              notes: notes)
        }
    }

    /// Slots → entries, dropping anything that fell before the day started
    /// and inserting synthetic meals where workout fuel has nowhere to go.
    private static func buildEntries(day: DayLog, plan: Plan, blocks: [SessionBlock]) -> [Entry] {
        let slots = plan.activeMealSlots
        var entries: [Entry] = slots.map {
            Entry(id: "slot-\($0.meal.rawValue)",
                  meal: $0.meal,
                  label: $0.label,
                  minutesOfDay: $0.minutesOfDay,
                  weight: max(0.1, $0.share),
                  skipped: day.isSkipped($0.meal),
                  isSynthetic: false)
        }

        // A late start compresses the day rather than deleting meals from it.
        //
        // The first instinct — drop every slot before you woke up — is wrong,
        // and wrong in a way that matters: someone who gets up at one o'clock
        // still eats two or three times before bed, and telling them a whole
        // day's food has to fit in one dinner is both useless and a good way
        // to make them stop opening the app. So the meals that fell before
        // waking get re-timed into the hours that are actually left, and only
        // the ones that genuinely don't fit — too many meals for too few
        // hours — come out.
        if let wake = day.wakeMinutesOfDay {
            entries = recompressed(entries, wake: wake)
        }

        // Training gets the clock. A session is a commitment with a time on
        // it; a meal time is a habit, and habits are the thing that should
        // bend. Meals that would land mid-session — or too close to the start
        // to have cleared — move first, so the synthetic-slot pass below sees
        // the day as it will actually be eaten and doesn't invent a
        // pre-session snack next to a lunch that just moved into the slot.
        entries = shiftedAroundTraining(entries, blocks: blocks, wake: day.wakeMinutesOfDay)

        // Workout fuel that no meal is near enough to carry gets its own slot.
        for block in blocks {
            let start = block.minutesOfDay
            let end = block.endMinutesOfDay

            if block.fuel.preCarbs > 0 {
                let hasPre = entries.contains {
                    !$0.skipped && $0.minutesOfDay <= start
                        && $0.minutesOfDay >= start - preWorkoutWindowMinutes
                }
                if !hasPre {
                    let at = max(day.wakeMinutesOfDay ?? 0, start - syntheticPreOffsetMinutes)
                    entries.append(Entry(id: "pre-\(block.id)",
                                         meal: availableMeal(at: at, taken: Set(entries.map(\.meal))),
                                         label: "Pre-Session Fuel",
                                         minutesOfDay: at,
                                         weight: 0.45,
                                         skipped: false,
                                         isSynthetic: true))
                }
            }

            if block.fuel.recoveryProtein > 0 || block.fuel.recoveryCarbs > 0 {
                let hasPost = entries.contains {
                    !$0.skipped && $0.minutesOfDay >= end
                        && $0.minutesOfDay <= end + recoveryWindowMinutes
                }
                if !hasPost {
                    let at = min(23 * 60 + 30, end + syntheticRecoveryOffsetMinutes)
                    entries.append(Entry(id: "recovery-\(block.id)",
                                         meal: availableMeal(at: at, taken: Set(entries.map(\.meal))),
                                         label: "Recovery Snack",
                                         minutesOfDay: at,
                                         weight: 0.55,
                                         skipped: false,
                                         isSynthetic: true))
                }
            }
        }

        return entries.sorted { $0.minutesOfDay < $1.minutesOfDay }
    }

    /// Nudge meals out of the way of training.
    ///
    /// Two things are wrong with a meal that overlaps a session, and they
    /// need different answers. A meal *during* the session simply can't
    /// happen. A meal shortly *before* it can happen, but shouldn't: food
    /// still being digested is blood flow that the working muscle wants, and
    /// it's why the session feels terrible. So each meal claims a clear
    /// window ahead of the session scaled to its own size, and if the
    /// schedule puts it inside that window it moves — earlier if there's room
    /// to digest, otherwise to after the session, whichever is the smaller
    /// disruption to the day.
    private static func shiftedAroundTraining(_ entries: [Entry],
                                              blocks: [SessionBlock],
                                              wake: Int?) -> [Entry] {
        guard !blocks.isEmpty, !entries.isEmpty else { return entries }
        var result = entries
        let floor = max(earliestMealMinutes, (wake.map { $0 + 15 }) ?? earliestMealMinutes)

        func clash(_ time: Int, lead: Int) -> SessionBlock? {
            blocks.first {
                time > $0.minutesOfDay - lead && time < $0.endMinutesOfDay + postSessionGap
            }
        }

        for i in result.indices where !result[i].skipped {
            let original = result[i].minutesOfDay
            var time = original
            let lead = result[i].digestionLeadMinutes

            // Bounded: moving clear of one session can land on the next, but
            // each pass moves strictly forward past one more session.
            for _ in 0..<blocks.count {
                guard let block = clash(time, lead: lead) else { break }
                let earlier = block.minutesOfDay - lead
                let later = block.endMinutesOfDay + postSessionGap
                let canGoEarlier = earlier >= floor
                let canGoLater = later <= bedtimeMinutes

                if canGoEarlier && canGoLater {
                    // Whichever asks less of the day — but with a thumb on
                    // the scale for eating *before*. Going into a session
                    // already fuelled beats finishing it and then having your
                    // first real meal of the afternoon, and a meal moved
                    // earlier keeps its job as the pre-session meal instead of
                    // leaving a hole that has to be filled with an invented
                    // snack. Only a session late enough that moving back would
                    // drag the meal hours off its time flips it.
                    let earlierCost = (time - earlier) - earlierBias
                    time = earlierCost <= (later - time) ? earlier : later
                } else if canGoEarlier {
                    time = earlier
                } else if canGoLater {
                    time = later
                } else {
                    break   // nowhere left to put it; leave it where it was
                }
            }

            if time != original {
                result[i].minutesOfDay = time
                result[i].shiftedFrom = original
            }
        }

        return spaced(result, blocks: blocks)
    }

    /// Keep meals in order and off each other, without shoving one back into
    /// a session on the way.
    private static func spaced(_ entries: [Entry], blocks: [SessionBlock]) -> [Entry] {
        var result = entries.sorted { $0.minutesOfDay < $1.minutesOfDay }
        for i in result.indices.dropFirst() where !result[i].skipped {
            let earliest = result[i - 1].minutesOfDay + minimumMealGap
            guard result[i].minutesOfDay < earliest else { continue }
            var time = earliest
            // Pushed into a session? Go past the end of it instead.
            if let block = blocks.first(where: {
                time >= $0.minutesOfDay && time < $0.endMinutesOfDay + postSessionGap
            }) {
                time = block.endMinutesOfDay + postSessionGap
            }
            time = min(time, 23 * 60 + 30)
            if result[i].shiftedFrom == nil, time != result[i].minutesOfDay {
                result[i].shiftedFrom = result[i].minutesOfDay
            }
            result[i].minutesOfDay = time
        }
        return result.sorted { $0.minutesOfDay < $1.minutesOfDay }
    }

    /// The earliest a planned meal should ever be pulled back to.
    ///
    /// Six, not five. A real meal two hours before a 7 a.m. session means
    /// eating at five, which nobody does and nobody should be told to do —
    /// the actual answer for an early session is a small top-up beforehand
    /// and the proper meal afterwards. Holding the floor here is what makes
    /// the engine reach that answer instead of the literal one.
    private static let earliestMealMinutes = 6 * 60
    /// Long enough after a session to have stopped and changed.
    private static let postSessionGap = 20
    /// The least two meals can sit apart and still be two meals.
    private static let minimumMealGap = 60
    /// How much further a meal will travel to land *before* a session rather
    /// than after it, when both would work.
    private static let earlierBias = 45
    /// The most of a day's carbohydrate the pre-session and recovery floors
    /// may claim between them before they start being scaled back.
    private static let maxWorkoutFloorShare = 0.7

    /// The last sensible hour to be eating a planned meal.
    private static let bedtimeMinutes = 22 * 60
    /// How far apart meals have to be to be worth planning separately.
    private static let minimumMealSpacing = 150

    /// Re-space a day's meals into the window between waking and bed.
    private static func recompressed(_ entries: [Entry], wake: Int) -> [Entry] {
        let displaced = entries.filter { $0.minutesOfDay < wake - 15 }
        guard !displaced.isEmpty else { return entries }

        let start = wake + 30
        let end = max(start, bedtimeMinutes)
        // How many meals the remaining hours can actually hold.
        let capacity = max(1, (end - start) / minimumMealSpacing + 1)

        // Keep the meals that were already in the window, then as many of the
        // displaced ones as still fit — latest first, since an eight o'clock
        // breakfast is the one with least claim on a day that started at one.
        let survivors = entries.filter { $0.minutesOfDay >= wake - 15 }
        let room = max(0, capacity - survivors.count)
        let rescued = displaced.suffix(room)
        var kept = (survivors + rescued).sorted { $0.minutesOfDay < $1.minutesOfDay }
        if kept.isEmpty, var last = entries.last {
            // Woke past bedtime. One meal, now, rather than nothing.
            last.minutesOfDay = min(23 * 60 + 30, start)
            return [last]
        }

        // Spread whatever survived evenly across the hours that are left.
        if kept.count == 1 {
            kept[0].minutesOfDay = max(kept[0].minutesOfDay, start)
        } else {
            let step = Double(end - start) / Double(kept.count - 1)
            for i in kept.indices {
                kept[i].minutesOfDay = start + Int((Double(i) * step).rounded())
            }
        }
        return kept
    }

    /// Which meal an invented slot should log its food under.
    ///
    /// It can't reuse one already on the plan: two entries sharing a `Meal`
    /// means everything logged to it counts against both, so a pre-session
    /// top-up at quarter to six would eat the real breakfast's progress. The
    /// unused meal whose usual hour is nearest gets it — which lands a dawn
    /// top-up in Morning Snack and an afternoon refuel in Afternoon Snack.
    private static func availableMeal(at minutes: Int, taken: Set<Meal>) -> Meal {
        let free = Meal.allCases.filter { !taken.contains($0) }
        guard !free.isEmpty else { return Meal.suggested(at: dateAt(minutes: minutes)) }
        let suggested = Meal.suggested(at: dateAt(minutes: minutes))
        if free.contains(suggested) { return suggested }
        return free.min {
            abs($0.typicalMinutesOfDay - minutes) < abs($1.typicalMinutesOfDay - minutes)
        } ?? suggested
    }

    private static func dateAt(minutes: Int) -> Date {
        let comps = DateComponents(hour: minutes / 60, minute: minutes % 60)
        return Calendar.current.date(from: comps) ?? Date()
    }

    /// Who's the pre-session meal, who's recovery, who's the big one.
    private static func assignRoles(_ entries: inout [Entry], blocks: [SessionBlock], bigMeal: Meal?) {
        for block in blocks {
            let start = block.minutesOfDay
            let end = block.endMinutesOfDay

            // The pre-session meal is the last one before the session that's
            // still inside the window — closest wins, because that's the one
            // the carbs actually have to go in.
            if block.fuel.preCarbs > 0 {
                let candidates = entries.indices.filter {
                    !entries[$0].skipped
                        && entries[$0].minutesOfDay <= start
                        && entries[$0].minutesOfDay >= start - preWorkoutWindowMinutes
                }
                if let i = candidates.max(by: { entries[$0].minutesOfDay < entries[$1].minutesOfDay }) {
                    entries[i].role = .preWorkout
                    entries[i].carbFloor = max(entries[i].carbFloor, Double(block.fuel.preCarbs))
                }
            }

            // Recovery is the first meal after the session ends.
            if block.fuel.recoveryProtein > 0 || block.fuel.recoveryCarbs > 0 {
                let candidates = entries.indices.filter {
                    !entries[$0].skipped
                        && entries[$0].minutesOfDay >= end
                        && entries[$0].minutesOfDay <= end + recoveryWindowMinutes
                }
                if let i = candidates.min(by: { entries[$0].minutesOfDay < entries[$1].minutesOfDay }) {
                    // A meal can't be both; the deadline after the session is
                    // the tighter one when they collide.
                    entries[i].role = .recovery
                    entries[i].carbFloor = max(entries[i].carbFloor, Double(block.fuel.recoveryCarbs))
                    entries[i].proteinFloor = max(entries[i].proteinFloor, Double(block.fuel.recoveryProtein))
                }
            }
        }

        if let bigMeal, let i = entries.firstIndex(where: { $0.meal == bigMeal && !$0.skipped }) {
            entries[i].isBig = true
            entries[i].weight *= bigMealWeightFactor
        }
    }

    /// Meals that have passed and have food against them stop being plans and
    /// become facts. Everything still ahead gets re-planned around them.
    private static func lockPastMeals(_ entries: inout [Entry], day: DayLog, nowMinutes: Int) {
        for i in entries.indices where !entries[i].skipped {
            guard entries[i].minutesOfDay < nowMinutes else { continue }
            let facts = day.facts(for: entries[i].meal)
            let eaten = day.calories(for: entries[i].meal)
            guard eaten > 0 else { continue }
            entries[i].isLocked = true
            entries[i].lockedCalories = eaten
            entries[i].carbs = facts.carbsGrams
            entries[i].fat = facts.fatGrams
            entries[i].protein = Double(day.protein(for: entries[i].meal))
        }
    }

    // MARK: - Allocation

    private static func allocate(_ entries: inout [Entry],
                                 openIndices: [Int],
                                 remaining: Macros,
                                 dayTotal: Macros,
                                 blocks: [SessionBlock],
                                 normalMealCount: Int,
                                 advisories: inout [String]) {
        guard !openIndices.isEmpty else { return }

        let weights = openIndices.map { entries[$0].weight }

        // The ceiling is a share of the WHOLE day, not of whatever is left of
        // it — measuring against the remainder would cap two surviving meals
        // at 45% each and lose 10% of the day for no reason, every time
        // breakfast was simply eaten.
        //
        // It's also relative to the shape of a normal day. Someone who eats
        // three meals should never see 80% of a day land on dinner because
        // lunch got skipped — but someone whose schedule genuinely is one
        // meal a day has no other sitting to put it in, and capping them
        // would be nonsense. Taking the larger of the two makes the cap bind
        // on skew and stay out of the way otherwise.
        let evenShare = 1.0 / Double(max(1, normalMealCount))
        func ceilingShare(_ i: Int) -> Double {
            max(entries[i].isBig ? maxShareOfDayBig : maxShareOfDay, evenShare)
        }

        // --- Protein: spread, not stacked.
        //
        // The per-meal number is a guideline about *effectiveness* — a dose
        // clearing roughly 0.3 g/kg is what actually triggers synthesis, and
        // much past that is mostly just fuel. It is emphatically not a limit
        // on what a person can eat, so it steers the weights and never caps
        // the day: a 170 g target across two meals is 85 g each, and telling
        // someone to eat 110 g of protein instead is simply wrong.
        let proteinCeilings = openIndices.map { _ in max(remaining.protein, 1) }
        let proteinFloors = openIndices.map { i -> Double in
            let floor = entries[i].proteinFloor
            // Don't force a full protein dose into a snack-sized slot.
            let wanted = entries[i].weight >= 0.6 ? minProteinPerMeal : 0
            return min(max(floor, wanted), max(remaining.protein, 1))
        }
        let proteinWeights = openIndices.map { max(0.35, entries[$0].weight) }
        let proteinResult = distribute(total: max(0, remaining.protein),
                                       weights: proteinWeights,
                                       floors: proteinFloors,
                                       ceilings: proteinCeilings)

        // --- Carbs: workout floors first, then by share.
        //
        // The floors can genuinely exceed what's left — a three-hour session
        // on a day whose carb target was set for something smaller. Forcing
        // them in would blow the day's total silently, so they're scaled back
        // together and the mismatch is said out loud.
        var carbFloors = openIndices.map { entries[$0].carbFloor }
        let floorTotal = carbFloors.reduce(0, +)
        // Leave something for the meals that aren't feeding the session. A day
        // whose carb target can't cover its own training will happen — but
        // answering it with a breakfast of zero carbs is not a plan, it's a
        // symptom. The other meals keep a share and the mismatch gets said.
        let floorCeiling = openIndices.count > 2
            ? max(0, remaining.carbs) * maxWorkoutFloorShare
            : max(0, remaining.carbs)
        if floorTotal > floorCeiling, floorTotal > 0 {
            let factor = floorCeiling / floorTotal
            carbFloors = carbFloors.map { $0 * factor }
            advisories.append("Today's carb target doesn't quite cover what the session itself asks for. The fuel around training has been scaled to fit — if this is a regular thing, the day's target is the number to raise, not the meals.")
        }
        let carbCeilings = openIndices.enumerated().map { n, i -> Double in
            max(carbFloors[n], dayTotal.carbs * ceilingShare(i))
        }
        let carbResult = distribute(total: max(0, remaining.carbs),
                                    weights: weights,
                                    floors: carbFloors,
                                    ceilings: carbCeilings)

        // --- Fat: by share, held down before a session.
        let fatWeights = openIndices.map { i -> Double in
            entries[i].role == .preWorkout ? entries[i].weight * preWorkoutFatFactor : entries[i].weight
        }
        let fatCeilings = openIndices.map { i in max(1, dayTotal.fat * ceilingShare(i)) }
        let fatResult = distribute(total: max(0, remaining.fat),
                                   weights: fatWeights,
                                   floors: [Double](repeating: 0, count: openIndices.count),
                                   ceilings: fatCeilings)

        for (n, i) in openIndices.enumerated() {
            entries[i].protein = proteinResult.allocation[n]
            entries[i].carbs = carbResult.allocation[n]
            entries[i].fat = fatResult.allocation[n]
        }

        // What wouldn't fit anywhere. Saying this is the whole point of having
        // a ceiling — a plan that quietly prints an impossible dinner is worse
        // than one that admits the day got away.
        let overflowCalories = carbResult.overflow * 4 + proteinResult.overflow * 4 + fatResult.overflow * 9
        if overflowCalories > 150 {
            advisories.append("About \(Int(overflowCalories.rounded())) calories more than fits sensibly in the meals you have left. Don't force it into one sitting — eat what you can, and let the day be a little short. Adding a snack slot would give it somewhere to go.")
        }
    }

    /// Spread `total` across weighted slots, honoring floors and ceilings.
    ///
    /// Water-filling: everyone starts at their floor, the rest goes out by
    /// weight, anything that overshoots a ceiling spills back to whoever still
    /// has room, and the loop repeats until either the total is placed or
    /// every slot is full. What's left over is returned rather than forced in.
    static func distribute(total: Double,
                           weights: [Double],
                           floors: [Double],
                           ceilings: [Double]) -> (allocation: [Double], overflow: Double) {
        let n = weights.count
        guard n > 0 else { return ([], total) }

        var allocation = (0..<n).map { min(max(0, floors[$0]), max(0, ceilings[$0])) }
        var remaining = total - allocation.reduce(0, +)

        // Floors already exceed the total: honor them and report the overrun
        // as a negative overflow — the caller decides whether that matters.
        guard remaining > 0.0001 else { return (allocation, remaining) }

        var open = Set((0..<n).filter { allocation[$0] < ceilings[$0] - 0.0001 })
        // Bounded: each pass saturates at least one slot or places everything.
        for _ in 0..<(n + 1) {
            guard remaining > 0.0001, !open.isEmpty else { break }
            let weightSum = open.reduce(0.0) { $0 + max(0, weights[$1]) }
            guard weightSum > 0 else { break }

            var spill = 0.0
            var saturated: [Int] = []
            let pool = remaining
            for i in open.sorted() {
                let want = pool * max(0, weights[i]) / weightSum
                let room = ceilings[i] - allocation[i]
                if want >= room {
                    allocation[i] = ceilings[i]
                    spill += want - room
                    saturated.append(i)
                } else {
                    allocation[i] += want
                }
            }
            saturated.forEach { open.remove($0) }
            remaining = spill
        }

        return (allocation, max(0, remaining))
    }

    /// The iron meal: the biggest one still ahead, because that's where a
    /// real portion of meat or lentils actually fits.
    private static func markIronFocus(_ entries: inout [Entry], openIndices: [Int]) {
        guard let i = openIndices.max(by: { entries[$0].protein < entries[$1].protein }) else { return }
        entries[i].isIronFocus = true
    }

    // MARK: - Words

    private static func why(for entry: Entry, blocks: [SessionBlock]) -> String {
        if entry.skipped {
            return "Skipped. Its share went to the meals still ahead of you."
        }
        if entry.isLocked {
            return "Already eaten — the rest of the day is planned around what actually went in."
        }
        switch entry.role {
        case .preWorkout:
            let session = blocks.first { $0.minutesOfDay >= entry.minutesOfDay }
            let gap = session.map { max(0, $0.minutesOfDay - entry.minutesOfDay) } ?? 0
            let when = gap >= 60
                ? "about \(gap / 60) hr\(gap % 60 >= 30 ? "½" : "") before"
                : "\(gap) min before"
            return "This one sits \(when) your session — carbs are the priority, and they need time to land."
        case .recovery:
            return "Straight after the session, while the muscle is still primed for it. Carbs to refill, protein to repair."
        case .normal:
            if entry.isBig {
                return "The meal you're planning around. Everything else today shrank to make room for it."
            }
            if entry.isSynthetic {
                return "Added because the training needed fuel here and no scheduled meal was close enough."
            }
            return "A normal meal — carbs, protein, and fat in the day's usual proportions."
        }
    }

    private static func headline(targets: DailyTargets, mealCount: Int, blocks: [SessionBlock]) -> String {
        var parts: [String] = []
        if let load = targets.trainingLoad { parts.append("\(load.label) day") }
        parts.append("\(targets.calories) cal")
        if mealCount > 0 { parts.append("\(mealCount) meal\(mealCount == 1 ? "" : "s")") }
        if !blocks.isEmpty { parts.append("\(blocks.count) session\(blocks.count == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }

    private static func subhead(day: DayLog, entries: [Entry], blocks: [SessionBlock]) -> String {
        if let big = day.bigMeal, entries.contains(where: { $0.meal == big && $0.isBig }) {
            return "Built around \(big.label.lowercased()) — the rest of the day makes room for it."
        }
        let skipped = entries.filter(\.skipped)
        if !skipped.isEmpty {
            let names = skipped.map { $0.label.lowercased() }.joined(separator: " and ")
            return "\(names.prefix(1).uppercased())\(names.dropFirst()) skipped — spread across what's left."
        }
        if day.wakeMinutesOfDay != nil {
            return "Late start — the day's food is packed into the hours you've actually got."
        }
        if let first = blocks.first, first.fuel.needsInWorkoutFuel {
            return "Fuel is built around \(first.session.name.lowercased()) — eat before it, refill after."
        }
        return "Targets are aims, not quotas. Close enough is the goal."
    }
}

// MARK: - Convenience

extension MealPlanEngine {
    /// Build the day plan from everything the app already knows.
    ///
    /// Sessions come from the training plan when there is one; when there
    /// isn't, the day's *logged* workouts stand in, so the plan bends around
    /// the training someone actually did even if they never scheduled it.
    /// That's what makes this work outside athlete mode.
    static func plan(for date: Date,
                     day: DayLog,
                     plan planModel: Plan,
                     profile: UserProfile,
                     targets: DailyTargets,
                     weather: WeatherContext? = nil,
                     cyclePhase: CyclePhase? = nil,
                     now: Date = Date()) -> DayPlan {
        planModel.ensureMealSchedule()

        let sweat = planModel.sweatProfile()
        func fuel(_ session: TrainingSession) -> FuelingPlan {
            FuelingEngine.plan(for: session,
                               bodyweightLbs: planModel.currentWeight,
                               sweat: sweat,
                               weather: planModel.weatherAwareFueling ? weather : nil,
                               cyclePhase: cyclePhase)
        }

        var everything = planModel.allSessions(on: date)
        if everything.isEmpty {
            everything = day.workouts
                .filter { $0.minutes > 0 }
                .map(TrainingSession.init)
                .sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        }
        let sessions = everything.filter { !day.isWorkoutSkipped($0.skipKey) }
        let skipped = everything
            .filter { day.isWorkoutSkipped($0.skipKey) }
            .map { SessionBlock(id: $0.id, session: $0, fuel: fuel($0), isSkipped: true) }

        let fuels = sessions.map(fuel)

        let iron = IronCoach.evaluate(labs: planModel.latestIronLabs,
                                      sex: profile.sex,
                                      now: now)

        return MealPlanEngine.plan(date: date,
                                   day: day,
                                   plan: planModel,
                                   profile: profile,
                                   targets: targets,
                                   sessions: sessions,
                                   fuels: fuels,
                                   skipped: skipped,
                                   iron: iron,
                                   now: now)
    }
}
