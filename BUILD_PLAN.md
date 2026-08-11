# CashLeak — build plan

**Local** is everything on your machine and your phone — 20 steps, ending with an
app you use daily. **Production** is the 10 steps between "it works for me" and
"it's on the App Store."

Each step lists what's **done** and what's **outstanding**. Update as you go.

---

## At a glance

| | Local | Production |
|---|---|---|
| Done | 9 | 0 |
| Partial | 3 | 0 |
| Not started | 8 | 10 |

**Verified:** builds and runs on iPhone 17 Pro / iOS 26.5.
**Not verified:** all 83 unit tests — there is no test target in the project yet.
**Gates:** none of the four have been run.

---

# Local

## Gates

### L1 · Validate the verdict mechanic — `gate` · not started

Two weeks of logging every purchase and labelling it *worth it* or *leak*.

- [ ] Start the two-week log
- [ ] Weekly tally, both weeks
- [ ] Answer: did labelling change what you bought?

The only step that can invalidate the other 29. Clock hasn't started.

### L2 · Shortcuts message body — `gate` · not started

- [x] Desk research — evidence leans toward the body being readable
- [x] Surfaced a new risk: sender field may reject bank short codes
- [ ] Build the test automation on device
- [ ] Record the alert output verbatim
- [ ] Test whether a short code is accepted as a sender

Not runnable in the Simulator — it has no Shortcuts app.

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
- [ ] No `.entitlements` file exists yet — **sync silently does nothing**

### L6 · Test target and fixtures — partial

Done:

- [x] 83 tests across 6 files
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

### L11 · Manual entry sheet — partial

Done:

- [x] Number pad opens focused, digits accumulate from the right
- [x] Category chips
- [x] Saves confirmed — the one deliberate exception to the unconfirmed rule

Outstanding:

- [ ] Merchant→category memory not implemented
- [ ] No merchant field in the primary path

### L12 · Sort queue — partial

Done:

- [x] Swipe right for worth it, left for leak
- [x] Source badges: Pay, Alert, Scan, Auto, Manual
- [x] Empty state reads as a reward
- [x] VoiceOver actions for both verdicts

Outstanding:

- [ ] Tap-to-assign-category not built
- [ ] No undo after a swipe

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

- [ ] Elements don't yet tap through to Analysis

### L17 · Analysis — not started

Placeholder showing raw totals.

- [ ] Range selector
- [ ] Spent-vs-leaked trend, Swift Charts
- [ ] Category breakdown
- [ ] Merchant leaderboard
- [ ] Day-of-week pattern
- [ ] One plain-language finding in serif
- [ ] Every row navigates somewhere

### L18 · Trips — not started

Model exists with the forecast maths and is tested. No UI.

- [ ] Trip creation and editing
- [ ] Curated cost index, ~150 cities
- [ ] Live burn rate during the trip
- [ ] Actual vs. estimate after

Unlocks the signature line — *"68% of your flight to Lisbon"* — which currently
can't fire.

### L19 · Notification and widget — not started

- [ ] Daily 21:00 notification, rescheduled on every write
- [ ] `BGAppRefreshTask` in the afternoon
- [ ] Copy carries meaning, not just a number
- [ ] Tapping opens Sort
- [ ] Home Screen widget with today's total

### L20 · You screen — partial

Done:

- [x] Apple Pay setup walkthrough
- [x] Recurring rules
- [x] Data counts including merged duplicates
- [x] Plain statement of what won't be captured
- [x] Debug tools

Outstanding:

- [ ] **Currency is hardcoded to `CAD`** in both formatters, ignoring the
      `currencyCode` stored on every transaction — wrong symbols outside Canada
- [ ] Accent picker
- [ ] Notification time
- [ ] Category management
- [ ] CSV export
- [ ] Privacy page
- [ ] Per-card automation status

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

### P8 · Screenshots and copy — not started

- [ ] Screenshots leading with the leak card
- [ ] Subtitle: "Find your cash leaks. No bank login."
- [ ] Description opens on no bank login, one-time price, automatic capture
- [ ] Keyword field to 100 characters

### P9 · Submit — not started

- [ ] Review notes explaining the Shortcuts dependency
- [ ] Budget a week for a rejection round

### P10 · Post-launch — not started

- [ ] Decide v1.1 scope from the L2 result
- [ ] Update DECISIONS.md

---

## Suggested order

1. Test target — 2 minutes, validates 83 tests
2. Capabilities — 5 minutes, unblocks L8
3. L1 — start the two-week clock today
4. L2 and L3 — one evening each, on the phone
5. L17 Analysis, then L18 Trips

---

## Out of scope

Bank sync · net worth · investments · debt payoff · shared budgets · envelope
budgeting · income tracking · receipt line items · Android, web, Mac

Receipt scanning is v1.1. Bank alerts are v1.1 if L2 comes back well. Reconcile
is v1.2.
