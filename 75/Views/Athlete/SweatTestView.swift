import SwiftUI
import SwiftData

/// The sweat test: a guided version of the standard field protocol, plus the
/// history it builds into a personal sweat rate.
struct SweatTestView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var weather = WeatherService.shared
    let plan: Plan

    @AppStorage(SaltLoss.storageKey) private var saltRaw = SaltLoss.typical.rawValue
    @State private var showAdd = false

    private var salt: SaltLoss { SaltLoss(rawValue: saltRaw) ?? .typical }
    private var tests: [SweatTest] { plan.sweatTests.sorted { $0.date > $1.date } }
    private var profile: SweatProfile? { plan.sweatProfile() }

    var body: some View {
        Form {
            if let profile {
                Section {
                    HStack {
                        Text("Sweat rate")
                        Spacer()
                        Text("\(profile.ouncesPerHour, specifier: "%.0f") oz/hr")
                            .font(.body.weight(.semibold).monospacedDigit())
                    }
                    HStack {
                        Text("Sodium loss")
                        Spacer()
                        Text("\(Int(profile.sodiumMgPerHour.rounded())) mg/hr")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("In litres")
                        Spacer()
                        Text("\(profile.litersPerHour, specifier: "%.2f") L/hr")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    SectionHeader(icon: "drop.fill", title: "Your numbers", tint: Theme.waterTint)
                } footer: {
                    Text("Blended from \(profile.testCount) test\(profile.testCount == 1 ? "" : "s"), weighted toward recent ones and toward sessions like the one being planned. Fueling plans replace their generic fluid guidance with this.")
                }
            } else {
                Section {
                    Text("No tests yet. Until there's one, hydration advice falls back to population averages — and those are wrong for most people by a lot.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    SectionHeader(icon: "drop.fill", title: "Your numbers", tint: Theme.waterTint)
                }
            }

            Section {
                Picker("Sweat saltiness", selection: $saltRaw) {
                    ForEach(SaltLoss.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Text(salt.cue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                SectionHeader(icon: "bolt.horizontal.fill", title: "Salt", tint: Theme.supplementTint)
            } footer: {
                Text("Sweat sodium runs anywhere from 200 to 2000 mg per litre and a lab test is the only way to know exactly. The white-crust tell tracks it well enough to be worth asking. Currently assuming \(Int(salt.sodiumMgPerLiter)) mg/L.")
            }

            Section {
                Button { showAdd = true } label: {
                    Label("Run a sweat test", systemImage: "plus.circle.fill")
                }
                NavigationLink {
                    SweatProtocolView()
                } label: {
                    Label("How to do one", systemImage: "list.number")
                }
            }

            if !tests.isEmpty {
                Section {
                    ForEach(tests) { test in
                        row(test)
                    }
                    .onDelete(perform: delete)
                } header: {
                    SectionHeader(icon: "clock.arrow.circlepath", title: "History", tint: Theme.waterTint)
                } footer: {
                    Text("Tests in different conditions make the estimate better — a cool morning and a hot afternoon tell you more than three identical sessions.")
                }
            }
        }
        .themedForm()
        .navigationTitle("Sweat Rate")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdd) {
            SweatTestSheet(plan: plan, weather: weather.effective)
        }
    }

    private func row(_ test: SweatTest) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(test.date.formatted(.dateTime.month(.abbreviated).day().year()))
                HStack(spacing: 5) {
                    Text("\(test.minutes) min · \(test.intensity.label)")
                    if let conditions = test.conditionsText {
                        Text("· \(conditions)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(test.sweatRateOuncesPerHour, specifier: "%.0f") oz/hr")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(test.isPlausible ? .primary : Theme.danger)
                if !test.isPlausible {
                    Text("not used").font(.caption2).foregroundStyle(Theme.danger)
                } else if test.dehydrationPercent >= 2 {
                    Text("\(test.dehydrationPercent, specifier: "%.1f")% down")
                        .font(.caption2).foregroundStyle(Theme.warn)
                }
            }
        }
    }

    private func delete(_ offsets: IndexSet) {
        let doomed = offsets.map { tests[$0] }
        let ids = Set(doomed.map(\.persistentModelID))
        plan.sweatTests.removeAll { ids.contains($0.persistentModelID) }
        doomed.forEach { context.delete($0) }
        try? context.save()
    }
}

// MARK: - Protocol

struct SweatProtocolView: View {
    var body: some View {
        Form {
            Section {
                step(1, "Weigh yourself right before", "Nude or in minimal dry kit, after using the bathroom. Write it down to the tenth of a pound.")
                step(2, "Train as normal", "Twenty minutes minimum, an hour is better. Any session works, but pick one you do often.")
                step(3, "Track everything you drink", "Every bottle, every sip. This is the number people forget, and it's half the calculation.")
                step(4, "Towel off and weigh again", "Dry skin and hair, same clothes as the first weigh-in. Sweat still on you hasn't left your body's ledger.")
            } header: {
                SectionHeader(icon: "list.number", title: "The protocol", tint: Theme.waterTint)
            } footer: {
                Text("Steady works out the rest: the weight you're missing plus everything you drank is what you sweated, divided by how long you were out.")
            }

            Section {
                Text("Don't eat during the test if you can avoid it — food adds mass the scale can't tell from retained fluid. A bathroom stop mid-session does the same thing in reverse, so note it if it happens.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Repeat it in genuinely different weather. Sweat rate in February and in August are different numbers, and knowing both is what makes the summer advice trustworthy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                SectionHeader(icon: "exclamationmark.circle", title: "Getting a clean number", tint: Theme.warn)
            }
        }
        .themedForm()
        .navigationTitle("Sweat Test")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.gradient))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Entry sheet

struct SweatTestSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let plan: Plan
    let weather: WeatherContext?

    @State private var date = Date()
    @State private var preText = ""
    @State private var postText = ""
    @State private var fluidText = ""
    @State private var minutes = 60
    @State private var category: WorkoutCategory = .cardio
    @State private var intensity: WorkoutIntensity = .moderate
    @State private var tempText = ""
    @State private var humidityText = ""
    @State private var notes = ""

    @FocusState private var focused: Bool

    private var pre: Double? { Double(preText) }
    private var post: Double? { Double(postText) }
    private var fluid: Double { Double(fluidText) ?? 0 }

    /// A live preview of the result, so a fat-fingered weight is obvious
    /// before it's saved rather than after it has skewed the average.
    private var preview: SweatTest? {
        guard let pre, let post, pre > 0, post > 0 else { return nil }
        return SweatTest(date: date, preWeightLbs: pre, postWeightLbs: post,
                         fluidOunces: fluid, minutes: minutes,
                         category: category, intensity: intensity,
                         tempF: Double(tempText), humidityPercent: Double(humidityText))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    field("Weight before", $preText, unit: "lb")
                    field("Weight after", $postText, unit: "lb")
                    field("Fluid drunk", $fluidText, unit: "oz")
                    Stepper("Duration: \(minutes) min", value: $minutes, in: 20...360, step: 5)
                } header: {
                    SectionHeader(icon: "scalemass.fill", title: "The measurements", tint: Theme.waterTint)
                } footer: {
                    Text("Weigh dry both times, in the same clothes. Everything you drank counts — that's what makes this a sweat rate rather than a weight loss.")
                }

                Section("The session") {
                    Picker("Type", selection: $category) {
                        ForEach(WorkoutCategory.allCases) { c in
                            Label(c.label, systemImage: c.icon).tag(c)
                        }
                    }
                    Picker("Intensity", selection: $intensity) {
                        ForEach(WorkoutIntensity.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text(intensity.cue).font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    field("Temperature", $tempText, unit: "°F")
                    field("Humidity", $humidityText, unit: "%")
                } header: {
                    SectionHeader(icon: "thermometer", title: "Conditions", tint: Theme.warn)
                } footer: {
                    Text(weather == nil
                         ? "Optional, but a rate without conditions can't be scaled to a hotter day."
                         : "Pre-filled from current conditions — change them if the session was earlier.")
                }

                if let preview {
                    Section {
                        HStack {
                            Text("Sweat rate")
                            Spacer()
                            Text("\(preview.sweatRateOuncesPerHour, specifier: "%.0f") oz/hr")
                                .font(.body.weight(.semibold).monospacedDigit())
                                .foregroundStyle(preview.isPlausible ? .primary : Theme.danger)
                        }
                        HStack {
                            Text("Body mass lost")
                            Spacer()
                            Text("\(preview.dehydrationPercent, specifier: "%.1f")%")
                                .foregroundStyle(preview.dehydrationPercent >= 2 ? Theme.warn : .secondary)
                        }
                        if !preview.isPlausible {
                            Text("That works out to \(preview.sweatRateLitersPerHour, specifier: "%.1f") L/hr, which is outside what a human does — check the weights and the duration.")
                                .font(.caption)
                                .foregroundStyle(Theme.danger)
                        } else if preview.dehydrationPercent >= 2 {
                            Text("Over 2% down is where endurance performance measurably suffers. Worth drinking more during sessions like this one.")
                                .font(.caption)
                                .foregroundStyle(Theme.warn)
                        }
                    } header: {
                        SectionHeader(icon: "function", title: "Result", tint: Theme.accent)
                    }
                }

                Section("Notes") {
                    TextField("Anything unusual about the session", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }
            }
            .themedForm()
            .navigationTitle("Sweat Test")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(preview == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
        .themedRoot()
        .onAppear {
            if let weather {
                if tempText.isEmpty { tempText = String(Int(weather.tempF.rounded())) }
                if humidityText.isEmpty {
                    humidityText = String(Int(weather.humidityPercent.rounded()))
                }
            }
            if preText.isEmpty { preText = String(format: "%.1f", plan.currentWeight) }
        }
    }

    private func field(_ label: String, _ text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("–", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .focused($focused)
            Text(unit).foregroundStyle(.secondary).font(.caption)
        }
    }

    private func save() {
        guard let pre, let post else { return }
        let test = SweatTest(date: date, preWeightLbs: pre, postWeightLbs: post,
                             fluidOunces: fluid, minutes: minutes,
                             category: category, intensity: intensity,
                             tempF: Double(tempText),
                             humidityPercent: Double(humidityText),
                             notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty ? nil : notes)
        plan.sweatTests.append(test)
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
