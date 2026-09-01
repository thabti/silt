# Development

## Prerequisites

macOS 14+, Xcode command-line tools, `brew install xcodegen`.

`project.yml` is the source of truth; `Silt.xcodeproj` is generated and git-ignored. After
adding, removing or renaming files:

```bash
xcodegen generate
```

## Build, run, test

```bash
# build + launch
xcodebuild -project Silt.xcodeproj -scheme Silt -configuration Release \
           -derivedDataPath build build
open build/Build/Products/Release/Silt.app

# all tests
xcodebuild -project Silt.xcodeproj -scheme SiltTests -configuration Debug \
           -derivedDataPath build test

# one test
xcodebuild -project Silt.xcodeproj -scheme SiltTests -configuration Debug \
           -derivedDataPath build test \
           -only-testing:SiltTests/SafetyGuardTests/testBlocksPersonalData
```

Builds are unsigned (`CODE_SIGN_IDENTITY: "-"`) — nothing to configure. The app is
deliberately **not sandboxed**: a sandboxed process cannot read other apps' cache folders.
Granting Full Disk Access additionally unlocks Safari's cache and `~/Library/Containers`
(otherwise shown as *Partly locked*).

## Adding a cleanable location

One entry in `Sources/Silt/Models/Catalog.swift`:

1. Pick the honest `CleanKind`: `.safe` (regenerates silently), `.prunable` (costs a
   re-download or rebuild), `.review` (Silt must never delete it — put the correct CLI command
   in the consequence line instead).
2. Use the tool's **documented default path**. Do not chase relocated caches.
3. Write the consequence for someone who does not know what a cache is.
4. Run the tests — `SafetyGuardTests` walks the catalog and fails if the guard disagrees with
   your path, or if a review entry is deletable.
5. Regenerate the catalog reference (below).

## Regenerating generated artifacts

```bash
# docs/catalog.md — after any Catalog.swift change
swiftc -O -o /tmp/dumpcat Sources/Silt/Models/CleanTarget.swift \
  Sources/Silt/Models/Catalog.swift docs/tools/dump-catalog/main.swift
/tmp/dumpcat > docs/catalog.md

# app icon — after replacing Icon/appicon-source.png
swift Icon/generate-appicon.swift Icon/appicon-source.png /tmp/out
cp /tmp/out/icon_*.png Sources/Silt/Assets.xcassets/AppIcon.appiconset/   # then re-map names per Contents.json
```
