# Architecture

How CashLeak is put together and why. Product reasoning lives in [plan.md](plan.md);
this file is the technical view.

---

## Shape

A single-target SwiftUI app plus a widget extension. No backend, no networking
layer, no dependency graph to manage. SwiftData is the source of truth and
CloudKit replicates it to the user's own private database.

```
                    ┌─────────────────────────────┐
  Wallet automation │                             │
  Bank alert (?)    │  App Intents surface        │
  Receipt scan      │  (Intents/)                 │
  Manual entry      │                             │
                    └──────────────┬──────────────┘
                                   │  unconfirmed Transaction
                                   ▼
                    ┌─────────────────────────────┐
                    │  Dedup + validation         │
                    └──────────────┬──────────────┘
                                   ▼
                    ┌─────────────────────────────┐
                    │  SwiftData ModelContainer   │───▶ CloudKit (private)
                    └──────────────┬──────────────┘
                                   ▼
                    ┌─────────────────────────────┐
                    │  Sort queue → verdict       │
                    └──────────────┬──────────────┘
                                   ▼
                     Overview · Analysis · Trips · Widget
```

Everything enters through one funnel and lands in the Sort queue unconfirmed,
regardless of source. That single invariant is what lets partial capture coverage
be honest rather than broken — a bad parse or a declined transaction is visible
and dismissible instead of silently corrupting the dataset.

## Target layout

```
cashleak/
├── App/                  entry point, shared ModelContainer, tab shell
├── Models/               SwiftData @Model types, enums, seed data
├── Features/
│   ├── Overview/         hero leak card, intensity ramp, trip card
│   ├── Sort/             queue, verdict swipe
│   ├── Entry/            number pad
│   ├── Analysis/         range selector, charts, leaderboards, drill-downs
│   ├── Trips/            forecast, live burn rate
│   └── Settings/         capture status, preferences, export, privacy
├── Intents/              App Intents surface
├── Support/              aggregates, dedup, ramp, formatting, settings
├── Resources/            city cost index
├── Notifications/        not built — L19
└── Widgets/              not built — L19
```

Feature folders own their views, view models, and any feature-local helpers.
Shared code moves up only once a second feature actually needs it — not in
anticipation.

`Support/` wasn't in the original plan; it emerged from that rule. It now holds
`LeakRamp`, `MerchantNormalizer`, `DeduplicationMatcher`, `TransactionIngest`,
`SpendingSummary`, `AnalysisAggregates`, `RecurringPoster`, `DiscretionarySpend`,
`CSVExport`, and `AppSettings` — each promoted when a second feature reached for
it.

## Data model

Five SwiftData `@Model` types.

| Model | Key fields |
|---|---|
| `Transaction` | `amount`, `currencyCode`, `date`, `merchant`, `normalizedMerchant`, `note`, `source`, `isConfirmed`, `isSuperseded`, `verdict`, `category`, `trip`, `receiptImage` |
| `Category` | `name`, `icon`, `colorHex`, `kind`, `monthlyBudget`, `sortIndex` |
| `Trip` | `name`, `destination`, `startDate`, `endDate`, `fixedCosts`, `costMultiplier`, `dailyDiscretionaryAtEstimate`, `transactions` |
| `RecurringRule` | `merchant`, `amount`, `cadence`, `nextRunDate`, `lastPostedDate`, `isEnabled` |
| `CardAutomation` | `label`, `isConfigured`, `createdAt`, `lastCapturedAt` |

Two fields exist purely to serve invariants rather than the UI.
`normalizedMerchant` is written on every save so dedup never compares raw
strings, and `isSuperseded` marks merged duplicates without deleting them.

`Trip.estimatedBudget` is computed, not stored — but
`dailyDiscretionaryAtEstimate` is a deliberate snapshot, so a past trip's
forecast doesn't drift as later spending changes the average.

`CardAutomation` is **self-reported**. No API lists Wallet cards or reports
whether a Shortcuts automation exists, so the user marks it themselves.
`lastCapturedAt` provides a factual counterweight — a card claiming to be active
with nothing captured in a fortnight says so.

```swift
enum TransactionSource: String, Codable {
    case applePay, bankAlert, scan, recurring, manual
}

enum Verdict: String, Codable {
    case worthIt, leak, unrated
}

enum CategoryKind: String, Codable {
    case need, want
}
```

### Two rules that are load-bearing

**`verdict` belongs to `Transaction`, never to `Category`.** A category-level
waste flag says "eating out is a leak," which is a lie the moment one of those
meals mattered. The whole product rests on the user judging individual purchases,
so the schema has to make the per-category shortcut impossible.

**`isConfirmed` is separate from `verdict`.** Confirmation means "this
transaction is real"; verdict means "I'd take it back." An unconfirmed
transaction is a claim from a parser. Collapsing them would let a mis-parsed SMS
count toward totals before a human ever saw it.

### CloudKit constraints

CloudKit's SwiftData integration forces some schema discipline:

- Every property needs a default value or must be optional
- No `@Attribute(.unique)` — uniqueness has to be enforced in application code
- Relationships must be optional and need explicit inverses

This is why deduplication is a code-level concern rather than a database
constraint.

## Capture pipeline

### Apple Pay — Shortcuts Wallet automation

No public API reads Apple Pay transactions. `PassKit` only accepts payments;
`FinanceKit` is US/UK-only, entitlement-gated, and requires a Finance category
listing. The workable path is the Shortcuts Wallet automation trigger (iOS 17+,
called "Transaction" before iOS 26), which passes `Amount` and `Merchant` into an
exposed App Intent.

```swift
struct LogWalletTransaction: AppIntent {
    static var title: LocalizedStringResource = "Log Transaction"
    static var openAppWhenRun = false

    @Parameter(title: "Amount") var amount: Double
    @Parameter(title: "Merchant") var merchant: String?

    func perform() async throws -> some IntentResult { /* ... */ }
}
```

`openAppWhenRun = false` matters — the intent has to write to the store from the
background without stealing focus mid-checkout.

Coverage is partial by construction:

| Captured | Not captured |
|---|---|
| NFC Apple Pay taps (phone, watch) | Physical card taps, chip-and-PIN |
| One automation per card | In-app and web Apple Pay |
| | Interac e-transfer, PADs, cash |

The trigger also fires on **declined** transactions and can time out when the
issuer delivers late. Both are handled by the unconfirmed-queue rule rather than
by trying to detect them.

### Bank alerts — unresolved

Gated on one unanswered question: does the Shortcuts Message trigger expose the
message **body** as readable Shortcut Input? Desk research leans yes — a
published SMS-to-webhook workflow depends on it — but it hasn't been confirmed on
device. See [GATES.md](GATES.md).

A second question surfaced alongside it: Message automations may only accept
phone numbers as senders, not the **short codes** Canadian banks text from. If
so, every rule has to key on message text instead, and onboarding can't offer a
list of banks to pick from.

`IdentityLookup` / `ILMessageFilterExtension` is not an alternative — Apple
sandboxed it specifically so a filter extension cannot pass message content to
its containing app.

If the body is readable, regex extraction roughly doubles automatic coverage and
becomes the v1.1 headline. If not, the trigger degrades to a notification that
deep-links into the add sheet.

### Deduplication

Required from day one, not deferred. A single phone tap can fire the Wallet
trigger *and* a bank alert, producing two records for one purchase.

Match key: **`amount` exact** + **`date` within 72h** + **normalized fuzzy
merchant match**.

The 72-hour window accommodates issuer settlement delay. Merchant normalization
has to strip the noise real feeds carry — store numbers, city suffixes, `SQ *`
and similar processor prefixes — before comparing.

When two records match, keep the richer one and mark the other superseded rather
than deleting, so a wrong merge stays recoverable.

### Receipts

`VisionKit` `DataScannerViewController` for live capture, `Vision`
`VNRecognizeTextRequest` with `.accurate` for OCR. Entirely on-device.

Three fields only: **total** (largest currency figure in the bottom third),
**merchant** (largest text in the top fifth), **date**. Each carries a confidence
badge the user can glance-correct. Line items are explicitly out of v1 — layout
variance across receipts turns them into a permanent support burden.

## Notifications

`UNNotificationContent` is frozen at schedule time, so a repeating trigger cannot
carry a live total. The workaround:

1. Schedule a daily fallback at 21:00.
2. On every `Transaction` write, recompute today's total, remove the pending
   request by identifier, and re-add it with the fresh figure.
3. Register a `BGAppRefreshTask` in the afternoon so auto-posted recurring items
   land even when the app hasn't been opened.

Copy carries meaning or it gets swiped away: `$67.40 today — $18 over your
average`, not `$67.40`. Tapping opens the Sort queue.

## Presentation rules

**Leak intensity.** The Overview card background deepens across four bands as the
leak *ratio* rises — under 15%, 15–25%, 25–40%, over 40%.

- Darkness maps to ratio, never to amount spent. A dark card for buying a laptop
  is a punishment, and punished users delete finance apps.
- Interpolate continuously; never snap between bands.
- Hold the palest shade until there's meaningful data — 10 transactions or a
  week — or one early leak reads as 100%.
- It must work in reverse. "Lightest month since March" is the retention moment.
- Dark mode inverts: deepening means going lighter.

**Navigation.** Five slots — `Overview · Sort · [Add] · Analysis · You`. Native
`TabView` so iOS 26 tab bar styling is inherited rather than reimplemented. Trips
is a card on Overview and a row in You, not a tab; it's used a few times a year
and doesn't earn permanent space.

## Testing

Unit tests cover the parts where being wrong is invisible:

- Merchant normalization and the dedup matcher
- Receipt field extraction against a fixture set of real receipt images
- Recurring rule date maths across DST boundaries and month-end
- Leak ratio and pace aggregates

UI is verified by hand. Snapshot testing SwiftUI at this project size costs more
than it returns.
