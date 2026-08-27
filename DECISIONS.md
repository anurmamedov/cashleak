# Decisions

Why things are the way they are. Each entry records what was decided, what it
rules out, and what would justify reversing it.

Add to the bottom. Don't edit history — supersede it with a new entry.

---

## D-001 · No bank sync, ever

**Decided.**

CashLeak never connects to a bank account. Data arrives via Shortcuts automations,
on-device receipt OCR, recurring rules, and manual entry.

Canada has no real open banking, so aggregators screen-scrape; connections break
constantly and vendors quietly drop Canadian institutions. They also bill per
user per connected account.

This started as a constraint and became the product. No aggregator means no
marginal cost per user, which is what makes a one-time price possible in a
category that is otherwise uniformly subscription-based. It also removes the
biggest objection to installing a finance app: handing over bank credentials.

**Rules out:** automatic complete coverage, real-time balances, net worth,
investments, debt payoff.

**Reverse if:** Canada ships genuine open banking with a free or flat-rate API.
Even then, it would be an optional layer, not the default — the no-credentials
promise is the marketing.

---

## D-002 · Verdict lives on the transaction

**Decided.**

`verdict` is a field on `Transaction`, not on `Category`.

Category-level waste flags produce dishonest data. "Eating out is a leak" is
false the moment one of those meals was worth it. The entire premise is that only
the user knows which coffee was the wasteful one, and the schema has to make the
lazy shortcut impossible rather than merely discouraged.

**Rules out:** auto-classification, "smart" leak detection, rule-based verdicts.

**Reverse if:** never. This is the product.

---

## D-003 · Partial capture, stated plainly

**Decided.**

Expect 40–60% automatic coverage. Say so in onboarding and in the You tab, per
card.

The Wallet trigger misses physical card taps, in-app and web Apple Pay, Interac
e-transfers, pre-authorized debits, and cash. It also fires on declined
transactions and times out when issuers deliver late.

Every captured item lands in the Sort queue **unconfirmed**. One swipe confirms.
Declines and garbage merchant strings never reach the dataset.

Overpromising coverage produces the worst review you can get: "it doesn't even
track my spending." Stating the limit up front converts that into an accepted
trade-off.

**Rules out:** marketing copy implying automatic, complete tracking.

---

## D-004 · One-time purchase, $19.99 CAD

**Decided**, though the number is a guess.

Seven-day StoreKit trial. No free tier, no ads, no subscription.

Marginal cost per user is effectively zero, so this undercuts the category
structurally rather than as a promotion — a competitor on aggregator infra
cannot match it without losing money.

Principle for later features: charge for what costs something, give away what
doesn't. AI monthly summaries and cost-index refreshes have real per-user cost
and can be a separate optional layer.

**Open:** whether $19.99 is the right point. Unresolvable before trial-to-purchase
data exists.

---

## D-005 · Dedup built from day one

**Decided.**

Match on `amount` exact + `date` within 72h + normalized fuzzy merchant.

A single phone tap can fire both the Wallet trigger and a bank alert. If bank
alert capture ships in v1.1 without dedup already in place, every affected user
sees doubled totals — and doubled totals in a spending app destroy trust
permanently. Retrofitting dedup also means reconciling historical data that has
already been sorted and verdicted.

Matched records are marked superseded, not deleted, so a wrong merge is
recoverable.

**Reverse if:** never. Cost of building early is a day; cost of building late is
a data migration plus a trust problem.

---

## D-006 · Trips is not a tab

**Decided.**

Five tab slots: `Overview · Sort · [Add] · Analysis · You`. Trips appears as a
card on Overview and a row in You.

Trips is used a few times a year. Analysis is used weekly. Permanent navigation
space goes to frequency, not to the feature that happens to be most interesting
to build.

**Reverse if:** usage data shows trips being opened weekly, which would mean the
feature is something other than what it looks like.

---

## D-007 · Working name is CashLeak

**Decided internally. App Store name still open.**

"Kept" was the working name in an earlier draft of the planning documents, while
the repository, Xcode project, and bundle ID said `cashleak`. That split produced
documents that contradicted each other and code that matched neither
consistently.

Settled: **CashLeak** everywhere — repo, bundle ID, module, documents. The cost
of the ambiguity was higher than the cost of picking.

It's descriptive, which makes it clear to a user and weak as a trademark. That's
an acceptable trade for a pre-launch working name and a bundle identifier nobody
sees.

**Still open:** the public App Store name. Descriptive marks are hard to defend,
so this may not survive the L4 check.

**Resolve by:** App Store search on device, CIPO, USPTO classes 9 and 42,
registrar availability — L4. Renaming the bundle identifier after the first
TestFlight build is painful, so do it before P6.

---

## D-008 · Shortcuts message body — on hold

**Parked.** Superseded in priority by D-013; the research below stands.

Unknown: whether the Shortcuts Message trigger exposes the message **body** as
parseable Shortcut Input. Documented examples only demonstrate reading the
*sender* for auto-replies, which proves a message object is passed but not that
its text is readable.

`IdentityLookup` / `ILMessageFilterExtension` is not a fallback — Apple sandboxed
it precisely to prevent passing message content to the containing app.

**Resolve by:** the three-step test in [plan.md](plan.md). One afternoon.

- **Body readable** → regex out amount and merchant. Coverage roughly doubles.
  This becomes the v1.1 headline feature.
- **Body not readable** → the trigger becomes a notification nudge that
  deep-links into the add sheet. Useful, not magical.

Either way: email triggers only work with Apple Mail, setup requires one
automation per bank, and bank presets for RBC, TD, Scotiabank, BMO, CIBC, and
Tangerine are mandatory or nobody completes onboarding.

---

## D-009 · No receipt line items in v1

**Decided.**

Receipt OCR extracts three fields: total, merchant, date. Each with a visible
confidence badge the user can correct.

Line-item parsing has to cope with unbounded layout variance across every
retailer, and it fails silently. Silent wrong guesses are how receipt scanning
earned its reputation for being useless.

**Reverse if:** v1 ships and line items are the top request, with a narrow enough
merchant set to make it tractable.

---

## D-010 · Validate the mechanic before building

**Decided, not yet done.**

Two weeks of manual logging and labelling — Notes is fine — before feature work
starts.

The verdict swipe is the entire product. If labelling purchases *worth it* /
*leak* doesn't change your own behaviour, it won't change a stranger's. Learning
that on paper costs two weeks. Learning it after building costs six.

This is the single item most likely to be skipped, because the repo now exists
and building is more fun than journalling.

**Status: skipped so far.** The foundation was built first. That's a risk taken
knowingly, not an oversight — but the two-week clock still hasn't started, and
every step built on top of the mechanic assumes it works.

---

## D-011 · Tests are written per step, not in a phase

**Decided.**

Every build step carries its own tests and isn't done until they pass. There is
no testing phase at the end; the only bulk step is P1, and that's manual device
matrix and regression work.

A test phase scheduled after the features is a test phase that gets compressed
when the features run late. Writing them alongside also surfaces design problems
while they're still cheap to fix.

What gets tested is where being wrong is invisible: merchant normalization and
dedup, recurring date maths, spending aggregates, the leak ramp rules, and
notification copy. Not SwiftUI snapshots — at this size they cost more than they
return.

**Reverse if:** never, though the specific coverage list will grow.

---

## D-012 · A profile, not an account

**Decided.** Supersedes nothing — clarifies the "no account" claim in D-001.

The app has a registration screen asking for first name, last name, email and an
optional password, plus Sign in with Apple. None of it creates an account
anywhere.

**What was asked for:** email/password login, Sign in with Apple, and Google
sign-in.

**What was built:** the same screens, resolved entirely on-device.

- **Sign in with Apple** — native `AuthenticationServices`, no SDK, no server.
  Stores Apple's app-specific user identifier, which is not an Apple ID and not
  an email.
- **Email registration** — name and email stored in the user's own SwiftData
  store, syncing through their private CloudKit database.
- **Password** — sets a device passcode for opening the app, stored as a salted
  SHA-256 hash in the Keychain. Optional, because a password that protects
  nothing beyond the device passcode is theatre.
- **Google sign-in** — **not built.**

**Why Google was dropped.** It needs the GoogleSignIn SDK, which breaks the
no-third-party-dependency rule, and it authenticates against Google's servers to
produce a token nothing here can verify without a backend of our own. It would be
a login screen that logs into nothing.

There's also an App Store rule: offering a third-party sign-in obliges the app to
offer Sign in with Apple too. We have Apple; adding Google buys nothing and costs
a dependency.

**Why not a real backend.** Email and password authentication needs somewhere to
store credentials, hash them, and handle resets. That's a server, which breaks
the no-backend constraint and introduces per-user cost — the exact thing that
makes the one-time price possible instead of a subscription (D-004).

**What this preserves.** "No account. No server." stays literally true. The
privacy label stays close to empty. The App Store subtitle stays defensible.

**Reverse if:** the product genuinely needs cross-user features — shared
budgets, a web app — both of which are currently out of scope. That would be a
decision to change the product, not to add a feature.

**Note for L5:** Sign in with Apple needs its capability enabled in Xcode. Until
then the button will fail at runtime.


---

## D-013 · Bank alert capture is parked

**Decided.**

Bank alert capture — the Shortcuts Message and Email triggers — is on hold. Not
cancelled, not proven impossible. Deprioritised.

Desk research suggests it would probably work: a published SMS-to-webhook
workflow depends on the message body being readable as Shortcut Input, and email
triggers are better attested still.

The problem isn't feasibility, it's **setup burden**. One automation per bank,
each requiring the user to know their own bank's alert wording, on top of the
Wallet automation they've already been asked to build. That's a lot of onboarding
friction for a feature nobody has requested yet.

Research also surfaced a design problem: Message automations may only accept
phone numbers as senders, not the short codes Canadian banks text from. If so,
rules must key on message text, and onboarding can't offer a bank picker — it has
to ask the user to find a distinctive phrase in their own alerts. Materially
worse.

There's a durability concern too. The whole approach rests on a Shortcuts
behaviour Apple never documented as an integration point and could change in any
release.

**What this leaves:** Wallet capture plus recurring rules. Roughly 40–60%
automatic, with the rest covered by rules and quick manual entry — which the app
already states plainly.

**Restart when:** v1 has shipped and coverage complaints are the top request.
That's evidence the setup burden is worth it; right now it's a guess.

---

## D-014 · Goals replace Trips

**Decided.** Supersedes D-006 in part.

Trips is removed. In its place, a **Goal** — a name and an amount — is what the
leak total gets compared against.

**Why.** Two different features were bundled together:

- A **comparison target**, which is essential. "Tells you what it cost you"
  needs a *what*. Without one the hero line degrades to "35% of what you spent
  this month", restating the number above it instead of converting it.
- A **trip tracker** — live burn rate, days remaining, actual vs. estimate —
  which is a travel budgeting app bolted onto a spending app.

The first is the product. The second was the largest surface in the codebase
(78-city cost index, forecast maths, burn rate, three screens) serving something
D-006 already admitted is used a few times a year.

**The deciding argument:** a trip only produces a trade-off line for people with
travel booked. A goal produces one for everyone — a camera, a deposit, an
emergency fund, a flight. The signature line now fires for every user from their
first sorted month.

**What was deleted:** `Trip`, `CityCostIndex`, `DiscretionarySpend`,
`TripsListView`, `AddTripSheet`, and `Transaction.trip`.

**What was lost.** The personalised forecast — *your* daily discretionary spend
× a destination multiplier — was the cleverest thing in the app and genuinely
differentiated. It's gone. That's the cost, and it's real.

**Also fixed by this.** Nothing ever assigned a transaction to a trip, so
`actualSpend` was permanently zero and the burn rate could never work. The
feature looked built and wasn't.

**Reverse if:** users ask for trip tracking specifically, rather than for a
target to save toward. Then it returns as a *type* of goal, with dates — not as
a parallel concept.

---

## D-015 · Everything must be editable

**Decided.**

Every record the user creates or receives can be edited and deleted:
transactions, categories, recurring rules, goals.

This is a correction, not a feature. The app previously had no way to fix a
mistyped amount — enter $450 instead of $45 and it sat in the totals
permanently. For an app whose entire argument is that its numbers mean
something, uncorrectable numbers are disqualifying.

Specifics worth keeping:

- **Editing a verdict is allowed after the Sort undo window closes.** Realising
  two days later that something *was* a leak is the reflection the product wants
  to encourage, not an error to prevent.
- **Clearing a verdict back to unrated also unconfirms**, returning the row to
  the queue. Otherwise it would count toward totals with no judgement attached —
  the exact state the model exists to prevent.
- **Deleting a category keeps its transactions**, which become uncategorised.
- **Transaction edits save on dismissal, not per keystroke**, so editing an
  amount digit by digit doesn't rewrite the month's totals on every character.

**Reverse if:** never.

---

## D-016 · Spent and leaked need tightening

**Open.**

The two headline numbers are defined as:

- **Spent** — every transaction where `isConfirmed && !isSuperseded`
- **Leaked** — the subset the user marked `.leak` in the Sort queue

That is precise about *provenance* and vague about *meaning*. Three problems,
none of them bugs — the code does exactly what it says. The definitions are what
need work.

**Unsorted spend counts toward neither.** A purchase in the queue is real money
that appears in no total. Both numbers therefore understate, and worse, the
*ratio* between them moves with sorting habit rather than with spending: sort the
regrettable ones first and the ratio inflates; sort the boring ones first and it
collapses. The number the whole product rests on is currently sensitive to the
order in which the user clears a queue.

**The denominator includes fixed costs.** Rent and groceries sit in Spent, so the
same €200 of regret reads as 8% for someone with a large mortgage and 30% for
someone without. The ratio partly measures cost of living, which is not the thing
being measured. `Support/DiscretionarySpend.swift` existed for this and was
deleted in a1a88da alongside Trips — the machinery is gone and would need
rebuilding, not restoring.

**Refunds have no representation.** `amount` is positive everywhere. A returned
purchase stays in Spent permanently, and if it was marked a leak, in Leaked too.

Options, none chosen:

1. Show a third figure — unsorted — beside Spent and Leaked, making the gap
   visible rather than trying to close it
2. Compute the ratio over discretionary categories only, and say so in the label
3. Allow negative amounts as refunds, matched to an original transaction by the
   dedup machinery
4. Leave the definitions alone and fix it in copy — state what the number
   excludes wherever it appears

**Blocks:** any claim in marketing copy that the ratio is comparable between
people. Right now it isn't, and LISTING.md should not imply otherwise.

**Decide by:** before P3. A pricing page that quotes a number the number can't
support is worse than no number.

---

## D-017 · Firebase Auth for identity — supersedes D-012

**Decided.** Reverses D-012, which held that the app would have "a profile, not
an account."

Sign-in, registration and password reset run through Firebase Authentication.
Email and password, or Sign in with Apple. `FirebaseAuth` is the only linked
product.

**What changed the answer.** D-012 rejected accounts because email/password
needs somewhere to store credentials, hash them, and handle resets — a server.
That reasoning was correct and the conclusion was that we'd skip password reset
entirely. In practice a lock with no recovery path is a lock that loses people
their data, and a local-only profile can't survive a new phone.

**What Firebase holds:** email, password hash, Apple credential, a UID.

**What it never holds:** transactions, amounts, merchants, verdicts, goals,
categories, card labels. All of that stays in SwiftData and the user's own
private CloudKit database. This boundary is the whole reason the change is
acceptable, and it should be treated as load-bearing rather than incidental.

**Analytics stay out.** `GoogleAppMeasurement` and the on-device conversion SDK
resolve as part of the Firebase package graph. Neither is linked. Linking either
would put a tracker in an app whose pitch is that it has none.

**What this costs, honestly:**

- "No account. No server." is no longer true and can't be used in the listing
- The privacy label now has an entry where it had none
- Launch depends on a cached Firebase session. `AppGate` shows the welcome
  screen whenever `authentication.user == nil`, so a user whose session is
  missing while offline can't reach transactions stored on their own device.
  That failure mode did not exist before and has no mitigation yet.
- D-004's pricing argument still holds — Firebase Auth is free at this volume —
  but it is no longer true that there is *no* per-user infrastructure

**Rules out:** claiming zero third-party code. Any further Firebase product
(Firestore, Analytics, Crashlytics, Storage) without a new decision.

**Reverse if:** Apple ships a first-party identity service covering
email/password with recovery, or the product drops email sign-in and keeps only
Sign in with Apple — which would make the whole dependency unnecessary.
