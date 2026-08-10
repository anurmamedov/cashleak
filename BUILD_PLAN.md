# CashLeak — build plan

Two phases. **Local** is everything that happens on your machine and your own
phone — 20 steps, ending with a complete app you use daily. **Production** is
everything between "it works for me" and "it's on the App Store" — 9 steps.

Steps marked **gate** should genuinely change the plan if they come back badly.
Don't skip past them because the code is more fun.

Testing isn't a phase at the end. The test target goes in at L6, before any model
exists, and every step after it carries its own **Tests** line. A step isn't done
until those pass. The only bulk testing is P1, and that's device matrix and
regression — not writing tests you should have written weeks earlier.

Working name is CashLeak. Descriptive, so weak as a trademark — fine for the repo
and bundle ID, resolve before the listing (P5).

---

## Progress

| | Steps |
|---|---|
| **Done** | L6 · L7 · L9 · L10 · L11 · L12 · L16, plus the test target and suite |
| **Partial** | L5 — source tree restructured, capabilities not yet enabled |
| **Gates unrun** | L1 · L2 · L3 · L4 |
| **Pending** | L8 · L13 · L14 · L15 · L17 · L18 · L19 · L20, all of P1–P9 |

Mark steps here as they land. A plan nobody updates gets ignored within a week.

Worth stating plainly: every completed step is code, and every gate is
untouched. L14's fixtures are guesses until L3 runs, and L1 can invalidate all
of it.

---

# Local — 20 steps

## Gates (do these first, in parallel)

### L1. Validate the verdict mechanic on yourself — gate

Two weeks. Apple Notes is fine. Log every purchase, label each *worth it* or
*leak*, tally weekly.

Two-week clock, and nothing else depends on it — start it today and let it run
while you do L2–L6. Every day you delay adds a day to the front of the project.

**Done when:** you can answer whether labelling changed what you bought. If it
didn't move you, it won't move a stranger.

### L2. Test the Shortcuts message body — gate

Shortcuts → Automation → Message → any sender, contains a test word. Actions:
`Get Text from Input` → `Show Alert`. Text yourself.

**Done when:** you know whether the body is readable. Readable → bank alerts are
the v1.1 headline and coverage roughly doubles. Not readable → it's a nudge
trigger that deep-links into the add sheet.

### L3. Test the Wallet trigger end to end — gate

Throwaway Shortcut on the Wallet trigger logging `Amount` and `Merchant` to a
note. Tap-pay for a coffee. Then deliberately trigger a decline.

**Done when:** you know the real latency, the actual shape of the merchant
string, and whether declines come through. **Save every merchant string you
see** — these become the fixtures for L14.

### L4. Name and trademark check

App Store search on device, CIPO, USPTO classes 9 and 42, domain, handles.

The bundle ID is already `cashleak`, so this is now a decision about whether to
rename before TestFlight rather than before first build.

**Done when:** the name is settled and DECISIONS.md D-007 is closed.

---

## Foundation

### L5. Finish project setup and restructure

Target → Signing & Capabilities → + Capability: **iCloud + CloudKit**,
**Background Modes** (background fetch), **Push Notifications**, **App Group**
shared with the widget.

Then move to the layout in ARCHITECTURE.md: `App/`, `Models/`, `Features/`,
`Intents/`, `Notifications/`, `Widgets/`, `Resources/`. Delete `Item.swift`.

Cheap now, tedious once there are thirty files.

**Done when:** structure matches ARCHITECTURE.md, four capabilities enabled, no
signing errors.

### L6. Test target and fixtures

Add a unit test target. Create an in-memory `ModelContainer` helper so tests run
against a real SwiftData stack without touching CloudKit or the simulator's
store.

Drop in fixtures: the merchant strings captured in L3, and 5–10 receipt photos
for L-phase receipt work later.

Do this **before** the models exist. A test target added at the end is a test
target that gets three tests and dies.

**Tests:** one trivial assertion that the in-memory container spins up and tears
down clean.

**Done when:** `⌘U` runs green in under five seconds.

### L7. SwiftData models

`Transaction`, `Category`, `Trip`, `RecurringRule`. Get the `source` and
`verdict` enums right now — migrating enum cases later is painful.

Every property defaulted or optional, no `@Attribute(.unique)`, relationships
optional with explicit inverses. CloudKit enforces all three.

Seed ~14 default categories on first launch.

**Tests:** each model round-trips through the in-memory container; seeding runs
exactly once across two launches; relationship inverses resolve both directions.

**Done when:** tests pass and the schema loads without a CloudKit validation
warning.

### L8. CloudKit sync

Configure the `ModelContainer` for the private database. Test on two physical
devices before building anything on top — sync bugs found later are far harder to
isolate.

Not unit-testable. This one is manual and has to be done on hardware.

**Done when:** a transaction created on one device appears on the other, and a
conflicting edit on both resolves without data loss.

### L9. Tab bar shell

`RootTabView.swift`. Five slots: `Overview · Sort · [Add] · Analysis · You`.
Placeholder screens, native `TabView` so iOS 26 styling is inherited.

**Done when:** the app is navigable end to end with nothing functional.

### L10. Seed data generator

Debug-only. 3–6 months of plausible transactions across categories, sources, and
verdicts. Deterministic given a seed value, so charts and tests are reproducible.

Every chart, empty state, and edge case after this depends on having data to look
at. An hour here saves ten later.

**Tests:** generator is deterministic — same seed produces the same dataset.

**Done when:** one call fills the store with a realistic dataset.

---

## Core loop

### L11. Manual entry sheet

Number pad opens focused. Amount → category chip → save. No mandatory fields, no
date picker. Remember category by merchant.

**Tests:** amount parsing across locales and decimal separators; the
merchant→category memory returns the last used category.

**Done when:** you can log a purchase in under five seconds without looking.

### L12. Sort queue

Inbox of unconfirmed transactions. Swipe left for leak, right for worth it, tap
for category. Source badges: Pay, Scan, Auto, Manual.

Empty state is a reward, not a blank slate.

**Tests:** confirming sets `isConfirmed` without touching `verdict`, and vice
versa — the two must stay independent; queue ordering is stable.

**Done when:** a seeded queue can be cleared entirely by swipe.

### L13. `LogWalletTransaction` App Intent

Exposed to Shortcuts, accepts amount and merchant, writes **unconfirmed**,
`openAppWhenRun = false`.

Then write the in-app setup walkthrough with screenshots. The feature is
worthless if nobody completes the eight taps in Shortcuts.

**Tests:** intent invoked with the L3 fixture strings writes exactly one
unconfirmed record; malformed and nil merchant inputs don't crash or write
garbage.

**Done when:** a real tap-payment lands in your Sort queue without the app
opening.

### L14. Deduplication

`amount` exact + `date` within 72h + normalized fuzzy merchant. Normalization
strips store numbers, city suffixes, and processor prefixes. Matched records
marked superseded, never deleted.

Build it now even though nothing duplicates yet — retrofitting after bank alerts
land means migrating data that's already been sorted.

**Tests:** this is the highest-value test file in the project. Cover the L3
merchant strings pairwise; the 72h boundary at 71h and 73h; same amount and
merchant on genuinely different days must **not** merge; superseded records stay
recoverable.

**Done when:** the matcher is right on every fixture pair and you'd trust it with
real money.

### L15. Recurring rules

Templates with cadence, auto-posted **unconfirmed** on their date. Rent,
subscriptions, phone, insurance.

This is what covers the 40–60% of spend Apple Pay can't see.

**Tests:** next-run dates across a DST spring-forward and fall-back; the 31st in
a 30-day month; Feb 29; a rule that hasn't run in three months backfills once,
not three times.

**Done when:** the date maths survives every boundary case in tests.

---

## The product

### L16. Overview screen

Leak card as hero with the four-step ratio ramp. Spent / pace / kept stats. Leak
breakdown by category. Trip card. Every element taps through to Analysis.

Ramp rules: darkness maps to **ratio not amount**, interpolate continuously, hold
the palest shade until 10 transactions or a week, invert direction in dark mode.

**Tests:** ratio and pace aggregates against a known seeded dataset; the ramp
holds the palest shade at 9 transactions and moves at 10; a single early leak
doesn't read as 100%.

**Done when:** the ramp reads correctly at 5%, 30%, and 60% in both appearances.

### L17. Analysis screen

Range selector, then in order: spent-vs-leaked trend, categories, merchant
leaderboard, day-of-week pattern, one plain-language finding in serif. Swift
Charts throughout.

Every row is a link. Dead-end analytics is why people stop opening these screens.

**Tests:** each aggregate against the seeded dataset; range boundaries include
and exclude the right days; empty ranges don't divide by zero.

**Done when:** every element navigates somewhere and nothing is a dead end.

### L18. Trips

Personalized forecast: real daily discretionary spend × destination multiplier ×
days + fixed costs. Hand-curate ~150 cities. Live burn rate during, actual vs.
estimate after.

**Tests:** forecast maths; burn rate with zero days elapsed; a trip spanning a
month boundary attributes transactions correctly.

**Done when:** a forecast uses your own spending data, not a generic per-diem.

### L19. Daily notification and widget

Reschedule the 21:00 notification on every transaction write — remove pending by
identifier, re-add with the fresh figure. `BGAppRefreshTask` in the afternoon as
backup.

Copy carries meaning: `$67.40 today — $18 over your average`. Tapping opens Sort.
Home Screen widget shows today's running total.

**Tests:** the copy builder produces the right string for zero, one, and many
transactions, and for above/below average; only one pending request exists after
ten rapid writes.

**Done when:** the figure is correct after a late-evening purchase.

### L20. You screen

Apple Pay card list with per-card automation status and a plain statement of what
won't be captured. Accent picker, notification time, categories, recurring,
trips, CSV export, privacy.

**Tests:** CSV export round-trips — export, re-import, compare. Deleting a
category reassigns its transactions rather than orphaning them.

**Done when:** a new user could set up their automations from this screen alone.

---

# Production — 9 steps

### P1. Device matrix and regression pass

The one bulk testing step, and it's manual on purpose — everything unit-testable
already has tests from L6 onward.

- Smallest and largest supported devices, both appearances
- Dynamic Type at the largest accessibility size on every screen
- VoiceOver through the full core loop: add → sort → overview
- Two-device CloudKit sync with a conflicting edit
- Airplane mode, then reconnect
- Fresh install with zero data — every empty state
- Upgrade install over a seeded database

**Done when:** the full suite is green and the manual checklist has no open
items.

### P2. Polish pass

Haptics. Animation timing. First-run onboarding — no account, straight to the
number pad. Fix whatever P1 surfaced.

**Done when:** the core loop feels finished rather than functional.

### P3. StoreKit

One-time purchase, seven-day trial, restore purchases.

**Tests:** StoreKit Testing framework for purchase, trial expiry, and restore.
Then manually with a sandbox account on a device that has never seen the app —
the automated tests won't catch a broken restore.

**Done when:** restore works on a clean device.

### P4. Audience — start during L16–L20, not here

The technical post about the Wallet automation. The contrarian Canadian angle:
don't sync at all. Build in public.

The build takes six weeks; an audience takes longer. Starting at submission is
the most common way a good indie app disappears. It sits in the production phase
only because that's where it pays off.

### P5. App Store Connect setup

Resolve the name from L4. Bundle ID, app record, privacy nutrition labels — which
are close to empty, and that's the selling point.

**Done when:** the app record exists and the privacy section is filled honestly.

### P6. TestFlight beta

10–20 people. Watch one metric: **are they still logging in week three?**

That answers whether the product works better than any feedback form will.

**Done when:** three weeks of retention data exists.

### P7. Screenshots and listing copy

Screenshots lead with the leak card. Subtitle: "Find your cash leaks. No bank
login." Description opens on the three things nobody else says — no bank login,
one-time price, automatic Apple Pay capture. Keyword field filled to 100
characters.

### P8. Submit

Expect at least one rejection round. Budget a week.

The likely flag is the Shortcuts dependency — be ready to explain in review notes
that the app is fully functional without it.

### P9. Post-launch — decide v1.1

Receipt scanning is committed. Bank alerts ship if L2 came back well. Reconcile
is v1.2, once real coverage numbers exist.

**Done when:** v1.1 scope is written down and DECISIONS.md is updated.

---

## Testing policy

Unit tests go where being wrong is invisible:

- Merchant normalization and the dedup matcher (L14)
- Recurring rule dates across DST and month-end (L15)
- Leak ratio and pace aggregates (L16, L17)
- Notification copy construction (L19)
- Receipt field extraction against fixture images (v1.1)

No snapshot tests for SwiftUI. At this project size they cost more than they
return, and UI gets checked by hand in P1.

Two invariants worth a test each, because breaking them silently corrupts the
dataset: **everything enters unconfirmed**, and **`isConfirmed` never implies a
`verdict`**.

---

## Deliberately not in this plan

Bank sync · net worth · investments · debt payoff · shared budgets · envelope
budgeting · income tracking · receipt line-item parsing · Android, web, Mac

Every one of these will be requested. Saying no is the strategy.
