# Kept

> Most spending apps tell you where your money went.
> This one tells you what it cost you.

**Find your cash leaks. No bank login.**

An iOS spending tracker that captures Apple Pay taps automatically, lets you
label each purchase *worth it* or *leak*, and turns what you waste into
something concrete — like the trip you could have taken instead.

No account. No server. No subscription.

> Name is provisional. Verify on the App Store, CIPO, and USPTO (classes 9 and
> 42) before locking the bundle ID. "Cash Leak" stays as the in-app feature
> name — it's descriptive, which makes it clear but weak as a trademark.

---

## The constraint that became the product

Canadian bank sync doesn't work properly. There's no real open banking here, so
aggregators fall back on screen-scraping, connections break constantly, and apps
quietly drop Canadian bank support. Those aggregators also cost money per user
per connected account, which is why every app in this category is a $10–20/month
subscription that wants your bank credentials.

Kept never connects to a bank. Apple Pay taps arrive through a Shortcuts
automation, receipts are scanned on-device, everything else takes five seconds to
enter. Data lives on your phone and syncs through your own iCloud.

No aggregator means no per-user cost. No per-user cost means no subscription.

## The idea

Tracking spending is easy and useless — everyone already knows they spend too
much. What nobody knows is *which* of it they'd take back.

So the app asks one question per purchase: **worth it, or leak?**

One swipe. The user decides — never an algorithm, never a category rule. Coffee
isn't a leak; the fourth coffee this week might be, and only they know that.

Then it converts leaks into something they want:

> **$412 leaked this month.** That's 68% of your flight to Lisbon.

---

## Screens

**Overview** — leak total as the hero, in a card whose colour deepens with the
leak *ratio*. Spent / pace / kept as secondary stats. Leak breakdown by category.
Active trip card. Every element taps through to Analysis.

**Sort** — one queue for everything, regardless of source. Each item gets a
category and a verdict. Source badges: Pay, Scan, Auto, Manual. Empty state is a
reward, not a blank slate.

**Add** — centre button in the tab bar. Number pad first, category chip, done.

**Analysis** — range selector, then six sections in order: spent-vs-leaked trend,
categories, merchant leaderboard, day-of-week pattern, and one plain-language
finding in serif at the bottom. Every row is a link.

**You** — Apple Pay card automations and their status, accent picker, daily
notification time, categories, recurring rules, trips, CSV export, privacy.

### Navigation

Five slots: `Overview · Sort · [Add] · Analysis · You`

Trips is not a tab. It's a card on Overview and a row in You — used a few times a
year, so it doesn't earn permanent space. Analysis does. Use SwiftUI's native
`TabView` so it picks up iOS 26 tab bar styling automatically.

---

## Design

**Direction: editorial.** Big type, one strong colour, the leak figure as the
hero rather than the monthly total. The main screen should state the product
thesis in its top third — that's what makes a screenshot legible to a stranger.

**Palette.** Coral as the leak accent, teal for "worth it", green for
improvement, everything else neutral. One accent, one warning, nothing
decorative. User-selectable accent in settings.

**Leak intensity.** The Overview card background deepens across four steps as the
leak ratio rises: under 15%, 15–25%, 25–40%, over 40%. Rules:

- Map darkness to leak *ratio*, never to amount spent. A heavy month may be
  entirely justified; a dark card for buying a laptop is a punishment, and
  punished users delete finance apps.
- Interpolate continuously. Never snap.
- Hold the palest shade until there's meaningful data (10 transactions or a
  week), or a single early leak reads as 100%.
- Make it work in reverse — "lightest month since March" is the retention moment.
- Dark mode inverts the direction: deepening means going *lighter*.

**Voice.** Never scold. State the number, state the trade-off, stop.

---

## Capture

### Apple Pay — Shortcuts Wallet automation

There is no public API for reading Apple Pay transactions. `PassKit` only lets
you *accept* payments. `FinanceKit` is US-only (Apple Card / Cash / Savings) and
UK-only (open banking), needs a per-bundle-ID entitlement, and requires Finance
category listing with US/UK distribution.

The workable path is the **Shortcuts Wallet automation trigger** (iOS 17+, named
"Transaction" before iOS 26). The user creates a personal automation on a chosen
card; it passes `Amount` and `Merchant` into an exposed App Intent.

```swift
struct LogWalletTransaction: AppIntent {
    static var title: LocalizedStringResource = "Log Transaction"
    static var openAppWhenRun = false

    @Parameter(title: "Amount") var amount: Double
    @Parameter(title: "Merchant") var merchant: String?

    func perform() async throws -> some IntentResult { /* ... */ }
}
```

**Coverage is partial — design for it, and say so in the UI.**

| Captured | Not captured |
|---|---|
| NFC Apple Pay taps (phone, watch) | Physical card taps and chip-and-PIN |
| One automation per card | In-app and web Apple Pay |
| | Interac e-transfer, PADs, cash |

Also: the trigger fires on *declined* transactions, and can time out when the
issuer delivers the transaction to Wallet late. Expect 40–60% automatic coverage
in practice.

Mitigation: everything lands in the Sort queue unconfirmed. One swipe confirms.
Declines and bad merchant strings never reach the dataset. The You tab lists each
card's automation status and states plainly what won't appear — setting that
expectation up front prevents the worst review you can get.

### Bank alerts — OPEN QUESTION, test before committing

**Status: unresolved. Decide this before planning v1.1.**

iOS gives apps no way to read SMS or email. `IdentityLookup` /
`ILMessageFilterExtension` exists but is deliberately sandboxed so a filter
extension cannot pass message content back to its containing app — Apple built
it that way specifically to prevent this use.

**Shortcuts can, though.** Communication triggers cover both channels:

- **Message** — fires on sender, or on a phrase the message contains
- **Email** — fires on sender, subject phrase, account, or recipient
- Multiple criteria are ANDed
- Since iOS 17 both run immediately, no confirmation tap

So a user could wire: *message from RBC containing "debit"* → `LogTransaction`.
That would cover physical card taps, Interac e-Transfers, and online purchases —
precisely the gaps the Wallet trigger leaves.

#### The test that decides it

Unconfirmed: whether the message **body text** is exposed as Shortcut Input in a
parseable form. Documented examples use Shortcut Input to identify the *sender*
for auto-replies, which proves a message object is passed but not that its text
is readable.

One afternoon to find out:

1. Shortcuts → Automation → Message, any sender, contains a test word
2. Actions: `Get Text from Input` → `Show Alert`
3. Text yourself; check whether the body appears

**If the body is readable** — regex out amount and merchant. Automatic coverage
roughly doubles. This becomes the v1.1 headline feature and is what makes
coverage feel complete rather than partial.

**If it isn't** — the trigger is only a nudge. Fire a notification ("log this?")
that deep-links into the add sheet. Still useful, far less magical.

#### Caveats to plan around

- **Email trigger only works with Apple Mail.** Gmail app users get nothing.
- **Setup burden is heavy.** One automation per bank, and the user must know
  their bank's sender ID and alert wording. Ship presets for RBC, TD,
  Scotiabank, BMO, CIBC, and Tangerine or nobody will complete it.
- **Formats change.** Parsers will break silently when a bank tweaks a template.
  Everything routes to the Sort queue unconfirmed so a bad parse is visible.
- **Duplicates.** A phone tap fires the Wallet trigger *and* the bank alert. The
  dedup rule (amount + 72h + fuzzy merchant) is required from day one, not v2.
- **Alerts aren't universal.** Many people have them off, or only above a
  threshold. Onboarding has to walk them through enabling it in their bank app.

### What still can't be captured

Even with both triggers working, these need recurring rules or manual entry:
pre-authorized debits (rent, hydro, insurance), online bill payments, and cash.
Most are large and predictable, so recurring rules handle them after one setup
session — roughly 40–60% of typical total spend.

### Reconcile — proposed

Monthly, the user reads their statement total from their banking app and types
that one number in. The app shows the gap:

> You logged $1,284. Your statement says $1,510. $226 unaccounted for — 85%
> coverage.

Takes 30 seconds, tells the user how far to trust their own data, and makes
missing money visible without pretending it was captured. Not in v1 scope; add
once real coverage numbers are known.

### Receipts

`VisionKit` `DataScannerViewController` for live capture, `Vision`
`VNRecognizeTextRequest` (`.accurate`) for OCR. Fully on-device.

Parse reliably: **total** (largest currency figure in the bottom third),
**merchant** (largest text in the top fifth), **date**. Show a confidence badge
per field and let the user glance-correct — silently guessing wrong is how
receipt scanning gets a reputation for being useless.

Do not attempt line items in v1. Layout variance makes it a support burden.

### Manual

Number pad opens first. Amount → category chip → done. No mandatory notes, no
date picker. Remember category by merchant so repeat purchases need only a
verdict.

---

## Data model

| Model | Key fields |
|---|---|
| `Transaction` | `amount`, `currency`, `date`, `merchant`, `note`, `source` (`.applePay` / `.bankAlert` / `.scan` / `.recurring` / `.manual`), `isConfirmed`, `verdict` (`.worthIt` / `.leak` / `.unrated`), `category`, `trip`, `receiptImage` |
| `Category` | `name`, `icon`, `colorHex`, `kind` (`.need` / `.want`), `monthlyBudget` |
| `Trip` | `name`, `destination`, `startDate`, `endDate`, `estimatedBudget`, `costMultiplier`, `transactions` |
| `RecurringRule` | `template`, `cadence`, `nextRunDate`, `lastPostedDate` |

`verdict` lives on `Transaction`, not `Category`. Category-level waste flags
produce dishonest data.

**Deduplication.** If bank sync is ever added, tap-captured and feed-imported
records will collide. Key: `amount` + `date` within 72h + normalized fuzzy
merchant match. Build it now.

---

## Daily notification

`UNNotificationContent` is fixed at schedule time, so a repeating trigger can't
carry a live total.

1. Schedule a daily fallback at 21:00.
2. On every `Transaction` write, recompute today's total, remove the pending
   request by identifier, re-add with the fresh figure.
3. Register a `BGAppRefreshTask` in the afternoon so auto-posted recurring items
   land even if the app hasn't been opened.

Copy should carry meaning: `$67.40 today — $18 over your average`, not `$67.40`.
Tapping it opens the Sort queue.

---

## Trips

Two estimation modes:

- **Bottom-up** — flights, lodging, daily food, activities, transport, buffer,
  with templates by trip type.
- **Personalized** — `their real daily discretionary spend × destination cost
  multiplier × days + fixed costs`. This is the differentiator. A generic
  calculator says "$80/day for food"; this says "you average $34/day, Lisbon runs
  0.8× Toronto, budget $27/day."

Ship a hand-curated cost index for ~150 cities in v1.

During the trip: live burn rate vs. plan with days remaining. After: actual vs.
estimate, which sharpens the next one.

---

## Stack

SwiftUI · SwiftData · CloudKit (private database) · Swift Charts · App Intents ·
VisionKit · Vision · UserNotifications · WidgetKit · StoreKit 2

iOS 17.0+ · Swift 5.9+ · Xcode 15+

No backend. No analytics SDK. No third-party dependencies.

Capabilities required: iCloud + CloudKit, Background Modes (background fetch),
Push Notifications, App Group shared with the widget target.

```
Kept/
├── App/                  entry point, ModelContainer
├── Models/               SwiftData @Model types
├── Features/
│   ├── Overview/
│   ├── Sort/             queue, verdict swipe
│   ├── Entry/            number pad, receipt scan
│   ├── Analysis/
│   ├── Trips/
│   └── Settings/
├── Intents/              App Intents surface
├── Notifications/
├── Widgets/
└── Resources/            city cost index
```

---

## Pricing

One-time purchase, $19.99 CAD. Seven-day StoreKit trial. No free tier, no ads.

Marginal cost per user is effectively zero, so this undercuts the category
structurally rather than promotionally. Anything that genuinely costs money per
user later (AI monthly summaries, cost-index refresh) can be a separate optional
layer. Charge for what costs something; give away what doesn't.

---

## Explicitly out of scope

Bank sync · net worth · investments · debt payoff · shared or household budgets ·
envelope and zero-based budgeting · income tracking · Android, web, Mac

Every one of these will be requested. Saying no is the strategy.

---

## Roadmap

- [ ] **v1.0** — entry, Sort queue, verdicts, Overview, Analysis, recurring,
      trips, daily notification, widget
- [ ] **v1.1** — receipt scan, bank alert capture *(pending the Shortcut Input
      test)*
- [ ] **v1.2** — Reconcile, optional AI monthly summary (aggregates only, never
      raw transactions)
- [ ] **v2.0** — evaluate FinanceKit for a US launch

## Open questions

| Question | Blocks | How to resolve |
|---|---|---|
| Does the Shortcuts Message trigger expose the message body as readable input? | Bank alert capture, v1.1 scope | Run the three-step test above. One afternoon. |
| Final name | Bundle ID, domain, handles | App Store search on device, CIPO, USPTO classes 9 and 42, registrar |
| Price point — is $19.99 right? | Launch | Guess until trial-to-purchase data exists |
| Does the verdict mechanic actually change behaviour? | Everything | Two weeks of manual self-testing before writing code |

## Before writing code

Validate the verdict mechanic manually for two weeks — even in Notes. Log
everything, label each purchase, and see whether it actually changes behaviour.
If it doesn't move you, it won't move a stranger, and that's a two-week lesson
instead of a six-week one.

## License

Proprietary. All rights reserved.
