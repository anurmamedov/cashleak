# CashLeak

> Most spending apps tell you where your money went.
> This one tells you what it cost you.

An iOS spending tracker that captures Apple Pay taps automatically, lets you
label each purchase **worth it** or **leak**, and turns what you waste into
something concrete — like the trip you could have taken instead.

No account. No server. No bank login. No subscription.

---

## Status

Pre-v1, foundation in place. The core loop runs: add a purchase, sort it *worth
it* or *leak*, watch the Overview card respond.

Built so far — SwiftData models, five-tab shell, seeded debug dataset, number-pad
entry, the Sort queue, and the Overview leak card with its ratio ramp. 56 unit
tests cover merchant normalization, spending aggregates, the ramp rules,
recurring date maths, and the two model invariants.

Not yet built — Wallet capture, deduplication, recurring posting, Analysis,
Trips, notifications, and the widget. See [BUILD_PLAN.md](BUILD_PLAN.md).

**The four gate steps haven't run.** L1 in particular — two weeks of validating
the verdict mechanic by hand — is the one step that can invalidate everything
else here.

## Documents

| File | What's in it |
|---|---|
| [plan.md](plan.md) | Product thesis, screens, capture strategy, pricing, roadmap |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Layers, data model, capture pipeline, target layout |
| [DECISIONS.md](DECISIONS.md) | Why things are the way they are, and what's still open |
| [GIT_SETUP.md](GIT_SETUP.md) | Repo setup, push workflow, common git errors |
| [CLAUDE.md](CLAUDE.md) | Working conventions for AI assistance in this repo |

## Why no bank sync

Canada has no real open banking. Aggregators fall back on screen-scraping,
connections break constantly, and they charge per user per connected account —
which is why every app in this category is a $10–20/month subscription that wants
your bank credentials.

CashLeak never connects to a bank. Apple Pay taps arrive through a Shortcuts
automation, receipts are scanned on-device, everything else takes five seconds to
enter. Data lives on the phone and syncs through the user's own iCloud.

No aggregator means no per-user cost. No per-user cost means no subscription —
one-time purchase instead.

The trade-off is honest and stated in the UI: expect roughly 40–60% automatic
capture. Everything lands in a Sort queue unconfirmed, and one swipe confirms it.

## Build

| | |
|---|---|
| Platform | iOS 17.0+ |
| Language | Swift 5.9+ |
| Tooling | Xcode 15+ |
| Dependencies | None |

```bash
git clone https://github.com/anurmamedov/cashleak.git
cd cashleak
open cashleak.xcodeproj
```

Capabilities required on the target: iCloud + CloudKit, Background Modes
(background fetch), Push Notifications, and an App Group shared with the widget.

## Stack

SwiftUI · SwiftData · CloudKit (private database) · Swift Charts · App Intents ·
VisionKit · Vision · UserNotifications · WidgetKit · StoreKit 2

No backend. No analytics SDK. No third-party packages.

## Out of scope

Bank sync · net worth · investments · debt payoff · shared or household budgets ·
envelope and zero-based budgeting · income tracking · Android, web, Mac

Every one of these will be requested. Saying no is the strategy.

## Naming

The product is **CashLeak** — repository, Xcode project, bundle identifier, and
documents all agree. An earlier draft used "Kept"; that split is resolved in
[DECISIONS.md](DECISIONS.md#d-007).

The public App Store name isn't settled. "CashLeak" is descriptive, which reads
clearly but defends poorly as a trademark. Check the App Store, CIPO, and USPTO
classes 9 and 42 before locking a bundle ID — step L4.

## License

Proprietary. All rights reserved.
