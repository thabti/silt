<img src="Icon/appicon-source.png" width="120" align="right" alt="Silt icon">

# Silt

*Silt is what settles on a disk. This clears it.*

A small, deliberately boring macOS disk cleaner. SwiftUI, no dependencies, no network access,
no background agent, no "1 GB of junk found!" theatre.

It measures 123 known cache and log locations across 25+ language ecosystems, lists the biggest
files on the disk, shows you what everything is in plain language, and clears only what you tick.

![built with SwiftUI](https://img.shields.io/badge/SwiftUI-macOS%2014%2B-5b57f0)

## Coverage

**123 locations**, each with an honest "what happens if this goes" line:

| Ecosystem | Tools covered |
|---|---|
| JavaScript & Node | npm, Yarn Classic, Yarn Berry, pnpm, Bun, Deno, node-gyp, TypeScript, Electron, electron-builder, Playwright, Puppeteer, Cypress, Selenium |
| JVM & Android | Maven, Gradle (caches/wrapper/daemon/native), Ivy, Coursier, sbt, Kotlin/Native, Android SDK |
| Apple & Xcode | DerivedData, Previews, DocumentationCache, iOS DeviceSupport, Simulator caches, SwiftPM, CocoaPods, Carthage |
| Python | pip, uv, Poetry, Pipenv, PDM, Conda, Miniconda, Anaconda |
| Ruby / PHP | Bundler, RubyGems specs, Composer (both layouts) |
| Rust / Go / .NET | Cargo registry + git + src, sccache, Go build cache, NuGet packages + HTTP + plugins |
| C & C++ | ccache (both paths), Conan 1 & 2, vcpkg |
| Mobile & cross-platform | Dart/Flutter pub, Expo, Unity |
| Other languages | Elixir Hex, Erlang rebar3, OCaml opam, Haskell Cabal + Stack, Lua LuaRocks, Perl cpanm, Nim Nimble, Crystal shards, Zig, Julia, R renv, Elm |
| Build & infra | Homebrew, Terraform, Helm, pre-commit |
| Browsers | Chrome, Safari, Arc, Dia, Firefox, Brave, Edge |
| Apps | VS Code, Cursor, JetBrains, Slack, Discord, Zoom, Figma, Adobe, Spotify, Ollama, Loom |
| System | user logs, Quick Look thumbnails, icon cache, Trash |
| Review only | iOS Simulators, Docker, Colima, Podman, Vagrant, Android SDK/AVDs, rustup, GHC, pnpm store, Go modcache, Julia artifacts, Xcode Archives, iPhone backups, Homebrew Cellar, Bazel |

Paths are each tool's documented macOS default. Anything a tool can relocate with an environment
variable (`PUB_CACHE`, `DENO_DIR`, `GRADLE_USER_HOME`, `POETRY_CACHE_DIR`, …) is listed at its
default only — a relocated cache simply is not found, which is the safe way to be wrong.

## Large files

A second, deliberately simple view: walk the home folder, list everything over a threshold
(20 MB → 1 GB), sorted biggest first, classified by what it is — video, audio, images, archives,
disk images, **binaries**, apps & bundles, code, documents, databases. Binaries are detected by
extension, by the executable bit, and by Mach-O magic number when the extension says nothing.

Bundles (`.app`, `.photoslibrary`, `.xcarchive`, `.framework`) are measured as one item instead of
thousands of parts. Filter chips narrow the list by kind; a breakdown bar shows the split.

Hand-picked files are **Trash-only** — the permanent-delete mode is not available here — and they
go through a separate, stricter guard (`verdictForUserFile`) that still refuses credentials,
keychains, system preferences, cloud placeholders and media libraries. iCloud Drive and
`Library/CloudStorage` are never walked at all, so no placeholder gets downloaded just by being
measured.

## What it does

- **One ring, one number.** Disk capacity, what is in use, and what is reclaimable.
- **Buckets, not files.** Each row is a known location — Xcode DerivedData, npm cache, Chrome
  cache — with the size, the file count, and one sentence about what happens if you clear it.
- **Trash by default.** Cleaning moves items to the Trash so you can put them back. Permanent
  deletion is a separate, clearly-marked mode.
- **A Review section it refuses to touch.** Simulators, Docker images, the pnpm store, Xcode
  archives, iPhone backups. These are big, but deleting them blindly breaks things — so the app
  shows the size and the correct command instead.

## Safety model

Three independent gates stand in front of every delete:

1. **Catalog allow-list.** The UI can only hand `Cleaner` buckets that came from `Catalog`.
   Arbitrary paths cannot enter the pipeline.
2. **Kind check.** Buckets marked `.review` are never deletable, in the model *and* in the cleaner.
3. **`SafetyGuard`.** Every individual path is re-checked immediately before removal:
   - must be inside your home folder — never `/System`, `/Library`, `/usr`, `/Applications`
   - never your home folder itself, and never a whole top-level folder like `~/Library`
   - never at or below a protected location: Documents, Desktop, Downloads, Pictures, Movies,
     Music, `~/.ssh`, `~/.gnupg`, `~/.aws`, `~/.config`, Keychains, iCloud Drive, Containers,
     Mail, Messages, Photos, iPhone backups, the pnpm store, the Go module cache, Xcode Archives
   - no `..` traversal, and symlinks are never followed out of the allowed area

Two more habits that matter:

- **Folders are kept, contents are cleared.** Apps expect their own cache folder to exist, so
  Silt removes what is inside a bucket and leaves the bucket itself in place.
- **Nothing runs without confirmation.** The confirmation sheet lists every bucket, its size and
  its full path before anything moves.

`SafetyGuardTests` (16 tests) covers all of the above, including a test that walks the whole
catalog and asserts every deletable entry passes the guard — and that every Review entry does not
— plus the Files-list rules and the binary/media classifier.

## Design

The visual reference is System Settings › Storage, not a landing page. Rules that came out of
the de-slop pass: one accent — the teal of the app icon (`systemTeal`) — and system semantic
colors for everything else; flat grouped-inset cards with a hairline edge, no shadows; small
solid icon squares instead of gradient tiles; system typography with monospaced digits where
numbers align; actions in the toolbar, where Mac apps keep them, instead of a floating bottom
bar. Appearance (System / Light / Dark) is a toolbar menu, stored in `AppStorage`.

## Performance

Measured on this Mac (376 GB used, 123 catalog entries, 35 present):

| | before | after |
|---|---|---|
| Normal scan | 96 s | **1.0 s** |
| First result on screen | after the whole scan | **2 ms** |
| Rescan after a clean | 96 s (all buckets) | **0.03 s** (only what was cleaned) |

What actually mattered, in order:

1. **Review-only folders are not part of a normal scan.** Profiling showed they were 98% of the
   time — the pnpm store alone is 80 s, being 26 GB of hard-linked files. They are measured on
   demand, when you open the Review page, and remembered for the session. A full rescan keeps
   those numbers rather than re-earning them.
2. **Results stream in.** `Scanner.stream` hands back each bucket the moment its own children are
   measured, so the sidebar and overview fill progressively instead of after the slowest bucket.
3. **A rescan after cleaning only re-measures what was cleaned.** Re-walking 123 locations to
   learn that 10 of them are now empty is pure waste.
4. **Work is flattened before it runs.** Every bucket's children become one job list fed through a
   single task group, so cores are shared instead of one worker per bucket.
5. Smaller wins: three resource keys per file instead of five (1–11% on big trees), a hand-rolled
   byte formatter instead of `ByteCountFormatter` per row per render, `LazyVStack` for the long
   lists, and no numeric-transition animation on 500 individual rows.

`fts(3)` was prototyped as a replacement for `FileManager.enumerator` and only bought 1.1–1.4x,
which was not worth the C interop — so the traversal stayed in Foundation.

## App icon

`Icon/appicon-source.png` is the artwork; `Icon/generate-appicon.swift` turns it into the asset
catalog. It finds the tile by counting saturated pixels per row and column — a plain bounding box
picks up the soft glow under the tile and squares out into the white page — then crops to the
dense square, trims the antialiased edge, and redraws it on the macOS icon grid (824 pt of art in
a 1024 pt canvas) with a rounded-rect clip and a contact shadow.

```bash
swift Icon/generate-appicon.swift Icon/appicon-source.png /tmp/out
# then copy /tmp/out/icon_*.png into Sources/Silt/Assets.xcassets/AppIcon.appiconset
```

## Running it locally

Requirements: macOS 14+, Xcode command-line tools, and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(the `.xcodeproj` is generated from `project.yml` and git-ignored — edit `project.yml`, never
the project file).

```bash
git clone git@github.com:thabti/silt.git
cd silt
brew install xcodegen          # once
xcodegen generate              # writes Silt.xcodeproj

# fastest path: build and launch from the terminal
xcodebuild -project Silt.xcodeproj -scheme Silt -configuration Release \
           -derivedDataPath build build
open build/Build/Products/Release/Silt.app

# or work in Xcode
open Silt.xcodeproj            # scheme "Silt", ⌘R
```

The app builds unsigned for local use (`CODE_SIGN_IDENTITY: "-"` in `project.yml`), so there is
nothing to configure — no team, no provisioning. First launch asks for no permissions; granting
**Full Disk Access** (System Settings › Privacy & Security) additionally lets it read Safari's
cache and app containers, which are otherwise shown as *Partly locked*.

Run the tests:

```bash
xcodebuild -project Silt.xcodeproj -scheme SiltTests -configuration Debug \
           -derivedDataPath build test

# one test only
xcodebuild -project Silt.xcodeproj -scheme SiltTests -configuration Debug \
           -derivedDataPath build test \
           -only-testing:SiltTests/SafetyGuardTests/testBlocksPersonalData
```

## Permissions

The app is **not sandboxed**, because a sandboxed app cannot read another app's cache folder.
It asks for nothing at launch. A few locations (Safari's cache, anything under `~/Library/Containers`)
stay unreadable unless you grant **Full Disk Access** in System Settings › Privacy & Security.
Those buckets are marked *Partly locked* in the UI rather than silently under-reported.

## Layout

```
Sources/Silt/
  Models/CleanTarget.swift    bucket, category, group, kind, scan result types
  Models/Catalog.swift        the allow-list — all 123 locations, grouped by ecosystem
  Models/FileEntry.swift      file kinds and the binary/bundle classifier
  Services/SafetyGuard.swift  the path rules; the only thing standing between a bug and your files
  Services/Scanner.swift      read-only concurrent sizing of cache buckets
  Services/FileScanner.swift  read-only home-folder walk for large files
  Services/Cleaner.swift      Trash / delete, gated three ways
  Services/DiskSpace.swift    volume capacity
  ViewModels/AppModel.swift   phases, selection, derived totals
  Design/Theme.swift          palette, rounded type scale, cards, tiles
  Views/                      hero ring, category cards, bucket rows, sheets
Tests/SiltTests/          safety rules and catalog integrity
```

## Adding a location

Add one entry to `Catalog`. Give it an honest `kind` and write the `consequence` line as if you
were explaining it to someone who does not know what a cache is. If clearing it would break
something or lose work, use `.review` and put the correct CLI command in the consequence text.

The catalog tests will tell you if the guard disagrees with your path.

## Path sources

Defaults were checked against vendor documentation rather than memory:

- [Poetry configuration](https://python-poetry.org/docs/configuration/) — `~/Library/Caches/pypoetry`
- [The pub cache](https://github.com/dart-lang/pub/blob/master/doc/cache_layout.md) — `~/.pub-cache`
- [Coursier cache](https://get-coursier.io/docs/cache) — `~/Library/Caches/Coursier/v1`
- [Deno default cache path](https://medium.com/deno-the-complete-reference/deno-nuggets-default-cache-path-on-mac-linux-and-windows-8fb68b5c69a2) — `~/Library/Caches/deno`
- [sccache local storage](https://github.com/mozilla/sccache/blob/main/docs/Local.md) — `~/Library/Caches/Mozilla.sccache`
- [ccache manual](https://ccache.dev/manual/latest.html) — `~/.ccache`, else `~/Library/Caches/ccache`
- [NuGet global folders](https://learn.microsoft.com/en-us/nuget/consume-packages/managing-the-global-packages-and-cache-folders) — `~/.nuget/packages`
- [Bundler cache](https://bundler.io/man/bundle-cache.1.html) — `~/.bundle/cache`
- [opam manual](https://opam.ocaml.org/doc/Manual.html) — `~/.opam/download-cache`
- [Julia environment variables](https://docs.julialang.org/en/v1/manual/environment-variables/) — `~/.julia`
