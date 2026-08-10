# CLAUDE.md

Working instructions for Claude Code in this repository.

## Read first

[plan.md](plan.md) is the product spec. [ARCHITECTURE.md](ARCHITECTURE.md) is the
technical shape. [DECISIONS.md](DECISIONS.md) records what's settled and what's
open.

If a request contradicts one of those documents, say so before writing code. The
plan is more considered than any single request will be, and the contradiction is
usually worth surfacing rather than silently resolving.

## Project state

Pre-v1. Foundation is in: models, tab shell, seed data, and the core loop
screens (Add, Sort, Overview). See BUILD_PLAN.md for step-by-step status —
L6, L7, L9, L10, L11, L12, and L16 are done.

Not yet done: capabilities (L5), CloudKit two-device verification (L8), the
Wallet App Intent (L13), dedup (L14), recurring posting (L15), Analysis (L17),
Trips (L18), notifications and widget (L19), the real You screen (L20).

**All four gates — L1 to L4 — are still unrun.** Code written ahead of them
rests on assumptions, particularly the merchant fixtures in
`cashleakTests/TestSupport.swift`, which are guesses until L3 supplies real
strings.

The product is called **CashLeak**. Repo, project, bundle ID, and docs all agree.
See D-007 — the name isn't cleared for the App Store yet, but it's no longer
ambiguous internally.

## Keeping documents current

When a change makes a document wrong, fix the document in the same commit. These
files describe the project as it is, not as it was planned:

- **BUILD_PLAN.md** — mark steps done as they land. A plan nobody updates gets
  ignored within a week.
- **README.md** — the status section, when the project state changes materially.
- **ARCHITECTURE.md** — when structure, models, or the capture pipeline change.
- **DECISIONS.md** — add an entry when something is decided, and close open ones
  (D-007, D-008) when their gate runs. Supersede, never edit history.

Not every commit touches a document. A bug fix usually doesn't. A new model,
a resolved gate, or a completed step always does.

## Stack constraints

iOS 17.0+ · Swift 5.9+ · SwiftUI · SwiftData · CloudKit private database.

**No third-party dependencies.** Not for networking, not for charts, not for
utilities. If something seems to need a package, propose it and explain what
platform API falls short — don't add it.

**No backend, no analytics SDK.** Everything on-device or in the user's own
iCloud. A request that implies a server is a request to change the product.

## Conventions

- Feature folders own their views, view models, and local helpers. Code moves to
  a shared location when a *second* feature needs it, not in anticipation.
- SwiftData models stay free of view concerns. Formatting belongs in the view or
  a formatter, not on the model.
- `async`/`await` over Combine. Combine only where an Apple API demands it.
- Prefer plain `struct` views over generic wrappers. Concrete and duplicated
  beats clever and abstract at this size.

### CloudKit schema rules

Non-negotiable — CloudKit's SwiftData integration enforces them:

- Every property has a default value or is optional
- No `@Attribute(.unique)`; enforce uniqueness in application code
- Relationships are optional with explicit inverses

This is why dedup is application logic rather than a database constraint.

## Product rules that constrain code

These come from DECISIONS.md and shouldn't be relitigated in a pull request.

**Verdict lives on `Transaction`, never `Category`.** Don't add category-level
waste flags, auto-classification, or rule-based verdicts. The user decides, every
time.

**`isConfirmed` and `verdict` are separate.** Confirmed means "this is real."
Verdict means "I'd take it back." Never let a parser's claim count toward totals
before a human has seen it.

**Everything enters through the Sort queue unconfirmed**, regardless of source.
No capture path writes a confirmed transaction directly.

**Leak intensity maps to ratio, never amount.** A dark card for a legitimate
large purchase is a punishment. Interpolate continuously, hold the palest shade
until 10 transactions or a week of data, and invert the direction in dark mode.

**Dedup on every write**: `amount` exact + `date` within 72h + normalized fuzzy
merchant. Mark superseded, don't delete.

## Voice

UI copy states the number and the trade-off, then stops. It never scolds.

> `$412 leaked this month. That's 68% of your flight to Lisbon.`

Not `You wasted $412 — try harder next month.`

The same restraint applies to notifications. `$67.40 today — $18 over your
average` earns its interruption; `$67.40` doesn't.

## Out of scope

Bank sync · net worth · investments · debt payoff · shared or household budgets ·
envelope and zero-based budgeting · income tracking · Android, web, Mac.

If asked to build one of these, point at this list first. Saying no is the
strategy, not an oversight.

## Testing

Write unit tests for logic where being wrong is invisible:

- Merchant normalization and the dedup matcher
- Receipt field extraction against fixture images
- Recurring rule dates across DST and month-end boundaries
- Leak ratio and pace aggregates

Skip snapshot tests for SwiftUI. UI gets checked by hand at this project size.

## Git

`main` is the only long-lived branch. Feature branches aren't worth the ceremony
until v1 ships and `main` needs to stay working.

Commit in small logical chunks. Present-tense imperative subjects: `Add sort
queue`, not `Added sort queue` or `sort queue stuff`.

Never commit `*.p12`, `*.cer`, `*.mobileprovision`, `.env`, `Secrets.swift`,
`DerivedData/`, or `xcuserdata/`. All are in `.gitignore`; if one appears in
`git status`, something is wrong with the working directory, not the ignore file.

See [GIT_SETUP.md](GIT_SETUP.md) for remote configuration and common errors.

## When uncertain

Ask rather than guess, particularly about product behaviour. This project has an
unusually opinionated spec — the answer is often already written down in
plan.md or DECISIONS.md, and a wrong guess costs more than a question.
