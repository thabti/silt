# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

`project.yml` is the source of truth — the `.xcodeproj` is generated and git-ignored. After
adding, removing, or renaming files, regenerate before building:

```bash
make build / make run / make test                # the usual loop (make help lists all)
make signed / make dmg / make release            # Developer ID pipeline (team N762FB52VL)
make docs                                        # regenerate docs/catalog.md after Catalog.swift changes
make icon                                        # regenerate icon PNGs

# a single test (no make target)
xcodebuild -project Silt.xcodeproj -scheme SiltTests -configuration Debug \
           -derivedDataPath build test \
           -only-testing:SiltTests/SafetyGuardTests/testBlocksPersonalData
```

No linter, no package manager, no dependencies — pure SwiftUI, macOS 14+, non-sandboxed
(deliberate: a sandboxed app cannot read other apps' caches).

Regenerate the app icon from `Icon/appicon-source.png` with
`swift Icon/generate-appicon.swift Icon/appicon-source.png /tmp/out`, then copy the PNGs into
`Sources/Silt/Assets.xcassets/AppIcon.appiconset/`.

## Architecture

Silt deletes files, so the design is built around three independent gates that each would have
to fail before anything wrong is removed:

1. **`Models/Catalog.swift` is an allow-list.** Every cleanable location is a hand-written
   `CleanTarget` with an id, a kind, and a plain-language consequence line. `Cleaner` rejects
   any bucket whose id is not in the catalog, so the UI cannot introduce new paths.
2. **`CleanKind.review` is never deletable.** Big stores (pnpm store, Docker, simulators,
   backups) are shown with the correct CLI command instead. Enforced in the model *and*
   re-checked in `Cleaner`.
3. **`Services/SafetyGuard.swift` re-checks every path immediately before removal** —
   home-folder containment, minimum depth, protected-location denylist, no symlink following,
   no `..`. A parallel, looser rule set (`verdictForUserFile`) governs the Large Files view,
   which is Trash-only. The SiltTests target compiles the guard + models directly (see
   `project.yml`), and `SafetyGuardTests` walks the whole catalog asserting the gates agree.

Data flow: `AppModel` (single `@MainActor` ObservableObject, owns all state and a pre-built
`ScanIndex` so views never re-aggregate 123 buckets per render) → `Scanner.stream` measures
buckets and hands each back the moment it finishes → views render from the index.

Performance invariants worth preserving (each was measured; numbers in README):

- A normal scan **excludes review-only buckets** — they were 98% of a 96s scan. They are
  measured on demand (`measureReview()`, triggered by opening the Review page) and cached for
  the session; a full rescan keeps them.
- After a clean, only the cleaned bucket ids are re-measured (`scan(only:)`).
- During any rescan, existing results stay on screen — `scan()` must never blank `scanned`
  (that bug made the sidebar vanish mid-scan).
- `Cleaner` removes a bucket's *children* and leaves the bucket folder itself in place.
- Hand-picked files (`trashSelectedFiles`) go to the Trash only, never `removeItem`.

## Design language

Reference is System Settings › Storage — the previous look was rejected as AI slop. Rules in
`Design/Theme.swift`: one accent (`systemTeal`, matches the app icon), NSColor system palette
for everything else, flat grouped-inset cards with hairline edges, no gradients, no glow
shadows, solid `IconTile` squares, system fonts with `.monospacedDigit()` for numbers. Actions
live in the toolbar, not floating bars. Appearance (System/Light/Dark) is `@AppStorage`-backed.
Do not reintroduce purples, gradients, or sparkles iconography.

## Adding a cleanable location

One entry in `Catalog.swift`: honest `kind` (`.safe` = regenerates silently, `.prunable` =
costs a re-download, `.review` = never deleted), the tool's documented default path (relocated
caches are intentionally not found), and a consequence line written for someone who does not
know what a cache is. The catalog tests fail if the guard disagrees with the path.
