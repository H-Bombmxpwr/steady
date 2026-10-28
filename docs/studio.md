---
title: The Studio
summary: Your buddy, notes, records, the tour, the shop, and the mealtime check-ins — what you earn, and why it's built this way.
---

# The Studio

<p class="lede">Weight-loss mode comes with a small music studio and a buddy who runs it. Logging fills it with gear, and losing weight fills its walls with real albums. Nothing here can be lost, and nothing here is AI.</p>

## Why it exists

A trend line that moves a tenth of a pound a day is honest, but it's not much of a reason to open an app on a Tuesday. The Studio borrows what works in cozy habit apps like Focus Friend and Finch: a creature whose world grows because of what *you* did, a currency for the behavior, and a shop to spend it in. It points all of that at two things the weight-loss research keeps finding matter most: **self-monitoring** (weighing in and logging food) and **coming back after a bad day**.

So the rules are:

- **Rewards come from logging, not from the scale.** A day's weight is mostly water. Paying out on it would punish an honest weigh-in after a salty dinner.
- **Weight loss pays through the smoothed trend only,** and only for new lows. A bounce up can't take anything back.
- **The game ends at your goal weight.** Not on a date, and not because you saved up. Progress toward the goal is what unlocks everything, so the last of it opens the day the trend gets there.
- **What you eat matters, not just how much.** Healthy food makes your buddy thrive and the studio earn more. Junk makes it sick and earnings drop.
- **Nothing is ever lost.** No dying pet, no shrinking balance, no streak shame. Miss a week and your buddy is just glad you're back.
- **The buddy isn't an AI.** Every line is written by hand and filled in with your own numbers, so what it says is always true.

## Your buddy

You pick one during setup: penguin, owl, otter, hedgehog, black cat, or chipmunk. Then you name it. You can change the look or the name any time from the studio's **Buddy** tab: tap the studio's name on the dashboard, or go through **Settings → Studio & Music**. Your records, gear, notes, and tour all stay.

The buddy's mood follows your day. It waits by the scale in the morning, looks at an empty plate if nothing's logged by lunch, sparkles when the sound check is mostly done, and celebrates a new low. Tap it and it hops. If the food's been heavy lately, it looks unwell: a little green, slower, and with a thermometer.

**App icon.** Any of the six buddies can be your home-screen icon: use **Buddy → Use as app icon** in the Studio, or **Settings → Appearance → App Icon**. If your icon is a buddy and you change the look, the icon follows.

## The idle game

The studio earns **notes ♪** on its own, around the clock, Cookie Clicker-style. You buy **promo**: busking, open mics, radio play, playlists, a tour bus, arena shows, a label deal, and finally a world tour. Each one pays notes per second, and every copy costs 15% more than the last.

What makes it a weight-loss game rather than a waiting game is everything multiplied on top:

| Multiplier | Range | Comes from |
|---|---|---|
| **Progress** | ×1 → ×20, then ×40 at the goal | How far your trend weight has got from your starting weight toward your goal |
| **Health** | ×0.5 → ×1.5 | The quality of the food you've logged this week (see below) |
| **Hype** | up to ×1.4 | +5% for each sound-check item done today; resets at midnight |
| **Collection** | grows | +3% per piece of gear, +10% per bandmate |

Every multiplier is shown in full on the **Promo** tab, so you can always see which one is yours to move.

**The jar.** Earnings collect in a royalty jar that fills for 12 hours, then stops. Tap **Collect** on the dashboard to empty it. Twelve hours covers a night's sleep, so opening the app once or twice a day keeps nothing wasted.

**It's weight that moves it, not time.** Generators unlock at fractions of the way to your goal, and the World Tour only at the goal itself. Each generator is also capped: 10 copies at the start, rising to 100 at the goal. If the trend stops moving, so does the studio. Within what you've unlocked, each copy costs more and pays the same, and the cap stops it outright. Nobody can buy their way to the end. Everyone gets there by reaching their goal weight.

### The sound check

Logging is the boost. Each item pays a slice of the studio's current output, or a small flat amount early on, whichever is bigger. That keeps logging worth doing at every stage, instead of turning into pocket change:

| Item | Pays |
|---|---|
| Weigh in | 30 min of output |
| Log a food | 15 min |
| Log 3 meals | 30 min |
| Under budget *(once 3 meals are logged)* | 20 min |
| Hit protein | 20 min |
| Hit water | 10 min |
| Move *(any workout)* | 20 min |
| Progress photo | 10 min |

Each item also adds 5% hype for the rest of the day. *Under budget* waits for three meals on purpose: breakfast alone is always under budget, and rewarding that would reward logging less.

**Extras:** a **daily gift** once you've logged anything (10–60 minutes of output, sometimes a whole record), streak milestones (3, 7, 14, 30… days), and a head start of 60 notes on day one.

## Health

Your buddy's health follows **what you eat**, not how much:

- Each food scores by **calorie density**, the same green/orange/red the app already shows. Green (under 1 kcal/g) scores high and red (over 2.4) low. Fiber nudges it up and added sugar pulls it down.
- A day's score is **weighted by calories**, so a side salad can't launder a large pizza. Drinks pull it down a little.
- Health is a moving average over the last week of logged days. It starts at neutral, one heavy dinner dents it, and a bad week makes your buddy **sick**.

| Health | Multiplier | Looks like |
|---|---|---|
| Thriving | up to ×1.5 | 🥰 |
| Healthy | ~×1.2 | 🙂 |
| Okay | ~×1.0 | 😐 |
| Queasy | ~×0.8 | 🤢, and a little green |
| Sick | down to ×0.5 | 🤒, washed out and slow |

A sick buddy halves the studio's earnings, but never takes anything away: notes, gear, and records are safe. Good food brings it back about as fast as bad food brought it down.

## Records

Every **new 1 lb low on your trend weight** earns a record: a real album with its cover art and a 30-second preview, courtesy of Apple Music. Records go up around the studio, framed on the walls first, then leaning on the shelf and the floor, then into the crate. Tap one, or the turntable, to play it. Your buddy and any bandmate dance while it spins.

You can also buy a record for 200 notes.

### Spotify (optional)

Link Spotify and the records you earn come from what you actually listen to. Albums you've saved but rarely play come first. Your **most-played album** is held back as the prize for finishing a tour. Link it in **Studio → Records → Link Spotify**, or from **Settings → Studio & Music**.

Spotify requires an app registration before anyone can sign in. If the app doesn't already have a Client ID built in, the Records tab walks you through creating one:

1. At **developer.spotify.com**, open the Dashboard and create an app.
2. Add `seventyfive://spotify-callback` as a Redirect URI and tick **Web API**.
3. Under **User Management**, add the email of each Spotify account that will sign in. Apps in development mode allow up to 25.
4. Paste the app's **Client ID** into Steady.

Steady reads only your top tracks and saved albums, and never writes anything back. Spotify no longer gives new apps preview audio, so previews always play through Apple Music.

## The tour

The distance from where you started to your goal weight is split into **ten tracks**: a tenth of the distance each. That's 1.5 lb a track with 15 to lose and 5 lb a track with 50, so everyone unlocks the same things on the way. Finishing a track pays six hours of output and unlocks gear you can't buy: a studio mic, a fader, a mirror ball, a saxophone, a mixing desk, a keyboard, a wall star, and a gold medal. Reaching your goal finishes the tour and unlocks the **Tour Trophy**. Tracks are judged on your trend's best point, so a rebound never un-finishes one.

**Fresh start.** If your trend climbs above where the tour began, the Tour card offers to start a new tour from today's weight. You keep everything you've earned, and the next track is close again instead of behind a hill. People are measurably more likely to try again at a clean starting line, and this gives you one whenever you need it.

## The shop

Tap the studio's name (✏️) or the room itself. **Gear** opens first. Gear goes in a spot in the room: speakers, desk, instrument, ceiling, wall, shelf, corner, walls, floor, and a **bandmate**. Owning more than one thing for a spot lets you swap.

The catalog is split into ten tiers, and **tier *t* unlocks at *t*/9 of the way to your goal**. Locked items show the trend weight that opens them. Prices climb with the studio's output, so each tier costs roughly a day of earnings at the point it opens. The top tier, the last bandmates, opens only at the goal. There's also a **Today's pick** at 40% off that changes daily.

**Bandmates** are the long game: ten animals, from Shelly the snail (tour manager) to Monty the peacock (frontman). One plays along beside your buddy.

**Records and Encores** never run out, so they're priced in hours of output (3 hours for a record, 1½ for an Encore). There's always something to spend on. **Encores** (hold up to two) cover a missed day automatically, so a streak survives a bad day.

### Does it really end at the goal?

Yes, at any size of goal. Everything is measured as a fraction of the way from start to goal, so 15 lb and 100 lb play the same game. Only the pace differs. The economy was simulated against people reaching their goal in 2, 4, 6, and 12 months. Each maxed out the room within a day of reaching their goal weight, and none of them could finish before it. A simulated person whose weight stalled at 30% of the way saw their earnings go completely flat for seven months. A person who never lost weight topped out at 18 notes a second with most of the studio locked.

## Home-screen widget

In weight-loss mode, the home-screen **Today** widget becomes your buddy's dashboard. It shows your buddy and how it's feeling, your notes, what the studio's earning per second, the jar, and your records. The large size adds your track and progress toward the goal, as a percentage, never your weight. Three buttons sit along the bottom: **Food** opens food logging, **Weight** opens a one-number weigh-in, and **Studio** opens the shop. Whatever you log there pays out the moment you close it.

## Mealtime check-ins

Like BeReal, but for meals. At each of your scheduled meal times (from **Settings → Meal schedule**), your buddy appears on the Lock Screen with a countdown until that meal is logged. It's not a notification you swipe away. It just stays there until you log.

- **Mealtime widget.** Add it to the Lock Screen (rectangular, circular, or inline) or the Home Screen. It flips at each meal time on its own: *Lunch time · 1:12:40 to log*, then *Lunch logged ✓ · Next: Dinner 6:30*. Tapping it during a meal opens food logging.
- **Live Activity.** The same check-in on the Lock Screen and in the **Dynamic Island**, with your buddy, the countdown, and today's calories, protein, and water. It's on by default, and you can turn it off with **Settings → Appearance → Mealtime Live Activity**.

Each meal's window is 90 minutes, or until the next meal if that's sooner. Logging late still counts, and the buddy says so.

*How it works without a server:* iOS lets a Live Activity mark itself "stale" at a set time. Steady sets that time to your next meal, so lunch arriving flips the Live Activity into the prompt with no push and no notification. The widget does the same with a timeline entry at every window edge. One limit: iOS ends a Live Activity after 8 hours, so Steady restarts it whenever you open the app.

<p class="next">Next: <a href="workouts-and-fueling">Workouts & fueling →</a></p>
