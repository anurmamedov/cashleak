# Gates — record results here

Four checks that can change the plan. Each one has a place to write what
actually happened, because "I think it worked" is not a result you can act on
three weeks later.

Fill these in as you go. When a gate closes, update DECISIONS.md and
BUILD_PLAN.md in the same sitting.

---

## L1 · Does the verdict mechanic change behaviour?

**Started:** _____ **Ends:** _____ (two weeks later)

Log every purchase the day it happens. Apple Notes is fine — the point is the
labelling, not the tooling. If you postpone to the evening you'll rationalise,
and rationalised data answers a different question.

### Daily log

Copy this into Notes, one block per day:

```
Mon 11 Aug
  6.75  Blue Bottle       leak
 88.40  Loblaws           worth it
 34.20  Uber Eats         leak
```

Three columns only: amount, where, verdict. No categories, no notes. Adding
fields is how a two-week test becomes a chore you abandon on day five.

### Weekly tally

| Week | Spent | Leaked | Ratio | Notes |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |

### The question, answered at the end

Not "was this interesting" — it will be. The question is whether labelling
changed what you bought.

Concretely, by the end you should be able to answer:

- Did you ever **not buy something** because you knew you'd have to label it?
- Did week 2's ratio differ from week 1's? Which direction?
- Which purchases were **hard** to label? Those are where the product is
  actually operating — a purchase that's obviously worth it teaches nothing.
- Did you skip logging on any day? Which, and why?

**Verdict:** _____

**If it didn't move you**, that's the result. It cost two weeks instead of six,
and the honest response is to change the mechanic rather than build the rest of
the app around it.

---

## L2 · Is the Shortcuts message body readable?

**Run on:** _____ **iOS version:** _____

This decides whether bank alert capture is the v1.1 headline feature or a
consolation notification. One afternoon.

### Prior evidence — leans yes, still unconfirmed on device

Desk research, August 2026. Third-party reports, not Apple documentation.

**Message trigger.** A published workflow forwards incoming SMS bodies to a
webhook via a Message automation, which only works if the body is reachable as
Shortcut Input. A commenter in July 2025 reported not finding the option; another
confirmed in August 2025 with a screenshot that it still works. There is also a
"Forward SMS" App Store app built entirely on this mechanism, which wouldn't
exist if the body were inaccessible.

**Email trigger.** Better attested. Multiple users report Shortcut Input arrives
as a file whose *name* is the subject and whose *contents* are the body — so
regex extraction works directly. One caveat repeated in those threads: the
trigger matches on the **subject line, not the body**, so filtering has to use
something in the subject.

**A new problem this surfaced.** As of iOS 16.6, Message automation senders can
reportedly only be phone numbers — not the short codes banks use for mass
texting. Canadian bank alerts come from short codes almost exclusively.

If that still holds, sender-based filtering is unusable and every rule has to key
on **"Message contains"** instead. That's workable but changes the design:
onboarding can't say "pick your bank," it has to capture a distinctive phrase
from the user's own alert text. Worth testing deliberately in the same session.

**Treat all of this as a hypothesis.** Run the test below and record what your
device actually does.

### Not testable in the Simulator

Checked on iPhone 17 Pro / iOS 26.5: the Simulator ships a reduced set of system
apps — Fitness, Watch, Contacts, Files, Preview, Utilities, Safari, Messages.
**No Shortcuts, no Wallet, no Mail.** Simulator Messages also can't receive a
real SMS.

L2 and L3 both need the physical phone. The Simulator is still the right place
for everything else: building, the UI, and the test suite.

### Setup

1. Shortcuts → **Automation** tab → **+**
2. Choose **Message**
3. Sender: leave as any. **Message contains:** `zzztest`
4. **Run Immediately**, and turn off **Notify When Run**
5. Next → **New Blank Automation**
6. Add action: **Get Text from Input**
7. Add action: **Show Alert**, with the text from step 6 as its content
8. Save

### Test

Text yourself: `zzztest debit purchase $12.34 BLUE BOTTLE`

### Record exactly what the alert showed

```
Alert contents:
_______________________________________________
```

### Result

- [ ] **Full body text appeared** → bank alerts become the v1.1 headline.
      Automatic coverage roughly doubles. Next: collect real alert templates
      from each bank and write the parser.
- [ ] **Only sender or metadata appeared** → the trigger is a nudge. Fire a
      notification that deep-links into the add sheet. Useful, not magical.
- [ ] **Automation never fired** → check that Messages notifications are on and
      the automation is enabled. Retest before concluding anything.

**Also note:** did it fire instantly, or was there a delay? A trigger that takes
30 seconds changes the UX.

### Second test, same session — short code senders

The desk research says sender filtering may reject short codes, which is how
every Canadian bank texts.

1. In the automation, try setting **Sender** to a short code you've actually
   received from — check your Messages for one from RBC, TD, Scotiabank, BMO,
   CIBC, or Tangerine
2. Record whether the field accepts it

```
Short code tried: __________
Accepted?         __________
```

If it rejects short codes, every rule must key on "Message contains" instead.
That's still workable — it just means onboarding asks the user for a phrase from
their own alert rather than offering a list of banks to pick from.

---

## L3 · What does the Wallet trigger actually deliver?

**Run on:** _____ **Card used:** _____

The foundation of the product. Verify before designing further on top of it.

### Setup

Shortcuts → Automation → **+** → **Wallet** (called **Transaction** on iOS 25
and earlier) → pick a card → Run Immediately, Notify When Run **off** → New Blank
Automation → **Show Alert** with `Amount` and `Merchant` as content.

Use Show Alert rather than the CashLeak intent for this test — you want to see
the raw values, not what the app made of them.

### Tap-pay for something small, then record

| | Value |
|---|---|
| Amount, exactly as delivered | |
| Merchant, **verbatim** | |
| Seconds between tap and trigger | |
| Fired on a decline? | |
| Fired for a watch payment? | |
| Fired for in-app Apple Pay? | |

### Observed 2026-09-26 — Wallet's own transaction list

From the Wallet app on a CIBC Dividend Visa. **This is what Wallet displays, not
proof of what the Shortcuts trigger publishes** — the two are separate questions
and conflating them is what caused the last three findings. Still, it settles
the merchant format.

| | Finding |
|---|---|
| Merchant format | **Clean, Maps-resolved.** `Tim Hortons`, `No Frills`, `Walmart Supercentre`, `Hatsu Sushi` — not processor descriptors |
| Why | Wallet states it: *"Wallet uses Maps to provide merchant name, category, and location"* |
| Category | **Exists in Wallet.** Named in that sentence, and the row icons are category-derived — cart, fork, bag |
| Status | `Status: Approved` on the detail screen, so declines are distinguishable |
| Card | Shown as `Dividend Visa` |
| Timestamp | Full date and time — `2026-09-19, 4:32 PM` |
| Non-Apple-Pay rows | The `Apple` row has no "Apple Pay" subtitle. Wallet's feed is wider than what the automation fires on |

**Acted on already** — the merchant format is observed, not inferred:

- `MerchantCategoryHints` suggests a category from the clean name, because a
  clean name is matchable and `SQ *BLUE BOTTLE #4412` is not. Category only,
  never a verdict.
- Dedup's window is now 5 minutes within a source, 72 hours across sources.
  Clean chain names made repeat purchases match exactly, so two $4.19 coffees a
  day apart were being merged.
- `TestSupport` splits `walletMerchantFixtures` from `processorMerchantFixtures`.

**Still unanswered, and only the Details capture answers it:** whether the
trigger publishes the category, the status and the card, or only Amount and
Merchant.

### What else is in the payload?

Apple documents none of this, so the only way to know is to look. When you reach
the action's parameters, the variable bar above the keyboard lists everything the
trigger publishes. **Write down every name it offers**, not just the two we read:

```
Amount      ✓ known
Merchant    ✓ known
___________________________  →  value delivered: _______________
___________________________  →  value delivered: _______________
___________________________  →  value delivered: _______________
```

The three that would change the product if they exist:

| Field | Present? | Format |
|---|---|---|
| The card tapped | | |
| A timestamp of its own | | |
| A merchant category or MCC | | |

The app collects this for you too. The `Details` field on **Log transaction**
takes every remaining variable at once, stores it verbatim, and
**Profile › Capture log → Copy raw payload** hands it back. Use
both: Show Alert tells you the variable *names*, the Details field proves what
actually arrives when the automation runs unattended.

A category would remove the guesswork from auto-categorisation. A timestamp
would let us stop defaulting to `.now`. Absence is a finding too — record it
either way, then delete the `details` parameter.

### Merchant strings — collect at least ten

This is the real deliverable. Every string you record here becomes a fixture.

```
1. ______________________________
2. ______________________________
3. ______________________________
4. ______________________________
5. ______________________________
6. ______________________________
7. ______________________________
8. ______________________________
9. ______________________________
10. _____________________________
```

Include repeat visits to the same merchant — the interesting question is whether
the same shop delivers the same string twice.

**Then:** replace `merchantFixtures` in `cashleakTests/TestSupport.swift` with
these, and rerun the suite. The dedup tests currently pass against guesses at
Canadian card formats. Expect some to fail once real data lands — that failure
is the test doing its job.

---

## L4 · Is the name usable?

**Run on:** _____

| Check | Result |
|---|---|
| App Store search on device, "cashleak" | |
| App Store search, "cash leak" | |
| CIPO (Canada) | |
| USPTO class 9 | |
| USPTO class 42 | |
| cashleak.app / .com available | |
| Handles free on the platforms you'd use | |

**Decision:** _____

Descriptive marks are clear to users and weak to defend. If something similar
already exists in class 9, decide now rather than after the first TestFlight —
bundle identifiers are painful to change once builds are distributed.

Note that the bundle ID is already `cashleak`. Changing it before P6 is
annoying; after is worse.
