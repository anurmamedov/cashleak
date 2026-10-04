# App Store listing

Draft copy for P8. Character counts are Apple's hard limits — App Store Connect
rejects anything over.

| Field | Limit | Indexed for search |
|---|---|---|
| Name | 30 | Yes |
| Subtitle | 30 | Yes |
| Keywords | 100 | Yes |
| Promotional text | 170 | No |
| Description | 4,000 | No |

Only name, subtitle and keywords affect search ranking. The description sells to
someone already on the page; it does nothing for discovery.

## Category

**Primary: Finance. Secondary: Productivity.**

The record was first created as Business → Productivity, which is wrong. Category
decides which top charts and browse sections the app appears in, and therefore
who it is ranked against. In Business it competes with invoicing and CRM tools
and is invisible to anyone looking for a spending tracker.

Finance is also where the pricing argument lands. The apps beside us there are
$10–20/month subscriptions funded by aggregator fees we do not pay — being on
that shelf is the whole comparison.

---

## Name

```
CashLeak
```

8 characters. Pending the L4 trademark check — descriptive marks read clearly and
defend poorly.

---

## Subtitle

```
No bank login. Ever.
```

20 characters.

The original line — "Find your cash leaks. No bank login." — is 36 and doesn't
fit. Of the two halves, this is the one worth keeping: it answers the first
question anyone asks about a spending app, and it's the one claim competitors
structurally can't copy. Every aggregator-based app needs the credentials.

Alternatives, all within limit:

| Line | Chars | Leads with |
|---|---|---|
| Worth it, or a leak? | 20 | The mechanic |
| Find what you'd take back | 25 | The benefit |
| Spending, minus the guilt | 25 | The feeling |

---

## Promotional text

Editable without shipping a build, so this is where seasonal or reactive copy
goes.

```
Label each purchase worth it or leak. See what you'd take back — and what it
cost you. Your flight to Lisbon, maybe.
```

118 characters.

---

## Keywords

Comma-separated, no spaces after commas — spaces waste characters. Don't repeat
words already in the name or subtitle; Apple indexes those separately.

```
spending,expense,tracker,budget,money,apple pay,goals,privacy,no bank,canada,leak,habit,face id
```

95 characters, under the 100 limit. `receipt` and `no sync` were removed —
receipt scanning isn't built yet, and the app does sync through iCloud — and
`leak` is kept although it's in the name, so drop it first if space is needed.

---

## Description

Opens on the thesis. Someone who reads two lines and leaves should still know
what makes this different.

```
Most spending apps tell you where your money went. This one tells you what it
cost you.

Tracking spending is easy. Knowing which of it you'd take back is harder.

CashLeak asks one question per purchase: worth it, or a leak?

One swipe, and you decide — not an algorithm or a category rule. Coffee isn't a
leak. The fourth coffee this week might be, and only you know that.

Then it puts what you'd take back next to something you want:

"$412 leaked this month. That's 68% of your flight to Lisbon."


NO BANK LOGIN

CashLeak doesn't connect to your bank or ask for banking credentials.

Apple Pay purchases can arrive automatically through a Shortcuts automation you
set up once. Recurring bills post themselves. Anything else takes a few seconds
to add.

Your spending is stored on your phone and synced through your own iCloud. We
don't receive it.


CLEAR ABOUT WHAT IT CATCHES

Apple Pay purchases from your iPhone and Apple Watch can be added automatically.
Physical card taps, in-app purchases, e-transfers and cash aren't, because apps
can't see those without a bank connection.

Recurring bills cover the predictable part: rent, insurance, subscriptions,
phone. The rest takes a moment to add by hand. The app explains this in its
setup screen.


WHAT'S INSIDE

• A monthly overview: what you spent, how much you'd take back, and today's
  purchases at a glance

• A Sort queue where new purchases wait until you've seen them, so nothing
  counts before you've confirmed it

• Analysis for the month, three months or a year, with findings in plain
  words: "The week of Sep 20 was your leakiest week."

• Goals that turn your leak total into something concrete

• Face ID to sign in and to lock the app

• CSV export, so your data is always yours to take


FREE

No subscription and no ads. Your spending data isn't sold, because we don't
receive it.


PRIVACY

Signing in uses your email address or Sign in with Apple. The app includes no
analytics, advertising or tracking tools.

Your purchases, amounts, shops and judgements are stored on your phone and in
your own private iCloud, which we have no access to.
```

~2,250 characters. Room to grow.

---

## What's in the App Store screenshots

Lead with the leak card. It states the thesis in the top third of the screen,
which is what makes the first screenshot legible to someone scrolling.

1. Overview — this month's spending, the leak share and the goal comparison
2. Sort — mid-swipe, with source badges visible
3. Analysis — the weekly bars with a finding beside them
4. Today — the day's purchases with their verdict pills
5. Apple Pay setup — the step-by-step guide, because being clear about what's
   captured is a feature

---

## Notes for review

Expect at least one rejection round. The likely flag is the Shortcuts
dependency — reviewers may read "requires setting up an automation" as the app
being incomplete.

Review notes should state plainly: the app is fully functional without any
automation. Manual entry and recurring bills work on their own. The Shortcuts
automation is an optional convenience for Apple Pay users, and the app explains
how it works, and its limits, in Profile › Apple Pay capture.

Also mention: Profile › Delete account deletes the account in-app (guideline
5.1.1(v)), and Profile › Privacy links to the full privacy policy at
https://karasandlabs.com/cashleak/privacy/.

**URLs for App Store Connect:** Privacy Policy
`https://karasandlabs.com/cashleak/privacy/` · Support
`https://karasandlabs.com/cashleak/`.
