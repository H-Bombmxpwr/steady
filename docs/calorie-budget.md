---
title: Your calorie budget
summary: How Steady sets your daily calories, learns your real burn rate, and tracks weight.
---

# Your calorie budget

<p class="lede">Where your daily calorie number comes from, how Steady corrects it from your own results, and why the weight chart shows a trend instead of your actual weigh-ins.</p>

## The starting estimate

On day one Steady has nothing to go on but arithmetic, so it uses the standard approach:

1. **Mifflin-St Jeor** turns your age, height, weight, and sex into a **basal metabolic rate** — what you'd burn lying in bed all day.
2. Your **activity level** multiplies that into a **total daily energy expenditure (TDEE)** — what you burn living your life.
3. Your **goal pace** subtracts from it. Losing a pound a week means a deficit of roughly 500 calories a day, since a pound of fat stores about 3,500 calories.

That gives your daily budget. It is an educated guess, and for a lot of people it's wrong by several hundred calories in one direction or the other — which is exactly why Steady doesn't stop there.

## Adaptive TDEE — learning your real burn rate

This is the part that makes the number yours. Once you have **14 or more days of logged food** and **14 or more days of weigh-ins**, Steady starts checking its own homework:

> If you averaged 2,100 calories a day and your weight trend dropped 1.2 lb over that stretch, then you actually burned about 2,100 + (1.2 × 3,500 ÷ days) per day — no matter what the formula predicted.

It compares that observed burn against the formula's guess and blends the two:

- **Trust grows with logging.** The more consistently you log, the more weight the observed number carries.
- **The formula keeps a 20% anchor.** Even with months of data, the equation never drops out entirely — it's a guardrail against a stretch of sloppy logging dragging the estimate somewhere silly.
- **The observed value is clamped** to a physiologically sane range, so one bad week (a salty holiday, a stomach bug, a broken scale) can't blow up your budget.

**It never changes silently.** Settings shows the learned value and the formula value side by side, so you can always see what Steady thinks you burn and how far that is from where it started. If you'd rather it didn't adapt at all, you can turn it off.

### Why it needs two weeks

Weight moves for reasons that have nothing to do with fat: sodium, carbohydrate stores, hydration, and hormones can swing the scale several pounds in either direction inside a single week. Over two weeks or more, those swings mostly cancel out and the underlying trend shows through. Correcting your budget from three days of data would mostly be chasing water.

## The weight trend

Steady charts two things: your **actual weigh-ins** as individual dots with a thin connecting line, and a thicker **trend line** that smooths them.

The trend uses an exponentially weighted moving average — recent weigh-ins count more than older ones, but no single morning can yank the line. This is the number Steady uses for everything: your headline weight, the adaptive TDEE math, and your projected goal date.

The practical upshot: **you can weigh yourself every day without the daily noise messing with your head.** A morning that's up two pounds barely moves the trend, because the trend already knows what the last two weeks looked like.

Other things on the chart:

- **Goal line** with its label, plus a *Hide goal line* toggle. Hiding it re-fits the vertical axis to just your own data, which makes progress far easier to see when the goal is still a long way off.
- **Projected goal date**, extrapolated from your current trend rather than your intended pace — so it tells you when you'll actually get there at the rate you're actually going.

## Protein, water, and training days

Your budget is three numbers, not one:

- **Calories** — from the math above.
- **Protein** — set high on purpose. Eating enough protein in a deficit is what preserves muscle while you lose fat, and it's the most filling macronutrient per calorie.
- **Water** — your hydration goal, logged in whatever bottle size you set.

On days with a **scheduled workout**, Steady adjusts both the calorie and water targets upward to cover the session, so eating and drinking what training requires doesn't read as going over. That math is explained in [Workouts & fueling](workouts-and-fueling).

## Changing your goals

Everything is editable at any time in **Settings** — goal weight, pace, protein target, water target. Changing a goal recalculates your budget going forward and **never rewrites your history**; past days stay exactly as you logged them, judged against the targets that were in effect at the time.

## The streak

The dashboard flame counts **any day you logged something** — food, water, weight, a workout, or a photo. The point is showing up, not perfection.

If you'd rather hold yourself to the harder standard, **strict streak** mode only counts days where you actually met the day's goals. You can switch modes during onboarding or in Settings.

Either way the streak is **recomputed from your data every time**, never stored as a counter. That means backfilling works: open the Calendar tab, tap a day you missed, log anything, and the streak reconnects retroactively. Forgetting to open the app isn't the same as not doing the work.

<p class="next">Next: <a href="food-logging">Food logging →</a></p>
