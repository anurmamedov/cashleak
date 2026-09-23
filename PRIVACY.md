# CashLeak Privacy Policy

*Last updated 23 September 2026*

**Your spending data never reaches us.** Every transaction, amount, merchant and
judgement you record stays on your device and in your own private iCloud, which
we have no access to. The only thing we handle is the account you sign in with.

## What we collect

CashLeak uses Firebase Authentication, a service from Google, to run sign-in. It
holds the minimum needed to prove an account is yours:

| Data | Why |
|---|---|
| Email address | Identifies your account and allows password reset |
| Password | Stored only as a cryptographic hash, never as text |
| Apple account identifier | Only if you choose Sign in with Apple |
| Account identifier and sign-in times | Created by Firebase to operate the account |

Firebase also records technical information such as IP address as part of
operating the service and preventing abuse. Google's handling of that is covered
by the [Firebase privacy documentation](https://firebase.google.com/support/privacy).

If you use Sign in with Apple and choose to hide your email, Apple gives us a
relay address instead of your real one. We never see the real address.

## What we do not collect

None of the following is ever transmitted to us or to any third party:

- Transactions, amounts, merchants, dates or notes
- Your *worth it* and *leak* judgements
- Categories, budgets, goals and recurring rules
- Receipt images
- Card labels you enter

All of it is stored on your device and synchronised through **your own private
iCloud database**. That database belongs to your Apple account. We cannot read
it, and neither can Apple.

## No bank connection

CashLeak never asks for banking credentials and has no technical ability to use
them. There is no aggregator, no screen-scraping and no read-only bank link.
Purchases arrive through a Shortcuts automation you set up yourself, through
on-device receipt scanning, through rules you define, or by typing them in.

## No analytics, no advertising, no tracking

The app contains no analytics SDK, no crash reporting SDK and no advertising SDK.
We do not build a profile of you, we do not track you across other apps or
websites, and we have nothing to sell to anyone because we never receive it.

## On-device processing

Receipt scanning uses Apple's Vision framework and runs entirely on your phone.
Images are not uploaded. Notifications are scheduled locally by the app; no
server sends you anything.

## Your choices

- **Delete your account.** Email us and we will delete the Firebase record
  holding your email and account identifier.
- **Delete your data.** Your spending data is yours to remove — delete the app,
  or clear it from within it. Because we never held a copy, there is nothing on
  our side to erase.
- **Export your data.** CashLeak exports everything to CSV from the You screen,
  at any time, without asking us.
- **Turn off sync.** Disable iCloud for CashLeak in iOS Settings and the app
  keeps working on that device alone.

Depending on where you live you may have further rights over the account data
described above, including access and correction. Email us and we will act on it.

## Children

CashLeak is not directed at children under 13 and we do not knowingly create
accounts for them.

## Changes

If this policy changes materially we will update the date above and note the
change in the app before it takes effect.

## Contact

CashLeak is published by Karasand Labs.

Questions, deletion requests or anything else: support@karasandlabs.com.
If that address ever bounces, use karasandlabs@gmail.com.

---

**Note for maintainers:** `docs/privacy.html` is the version Apple links to and
is the one that must stay live. This file is the same text in Markdown for
reuse elsewhere. Change both together — a policy that contradicts itself across
two published copies is worse than either copy alone.
