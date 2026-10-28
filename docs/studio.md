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
- **Nothing is ever lost.** No dying pet, no shrinking balance, no streak shame. Miss a week and your buddy is just glad you're back.
- **The buddy isn't an AI.** Every line is written by hand and filled in with your own numbers, so what it says is always true.

## Your buddy

You pick one during setup: penguin, owl, otter, hedgehog, black cat, or chipmunk. Then you name it. You can change the look or the name any time by tapping the studio's name on the dashboard, or from **Settings → Studio & Music**. Your records, gear, notes, and tour all stay.

The buddy's mood follows your day. It waits by the scale in the morning, looks at an empty plate if nothing's logged by lunch, sparkles when the sound check is mostly done, and celebrates a new low. Tap it and it hops.

**App icon.** Any of the six buddies can be your home-screen icon: use **Buddy → Use as app icon** in the Studio, or **Settings → Appearance → App Icon**. If your icon is a buddy and you change the look, the icon follows.

## Notes ♪ — the sound check

Each day has a checklist. Every item pays notes the moment the log shows it:

| Item | Notes |
|---|---|
| Weigh in | 10 |
| Log a food | 10 |
| Log 3 meals | 15 |
| Under budget *(once 3 meals are logged)* | 10 |
| Hit protein | 10 |
| Hit water | 5 |
| Move *(any workout)* | 10 |
| Progress photo | 5 |

That's up to **75 a day**. Notes are worked out from your log, not stored, so editing a past day updates its notes and the two can never disagree. *Under budget* waits for three meals on purpose: breakfast alone is always under budget, and rewarding that would reward logging less.

**Extras:** a **daily gift** once you've logged anything (10–40 notes, sometimes a whole record), streak milestones (3, 7, 14, 30… days), and a head start of 60 on day one.

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

The distance from where you started to your goal weight is split into **tracks of 5 lb**. Finishing a track pays 100 notes and unlocks gear you can't buy: a studio mic, a fader, a mirror ball, a saxophone, a mixing desk, a keyboard, a wall star, and a gold medal. Reaching your goal finishes the tour and unlocks the **Tour Trophy**. Tracks are judged on your trend's best point, so a rebound never un-finishes one.

**Fresh start.** If your trend climbs above where the tour began, the Tour card offers to start a new tour from today's weight. You keep everything you've earned, and the next track is 5 lb away again instead of behind a hill. People are measurably more likely to try again at a clean starting line, and this gives you one whenever you need it.

## The shop

Tap the notes badge or the room itself. Gear goes in a spot in the room: speakers, desk, instrument, ceiling, wall, shelf, corner, walls, floor, and a **bandmate**. Owning more than one thing for a spot lets you swap.

There's a **Today's pick** at 40% off that changes daily. **Bandmates** are the long game: ten animals, from Shelly the snail (tour manager) to Monty the peacock (frontman), at 450–1,600 notes each. One plays along beside your buddy.

**Encores** (120 notes, hold up to two) cover a missed day automatically, so a streak survives a bad day.

### Is there enough to earn?

The shop holds about **17,700 notes** of gear. Steady logging is around 50 notes a day, and gifts, milestones, pounds, and tracks add roughly 5,000 more over six months. That's about 13,000 in six months: most of the shop, with the last bandmates still to come. Records and Encores never run out, so notes always have somewhere to go.

## Mealtime check-ins

Like BeReal, but for meals. At each of your scheduled meal times (from **Settings → Meal schedule**), your buddy appears on the Lock Screen with a countdown until that meal is logged. It's not a notification you swipe away. It just stays there until you log.

- **Mealtime widget.** Add it to the Lock Screen (rectangular, circular, or inline) or the Home Screen. It flips at each meal time on its own: *Lunch time · 1:12:40 to log*, then *Lunch logged ✓ · Next: Dinner 6:30*. Tapping it during a meal opens food logging.
- **Live Activity.** The same check-in on the Lock Screen and in the **Dynamic Island**, with your buddy, the countdown, and today's calories, protein, and water. It's on by default, and you can turn it off with **Settings → Appearance → Mealtime Live Activity**.

Each meal's window is 90 minutes, or until the next meal if that's sooner. Logging late still counts, and the buddy says so.

*How it works without a server:* iOS lets a Live Activity mark itself "stale" at a set time. Steady sets that time to your next meal, so lunch arriving flips the Live Activity into the prompt with no push and no notification. The widget does the same with a timeline entry at every window edge. One limit: iOS ends a Live Activity after 8 hours, so Steady restarts it whenever you open the app.

<p class="next">Next: <a href="workouts-and-fueling">Workouts & fueling →</a></p>
