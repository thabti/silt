# Development

## Prerequisites

macOS 14+, Xcode command-line tools, `brew install xcodegen`.

`project.yml` is the source of truth; `Silt.xcodeproj` is generated and git-ignored. After
adding, removing or renaming files:

```bash
xcodegen generate
```

## Build, run, test

The Makefile wraps everything (`make help` lists targets):

```bash
make build      # unsigned Release build (local dev)
make run        # build + launch
make test       # test suite
```

Or raw xcodebuild, e.g. a single test:

```bash
xcodebuild -project Silt.xcodeproj -scheme SiltTests -configuration Debug \
           -derivedDataPath build test \
           -only-testing:SiltTests/SafetyGuardTests/testBlocksPersonalData
```

## Distribution builds

Signing uses the Developer ID Application identity for team `N762FB52VL` (override with
`make signed TEAM_ID=...`):

```bash
make signed     # Developer ID + hardened runtime + timestamp, then verifies the signature
make dmg        # signed .dmg in dist/
make release    # sign → dmg → notarize → staple (the full pipeline)
```

`make notarize` needs stored notary credentials once:

```bash
xcrun notarytool store-credentials silt-notary \
  --apple-id you@example.com --team-id N762FB52VL
```

Until notarized, `spctl` reports the dmg as "Unnotarized Developer ID" — signed correctly,
just not yet cleared by Apple. That is expected. The full pipeline, stage by stage, with
verification and troubleshooting: [releasing.md](releasing.md).

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
make docs   # docs/catalog.md — after any Catalog.swift change
make icon   # icon PNGs from Icon/appicon-source.png, then copy per Contents.json
```
