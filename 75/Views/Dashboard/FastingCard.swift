import SwiftUI

/// Dashboard fasting timer (opt-in, Settings → Fasting). The clock anchors
/// to the last logged food, so logging meals is the only "tracking" needed.
struct FastingCard: View {
    let plan: Plan

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Card(title: "Fasting", icon: "timer", tint: Theme.sleepTint) {
                if let status = Fasting.status(plan: plan, now: context.date) {
                    content(status: status, now: context.date)
                } else {
                    Text("Log a meal and the fasting clock starts from your last food of the day.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    @ViewBuilder
    private func content(status: Fasting.Status, now: Date) -> some View {
        let fasted = status.fastedHours(at: now)
        let target = Double(Fasting.targetHours)
        let reached = fasted >= target

        HStack(alignment: .firstTextBaseline) {
            Text(hm(fasted))
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("fasted")
                .foregroundStyle(Theme.textDim)
            Spacer()
            Text(reached ? "goal hit 🎉" : "goal \(Fasting.targetHours) h")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(reached ? Theme.accent : Theme.textDim)
        }

        GradientBar(value: fasted / max(1, target))

        HStack {
            Text("Last food \(status.lastFood.formatted(date: .omitted, time: .shortened))")
            Spacer()
            if let opened = status.firstFoodToday {
                Text("Window opened \(opened.formatted(date: .omitted, time: .shortened))")
            } else if !reached, let eta = Calendar.current.date(
                byAdding: .minute, value: Int((target - fasted) * 60), to: now) {
                Text("\(Fasting.targetHours) h at \(eta.formatted(date: .omitted, time: .shortened))")
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.textDim)
    }

    private func hm(_ hours: Double) -> String {
        let totalMinutes = Int(hours * 60)
        return "\(totalMinutes / 60)h \(totalMinutes % 60)m"
    }
}
