---
title: Workouts & fueling
summary: Building workouts, scheduling your week, and eating around training.
---

# Workouts & fueling

<p class="lede">Building real workouts from an 873-exercise database, putting them on a weekly schedule, and letting that schedule change what you should eat and drink.</p>

## Building workouts

The Workouts tab works in the order you'd expect: build workouts first, then put them on your week.

**Create a workout** with a name, type (strength, cardio, sports, mobility, other), default duration, and whether it's outdoors. Then open it and add exercises from the built-in database — **873 exercises with instructions**, searchable by name, muscle group, and equipment.

Each exercise carries **target sets × reps × weight**. When you train, you log **set by set**, and Steady keeps the history — so next time you open that exercise you can see what you actually lifted last time. That's the entire mechanism behind progressive overload: knowing your last numbers at the moment you need them.

**Starter templates** are there if you don't want to build from scratch — StrongLifts 5×5, Push/Pull/Legs, and Couch-to-5K. Start from one and edit it into whatever you actually do.

As your collection grows, **All Workouts** keeps everything searchable and alphabetized one tap away, so the main screen never turns into a wall.

## The weekly schedule

Put any workout on a day and time and it becomes part of your week. The schedule drives several things at once:

- **Rest days vs. training days.** Workouts only count toward your daily goals on scheduled days; everything else is a rest day and Steady doesn't nag you about it.
- **Your calorie and water targets** for that day (below).
- **Workout reminders**, if you've enabled notifications.
- **Calendar sync.** One tap writes your schedule into your iPhone calendar as weekly repeating events, using EventKit — locally, no server. Re-run it after you change the schedule.

## The fueling engine

This is the part that answers *"I'm riding for two hours tomorrow, what do I actually eat?"* — and it runs entirely on your phone. **No AI, no network.** It's deterministic sports-nutrition math from your workout's type, intensity, duration, and your current bodyweight.

The guidance follows mainstream endurance nutrition (ACSM and ISSN ranges):

| What | Guidance |
|---|---|
| **Carbs during** | Roughly 30–60 g/hr for sessions of 1–2.5 hours, scaling up toward ~90 g/hr beyond that. Zero under an hour — you're running on what's already stored. |
| **Fluids** | 16–24 oz/hr depending on intensity |
| **Sodium** | 300–700 mg/hr on long or hard endurance days |
| **Before** | A light carb top-up ahead of endurance work; a smaller one before lifting |
| **After** | About 1 g/kg bodyweight in carbs to refill glycogen, plus ~0.3 g/kg protein for repair |

**Mid-workout carbs only matter for cardio and sports that run long.** For strength training, mobility, and anything under an hour, the engine tells you so plainly and focuses on what you eat before and after — which is where it actually matters.

Everything scales with your bodyweight and the specific session. A 45-minute easy jog and a three-hour hard ride get genuinely different answers, not the same advice with different numbers.

> It's guidance, not a prescription. Dial it to how you feel — the app says as much on the screen.

## Where fueling shows up

**Today's Fuel card** appears on the dashboard on days with a scheduled workout. It shows carbs-per-hour at a glance for each session; tap one for the full before/during/after breakdown.

**Any day's detail page** shows the same guidance for whatever date you're looking at — so you can open next Saturday's long run and plan for it now, rather than only finding out on the morning.

**Week's Fuel** (Workouts tab) maps the **next seven days** in one screen: what's scheduled each day, carbs during the long sessions, recovery protein, each day's budget adjustment, and which days are rest days. This is the "what does my eating look like this week" view.

**Fuel Calculator** answers the question without touching your schedule at all. Pick a type, intensity, and duration and the plan updates live. Useful for a one-off event, or for sanity-checking a session you're considering.

## Training-day nutrition

A scheduled workout changes that day's targets automatically:

- **Calories go up** by the session's estimated burn, so eating the fuel your training requires doesn't read as going over budget.
- **Water goes up** by the session's fluid guidance, for the same reason.

Both adjustments show on the day, labeled — *"+450 cal · +20 oz water added to today's budget for training"* — so you always know why today's number differs from yesterday's. Nothing changes behind your back.

You can turn this off in Settings if you'd rather hold one flat budget every day.

## Workouts from other apps

Anything written to Apple Health imports automatically — Apple Watch, Garmin Connect, Strava, and anything else that syncs there. Each session imports **once** (Steady remembers the identifier), gets mapped to a workout category, and counts toward your minutes and your streak.

So if you track your runs elsewhere, you don't have to log them twice. See [Integrations](integrations).

<p class="next">Next: <a href="tracking-and-stats">Tracking & stats →</a></p>
