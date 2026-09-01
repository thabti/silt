<img src="Icon/appicon-source.png" width="110" align="right" alt="Silt icon">

# Silt

*Silt is what settles on a disk. This clears it.*

A small, deliberately boring macOS disk cleaner. SwiftUI, no dependencies, no network access,
no background agent, no "1 GB of junk found!" theatre.

![built with SwiftUI](https://img.shields.io/badge/SwiftUI-macOS%2014%2B-2aa198)

![Silt overview](docs/images/overview-dark.png)

## What it does

- **Measures [123 known cache and log locations](docs/catalog.md)** across 25+ language
  ecosystems — npm, Gradle, Maven, Cargo, pip/uv/Poetry/Conda, CocoaPods, Composer, Bundler,
  NuGet, Hex, opam, Cabal, and the rest — each with a plain-language line about what happens
  if it goes.
- **Lists the biggest files on the disk**, sorted by size and classified by what they are —
  video, archives, disk images, binaries (detected down to the Mach-O magic number), bundles
  counted as single items.
- **Clears only what you tick.** Trash by default, so everything is recoverable; permanent
  deletion is a separate, clearly marked mode. Hand-picked files are Trash-only.
- **Refuses to touch what it shouldn't.** Simulators, Docker images, package stores, backups —
  shown with their size and the correct native command instead of a delete button.

A normal scan takes about **one second** and the first result is on screen in milliseconds —
the numbers and how they were reached are in [docs/performance.md](docs/performance.md).

## Safety, in one paragraph

Three independent gates stand in front of every removal: a hand-written **catalog allow-list**
(paths cannot enter the pipeline from anywhere else), a **review-only kind** the cleaner
re-checks independently, and **per-path SafetyGuard rules** — home-folder containment, a
protected-location denylist (Documents, Desktop, `~/.ssh`, Keychains, iCloud, Photos, …), no
symlink following, no `..`. Folders stay in place; only their contents are cleared. The full
model, including what the Large Files view refuses, is in [docs/safety.md](docs/safety.md),
and 16 tests hold it in place.

## Install

```bash
brew install --cask thabti/tap/silt
```

Signed but not yet notarized — right-click → Open on first launch. Or grab the dmg from
[Releases](https://github.com/thabti/silt/releases).

## Running it locally

Requirements: macOS 14+, Xcode command-line tools, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen). The `.xcodeproj` is generated from
`project.yml` and git-ignored — edit `project.yml`, never the project file.

```bash
git clone git@github.com:thabti/silt.git
cd silt
brew install xcodegen          # once
make run                       # generate project, build, launch

# or work in Xcode: make generate && open Silt.xcodeproj, scheme "Silt", ⌘R
```

`make help` lists everything else — `test`, `signed`, `dmg`, `release` (sign → notarize →
staple), `docs`, `icon`.

Builds are unsigned for local use — no team, no provisioning, nothing to configure. The app
asks for no permissions at launch; granting **Full Disk Access** (System Settings › Privacy &
Security) additionally lets it read Safari's cache and app containers, which are otherwise
shown as *Partly locked*. It is deliberately not sandboxed — a sandboxed app cannot read other
apps' caches.

Tests: `make test`.

## Documentation

Everything deeper lives in [`docs/`](docs/README.md):

| | |
|---|---|
| [Architecture](docs/architecture.md) | catalog → scanner → index → cleaner, and why |
| [Safety model](docs/safety.md) | the three gates, the exact guard rules |
| [Catalog reference](docs/catalog.md) | all 123 locations, generated from source |
| [Performance](docs/performance.md) | 96 s → 1 s, measured; what was rejected and why |
| [Design language](docs/design.md) | the System Settings reference, light & dark |
| [Development](docs/development.md) | building, testing, adding locations, regenerating artifacts |

## Layout

```
Sources/Silt/
  Models/       catalog (the allow-list), scan types, file classification
  Services/     SafetyGuard, Scanner, FileScanner, Cleaner, DiskSpace
  ViewModels/   AppModel — all state, pre-aggregated ScanIndex
  Views/        overview, category detail, large files, sheets
  Design/       theme: one teal accent, system palette, flat cards
Tests/SiltTests/  safety rules, catalog integrity, classification
docs/             the documentation above + dump-catalog tool
Icon/             icon artwork + generator script
project.yml       source of truth for the Xcode project
```
