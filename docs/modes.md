---
title: Modes
summary: Weight loss or athlete — two different dashboards, two different sets of targets.
---

# Modes

<p class="lede">People use a tracker for genuinely different reasons, and the same dashboard can't serve both. Steady asks which one you are before it asks anything else.</p>

## The question at setup

The first screen of setup asks what you're here for. Your answer decides your dashboard, how your targets are worked out, and which questions the rest of setup bothers you with.

You can switch modes later in **Settings → Mode** without losing anything you've logged.

| | Weight Loss | Athlete |
|---|---|---|
| **Dashboard opens on** | Your weight trend and today's budget | Today's session and the fuel for it |
| **Calories** | Maintenance minus a deficit set by your pace | Maintenance **plus** the day's training |
| **Macros** | A protein target; calories do the rest | Carbs, protein, and fat periodized to the day's load |
| **Hydration** | A flat daily goal | Your measured sweat rate, scaled to the weather |
| **Weight** | The scoreboard | A data point, watched for under-fuelling |
| **Plan** | A weekly grid of workout days | Dated sessions, imported or entered |

## Weight loss mode

Unchanged, and still the default: an adaptive calorie budget, a smoothed weight trend, a streak, and a goal date. See [Your calorie budget](calorie-budget).

## Athlete mode

Built for training for something rather than shrinking.

**Today's session leads.** Imported from [TrainingPeaks](integrations#trainingpeaks) or entered by hand, with carbs-per-hour, fluid, sodium, and estimated burn on the card itself. Tap through for the full before/during/after breakdown.

**Calories start at maintenance and add the training on top.** An athlete eating one fixed number on a rest day and a five-hour day is under-fuelling one of them. Steady is careful not to double-count here: the maintenance figure has training stripped out of it, so each day's sessions can be added back individually.

**Carbs are periodized to the day's load.** Not a fixed macro split — the ISSN and ACSM bands run from about 3.5 g/kg on a rest day to 9 g/kg on a very big one, and the day's classification comes from its TSS when your plan publishes one, or its duration and intensity when it doesn't.

**Protein holds steady** at 1.6–2.0 g/kg, higher on hard days and higher again if you're running a deliberate deficit. **Fat has a floor** — going too low costs hormones and fat-soluble vitamin absorption, so calories give way before fat does.

**Hydration comes from your own sweat rate** once you've run a test, scaled to the local heat index. See [Workouts & fueling](workouts-and-fueling#your-own-sweat-rate).

### Eating at maintenance

Athlete mode defaults to **eat at maintenance**, because under-fuelling is the most common way athletes lose a season.

If you want a body-composition block, turn it off and set a pace — but Steady caps the deficit at **1 lb/week** whatever you ask for, and raises your protein target to 2.0 g/kg. Steeper than that and performance and lean mass go before fat does.

The weight card also watches for this: a sustained drop during a hard training block gets called out, because it usually means under-fuelling before it means progress.

## General health

A separate switch, not a third mode. Turn it on and whichever dashboard you picked also surfaces **fiber, sodium, and added sugar** against sensible daily marks, and blood-work tracking comes along with it.

Useful if you care about more than the number on the scale or the stopwatch. Switchable any time in **Settings → Mode**.

## Cycle tracking

Optional, off unless you ask for it, and offered at setup only when your profile makes it relevant — asked as a genuine question when your profile says *prefer not to say*, rather than assumed either way.

Log the first day of a period and Steady works out where you are: **menstrual, follicular, ovulatory, or luteal**. It learns your cycle length from your own history (recent cycles weighted more heavily, implausible gaps ignored as missed logs) and falls back to a 28-day default until it has two or three to learn from.

What you get from it:

- **Context for the scale.** A jump in the luteal week is usually water, and the app says so instead of leaving you to wonder.
- **A small hydration nudge.** Core temperature runs a touch higher in the luteal phase, so you sweat sooner. It's the one phase effect concrete enough to earn a change to a number rather than just a note.
- **Phase notes that are honest about the evidence.** The research on cycle phase and performance is genuinely mixed and individual variation dwarfs the average effect, so these read as context for your own data, not a prescription.

### Privacy

Cycle data is held to a stricter standard than anything else in the app:

- **Locked behind Face ID**, with your backup PIN as the fallback, alongside your progress photos. It re-locks every time the app leaves the foreground, and the dashboard card shows nothing but the word "Locked" until you unlock it — no phase, no day count, nothing.
- **Stored only on this device.** Never transmitted anywhere, by any feature.
- **Never written to Apple Health**, even with Health sync switched on.
- **Never included in anything sent to an AI** for a nutrition estimate.
- **Switchable off, and erasable for good**, in Settings.

<p class="next">Next: <a href="getting-started">Getting started →</a></p>
