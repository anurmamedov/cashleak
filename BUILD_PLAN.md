# CashLeak — build plan

**Local** is everything on your machine and your phone — 20 steps, ending with an
app you use daily. **Production** is the 10 steps between "it works for me" and
"it's on the App Store."

Each step lists what's **done** and what's **outstanding**. Update as you go.

---

## At a glance

| | Local | Production |
|---|---|---|
| Done | 16 | 0 |
| Partial | 2 | 0 |
| Not started | 3 | 10 |

**Verified:** builds and runs on iPhone 17 Pro / iOS 26.5.
**Not verified:** all 192 unit tests — there is no test target in the project yet.
**Gates:** L2 is on hold. L1, L3 and L4 haven't run.

---

# Local

## Gates

### L1 · Validate the verdict mechanic — `gate` · not started

Two weeks of logging every purchase and labelling it *worth it* or *leak*.

- [ ] Start the two-week log
- [ ] Weekly tally, both weeks
- [ ] Answer: did labelling change what you bought?

The only step that can invalidate the rest. Clock hasn't started.

### L2 · Shortcuts message body — **on hold**

Bank alert capture is parked. Not cancelled — deprioritised until v1 ships and
real coverage numbers exist.

What the research found, kept for whenever this restarts:

- Message body is probably readable as Shortcut Input — a published
  SMS-to-webhook workflow depends on it, confirmed working August 2025
- Email triggers are better attested: Shortcut Input arrives as a file whose
  name is the subject and contents are the body
- **Sender filtering may reject short codes**, which is how every Canadian bank
  texts. If so, rules must key on message text instead, and onboarding can't
  offer a list of banks to pick from
- Email triggers only work with Apple Mail

Why it's parked: it doubles automatic coverage, but it also doubles the setup
burden — one automation per bank, each needing the user to know their own alert
wording. That's a lot of onboarding for a feature nobody has asked for yet,
built on a capability Apple could remove without notice.

Wallet capture alone plus recurring rules covers the ground v1 needs.

**Restart when:** v1 has shipped and coverage complaints are the top request.

**Parser built ahead of the gate.** L2 is really two questions, and only one is
Apple's:

- [x] *Can we parse a bank alert once we have it?* Ours, and testable anywhere.
      `BankAlertParser` extracts amount and merchant, rejects balances,
      deposits, refunds, declines and one-time codes, and carries a confidence
      level. 8 bank presets. 20 tests. A debug button runs the samples through
      the ingest funnel so the whole path is exercisable in the Simulator.
- [ ] *Does Shortcuts hand us the message body?* **Only a physical phone can
      answer this.** Confirmed by inspection: the Simulator ships Fitness,
      Watch, Contacts, Files, Preview, Utilities, Safari and Messages — no
      Shortcuts app at all.

The sample alerts are **invented, not collected**. They're modelled on how banks
tend to phrase things, which isn't the same as being right. Real alerts replace
them when L2 runs — same discipline as the Wallet merchant fixtures.

### L3 · Wallet trigger end to end — `gate` · not started

- [ ] Throwaway Shortcut logging `Amount` and `Merchant`
- [ ] Tap-pay and record latency
- [ ] Confirm behaviour on a decline
- [ ] **Collect 10+ verbatim merchant strings**

The merchant strings are the real deliverable — they replace the guessed
fixtures that L14 currently depends on.

### L4 · Name and trademark — not started

- [ ] App Store search on device
- [ ] CIPO, USPTO classes 9 and 42
- [ ] Domain and handles
- [ ] Close DECISIONS.md D-007

Bundle ID is already `cashleak`, so this is now a rename-before-TestFlight
decision rather than a pre-build one.

---

## Foundation

### L5 · Project setup — partial

Done:

- [x] Source tree matches ARCHITECTURE.md
- [x] Template files removed
- [x] Project builds and runs

Outstanding:

- [ ] iCloud + CloudKit capability
- [ ] Background Modes — background fetch
- [ ] Push Notifications
- [ ] App Group for the widget
- [ ] **Sign in with Apple** — needed by the welcome screen
- [ ] No `.entitlements` file exists yet — **sync silently does nothing**

### L6 · Test target and fixtures — partial

Done:

- [x] 192 tests across 13 files
- [x] In-memory `ModelContainer` helper, CloudKit disabled
- [x] Merchant fixture corpus

Outstanding:

- [ ] **No test target in the project** — `⌘U` does nothing
- [ ] Not one test has ever executed
- [ ] Fixtures are guesses at Canadian formats until L3 lands
- [ ] Receipt images for v1.1

### L7 · SwiftData models — done

- [x] `Transaction`, `Category`, `Trip`, `RecurringRule`
- [x] Enums stored as raw strings so reordering can't remap records
- [x] CloudKit rules honoured — defaults, no unique attributes, explicit inverses
- [x] 14 default categories seeded once
- [x] `CardAutomation` added for self-reported per-card capture status
- [x] 13 model tests written

Schema versioning deferred to P5 — see the note there.

### L8 · CloudKit sync — not started

- [ ] Blocked on L5 capabilities
- [ ] Two-device test with a conflicting edit
- [ ] Airplane mode and reconnect

Not unit-testable. Needs two physical devices.

### L9 · Tab bar shell — done

- [x] Five slots: Overview · Sort · [Add] · Analysis · You
- [x] Add opens a sheet and restores the previous tab
- [x] Unsorted count badges the Sort tab
- [x] Native `TabView`, inherits iOS 26 styling

### L10 · Seed data generator — done

- [x] 4 months of plausible transactions across 16 merchants
- [x] Deterministic per seed, so charts and tests reproduce
- [x] Recent items left unconfirmed so the queue has content
- [x] Debug-only, exposed in the You tab

---

## Core loop

### L11 · Manual entry sheet — done

- [x] Number pad opens focused, digits accumulate from the right
- [x] Category chips
- [x] Saves confirmed — the one deliberate exception to the unconfirmed rule
- [x] Optional merchant field with recent-merchant suggestions
- [x] Category pre-fills from the last time that merchant was filed
- [x] An explicit category tap always beats the remembered one
- [x] Memory returns categories only, never verdicts
- [x] 11 memory tests

### L12 · Sort queue — done

- [x] Swipe right for worth it, left for leak
- [x] Source badges: Pay, Alert, Scan, Auto, Manual
- [x] Empty state reads as a reward
- [x] VoiceOver actions for both verdicts
- [x] Tap a row to assign a category, without confirming it
- [x] Uncategorised rows say so, rather than showing nothing
- [x] Undo banner for 4 seconds after each swipe
- [x] Undo restores verdict and confirmation together
- [x] 3 action tests

### L13 · Wallet App Intent — done

- [x] `LogWalletTransaction`, `openAppWhenRun = false`
- [x] Writes unconfirmed through the ingest funnel
- [x] `AppShortcutsProvider` for discovery
- [x] In-app setup walkthrough with the eight Shortcuts steps
- [x] States plainly what won't be captured

- [ ] Never exercised by a real Shortcuts automation — blocked on L3

### L14 · Deduplication — done

- [x] Amount exact + 72h window + fuzzy merchant
- [x] Normalization strips processor prefixes, store numbers, province suffixes
- [x] Superseded, never deleted — wrong merges stay recoverable
- [x] Richness ranking; human judgement always wins
- [x] Single ingest funnel — nothing writes a `Transaction` directly
- [x] Declines and implausible amounts rejected before the store
- [x] 30 tests across matcher and ingest

- [ ] Tuned against guessed fixtures until L3

### L15 · Recurring rules — done

- [x] Poster backfills one transaction per missed period
- [x] Idempotent — safe on launch and foreground
- [x] Backfilled charges keep their own dates
- [x] Posts unconfirmed; carries the rule's category
- [x] Rules management UI with 11 templates
- [x] Pause and resume
- [x] 11 poster tests

- [ ] `BGAppRefreshTask` registration — lands with L19

---

## The product

### L16 · Overview — done

- [x] Leak card as hero with continuous four-band ratio ramp
- [x] Palest shade held below 10 transactions or a week
- [x] Dark mode inverts direction
- [x] Spent / pace / kept, kept in teal
- [x] Leak breakdown by category
- [x] Trip card
- [x] Trade-off line falls back gracefully with no trip
- [x] Trade-off copy handles leaks above 100% of a trip — "more than the whole
      trip", or a whole-trip count, never "159%"
- [x] Pace suppressed in the first week and labelled "on pace for ... by month
      end" rather than shown as a bare number
- [x] Trip card navigates to trip detail
- [x] Leak breakdown rows tap through to the category detail
- [x] **Week-over-week banner** — the month figure blends a good week with a bad
      one and hides improvement. plan.md's "make it work in reverse"
- [x] Trip card reads "Starts today" / "Tomorrow", not "In 0 days"

### L17 · Analysis — done

- [x] Range selector: month, 3M, year
- [x] Spent-vs-leaked trend in Swift Charts, bucketed by day or month
- [x] Category breakdown, tappable
- [x] Merchant leaderboard ranked by leak, grouped by normalized merchant
- [x] Day-of-week pattern, always seven bars
- [x] One plain-language finding in serif, suppressed below 15 transactions
- [x] Merchant and category drill-downs
- [x] Empty state
- [x] Weekday finding gated on 3+ occurrences of each day and compared per
      occurrence — a fortnight has two Sundays, which isn't a pattern
- [x] Day-of-week chart stacked leaked over kept, so it encodes leaks at any
      ratio rather than staying grey below 40%
- [x] 30 aggregate and comparison tests

### L18 · Trips — done

- [x] Trip list grouped by now, coming up, been
- [x] Curated cost index, 78 cities, multipliers relative to Toronto
- [x] Personalised forecast from the user's own discretionary spend
- [x] Fixed-cost categories excluded from the daily rate
- [x] Live forecast preview while planning
- [x] Detail screen shows the arithmetic, not just the total
- [x] Live burn rate with on-pace indicator
- [x] Actual vs. estimate after the trip
- [x] Overview trip card navigates here
- [x] 15 tests across index, forecast, and averaging

- [ ] Index is 78 cities, not the ~150 the plan asked for

### L19 · Notification and widget — not started

- [ ] Daily 21:00 notification, rescheduled on every write
- [ ] `BGAppRefreshTask` in the afternoon
- [ ] Copy carries meaning, not just a number
- [ ] Tapping opens Sort
- [ ] Home Screen widget with today's total

### L21 · Profile and app lock — done

Added after the plan was written, in response to a request for login screens.
Resolved locally rather than with a backend — see D-012.

- [x] Welcome screen with Sign in with Apple
- [x] Registration: first name, last name, email, optional password
- [x] Sign-in screen matching against the on-device profile
- [x] Passcode stored as a salted SHA-256 hash in the Keychain, never the
      password itself
- [x] Face ID and Touch ID unlock, attempted automatically
- [x] 60-second grace period so a glance at a notification doesn't re-lock
- [x] Profile row and sign out in the You screen
- [x] Signing out clears the profile and passcode, never the transactions
- [x] 24 validation, hashing and profile tests

- [ ] **Sign in with Apple capability not enabled in Xcode** — the button will
      fail at runtime until it is (L5)
- [ ] Google sign-in deliberately not built — needs an SDK and a backend

### L20 · You screen — done

- [x] Per-card automation status, self-reported, with staleness detection
- [x] Apple Pay setup walkthrough
- [x] Recurring rules and Trips
- [x] Plain statement of what won't be captured
- [x] Accent picker, four options
- [x] Daily summary time
- [x] **Currency now follows device locale**, overridable
- [x] Category management with safe deletion
- [x] CSV export via share sheet, RFC 4180 quoting
- [x] Privacy page
- [x] Debug tools

- [ ] Card status is self-reported — no API can verify an automation exists

---

# Production

### P1 · Device matrix and regression — not started

- [ ] Smallest and largest devices, both appearances
- [ ] Largest Dynamic Type on every screen
- [ ] VoiceOver through add → sort → overview
- [ ] Two-device sync with a conflicting edit
- [ ] Airplane mode and reconnect
- [ ] Fresh install — every empty state
- [ ] Upgrade install over existing data

### P2 · Polish — not started

- [ ] Haptics and animation timing
- [ ] First-run onboarding, no account
- [ ] Fixes from P1

### P3 · StoreKit — not started

- [ ] One-time purchase, seven-day trial
- [ ] Restore purchases
- [ ] StoreKit Testing coverage
- [ ] Manual restore on a clean device

Note: `StoreKit.Transaction` collides with our model. Qualify it rather than
renaming.

### P4 · Audience — start during L16–L20

- [ ] Technical post on the Wallet automation
- [ ] The contrarian Canadian angle: don't sync at all
- [ ] Build in public

### P5 · Release readiness — not started

- [ ] **App icon** — `AppIcon.appiconset` is empty, ships a blank tile
- [ ] **Privacy manifest** — no `PrivacyInfo.xcprivacy`; required at submission
- [ ] **Schema versioning** — unversioned today, so any model change wipes
      TestFlight users' data. Must land before P7
- [ ] Support and privacy policy URLs

### P6 · App Store Connect — not started

- [ ] Resolve the name from L4
- [ ] App record and bundle ID
- [ ] Privacy nutrition labels — nearly empty, which is the selling point

### P7 · TestFlight — not started

- [ ] 10–20 testers
- [ ] One metric: are they still logging in week three?

### P8 · Screenshots and copy — partial

- [x] Full listing drafted in [LISTING.md](LISTING.md)
- [x] Subtitle fixed to fit 30 characters — the original was 36 and would have
      been rejected
- [x] Description, promo text, keywords, screenshot order, review notes

- [ ] Take the actual screenshots
- [ ] Trim keywords from 103 to 100 characters
- [ ] Final subtitle choice

### P9 · Submit — not started

- [ ] Review notes explaining the Shortcuts dependency
- [ ] Budget a week for a rejection round

### P10 · Post-launch — not started

- [ ] Decide v1.1 scope from the L2 result
- [ ] Update DECISIONS.md

---

## Suggested order

Only three local steps remain, and every one of them is blocked on something
outside the code.

1. **Test target** — 2 minutes in Xcode. 131 tests have never executed, and four
   features have now been built on top of them. If `MerchantNormalizer` is
   wrong, dedup is wrong, the Analysis leaderboard groups wrong, and merchant
   memory misfires — one bug wearing four costumes, none of it visible on screen.
2. **L5 capabilities** — 5 minutes in Xcode. Unblocks L8 sync and L19
   notifications. Until this lands, CloudKit is configured in code and does
   nothing at runtime.
3. **L1** — start the two-week clock today. Nothing depends on it and everything
   is invalidated by it.
4. **L3** — one evening, on the phone. Its merchant strings replace the guessed
   dedup fixtures. L2 is parked.
5. **L19** — the last unbuilt feature. Needs step 2 first.
6. **L8** — two-device sync check. Needs step 2 and a second device.

The pattern worth noticing: everything I can do alone is done. What's left needs
Xcode, a phone, or two weeks.

---

## Out of scope

Bank sync · net worth · investments · debt payoff · shared budgets · envelope
budgeting · income tracking · receipt line items · Android, web, Mac

Receipt scanning is v1.1. Bank alerts are v1.1 if L2 comes back well. Reconcile
is v1.2.
