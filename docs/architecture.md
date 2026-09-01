# Architecture

Silt is one process, one window, no dependencies. Everything hangs off a single flow:

```
Catalog (allow-list, 123 entries)
   │  Catalog.present() — filter to what exists on this Mac
   ▼
Scanner.stream (concurrent, read-only)
   │  one ScannedTarget at a time, the moment its children are measured
   ▼
AppModel (@MainActor)  ──►  ScanIndex (pre-aggregated totals)
   │                              │
   │ selection, routing           ▼
   ▼                        SwiftUI views (read the index, never re-aggregate)
Cleaner (Trash / delete, three gates)
   ▲
SafetyGuard (per-path rules, checked immediately before every removal)
```

## The pieces

**`Models/Catalog.swift`** — the allow-list. Every location Silt may ever touch is a
hand-written `CleanTarget`: id, name, owner, group (ecosystem heading), documented default
path, `CleanKind`, and a one-sentence consequence. Paths a tool can relocate via environment
variables are listed at their defaults only — a moved cache is simply not found, which is the
safe way to be wrong.

**`Services/Scanner.swift`** — read-only measurement. The shallow listing of every bucket is
flattened into one job list and fed through a single task group, so cores are shared instead of
one worker per bucket. Each bucket streams back the moment its own children are done —
`Scanner.stream(targets:onBucket:)` — which is why the UI fills progressively. `quickTargets`
vs `reviewTargets` splits the catalog for the two-stage scan (see [performance](performance.md)).

**`Services/FileScanner.swift`** — the Large Files walk. One concurrent worker per top-level
home folder, `.skipsPackageDescendants` so bundles arrive as single items, cloud placeholder
folders never entered.

**`ViewModels/AppModel.swift`** — all state, single `@MainActor` ObservableObject. The key
type is `ScanIndex`: totals per category, cleanable/review splits, built once per data change.
Views read the index; nothing in a view body walks all 123 buckets. Cleaning is scoped to the
page you are on (`scopedBuckets`), and the confirmation sheet operates on a captured `pending`
list so what it shows is exactly what runs.

**`Services/Cleaner.swift`** — the only code that removes anything, behind three gates
([safety.md](safety.md)). It removes a bucket's *children* and leaves the bucket folder in
place, because apps expect their cache directory to exist.

**`Models/FileEntry.swift`** — file classification for the Large Files view: extension map,
executable bit, and a Mach-O magic-number sniff for extensionless binaries.

## Why it is shaped this way

- **The catalog is data, not discovery.** Silt never guesses what a folder is. If it is not in
  the catalog, it does not exist to the cleaner. That trades coverage for predictability, on
  purpose.
- **Streaming beats batching for a tool you watch.** The first bucket lands ~2 ms after a scan
  starts; the sidebar and overview populate live instead of appearing after the slowest tree.
- **State never blanks.** A rescan merges into what is on screen. The first version cleared
  `scanned` before re-measuring, which made the sidebar vanish mid-scan — the fix is an
  invariant now: `scan()` keeps existing results until fresh ones replace them.
