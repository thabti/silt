# Performance

Measured on the development Mac (376 GB used, 123 catalog entries, 35 present). Every change
here was profiled before it was kept; two attractive ideas were rejected because the numbers
said no.

| | before | after |
|---|---|---|
| Normal scan | 96 s | **1.0 s** |
| First result on screen | after the whole scan | **2 ms** |
| Rescan after a clean | 96 s (all buckets) | **0.03 s** (only what was cleaned) |

## What mattered, in order

1. **Review-only folders are not part of a normal scan.** Profiling showed they were 98% of
   the 96 s — the pnpm store alone was 80 s, being 26 GB of hard-linked small files. They are
   measured on demand (opening the Review page), streamed in, and cached for the session. A
   full rescan keeps those numbers instead of re-earning them.
2. **Results stream.** Each bucket is handed to the UI the moment its children are measured.
3. **Post-clean rescans are partial.** `scan(only:)` re-measures just the cleaned ids.
4. **Work is flattened.** All buckets' children form one job list through one task group.
5. Small wins: three resource keys per file instead of five (1–11% on 100k-file trees), a
   hand-rolled byte formatter (`ByteCountFormatter` allocates per call, visible when a 500-row
   list scrolls), `LazyVStack` for long lists, no per-row numeric transitions.

## Rejected on evidence

- **`fts(3)` traversal** instead of `FileManager.enumerator`: 1.1–1.4× — not worth C interop.
- **Flattening alone** (before deferring review folders): 1.01× — one giant tree still
  serializes onto one worker; parallel shape cannot fix a workload dominated by a single item.

## Invariants to preserve

- `scan()` never blanks existing results; the sidebar must not flicker during a rescan.
- Review measurements are session-cached; never re-walk them implicitly.
- The scanner checks `Task.isCancelled` every 512 entries — keep cancellation cheap.
