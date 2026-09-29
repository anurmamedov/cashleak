# Automatic capture — what it would actually take

**Status:** research, not a decision. Nothing here has been built.
**Date:** 2026-09-28
**Question asked:** capture every payment — amount and merchant — into CashLeak,
worldwide, with no manual setup and no manual entry.

This document exists because the answer contradicts `plan.md`, `CLAUDE.md` and
`PRIVACY.md`, and that contradiction deserved more than a chat reply.

---

## 1. The short version

There is exactly one mechanism that delivers near-total capture: **bank account
aggregation**. Everything else is either impossible on iOS or covers a fraction
of spending.

It is achievable globally — the aggregators exist, the regulation now supports
it, and a solo developer can operate under an aggregator's licence rather than
obtaining one.

The reasons not to do it are **not** technical. They are: it inverts the
product's privacy promise, it costs real money per user per month forever, and —
the part that gets least attention — **it may break the product itself**. See
§7, which is the section I would read first.

---

## 2. What is impossible, and why

Ruled out on iOS. These are not "hard", they are closed.

| Approach | Why not |
|---|---|
| `FinanceKit` | Covers Apple Card, Apple Cash, Apple Savings only. All three are US-only. A bank card in Wallet is invisible to it — Wallet is the payment interface, the data belongs to the bank. Zero capture outside the US, near-zero inside it for anyone without an Apple Card. |
| Reading notifications | iOS has no equivalent of Android's notification listener. No app can read another app's notifications. A Notification Service Extension only touches your own push payloads. |
| Parsing bank SMS | No programmatic access to Messages. `ILMessageFilterExtension` sees only unknown senders, is sandboxed, and exists for spam filtering — using it to harvest transactions would be rejected, correctly. |
| Core NFC | Cannot intercept an Apple Pay tap. |
| `PassKit` | Exposes passes, not transactions. `PKPassLibraryDidChange` tells you a pass changed, not what was bought. |
| Screen scraping the Wallet app | No API, and an accessibility-API approach would be rejected and would deserve to be. |

**What we use today — the Shortcuts Wallet automation** — is not impossible, it
is just weak: roughly 50% ceiling (phone and watch taps only), and it requires
a nine-step manual setup that Apple gives no way to install on the user's
behalf. See `GATES.md` L3.

---

## 3. Bank aggregation — how it actually works

1. User taps "Connect your bank" and picks their institution.
2. They authenticate **on the bank's own page**, in a hosted flow. We never see
   the credentials.
3. The bank returns a consent token to the aggregator.
4. The aggregator sends us transactions — amount, merchant, date, and usually a
   category — via webhook, forever, until the user revokes consent.

**One login, roughly thirty seconds.** That is the honest comparison: it is
*less* manual than the Shortcuts automation we ship today, not more. And it
captures physical card taps, online purchases, e-transfers, pre-authorised
debits and subscriptions — the entire "what won't be captured" list in
`WalletSetupView` disappears.

---

## 4. Global coverage

No single provider covers the world. Realistic combinations:

| Region | Provider | Notes |
|---|---|---|
| US, Canada, UK, much of EU | **Plaid** | ~20 countries, >95% bank coverage. Covers CIBC and the other big Canadian banks. Free production trial for new US/Canada teams created after 2026-04-15, capped at 10 items. |
| Canada specifically | **Flinks** | Montreal, majority-owned by National Bank. Strongest Canadian coverage. |
| Europe, widest reach | **Salt Edge** | ~47 countries across Europe, the Americas, APAC and MENA. The broadest single footprint found. |
| Europe, deepest | **Tink** (Visa) | 3,400+ institutions, 18 markets. |
| Latin America | **Belvo** | >90% of institutions in Brazil, Mexico, Colombia. |

**"Whole world" is not on the table.** Large parts of Africa, South and
Southeast Asia have no aggregator coverage worth shipping. A realistic global
v1 is Plaid or Salt Edge for North America and Europe, with Belvo added if
Latin America matters. Two integrations, not one.

The regulatory tailwind is real: EU/UK have PSD2, Brazil has mandatory Open
Finance, Australia has the CDR, the US has CFPB 1033, and **Canada's
Consumer-Driven Banking Act received Royal Assent in March 2026** with read
access phasing in now. This is shifting from screen-scraping to
bank-supported APIs.

---

## 5. The licensing question — and the answer is better than expected

In the EU and UK, providing consolidated account information to end users is a
regulated activity. CashLeak is *exactly* that, so on the face of it we would
need our own AISP licence: home-country authorisation, passporting, professional
indemnity insurance. For a solo developer that is prohibitive.

**The agency model is the way through.** Aggregators let you operate as their
agent, under their licence:

- Plaid runs an explicit agency programme for apps not ready to hold their own
  AIS licence.
- Salt Edge runs a "Partner Program without licence".

This is real and widely used. Two caveats worth stating plainly:

- **It is not automatic.** You apply, they do due diligence, and they can
  decline. The licence-holder is liable for what their agent does, so they care.
- **It is a dependency on a commercial relationship.** If Plaid drops you, the
  product stops working in every regulated market at once.

Canada and the US are lighter — no AISP equivalent is required today — which is
why launching in North America first is materially simpler than launching
globally.

---

## 6. Cost

Plaid does not publish list pricing; it is negotiated on forecast volume.
Published ranges put Transactions at roughly **$0.30–$0.60 per connection per
month**, and it is a *subscription* — charged for as long as the connection
exists, not per fetch.

Rough monthly aggregator spend, one bank connection per user, at $0.45:

| Users | Monthly | Annual |
|---|---|---|
| 100 | ~$45 | ~$540 |
| 1,000 | ~$450 | ~$5,400 |
| 10,000 | ~$4,500 | ~$54,000 |

Plus a backend that does not exist today: token storage, webhook receiver,
encryption at rest, key management, uptime. Call it $20–50/month at small scale
on a managed platform, plus the engineering to build and maintain it.

**This forces a pricing decision.** D-018 ships v1 free. Free plus a recurring
per-user cost is a business that loses money faster the better it does. Bank
sync effectively requires the D-004 paid model to land first, or a subscription
— which `docs/index.html` currently promises never to charge:

> **No subscription.** Free today, a one-time unlock later — never a monthly bill.

A one-time unlock cannot fund a recurring per-user cost indefinitely.

---

## 7. What it does to the product — read this part twice

This is the argument I find most persuasive, and it has nothing to do with
privacy or cost.

**CashLeak's entire premise is that a human judges every transaction.** From
`CLAUDE.md`: *"Verdict lives on `Transaction`, never `Category`. Don't add
category-level waste flags, auto-classification, or rule-based verdicts. The
user decides, every time."* Everything flows through the Sort queue
unconfirmed, and the user swipes each one.

Today, capture is ~50% of taps. That is maybe 20–40 transactions a month
reaching the queue. Sorting them takes a couple of minutes a week, and the act
of judging each one *is the product*.

Bank sync delivers **everything**: every subscription, every bill, every
pre-authorised debit, every transfer — 100–200+ transactions a month. Now the
Sort queue is a chore. And the pressure to fix the chore is pressure to
auto-classify, which is precisely the thing D-002 forbids and the thing that
makes every other budgeting app forgettable.

This is the trap: **the feature that makes capture complete is the feature that
makes the product's core interaction unusable.** Bank-sync apps optimise for
completeness because they have to — nobody reviews 300 imported rows, so they
categorise automatically and show you charts. That is a different product, and
it is a crowded one.

A short list you sorted by hand is the product *working*, not a degraded version
of a complete one.

If bank sync happens, it needs an answer to this, designed up front. Options
worth considering: route only discretionary categories to the queue and let
fixed costs post silently; batch weekly rather than per-transaction; or make
sorting opt-in per connected account. None of these is obviously right.

---

## 8. What would have to change

Not code — commitments already filed with Apple.

| Document | Change |
|---|---|
| `CLAUDE.md` | *"Financial data never leaves the device or the user's own iCloud"* — false. *"A request to sync spending through a server is a request to change the product"* — this would be that request. |
| `plan.md` | Bank sync moves off the out-of-scope list. The list says saying no *"is the strategy, not an oversight."* |
| `PRIVACY.md` | Rewrite. A third-party processor now receives account data. |
| `LISTING.md`, `docs/index.html` | *"No bank connection. It never asks for banking credentials and couldn't use them."* — false. |
| App Privacy declarations | Refiled. Financial info becomes collected data linked to identity. |
| `DECISIONS.md` | New entry superseding the scope decision; D-018 revisited. |

Apple's review of finance apps handling bank data is stricter than a general
app's — expect scrutiny of the privacy policy, data deletion, and the
aggregator relationship. **This should be verified directly against current App
Review Guidelines before committing**; I have not confirmed the specifics.

---

## 9. Options

**A. Stay on-device. Fix the setup, not the mechanism.**
Keep the privacy promise and the App Store filings intact. Make the Shortcuts
setup dramatically easier, make sign-in skippable, and stop framing capture as
the foundation. Ceiling stays ~50%. Cost: zero. Risk: the app is never
"automatic" in the way a mainstream user expects.

**B. Bank sync, North America first.**
Plaid, US + Canada, where no AISP licence is needed. Smallest regulatory
surface, real coverage, free trial to prototype against. Defer Europe until it
is earning. Requires solving §7 and a paid tier.

**C. Bank sync, global from the start.**
Plaid or Salt Edge plus Belvo, agency model in the EU/UK. Everything in B plus
licensing due diligence, more integration surface, and GDPR obligations as a
data controller. Not a first move.

**D. Decide with evidence.**
Ship v1, watch what real TestFlight users do with the Shortcuts setup, then
choose. Costs a few weeks and answers the question properly.

---

## 10. Recommendation

**D, then B if the evidence supports it.**

The honest state of things: no build has been accepted by App Store Connect
yet, the test suite has not been confirmed green since the last four commits,
and L1, L2 and L4 have never run. Committing to a backend, a recurring cost, a
pricing model and a rewritten privacy posture — before a single external user
has opened the app — is a large bet placed on an assumption.

The assumption worth testing first is not *"can we capture more?"* It is
*"does anyone want to sort their spending at all?"* If week-two retention is
near zero, capture completeness was never the problem and bank sync would have
been an expensive way to find that out. If people do sort, and the thing they
complain about is missing transactions, that is a clear signal and option B
becomes well-founded rather than speculative.

Ten TestFlight users who are not you, left unhelped for two weeks, would settle
this.

---

## Sources

- [FinanceKit — Apple Developer](https://developer.apple.com/financekit)
- [Apple releases a new API to fetch transactions from Apple Card and Apple Cash — TechCrunch](https://techcrunch.com/2024/03/06/apple-releases-a-new-api-to-fetch-transactions-from-apple-card-and-apple-cash/)
- [Apple Card in Canada 2026 — Loans Canada](https://loanscanada.ca/credit/apple-card-in-canada/)
- [Canada Gazette, Part 1 — Consumer-Driven Banking Regulations](https://gazette.gc.ca/rp-pr/p1/2026/2026-06-27/html/reg3-eng.html)
- [Open banking in Canada: key insights into the proposed regulations — Norton Rose Fulbright](https://www.nortonrosefulbright.com/en-ca/knowledge/publications/83263b6e/open-banking-in-canada)
- [Plaid global coverage](https://plaid.com/global/)
- [Plaid pricing — US & Canada](https://plaid.com/pricing/)
- [FCA registration and how Plaid can help](https://plaid.com/blog/fca-registration-and-how-plaid-can-help/)
- [Salt Edge — data aggregation partner program without licence](https://www.saltedge.com/products/account_information/partner_program)
- [AISP agency models under PSD2 — FCA](https://www.fca.org.uk/firms/agency-models-under-psd2)
- [Belvo — open finance aggregation in Latin America](https://belvo.com/solutions/aggregation/)
- [Flinks vs Plaid](https://www.flinks.com/flinks-vs-plaid)
- [API aggregators in Canada — Open Banking Tracker](https://www.openbankingtracker.com/api-aggregators?country=CA)
