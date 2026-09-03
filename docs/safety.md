# Safety model

Silt deletes files, so the design assumes any single layer can have a bug. Three independent
gates stand in front of every removal; all three would have to fail together.

## Gate 1 — the catalog allow-list

`Cleaner` accepts only `ScannedTarget`s whose id exists in `Catalog`. Arbitrary paths cannot
enter the pipeline from the UI, a future feature, or a bad merge. If it is not one of the 123
hand-written entries, it is not cleanable.

## Gate 2 — the review kind

`CleanKind.review` marks locations that are huge but dangerous to delete blindly: iOS
simulators, Docker data, the pnpm content store, the Go module cache, Xcode archives, iPhone
backups, Homebrew's Cellar. The UI renders them lock-only, and `Cleaner` re-checks the kind
independently. For each, the consequence line carries the correct native command instead
(`docker system prune`, `pnpm store prune`, `xcrun simctl delete unavailable`, …).

## Gate 3 — SafetyGuard

`SafetyGuard.verdict(for:)` re-checks the exact path immediately before removal:

- must be **inside your home folder** — never `/System`, `/Library`, `/usr`, `/Applications`
- never the home folder itself, never a whole top-level folder (`~/Library`), minimum depth 2
- never at or below a protected location: Documents, Desktop, Downloads, Pictures, Movies,
  Music, `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.config`, `~/.kube`, Keychains, iCloud Drive,
  CloudStorage, Containers, Mail, Messages, Photos, iPhone backups, pnpm store, Go modcache,
  Xcode Archives, simulators
- no `..` traversal; symlinks are never followed out of the allowed area (the link may be
  deleted, its target may not); resolved paths are re-checked against the same rules

## The Large Files view is different, deliberately

Hand-picked files go through `verdictForUserFile` — looser (you may throw away your own big
files anywhere in your home folder) but still refusing credentials, keychains, preferences,
cloud placeholders, plain folders, and media libraries (`.photoslibrary`, `.musiclibrary`, …).
The page honors the same Trash/Delete mode as the cache pages, and **every job goes through a
confirmation sheet** that lists each file and its path; permanent deletion carries an extra
warning that these are your own files, not regenerable caches. Build artifacts remain
Trash-only — they regenerate anyway, so permanence buys nothing.

## Uninstalling applications

The Applications page removes an app together with the support files keyed to its bundle id.
Extra rules on top of the usual gates:

- **A new additive rule set**, `verdictForApplicationBundle`: the target must be a `.app`
  directory whose parent is `/Applications`, `~/Applications`, or one subfolder of
  `/Applications`; never under `/System`; never a `com.apple.*` bundle id; never Silt's own
  bundle (checked by id *and* by URL); never a symlink.
- **Support files match on bundle id only** — never on app name. Removing
  `Application Support/Code` because an app called Code is being uninstalled is the false
  positive that makes uninstallers dangerous. Each file is still re-checked by
  `verdictForAppLeftover(..., verifyInstalled: false)` immediately before removal.
- **Running apps are refused.** Trashing a running bundle leaves a broken state, so the
  confirmation sheet lists them, offers to quit them, and keeps the confirm button disabled
  until they are gone.
- **Trash-only, always.** There is no permanent-delete mode in this feature.
- macOS 13+ requires **App Management** (System Settings › Privacy & Security) before
  anything can be moved out of `/Applications`. Silt does not escalate privileges — a
  refused move is reported per app with that hint.

## Habits that back the gates

- **Trash by default.** The cache cleaner offers permanent deletion as an explicit,
  red-tinted second mode. The Trash bucket itself is forced permanent and labelled as
  irreversible — you cannot move the Trash to the Trash.
- **Folders stay, contents go.**
- **Nothing runs unconfirmed.** The sheet lists every bucket, path and size of the exact
  captured job.
- **Default selection is `.safe` only.** Anything that costs a re-download starts unticked.
- **iCloud is never walked.** Measuring a placeholder would download it.

## Tests

`SafetyGuardTests` (16 tests) asserts the blocked and allowed lists above, walks the entire
catalog asserting every deletable entry passes the guard and every review entry does not, and
covers the file classifier. Run them before trusting any change to `Catalog.swift` or
`SafetyGuard.swift`.
