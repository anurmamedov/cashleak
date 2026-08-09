# Git setup — CashLeak

Everything needed to get the project onto GitHub, plus the day-to-day commands
and the errors you'll actually hit.

**Repo:** `anurmamedov/cashleak`
**SSH:** `git@github.com:anurmamedov/cashleak.git`
**HTTPS:** `https://github.com/anurmamedov/cashleak.git`

---

## Status

| Step | State |
|---|---|
| 1. SSH key | **You must do this** — runs on your machine |
| 2. Xcode project | Done — `cashleak.xcodeproj` exists |
| 3. `.gitignore` | Done — added, `xcuserdata/` untracked |
| 3. Other docs | Outstanding — `README.md`, `plan.md`, `ARCHITECTURE.md`, `DECISIONS.md`, `CLAUDE.md` |
| 4. `git init` / branch / remote | Done — on `main`, `origin` set to SSH |
| 4. Push | **Blocked** — repo doesn't exist on GitHub yet |
| 5. Confirm | Pending |

Two deviations from the original plan, both harmless:

- The project is named `cashleak` (lowercase), not `CashLeak`. GitHub repo names
  are case-insensitive, so the remote still resolves.
- Xcode created the git repo despite the "uncheck" instruction, so `Initial
  Commit` predates `.gitignore`. Fixed with `git rm -r --cached xcuserdata`
  rather than a history rewrite — nothing sensitive was in it.

---

## 1. SSH key

Check whether you already have one before generating anything:

```bash
ls -la ~/.ssh/
```

If `id_ed25519` and `id_ed25519.pub` are both there, skip to step 2.

If not:

```bash
ssh-keygen -t ed25519 -C "anar.nurdev@gmail.com"
```

- When it asks where to save, **press Enter** to accept
  `/Users/anarnurtech/.ssh/id_ed25519`. That's the default and it's where SSH
  looks automatically.
- Passphrase is optional. Empty is fine on a personal machine.

Copy the **public** key to the clipboard:

```bash
pbcopy < ~/.ssh/id_ed25519.pub
```

Paste it into GitHub → Settings → SSH and GPG keys → New SSH key. Any title.

Verify:

```bash
ssh -T git@github.com
```

Expect: `Hi anurmamedov! You've successfully authenticated...`

> `id_ed25519.pub` (with `.pub`) is the **public** key — safe to share.
> `id_ed25519` (no extension) is the **private** key — never paste it anywhere.

---

## 2. Create the Xcode project

Already done. For reference, the settings used:

| Field | Value |
|---|---|
| Product Name | `cashleak` |
| Interface | SwiftUI |
| Language | Swift |
| Storage | SwiftData |
| Location | `~/Desktop/programming/` |

---

## 3. Add the docs

These go in the project root, the folder containing `cashleak.xcodeproj`:

```
.gitignore        ← done
README.md
plan.md
ARCHITECTURE.md
DECISIONS.md
CLAUDE.md
```

`RootTabView.swift` goes into the app target, not the root — drag it into Xcode
rather than just into the folder, so it gets added to the target.

---

## 4. Create the repo on GitHub, then push

The repo does not exist yet. Create it first at
[github.com/new](https://github.com/new):

- Name: `cashleak`
- Private
- **No** README, `.gitignore`, or licence — the local repo already has commits,
  and initialising on GitHub causes the "unrelated histories" error below

Local git is already configured:

```bash
cd ~/Desktop/programming/cashleak
git remote -v     # origin → git@github.com:anurmamedov/cashleak.git
git log --oneline # two commits on main
```

Then push:

```bash
git push -u origin main
```

---

## 5. Confirm

Refresh the repo page on GitHub. Files should be there.

---

## Common errors

**`Repository not found`**

The repo hasn't been created on GitHub, or the SSH key isn't on the account that
owns it.

**`Updates were rejected because the remote contains work you do not have`**

GitHub created the repo with a README or licence.

```bash
git pull origin main --allow-unrelated-histories
git push -u origin main
```

**`Permission denied (publickey)`**

SSH key isn't registered. Redo step 1.

**`src refspec main does not match any`**

Nothing committed yet, or you're on `master`.

```bash
git branch -M main
git add . && git commit -m "Initial commit"
```

**`remote origin already exists`**

Fix the URL rather than adding a second remote:

```bash
git remote set-url origin git@github.com:anurmamedov/cashleak.git
```

**Xcode junk got committed anyway**

```bash
git rm -r --cached .
git add .
git commit -m "Apply gitignore"
```

---

## SSH vs HTTPS

| | SSH | HTTPS |
|---|---|---|
| Auth | Key you already made | Personal Access Token |
| Setup | Done | Generate token, paste on first push |
| Expiry | None | Tokens expire |

Stay on SSH — the key work is already done.

To switch:

```bash
# to HTTPS
git remote set-url origin https://github.com/anurmamedov/cashleak.git

# back to SSH
git remote set-url origin git@github.com:anurmamedov/cashleak.git
```

For HTTPS, the password is a token from GitHub → Settings → Developer settings →
Personal access tokens → Fine-grained, scoped to this repo with Contents: read
and write. Username is `anurmamedov`.

---

## Daily commands

```bash
git status                        # what's changed
git add -A                        # stage everything
git commit -m "Add sort queue"    # commit
git push                          # push (after the first -u push)

git log --oneline -10             # recent history
git diff                          # unstaged changes
git diff --staged                 # staged changes
git restore <file>                # discard changes to a file
```

Commit in small logical chunks rather than one large commit per session. When
something breaks, small commits make it obvious where.

---

## Branches, once there's something to protect

```bash
git checkout -b feature/sort-queue
# work, commit
git push -u origin feature/sort-queue
```

Merge on GitHub via a pull request, or locally:

```bash
git checkout main
git merge feature/sort-queue
git push
```

Not worth bothering with until v1 is shipped and `main` needs to stay working.

---

## Never commit

Already covered by `.gitignore`, but worth knowing why:

- `*.p12`, `*.cer`, `*.mobileprovision` — signing certificates and profiles
- `.env`, `Secrets.swift` — API keys
- `DerivedData/`, `xcuserdata/` — build artefacts and per-user editor state

If a secret does get committed, rotating it is the only real fix. Removing it
from history doesn't help once it's been pushed.

---

## Alternative: do it all in Xcode

Source Control → New Git Repository, then Source Control → Push and paste the
remote URL.

Same result, no Terminal. Still add `.gitignore` manually first — Xcode's
built-in one is thinner than the one in this project.
