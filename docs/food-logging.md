---
title: Food logging
summary: Six ways to log a meal, the nutrition panel, density colors, and the daily report.
---

# Food logging

<p class="lede">Six ways to get a meal into the day, what Steady records about it, and how it grades what you ate.</p>

Food is logged into **meals** — breakfast, morning snack, lunch, afternoon snack, dinner, and dessert — which default to whatever fits the current time of day. Every meal rolls up into whole-day totals.

## The six ways in

| Path | What it does | Best for |
|---|---|---|
| **Describe Your Meal** | Type or dictate a sentence; AI itemizes every component separately with a portion assumption for each | Home cooking, restaurant meals, anything without a label |
| **Photo of Food** | Photograph the plate and AI reads it into separate items | When describing it is more work than shooting it |
| **Recipe from a Link** | Paste a recipe page or YouTube URL; reads the ingredients into items with a servings stepper | Cooking from a recipe you found online |
| **Barcode scan** | Crosshair reticle that reads only inside the frame | Packaged food |
| **Database search** | Live search of Open Food Facts (~3 million products, US-first, relevance ranked) | Branded items without the package handy |
| **Saved Meals / Quick Log / Custom** | Re-log a whole saved combo, a starred or recent food, or type the numbers yourself | The things you eat constantly |

The first three are covered in detail on the [AI features](ai-features) page, including exactly what gets sent.

### Describe Your Meal

Type or hit the microphone and say it: *"two eggs, sourdough toast with butter, and a flat white."* You get back four separate line items — not one lump called "breakfast" — each with its own calories, protein, full nutrition panel, and a note about the portion it assumed.

Every item is editable before it lands in your day, and you can swipe away anything you didn't actually eat.

### Recipe from a Link

Paste a recipe website or a YouTube cooking video. Steady reads the ingredient list — for videos, it uses the description and top comments too, since that's usually where exact quantities end up — and breaks the **whole recipe** into ingredients with nutrition for each.

Then it asks the question that actually matters: **how many servings did you eat?** The recipe knows roughly how many it makes, and a stepper scales every number to the fraction you're logging. Cook a pot of chili, log one bowl, come back tomorrow and log another.

If a link can't be read — short-form video is hit-or-miss — Steady says so rather than inventing numbers.

## What gets recorded

Every logged food carries a **full nutrition panel**, not just calories and protein:

carbohydrates · fat (including saturated and trans) · cholesterol · sodium · fiber · sugars (including added) · potassium · calcium · iron

**Portion steppers are everywhere.** Change the portion and every number scales with it — you never rebuild an entry because you had one and a half servings.

**Everything stays editable.** Tap any logged food to fix its name, move it to a different meal, change the portion, or correct a single nutrient by hand. Swipe to delete. Changes save immediately.

## Calorie-density colors

Every food gets a colored dot, computed locally from calories ÷ grams:

- 🟢 **Green** — under 1 cal/g. Vegetables, fruit, broth soups, most lean protein. Physically filling for very few calories.
- 🟠 **Orange** — 1 to 2.4 cal/g. Most cooked dishes, bread, lean meats.
- 🔴 **Red** — above 2.4 cal/g. Oils, nuts, cheese, chocolate, most snack food. Easy to eat a lot of calories without noticing.

This isn't a moral ranking — olive oil and almonds are red — it's a volume signal. When you're hungry all afternoon on the same calories, the fix is usually shifting the mix greener, not eating less.

## The Nutrition Report

Beyond the daily rings, Steady grades the day properly:

- **Macro split** — how your calories divided across protein, carbs, and fat
- **Keep under** — sodium, saturated fat, added sugar against FDA reference limits
- **Get enough** — fiber, protein, potassium, calcium, iron against daily goals
- **Density mix** — how much of the day was green, orange, and red
- **Per-meal breakdown** — where the calories actually went

If you've opted into [blood work tracking](tracking-and-stats), the relevant limits tighten to match the markers you're trying to move.

## Grounding badge

AI estimates run with Google Search enabled, so named restaurant items and branded products get checked against published nutrition rather than guessed at. A badge tells you which happened:

- **Looked up** *(green)* — the numbers came from a real source it found
- **Best guess** *(orange)* — it estimated from what the food is made of

A best guess is still useful. It just deserves more skepticism, and it's a hint that a quick portion edit might be worth your time.

<p class="next">Next: <a href="ai-features">AI features →</a></p>
