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
spending,expense,tracker,budget,money,apple pay,receipt,privacy,offline,no sync,canada,leak,waste,habit
```

103 characters — trim one term before submitting. Drop `waste` first; `leak`
already covers the concept and appears in the name.

---

## Description

Opens on the thesis. Someone who reads two lines and leaves should still know
what makes this different.

```
Most spending apps tell you where your money went. This one tells you what it
cost you.

Tracking spending is easy and useless. You already know you spend too much. What
you don't know is which of it you'd take back.

CashLeak asks one question per purchase: worth it, or a leak?

One swipe. You decide — never an algorithm, never a category rule. Coffee isn't a
leak. The fourth coffee this week might be, and only you know that.

Then it turns what you'd take back into something you actually want:

"$412 leaked this month. That's 68% of your flight to Lisbon."


NO BANK LOGIN

CashLeak never connects to your bank. It can't — there's no code in it that
could.

Apple Pay taps arrive automatically through a Shortcuts automation you set up
once. Recurring bills post themselves. Anything else takes five seconds on a
number pad that opens ready to type.

Your data lives on your phone and syncs through your own iCloud. There is no
CashLeak server. There is no account to create.


HONEST ABOUT WHAT IT CATCHES

Apple Pay taps from your phone and watch arrive on their own. Physical card taps,
in-app purchases, e-transfers and cash don't — no app can see those without your
bank credentials.

Recurring rules cover the predictable rest: rent, insurance, subscriptions,
phone. What's left takes a moment to add by hand.

The app tells you this up front, on the settings screen, before you've spent a
month wondering why something's missing.


WHAT'S INSIDE

• A leak total that deepens in colour as the share of regretted spending rises —
  tied to the ratio, never the amount, so a big month you meant to have doesn't
  get treated as a failure

• A sort queue where everything lands unconfirmed until you've seen it, so a
  mis-read receipt never quietly counts

• Charts that end in a sentence, not another chart: "Friday is your most
  expensive day. It costs about $52 more than a Tuesday."

• Trip forecasts built from your own daily spending and a cost index for 78
  cities — not a generic per-diem

• CSV export, because data you can't take out isn't really yours


ONE PRICE, ONCE

No subscription. No free tier that nags. No ads, ever.

Most apps in this category charge monthly because they pay an aggregator for
every bank connection. CashLeak has no aggregator and no server, so it has no
per-user cost to pass on.

Seven-day trial, then a single purchase.


PRIVACY

No account. No analytics. No tracking SDK. No crash reporter.

Receipt scanning runs on-device with Apple's Vision framework — images never
leave your phone.

The privacy label is nearly empty, and that's the point.
```

~2,150 characters. Room to grow.

---

## What's in the App Store screenshots

Lead with the leak card. It states the thesis in the top third of the screen,
which is what makes the first screenshot legible to someone scrolling.

1. Overview — the leak card with a real figure and the trip comparison
2. Sort — mid-swipe, source badges visible
3. Analysis — the trend chart with the serif finding underneath
4. Trips — the forecast with its arithmetic shown
5. You — the "what won't be captured" panel, because the honesty is a feature

---

## Notes for review

Expect at least one rejection round. The likely flag is the Shortcuts
dependency — reviewers may read "requires setting up an automation" as the app
being incomplete.

Review notes should state plainly: the app is fully functional without any
automation. Manual entry, receipt scanning and recurring rules all work
standalone. The Shortcuts automation is an optional convenience for Apple Pay
users, and the app explains its limits inside the settings screen.
