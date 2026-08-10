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

## D-008 · Shortcuts message body — untested

**Open.** Blocks bank alert capture and therefore v1.1 scope.

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
