# CashLeak — build plan

24 steps, roughly sequenced. Each one is small enough to finish in a sitting or
two. Steps marked **gate** should genuinely change the plan if they come back
badly — don't skip past them because the code is more fun.

Working name is CashLeak. It's descriptive, so it's weak as a trademark — fine
for the repo and bundle ID, but resolve the real name before the App Store
listing (step 24).

---

## Phase 0 — Before writing code

### 1. Validate the verdict mechanic on yourself — gate

Two weeks. Apple Notes is fine. Log every purchase, label each one *worth it* or
*leak*, tally weekly.

Ask at the end: did labelling change what you bought? If it didn't move you, it
won't move a stranger, and you've learned that for two weeks instead of six.

### 2. Test the Shortcuts message body — gate

Shortcuts → Automation → Message → any sender, contains a test word. Actions:
`Get Text from Input` → `Show Alert`. Text yourself.

If the body is readable, bank-alert capture becomes v1.1 and coverage roughly
doubles. If not, it's only a nudge trigger. One afternoon, and it decides the
roadmap.

### 3. Test the Wallet trigger end to end

Build a throwaway Shortcut on the Wallet trigger that logs `Amount` and
`Merchant` to a note. Tap-pay for a coffee. Confirm what actually arrives, how
fast, and whether it fires on a decline.

This is the foundation of the whole product — verify it before designing around
it.

### 4. Name and trademark check

App Store search on device, CIPO and USPTO classes 9 and 42, domain, social
handles. Do all four before the bundle ID is locked.

---

## Phase 1 — Foundation

### 5. Project setup

Xcode → iOS App → SwiftUI + SwiftData. Add `.gitignore` and `README.md`, push to
the remote. Enable capabilities: iCloud + CloudKit, Background Modes (background
fetch), Push Notifications, App Group for the widget.

### 6. SwiftData models

`Transaction`, `Category`, `Trip`, `RecurringRule`. Get `source` and `verdict`
enums right now — migrating them later is painful. Seed ~14 default categories on
first launch.

### 7. CloudKit sync

Configure the `ModelContainer` for the private database. Test on two devices
before building anything on top; sync problems found later are much harder to
isolate.

### 8. Tab bar shell

Drop in `RootTabView.swift`. Four placeholder screens plus the add sheet. App
navigable end to end, nothing functional yet.

### 9. Seed data generator

A debug-only function that creates 3–6 months of plausible transactions. Every
chart, empty state, and edge case you build after this depends on having data to
look at. Worth an hour, saves ten.

---

## Phase 2 — Core loop

### 10. Manual entry sheet

Number pad opens focused. Amount → category chip → save. No mandatory fields, no
date picker. Target under five seconds. Remember category by merchant.

### 11. Sort queue

Inbox of unconfirmed transactions. Swipe left for leak, right for worth it, tap
for category. Source badges: Pay, Scan, Auto, Manual. Make the empty state a
reward, not a blank slate.

### 12. `LogWalletTransaction` App Intent

Exposed to Shortcuts, accepts amount and merchant, writes unconfirmed, never
opens the app. Then write the in-app setup walkthrough with screenshots — the
feature is worthless if nobody completes the eight taps in Shortcuts.

### 13. Deduplication

Amount + 72h window + fuzzy merchant match. Build it now even though nothing
duplicates yet — retrofitting it after bank alerts land is a bad afternoon.

### 14. Recurring rules

Templates with cadence, auto-posted as unconfirmed on their date. Rent,
subscriptions, phone, insurance. This is what covers the 40–60% of spend Apple
Pay can't see.

---

## Phase 3 — The product

### 15. Overview screen

Leak card as hero with the four-step ratio ramp, spent / pace / kept stats, leak
breakdown by category, trip card. Every element taps through to Analysis.

Ramp rules: map darkness to ratio not amount, interpolate continuously, hold the
palest shade until 10 transactions or a week, invert direction in dark mode.

### 16. Analysis screen

Range selector, then: spent-vs-leaked trend, categories, merchant leaderboard,
day-of-week pattern, one plain-language finding in serif. Swift Charts
throughout. Every row is a link — dead-end analytics is why people stop opening
these screens.

### 17. Trips

Personalized forecast: real daily discretionary spend × destination multiplier ×
days + fixed costs. Hand-curate ~150 cities. Live burn rate during, actual vs.
estimate after.

### 18. Daily notification and widget

Reschedule the 9pm notification on every transaction write; `BGAppRefreshTask` in
the afternoon as backup. Copy carries meaning — "$67.40 today, $18 over your
average". Tapping it opens Sort. Home Screen widget shows today's running total.

### 19. You screen

Apple Pay card list with per-card automation status and a plain statement of what
won't be captured. Accent picker, notification time, categories, recurring,
trips, CSV export, privacy.

---

## Phase 4 — Ship

### 20. Polish pass

Dark mode on every screen. Dynamic Type at largest size. VoiceOver labels. Empty
states everywhere. Haptics. First-run onboarding — no account, straight to the
number pad.

### 21. StoreKit

One-time purchase, 7-day trial, restore purchases. Test with sandbox accounts and
verify restore actually works on a fresh device.

### 22. Beta

TestFlight to 10–20 people. Watch one metric: are they still logging in week
three? That answers whether the product works better than any feedback form.

### 23. Start building the audience — do this during Phase 3, not after

The technical post about the Wallet automation. The contrarian Canadian angle:
don't sync at all. Build in public.

The build takes six weeks; an audience takes longer. Starting this at submission
is the single most common way a good indie app disappears.

### 24. Submit

Screenshots leading with the leak card. Subtitle: "Find your cash leaks. No bank
login." Description opens on the three things nobody else says — no bank login,
one-time price, automatic Apple Pay capture. Keyword field filled to 100 chars.

---

## Deliberately not in this plan

Bank sync · net worth · investments · debt payoff · shared budgets · envelope
budgeting · income tracking · receipt line-item parsing · Android, web, Mac

Receipt scanning is v1.1. Bank alerts are v1.1 if step 2 comes back well.
Reconcile is v1.2, once real coverage numbers exist.
