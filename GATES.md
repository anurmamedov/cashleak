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

---

## L3 · What does the Wallet trigger actually deliver?

**Run on:** _____ **Card used:** _____

The foundation of the product. Verify before designing further on top of it.

### Setup

Shortcuts → Automation → **+** → **Transaction** (called **Wallet** before
iOS 26) → pick a card → Run Immediately, Notify When Run **off** → New Blank
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
