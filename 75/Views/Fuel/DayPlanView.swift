import SwiftUI
import SwiftData

/// The day, in the order it happens.
///
/// Every other screen in the app answers "how am I doing?" — a total, a
/// remainder, a ring. This one answers "what am I doing next?", which is the
/// question people actually have at nine in the morning. Meals and sessions
/// share one column in clock order, each meal carrying its own target rather
/// than a share of an abstract daily number, and the whole thing re-plans
/// itself the moment the day stops going to plan.
struct DayPlanView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var weather = WeatherService.shared
    var plan: Plan
    var profile: UserProfile

    /// False when this is pushed onto an existing navigation stack rather
    /// than being a tab's root. A view that supplies its own NavigationStack
    /// cannot be pushed onto one — the push lands on a dead end — so the
    /// stack belongs to whoever owns the screen, not to the screen.
    var isRoot: Bool = true

    @State private var date: Date

    init(plan: Plan, profile: UserProfile, date: Date? = nil, isRoot: Bool = true) {
        self.plan = plan
        self.profile = profile
        self.isRoot = isRoot
        let start = Calendar.current.startOfDay(for: date ?? Date())
        _date = State(initialValue: start)
    }

    @State private var expanded: Set<String> = []
    @State private var showShapeSheet = false
    @State private var foodEntry: FoodEntryRequest?
    @State private var ideasRequest: MealIdeasRequest?
    @State private var fuelDetail: FuelingPlan?

    private var day: DayLog { ensureDay(plan: plan, date: date) }

    private var cyclePhase: CyclePhase? {
        guard profile.cycleTracking else { return nil }
        return CycleEngine.status(entries: plan.cycles, on: date)?.phase
    }

    private var targets: DailyTargets {
        CalorieEngine.targets(profile: profile, plan: plan, on: date,
                              weather: weather.effective, cyclePhase: cyclePhase)
    }

    private var dayPlan: MealPlanEngine.DayPlan {
        MealPlanEngine.plan(for: date, day: day, plan: plan, profile: profile,
                            targets: targets, weather: weather.effective,
                            cyclePhase: cyclePhase)
    }

    private var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        if isRoot {
            NavigationStack { content }
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            ScrollViewReader { proxy in
                ScrollView {
                    let today = dayPlan
                    VStack(alignment: .leading, spacing: 14) {
                        dayHeader(today)

                        if let iron = today.iron, iron.isActionable {
                            IronCard(finding: iron, day: day, profile: profile)
                        }

                        ForEach(today.advisories, id: \.self) { advisory in
                            AdvisoryRow(text: advisory)
                        }

                        timeline(today, proxy: proxy)

                        footerNote(today)
                    }
                    .padding()
                }
                .onAppear { scrollToNow(plan: dayPlan, proxy: proxy) }
            }
            .brandBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Adjust is the only thing this screen owns. Settings lives on
                // the dashboard — one gear, one place, rather than the same
                // button repeated on every tab.
                //
                // Pushed, the leading slot belongs to the back button.
                ToolbarItem(placement: isRoot ? .topBarLeading : .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showShapeSheet = true
                    } label: {
                        Label("Adjust", systemImage: "slider.horizontal.3")
                            .font(.headline)
                    }
                    .accessibilityIdentifier("dayplan.adjust")
                }
            }
            .sheet(isPresented: $showShapeSheet) {
                DayShapeSheet(plan: plan, day: day)
            }
            .sheet(item: $foodEntry) { request in
                NavigationStack {
                    FoodSearchView(day: day, meal: request.meal)
                }
                .themedRoot()
            }
            .sheet(item: $ideasRequest) { request in
                MealIdeasView(day: day,
                              targets: targets,
                              labs: labSnapshot,
                              preferences: FoodPreferences(plan: plan),
                              meal: request.target.meal,
                              brief: request.brief)
                    .themedRoot()
            }
            .sheet(item: $fuelDetail) { detail in
                NavigationStack {
                    Form { FuelPlanBreakdown(plan: detail) }
                        .themedForm()
                        .navigationTitle("Fueling")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .themedRoot()
            }
            .task { await weather.refreshIfNeeded() }
        }
    }

    private var labSnapshot: AIFoodEstimator.LabSnapshot? {
        guard profile.showsGeneralHealth || profile.mode == .athlete else { return nil }
        let iron = IronCoach.evaluate(labs: plan.latestIronLabs, sex: profile.sex)
        return AIFoodEstimator.LabSnapshot(labs: plan.latestLabs ?? plan.latestIronLabs, iron: iron)
    }

    // MARK: - Header

    private func dayHeader(_ p: MealPlanEngine.DayPlan) -> some View {
        Card(tint: Theme.foodTint) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button {
                        shift(by: -1)
                    } label: {
                        Image(systemName: "chevron.left").font(.headline)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Previous day")

                    Spacer()
                    VStack(spacing: 1) {
                        Text(isToday ? "Today" : date.formatted(.dateTime.weekday(.wide)))
                            .font(.title3.bold())
                        Text(date.formatted(.dateTime.month().day()))
                            .font(.caption)
                            .foregroundStyle(Theme.textDim)
                    }
                    Spacer()

                    Button {
                        shift(by: 1)
                    } label: {
                        Image(systemName: "chevron.right").font(.headline)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Next day")
                }

                Text(p.headline)
                    .font(.headline)
                    .foregroundStyle(Theme.foodTint)

                Text(p.subhead)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().opacity(0.4)

                HStack(spacing: 14) {
                    macroStat("\(p.targets.carbGrams ?? derivedCarbs(p))", "g carbs", Theme.foodTint)
                    macroStat("\(p.targets.proteinGrams)", "g protein", Theme.workoutTint)
                    macroStat("\(p.targets.fatGrams ?? derivedFat(p))", "g fat", Theme.alcoholTint)
                    if p.duringSessionCarbs > 0 {
                        macroStat("\(p.duringSessionCarbs)", "g mid-session", Theme.waterTint)
                    }
                    Spacer()
                }

                if day.hasDayShapeChanges {
                    Button {
                        Haptics.tap()
                        day.resetDayShape()
                    } label: {
                        Label("Back to the normal day", systemImage: "arrow.uturn.backward")
                            .font(.caption.bold())
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func derivedCarbs(_ p: MealPlanEngine.DayPlan) -> Int {
        Int(MealPlanEngine.resolveMacros(targets: p.targets,
                                         bodyweightLbs: plan.currentWeight).carbs.rounded())
    }

    private func derivedFat(_ p: MealPlanEngine.DayPlan) -> Int {
        Int(MealPlanEngine.resolveMacros(targets: p.targets,
                                         bodyweightLbs: plan.currentWeight).fat.rounded())
    }

    private func macroStat(_ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.headline).foregroundStyle(tint)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Timeline

    private func timeline(_ p: MealPlanEngine.DayPlan, proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(p.items.enumerated()), id: \.element.id) { index, item in
                TimelineRow(isFirst: index == 0,
                            isLast: index == p.items.count - 1,
                            item: item) {
                    switch item {
                    case .meal(let target):
                        MealPlanRow(target: target,
                                    isExpanded: expanded.contains(target.id),
                                    onToggle: { toggle(target.id) },
                                    onLog: { foodEntry = FoodEntryRequest(meal: target.meal) },
                                    onIdeas: { ideasRequest = MealIdeasRequest(target: target, brief: brief(for: target, in: p)) },
                                    onSkip: { skip(target) })
                    case .session(let block):
                        SessionPlanRow(block: block,
                                       onDetail: { fuelDetail = block.fuel },
                                       onToggleSkip: { toggleSkip(block) })
                    }
                }
                .id(item.id)
            }
        }
    }

    /// The carbs/protein/fat this meal is aiming at, handed to the AI so a
    /// suggestion is judged against this meal rather than the day.
    private func brief(for target: MealPlanEngine.MealTarget,
                       in p: MealPlanEngine.DayPlan) -> AIFoodEstimator.MealBrief {
        let nextSession = p.sessions.first { $0.minutesOfDay >= target.minutesOfDay }
        return AIFoodEstimator.MealBrief(
            label: target.label,
            calories: target.calories,
            carbGrams: target.carbGrams,
            proteinGrams: target.proteinGrams,
            fatGrams: target.fatGrams,
            role: target.role == .normal ? nil : target.role.rawValue.lowercased(),
            minutesBeforeSession: target.role == .preWorkout
                ? nextSession.map { max(0, $0.minutesOfDay - target.minutesOfDay) }
                : nil)
    }

    private func footerNote(_ p: MealPlanEngine.DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Meals add up to \(p.plannedCalories) cal\(p.duringSessionCarbs > 0 ? " — the other \(p.duringSessionCarbs * 4) goes in during training" : "").")
            Text("Every number here is an aim. Landing near them beats hitting one exactly and missing the rest of the day.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 4)
        .padding(.horizontal, 4)
    }

    // MARK: - Actions

    private func toggle(_ id: String) {
        Haptics.tap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        }
    }

    /// Calling a session off re-plans the whole day around it, not just the
    /// timeline row: the budget loses its burn, the carb band steps down, and
    /// the pre-session and recovery meals stop being pre-session and recovery
    /// meals.
    private func toggleSkip(_ block: MealPlanEngine.SessionBlock) {
        Haptics.success()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            day.setWorkoutSkipped(block.session.skipKey, !block.isSkipped)
        }
    }

    private func skip(_ target: MealPlanEngine.MealTarget) {
        Haptics.success()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            day.setSkipped(target.meal, !target.skipped)
        }
    }

    private func shift(by days: Int) {
        Haptics.selection()
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: date) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            date = Calendar.current.startOfDay(for: next)
            expanded.removeAll()
        }
    }

    /// Open on what's next rather than at breakfast — by lunchtime the top of
    /// the list is history.
    private func scrollToNow(plan p: MealPlanEngine.DayPlan, proxy: ScrollViewProxy) {
        guard isToday else { return }
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        guard let next = p.next(after: minutes) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation { proxy.scrollTo(next.id, anchor: .center) }
        }
    }
}

// MARK: - Sheet payloads

private struct FoodEntryRequest: Identifiable {
    let meal: Meal
    var id: String { meal.rawValue }
}

private struct MealIdeasRequest: Identifiable {
    let target: MealPlanEngine.MealTarget
    let brief: AIFoodEstimator.MealBrief
    var id: String { target.id }
}

// MARK: - Timeline scaffolding

/// The time gutter and the connecting rail. Pulling this out keeps the meal
/// and session rows from each re-implementing the spine.
private struct TimelineRow<Content: View>: View {
    let isFirst: Bool
    let isLast: Bool
    let item: MealPlanEngine.Item
    @ViewBuilder var content: Content

    private var timeString: String {
        let comps = DateComponents(hour: item.minutesOfDay / 60, minute: item.minutesOfDay % 60)
        let date = Calendar.current.date(from: comps) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var tint: Color {
        switch item {
        case .meal(let m): return m.skipped ? Theme.textDim : m.meal.color
        case .session: return Theme.workoutTint
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(timeString)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textDim)
                .frame(width: 58, alignment: .trailing)
                .padding(.top, 18)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: 2)
                    .frame(height: 14)
                    .opacity(isFirst ? 0 : 1)
                Circle()
                    .fill(tint)
                    .frame(width: 9, height: 9)
                Rectangle()
                    .fill(Theme.hairline)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .opacity(isLast ? 0 : 1)
            }
            .padding(.top, 8)

            content
                .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Meal row

private struct MealPlanRow: View {
    let target: MealPlanEngine.MealTarget
    let isExpanded: Bool
    let onToggle: () -> Void
    let onLog: () -> Void
    let onIdeas: () -> Void
    let onSkip: () -> Void

    private var tint: Color { target.skipped ? Theme.textDim : target.meal.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(target.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(target.skipped ? Theme.textDim : .primary)
                            .strikethrough(target.skipped)
                        if let badge = target.role.badge {
                            TagChip(text: badge, tint: badgeTint)
                        }
                        if target.isBig { TagChip(text: "BIG", tint: Theme.alcoholTint) }
                        if target.isIronFocus { TagChip(text: "IRON", tint: Theme.workoutTint) }
                        if target.movedFrom != nil {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Theme.textDim)
                                .accessibilityLabel("Moved for training")
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(Theme.textDim)
                    }

                    Text(target.aim)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(target.skipped ? Theme.textDim : tint)

                    if !target.skipped {
                        Text(target.macroLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let moved = target.movedNote {
                            Text(moved)
                                .font(.caption2)
                                .foregroundStyle(Theme.textDim)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if target.hasLoggedFood {
                            MealProgressBar(progress: target.progress, tint: tint)
                            Text("\(target.eatenCalories) of \(target.calories) cal logged · \(target.eatenProtein) g protein")
                                .font(.caption2)
                                .foregroundStyle(Theme.textDim)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(target.why)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(target.notes, id: \.self) { note in
                        Label(note, systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(Theme.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Equal-width pills rather than the stock bordered
                    // styles: those size themselves to their labels, so
                    // "Log", "Ideas" and "Skipped it" came out three
                    // different widths and two different heights in a row
                    // that reads as one control.
                    HStack(spacing: 8) {
                        if !target.skipped {
                            MealActionButton(title: "Log", icon: "plus",
                                             tint: tint, filled: true, action: onLog)
                            MealActionButton(title: "Ideas", icon: "sparkles",
                                             tint: tint, action: onIdeas)
                        }
                        // "Skipped it" doesn't fit a third of this card once
                        // the timeline gutter has taken its 58 points — and a
                        // label that clips is worse than a shorter one. The
                        // sentence it was carrying lives in the why line
                        // directly above these buttons anyway.
                        MealActionButton(title: target.skipped ? "Undo" : "Skip",
                                         icon: target.skipped ? "arrow.uturn.backward" : "xmark",
                                         tint: Theme.textDim, action: onSkip)
                    }
                    .padding(.top, 4)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(tint.opacity(target.skipped ? 0.12 : 0.24))
                )
        )
        .opacity(target.skipped ? 0.6 : 1)
    }

    private var badgeTint: Color {
        switch target.role {
        case .preWorkout: return Theme.waterTint
        case .recovery: return Theme.supplementTint
        case .normal: return Theme.textDim
        }
    }
}

/// One of the three actions under an expanded meal. Fixed height, equal
/// width, same icon weight — so the row reads as a single control instead of
/// three buttons that happen to be next to each other.
private struct MealActionButton: View {
    let title: String
    let icon: String
    let tint: Color
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    // A backstop for large Dynamic Type, not a substitute for
                    // a label that fits: these read as one control, so one of
                    // them shrinking on its own would look like a mistake.
                    .minimumScaleFactor(0.75)
            }
            .padding(.horizontal, 6)
            .foregroundStyle(filled ? Color.white : tint)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                Capsule().fill(filled
                               ? AnyShapeStyle(tint)
                               : AnyShapeStyle(tint.opacity(0.15)))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }
}

private struct MealProgressBar: View {
    let progress: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.hairline)
                Capsule()
                    .fill(progress > 1.15 ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(tint))
                    .frame(width: geo.size.width * min(1, max(0.02, progress)))
            }
        }
        .frame(height: 5)
    }
}

// MARK: - Session row

private struct SessionPlanRow: View {
    let block: MealPlanEngine.SessionBlock
    let onDetail: () -> Void
    let onToggleSkip: () -> Void

    private var tint: Color { block.isSkipped ? Theme.textDim : Theme.workoutTint }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: block.session.category.icon)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text(block.session.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(block.isSkipped ? Theme.textDim : .primary)
                    .strikethrough(block.isSkipped)
                    .lineLimit(1)
                if block.session.completed && !block.isSkipped {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                Spacer(minLength: 0)

                if block.session.canBeSkipped {
                    Menu {
                        if block.isSkipped {
                            Button {
                                onToggleSkip()
                            } label: {
                                Label("Put it back on the plan", systemImage: "arrow.uturn.backward")
                            }
                        } else {
                            Button {
                                onDetail()
                            } label: {
                                Label("See the fueling", systemImage: "drop.fill")
                            }
                            Button(role: .destructive) {
                                onToggleSkip()
                            } label: {
                                Label("Not doing this today", systemImage: "xmark.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textDim)
                            .padding(.leading, 4)
                    }
                    .accessibilityIdentifier("session.menu")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(Theme.textDim)
                }
            }

            if block.isSkipped {
                Text("Called off — the day's calories and carbs came down with it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onToggleSkip) {
                    Label("Put it back", systemImage: "arrow.uturn.backward")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.workoutTint)
                }
                .buttonStyle(.pressable)
                .padding(.top, 2)
            } else {
                Button(action: onDetail) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(block.session.minutes) min · \(block.session.intensity.label) · \(block.fuel.burnCalories) cal")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let during = block.duringLine {
                            Label(during, systemImage: "bolt.fill")
                                .font(.caption)
                                .foregroundStyle(Theme.foodTint)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Label(block.hydrationLine, systemImage: "drop.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.waterTint)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint.opacity(block.isSkipped ? 0.05 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(tint.opacity(block.isSkipped ? 0.14 : 0.28))
                )
        )
        .opacity(block.isSkipped ? 0.65 : 1)
    }
}

// MARK: - Small parts

struct TagChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy))
            .kerning(0.6)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.16)))
    }
}

struct AdvisoryRow: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.alcoholTint.opacity(0.10))
            )
    }
}
