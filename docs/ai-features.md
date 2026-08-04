---
title: AI features
summary: What the AI does, how to use your own Gemini key, and exactly what leaves your phone.
---

# AI features

<p class="lede">Steady uses Google Gemini for the parts of tracking that are genuinely tedious — turning a sentence, a photo, or a recipe link into real numbers. Here's what it powers, and exactly what leaves your phone.</p>

## What the AI does

| Feature | What you give it | What you get back |
|---|---|---|
| **Describe Your Meal** | A typed or spoken sentence | Every component as its own item, with nutrition and portion assumptions |
| **Photo of Food** | A photo of the plate | The same, read from the image |
| **Recipe from a Link** | A recipe URL or YouTube link | The whole recipe broken into ingredients, plus a servings count |
| **Estimate Nutrition** | A food name with no database match | A full nutrition panel |
| **Missing protein fill-in** | A food logged without protein data | A protein estimate for that item |
| **What Should I Eat?** | Nothing — it reads your day | Three realistic options that fit your remaining calories and protein gap |
| **Summarize My Day / Week in Review** | Nothing — it reads your log | A review with concrete substitutions |

Everything else in Steady — the calorie budget, weight trends, streaks, fueling math, patterns, stats — is **plain arithmetic running on your phone**. No AI involved, no network needed.

## Using your own key

Steady's AI works as soon as you install it, with no setup. But **adding your own free Gemini key is recommended**, and takes about a minute:

1. Go to **[aistudio.google.com/apikey](https://aistudio.google.com/apikey)** and sign in with a Google account.
2. Tap **Create API key**.
3. Copy it.
4. In Steady: **Settings → AI & Estimates**, paste it into the key field.

The app has this guide built in, with a button that opens the right page directly — **Settings → AI & Estimates → How to get a free key**.

**Why bother?** Two reasons. You get your own rate limits rather than sharing a pool, so estimates stay fast when lots of people are using the app at once. And your food descriptions go to Google under *your* account rather than someone else's.

Google's free tier is generous — normal food logging won't come close to the limits. A key you enter always overrides the built-in one, and you can clear it any time to go back.

### Fast vs. accurate

**Settings → AI & Estimates** has a *Higher accuracy* toggle:

- **Off** (default) — a lighter model that answers in about a second, with a higher free-tier rate limit. Fine for the vast majority of meals.
- **On** — the fuller model. Slower and more rate-limited, but noticeably better on complicated plates with a lot of components.

Recipe imports always use the fuller model regardless of the toggle, since reading a recipe is an occasional get-it-right action rather than something you do ten times a day.

## What actually leaves your phone

Only what a specific AI feature needs, only when you tap the button that uses it:

**Sent to Google:**
- The meal text you typed or dictated
- The food photo you took, when you use Photo of Food
- The URL you pasted, when you import a recipe
- For coaching features, the day's food names and totals
- If blood work is enabled, the bare marker numbers — nothing identifying

**Never sent anywhere:**
- Your weight, weight history, or goals
- Progress photos
- Your name, email, or any identifier — there isn't an account to identify you with
- Steps, sleep, or anything else from Apple Health
- Your location
- Anything at all, if you never use an AI feature

Requests go **directly from your phone to Google's API**. They don't pass through any server belonging to Steady, because there isn't one. Nobody but you and Google sees them, and Google's handling is governed by the [Google APIs Terms](https://developers.google.com/terms) and [Privacy Policy](https://policies.google.com/privacy).

## Seeing the prompts yourself

**Settings → AI & Estimates** lists every AI feature and shows you the **verbatim prompt** it sends, with your input rendered as `‹placeholders›`. Nothing is paraphrased for the settings screen — it's the actual text.

If you want to know what the app says about you before it says it, that screen is the answer, and it's worth two minutes of reading.

## When the AI is wrong

It sometimes will be. Portion size is the usual culprit — "a bowl of pasta" spans a 400-calorie range, and the model has to pick one.

Steady is built around that rather than pretending otherwise:

- **Every item shows its assumption** — "assumed 2 cups, ~250 g" — so you can see what it guessed.
- **Every number is editable** before it lands in your day, and after.
- **The grounding badge** tells you whether the numbers came from a real lookup or an estimate.
- **Items are separate**, so fixing the rice doesn't mean rebuilding the whole plate.

And a wrong estimate matters less than it feels like it should. The [adaptive budget](calorie-budget) learns from the relationship between your logging and your actual weight trend — so if you consistently under-log by 10%, Steady works out that your real burn rate is lower than the formula says and adjusts your budget to compensate. Consistency beats precision.

<p class="next">Next: <a href="workouts-and-fueling">Workouts & fueling →</a></p>
