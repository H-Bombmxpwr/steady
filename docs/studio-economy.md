---
title: Studio economy simulations
summary: Progression rules, reproducible Swift simulations, and balance results.
---

# Studio economy and journey simulations

## Intent

Fix the weight-loss idle-game audit: spread meaningful purchases through the
journey, reward continued logging during plateaus, make the first session useful,
remove incentives to undereat or omit food, fix goal editing and offline income,
and support affordable recurring purchases. Validate real journeys for 100 lb,
50 lb and less than 15 lb goals, including imperfect attendance.

## Rules

- Weight tracks remain ten equal parts of a tour, with exclusive gear and a goal
  trophy. Weight rewards stop at the tour goal. Existing purchases survive.
- A tour captures its start, goal and date. Editing the plan in Settings changes
  nutrition planning, not the active studio tour. Explicitly starting a new tour
  uses the current trend and new goal, resets weight progress, and retains notes,
  generators, gear, records and logging days. Legacy states capture their goal
  on first sync; old unanchored progress fractions are recomputed from history.
- Any three sound-check actions (excluding the retrospective calorie reward)
  earn a distinct logging day. Days need not be consecutive. Each seven days
  unlocks another shop tier and earns a record. Weight progress can open tiers
  sooner. Studio progress is max(weight progress, logging days / 63), capped at
  one. Weight trophies cannot be earned by waiting or logging alone.
- Explicit item tiers replace sorting by price. Tier 1 contains the first
  bandmate, with more at every subsequent tier. Coffee costs 30 notes so the
  initial 60 buys both it and a 15-note busker. The shop guides that first purchase.
- Gear prices are fixed at 2–4 hours of a reference studio at the tier's unlock.
  The reference uses unlocked generators at the current cap, the progress
  multiplier and a 1.5 allowance for other multipliers. This is a calibration
  reference, not a promise about a player's actual waiting time.
- The jar holds 24 hours. Its saved rate applies prospectively; rate changes
  settle old earnings without resetting the cap. Hype expires at local midnight.
  The widget uses the same saved ledger. Legacy jars have no saved rate history;
  their first migration necessarily estimates using the then-current rate.
- Nutrition adds 0–25%, never a penalty or sickness. Half the bonus comes from
  logged protein relative to the existing protein target, half from logged fiber
  up to 20 g. The fiber threshold is a game-bonus threshold, not personal medical
  advice. Missing nutrition data yields no bonus; calorie density has no role.
  Completed logged days in the prior week determine the bonus.
- The former "Under budget" reward is now "Yesterday on target": a completed
  day with three logged meals and calories in 90–110% of the target. This range
  is reward design, not a prescription. Today's partial intake cannot earn it.
  Logging and weekly progression remain available outside this range.
- Records cannot be bought. Weekly earned records continue indefinitely.

## Validation

Run the Swift tests against the actual app store and pricing functions:

```sh
./scripts/test-studio-economy.sh 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```

The tests use an in-memory store and controlled clock, so no real user defaults,
widgets, music services, health data or network services are touched. The app and
widget are compiled by Xcode. Journey simulations print `JOURNEY` table rows.

Each journey has daily ±0.6 lb deterministic weight noise around a specified
weight trajectory, calendar-day visits, actual food logs, actual sync and jar
collection, purchases, gifts, weekly records, tour and streak awards. The store
is encoded and decoded every 30 days to exercise relaunches. Shopping allocates
50% of available notes to the best affordable generator return, then buys
unlocked gear; the irregular-logging scenario uses 25%. Daily deals are not assumed.
Two-visit players log at their final visit. Non-logging days still include a visit;
separate ledger tests verify the offline cap and rate transitions.

Assertions cover an immediate decoration, first bandmate by day 9 for daily
logging, completion of purchasable gear by day 90 (120 with imperfect logging),
continued rewards through plateaus, no weight trophy without weight loss,
affordable repeat records, finite nonnegative balances, goal edits, migrations,
reward idempotency, nutrition conditions, midnight and rate-change accounting.

These are deterministic balance checks, not clinical predictions or evidence of
retention. This design deliberately allows the purchasable room to finish before
a long weight journey; tour exclusives, the trophy, albums and recurring weekly
rewards continue afterward. A nine-week shop does not provide years of new room
art. Additional cosmetic seasons would need separate content and validation.

## Results

Initial production-store simulation results (zero-based days, so day 0 is the
first session). All nine scenario runs passed their balance assertions:

| Scenario | First decoration | First bandmate | Shop complete | Trend goal reached | Longest reward gap |
| --- | ---: | ---: | ---: | ---: | ---: |
| 100 lb, 1 lb/week | 0 | 7 | 63 | 704 | 7 days |
| 50 lb, 1 lb/week | 0 | 7 | 63 | 355 | 7 days |
| 12 lb, 0.5 lb/week | 0 | 7 | 63 | 173 | 7 days |
| 5 lb, 0.5 lb/week | 0 | 7 | 63 | 75 | 7 days |
| 50 lb, eight-week plateau | 0 | 7 | 63 | 411 | 7 days |
| 100 lb goal, no weight loss | 0 | 7 | 63 | Never | 7 days |
| 50 lb, logging five days/week, 25% promo spend | 0 | 9 | 86 | 361 | 7 days |
| 12 lb, once-daily visit | 0 | 7 | 63 | 173 | 7 days |
| 12 lb, twice-daily visits | 0 | 7 | 63 | 173 | 7 days |

A reward event means a generator purchase, gear purchase, or record entitlement;
it does not count merely accruing currency. Goal dates reflect the actual
smoothed trend with deterministic weight noise. They are simulated dates,
not promised weight-loss timelines.

## Review and verification

The full Xcode suite passed: 157 unit tests and 13 UI tests. Standards review
found no documented-standard violations; its ledger encapsulation suggestion
and collection-assertion finding were addressed. Spec review found one misleading
"any three" label, now explicitly limited to today's seven actions. The widget
also labels studio progress separately from tour weight progress.

The final focused rerun passed 38 unit tests and the weight-loss dashboard UI
test, including a widget-ledger parity test and real pre-collection balance
assertions in every journey.
