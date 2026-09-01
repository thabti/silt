# Catalog reference

> Generated from `Sources/Silt/Models/Catalog.swift` — do not edit by hand.
> Regenerate: `swiftc -O -o /tmp/dumpcat Sources/Silt/Models/CleanTarget.swift Sources/Silt/Models/Catalog.swift docs/tools/dump-catalog/main.swift && /tmp/dumpcat > docs/catalog.md`

123 locations. **Safe** = regenerates silently. **Re-downloads** = comes back at the cost of a download or rebuild. **Review-only** = Silt will never delete it; the consequence column carries the correct command instead.

## Developer — 82 locations

### JavaScript & Node

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| npm cache | npm | `~/.npm/_cacache` | Re-downloads | Packages re-download on the next install. Safe equivalent: npm cache clean --force |
| Yarn cache | Yarn Classic | `~/Library/Caches/Yarn` | Re-downloads | Packages re-download on the next install. |
| Yarn Berry cache | Yarn 2+ | `~/.yarn/berry/cache` | Re-downloads | Zip archives of every dependency. Re-downloads unless a project uses zero-installs. |
| pnpm metadata cache | pnpm | `~/Library/Caches/pnpm` | Re-downloads | Registry metadata and tarballs re-download. This is not the content store. |
| Bun cache | Bun | `~/.bun/install/cache` | Re-downloads | Packages re-download on the next bun install. |
| Deno cache | Deno | `~/Library/Caches/deno` | Re-downloads | Remote modules and compiled TypeScript re-download on the next run. |
| node-gyp headers | node-gyp | `~/Library/Caches/node-gyp` | Re-downloads | Node headers re-download when a native module builds. |
| TypeScript type cache | TypeScript | `~/Library/Caches/typescript` | Safe | Auto-acquired type definitions come back when needed. |
| Electron binaries | Electron | `~/Library/Caches/electron` | Re-downloads | Electron runtimes re-download on the next build — hundreds of MB each. |
| electron-builder cache | electron-builder | `~/Library/Caches/electron-builder` | Re-downloads | Packaging tools and app images re-download on the next package run. |
| Playwright browsers | Playwright | `~/Library/Caches/ms-playwright` | Re-downloads | Test browsers re-download — around 1 GB. |
| Puppeteer browsers | Puppeteer | `~/.cache/puppeteer` | Re-downloads | Chromium re-downloads on the next run. |
| Cypress binaries | Cypress | `~/Library/Caches/Cypress` | Re-downloads | Cypress re-downloads on the next run. |
| Selenium drivers | Selenium | `~/.cache/selenium` | Re-downloads | Drivers re-download on the next run. |

### JVM & Android

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| Maven repository | Maven | `~/.m2/repository` | Re-downloads | Your local copy of every Java dependency. Re-downloads on the next mvn build — often slow. |
| Gradle caches | Gradle | `~/.gradle/caches` | Re-downloads | Dependencies re-download and build fingerprints rebuild on the next build. |
| Gradle distributions | Gradle | `~/.gradle/wrapper` | Re-downloads | Gradle itself re-downloads on the next build. |
| Gradle daemon logs | Gradle | `~/.gradle/daemon` | Safe | Logs from past daemon runs. |
| Gradle native bits | Gradle | `~/.gradle/native` | Safe | Small platform helpers Gradle re-extracts on demand. |
| Ivy cache | Ivy / sbt | `~/.ivy2/cache` | Re-downloads | Scala and Ant dependencies re-download on the next build. |
| Coursier cache | Coursier / sbt | `~/Library/Caches/Coursier` | Re-downloads | Scala artifacts re-download. Modern sbt and Scala CLI use this. |
| sbt boot files | sbt | `~/.sbt/boot` | Re-downloads | sbt re-downloads its launcher and Scala versions. |
| Kotlin/Native dependencies | Kotlin | `~/.konan` | Re-downloads | Native toolchains re-download — large, and slow to fetch again. |
| Android build cache | Android | `~/.android/build-cache` | Safe | Rebuilt on the next Android build. |
| Android SDK cache | Android | `~/.android/cache` | Safe | SDK metadata refetches on the next sync. |

### Apple & Xcode

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| Xcode DerivedData | Xcode | `~/Library/Developer/Xcode/DerivedData` | Safe | Xcode re-indexes and rebuilds on the next build. Usually the biggest win on a dev Mac. |
| Xcode Previews cache | Xcode | `~/Library/Developer/Xcode/UserData/Previews` | Safe | SwiftUI previews rebuild themselves. |
| Xcode documentation cache | Xcode | `~/Library/Developer/Xcode/DocumentationCache` | Safe | Docs re-download when you open the documentation window. |
| iOS DeviceSupport symbols | Xcode | `~/Library/Developer/Xcode/iOS DeviceSupport` | Re-downloads | Re-created the next time you plug in a device on that iOS version. |
| Simulator caches | Xcode | `~/Library/Developer/CoreSimulator/Caches` | Safe | Runtimes re-extract on next launch. Your simulators stay. |
| Swift Package Manager cache | SwiftPM | `~/Library/Caches/org.swift.swiftpm` | Re-downloads | Packages re-clone on the next resolve. |
| CocoaPods cache | CocoaPods | `~/Library/Caches/CocoaPods` | Re-downloads | Pods re-download on the next pod install. |
| CocoaPods spec repos | CocoaPods | `~/.cocoapods/repos` | Re-downloads | The spec repo re-clones on the next pod install — slow, several minutes. |
| Carthage cache | Carthage | `~/Library/Caches/org.carthage.CarthageKit` | Re-downloads | Frameworks rebuild or re-download. |

### Python

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| pip cache | pip | `~/Library/Caches/pip` | Re-downloads | Wheels re-download on the next install. Safe equivalent: pip cache purge |
| uv cache | uv | `~/.cache/uv` | Re-downloads | Packages re-download on the next sync. Safe equivalent: uv cache clean |
| Poetry cache | Poetry | `~/Library/Caches/pypoetry/cache` | Re-downloads | Downloaded distributions re-fetch. Your virtualenvs are left alone. |
| Poetry artifacts | Poetry | `~/Library/Caches/pypoetry/artifacts` | Re-downloads | Built wheels re-download or rebuild. |
| Pipenv cache | Pipenv | `~/Library/Caches/pipenv` | Re-downloads | Dependency resolution cache. Rebuilt on the next lock. |
| PDM cache | PDM | `~/Library/Caches/pdm` | Re-downloads | Packages re-download on the next install. |
| Conda package cache | Conda | `~/.conda/pkgs` | Re-downloads | Extracted packages re-download. Safe equivalent: conda clean --all |
| Miniconda package cache | Miniconda | `~/miniconda3/pkgs` | Re-downloads | Extracted packages re-download. Existing environments keep working. |
| Anaconda package cache | Anaconda | `~/anaconda3/pkgs` | Re-downloads | Extracted packages re-download. Existing environments keep working. |

### Ruby

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| Bundler cache | Bundler | `~/.bundle/cache` | Re-downloads | Gems re-download on the next bundle install. |
| RubyGems spec cache | RubyGems | `~/.gem/specs` | Safe | Index of available gems. Refetched on the next gem command. |

### PHP

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| Composer cache | Composer | `~/Library/Caches/composer` | Re-downloads | Packages re-download on the next composer install. |
| Composer cache (legacy path) | Composer | `~/.composer/cache` | Re-downloads | Older Composer layout. Same effect — packages re-download. |

### Rust

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| Cargo registry cache | Rust | `~/.cargo/registry/cache` | Re-downloads | Crate archives re-download on the next build. |
| Cargo unpacked sources | Rust | `~/.cargo/registry/src` | Re-downloads | Re-extracted from the archives, or re-downloaded. |
| Cargo git checkouts | Rust | `~/.cargo/git` | Re-downloads | Git dependencies re-clone on the next build. |
| sccache | sccache | `~/Library/Caches/Mozilla.sccache` | Safe | Compiler output cache. Rebuilt as you compile. |

### Go

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| Go build cache | Go | `~/Library/Caches/go-build` | Safe | Go rebuilds packages on the next build. Safe equivalent: go clean -cache |

### .NET

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| NuGet packages | NuGet | `~/.nuget/packages` | Re-downloads | Your global package folder. Re-downloads on the next restore. |
| NuGet HTTP cache | NuGet | `~/.local/share/NuGet/v3-cache` | Safe | Registry responses. Refetched on the next restore. |
| NuGet plugins cache | NuGet | `~/.local/share/NuGet/plugins-cache` | Safe | Rebuilt automatically. |

### C & C++

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| ccache | ccache | `~/.ccache` | Re-downloads | Compiler output cache. The next build is slower, then back to normal. |
| ccache (XDG path) | ccache | `~/Library/Caches/ccache` | Re-downloads | Same as above, newer default location. |
| Conan 2 packages | Conan | `~/.conan2/p` | Re-downloads | Binary packages re-download or rebuild on the next conan install. |
| Conan 1 data | Conan | `~/.conan/data` | Re-downloads | Older Conan layout. Packages re-download or rebuild. |
| vcpkg binary cache | vcpkg | `~/.cache/vcpkg/archives` | Re-downloads | Prebuilt ports rebuild from source — this one can cost real time. |

### Mobile & cross-platform

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| Pub cache | Dart / Flutter | `~/.pub-cache` | Re-downloads | Dart and Flutter packages re-download on the next pub get. |
| Expo simulator builds | Expo | `~/.expo/ios-simulator-app-cache` | Re-downloads | Expo Go re-downloads for the simulator. |
| Expo Go cache | Expo | `~/.expo/expo-go` | Re-downloads | Re-downloads on the next expo start. |
| Unity asset cache | Unity | `~/Library/Unity/cache` | Re-downloads | Imported assets re-import — slow for big projects, but nothing is lost. |

### Other languages

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| Hex package cache | Elixir | `~/.hex/packages` | Re-downloads | Packages re-download on the next mix deps.get. |
| rebar3 cache | Erlang | `~/.cache/rebar3` | Re-downloads | Hex packages and plugins re-download. |
| opam download cache | OCaml | `~/.opam/download-cache` | Re-downloads | Source archives re-download on the next opam install. |
| Cabal package cache | Haskell | `~/.cache/cabal/packages` | Re-downloads | Hackage archives re-download. |
| Cabal cache (legacy path) | Haskell | `~/.cabal/packages` | Re-downloads | Older Cabal layout. Same effect. |
| Stack package index | Haskell | `~/.stack/pantry` | Re-downloads | The package index re-downloads — large, and slow to fetch again. |
| LuaRocks cache | Lua | `~/.cache/luarocks` | Re-downloads | Rocks re-download on the next install. |
| cpanm work directory | Perl | `~/.cpanm/work` | Safe | Build logs and unpacked sources from past installs. |
| Nimble package cache | Nim | `~/.nimble/pkgcache` | Re-downloads | Packages re-download on the next nimble install. |
| Shards cache | Crystal | `~/.cache/shards` | Re-downloads | Dependencies re-clone on the next shards install. |
| Zig global cache | Zig | `~/.cache/zig` | Safe | Compilation artifacts. Rebuilt on the next build. |
| Julia precompiled cache | Julia | `~/.julia/compiled` | Re-downloads | Packages precompile again on first use — noticeably slow once, then fine. |
| renv cache | R | `~/Library/Caches/org.R-project.R/R/renv` | Re-downloads | R packages re-install into projects from CRAN. |
| Elm package cache | Elm | `~/.elm` | Re-downloads | Packages re-download on the next elm make. |

### Build & infra

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| Homebrew downloads | Homebrew | `~/Library/Caches/Homebrew` | Re-downloads | Bottles re-download on the next install. Safe equivalent: brew cleanup --prune=all |
| Terraform plugin cache | Terraform | `~/.terraform.d/plugin-cache` | Re-downloads | Providers re-download on the next terraform init. |
| Helm cache | Helm | `~/Library/Caches/helm` | Safe | Chart index and archives refetch on the next repo update. |
| pre-commit environments | pre-commit | `~/.cache/pre-commit` | Re-downloads | Hook environments rebuild on the next commit — slow once. |


## Browsers — 7 locations

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| Chrome cache | Google Chrome | `~/Library/Caches/Google` | Safe | Pages re-download. You stay signed in — logins and history live elsewhere. |
| Safari cache | Safari | `~/Library/Caches/com.apple.Safari` | Safe | Pages re-download. Bookmarks and history are untouched. |
| Arc cache | Arc | `~/Library/Caches/Arc` | Safe | Pages re-download. Spaces and tabs are untouched. |
| Dia cache | Dia | `~/Library/Caches/company.thebrowser.dia` | Safe | Pages re-download. |
| Firefox cache | Firefox | `~/Library/Caches/Firefox` | Safe | Pages re-download. Profiles are untouched. |
| Brave cache | Brave | `~/Library/Caches/BraveSoftware` | Safe | Pages re-download. |
| Edge cache | Microsoft Edge | `~/Library/Caches/Microsoft Edge` | Safe | Pages re-download. |


## Apps — 14 locations

### Editors

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| VS Code cache | VS Code | `~/Library/Application Support/Code/Cache` | Safe | Rebuilt on the next launch. Extensions and settings are untouched. |
| VS Code cached data | VS Code | `~/Library/Application Support/Code/CachedData` | Safe | Compiled JS cache, rebuilt on the next launch. |
| Cursor cache | Cursor | `~/Library/Application Support/Cursor/Cache` | Safe | Rebuilt on the next launch. Settings are untouched. |
| Cursor cached data | Cursor | `~/Library/Application Support/Cursor/CachedData` | Safe | Rebuilt on the next launch. |
| JetBrains caches | JetBrains | `~/Library/Caches/JetBrains` | Re-downloads | The IDE re-indexes your projects on next open — slow but harmless. |

### Chat & meetings

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| Slack cache | Slack | `~/Library/Application Support/Slack/Cache` | Safe | Slack refetches avatars and files. You stay signed in. |
| Slack service worker cache | Slack | `~/Library/Application Support/Slack/Service Worker/CacheStorage` | Safe | Rebuilt on the next launch. |
| Discord cache | Discord | `~/Library/Application Support/discord/Cache` | Safe | Media refetches. You stay signed in. |
| Zoom cache | Zoom | `~/Library/Caches/us.zoom.xos` | Safe | Rebuilt on the next meeting. |

### Design

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| Figma cache | Figma | `~/Library/Caches/com.figma.Desktop` | Safe | Files re-download from Figma's servers. |
| Adobe caches | Adobe | `~/Library/Caches/Adobe` | Re-downloads | Media caches and previews regenerate. |

### Media

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| Spotify cache | Spotify | `~/Library/Caches/com.spotify.client` | Re-downloads | Downloaded audio re-streams. Offline playlists re-sync. |
| Ollama cache | Ollama | `~/Library/Caches/ollama` | Re-downloads | Cached blobs re-download. Pulled models live elsewhere. |

### Updaters

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| Loom updater downloads | Loom | `~/Library/Caches/loom-updater` | Safe | Installer downloads that already ran. |


## System — 4 locations

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| User logs | macOS | `~/Library/Logs` | Safe | Diagnostic logs from apps. New ones are written as needed. |
| Quick Look thumbnails | macOS | `~/Library/Caches/com.apple.QuickLook.thumbnailcache` | Safe | Finder previews regenerate as you browse. |
| Icon cache | macOS | `~/Library/Caches/com.apple.IconServices` | Safe | App icons redraw automatically. |
| Trash | macOS | `~/.Trash` | Re-downloads | Permanently erases what you already threw away. This one cannot be undone. |


## Review — 16 locations

### Runtimes & VMs

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| iOS Simulators | Xcode | `~/Library/Developer/CoreSimulator/Devices` | Review-only | Delete unused ones with: xcrun simctl delete unavailable |
| Docker data | Docker | `~/Library/Containers/com.docker.docker` | Review-only | Images and volumes. Reclaim space with: docker system prune |
| Colima VMs | Colima | `~/.colima` | Review-only | VM disk images. Remove one with: colima delete <profile> |
| Podman container storage | Podman | `~/.local/share/containers` | Review-only | Image layers. Reclaim with: podman system prune |
| Vagrant boxes | Vagrant | `~/.vagrant.d/boxes` | Review-only | Base box images. Remove with: vagrant box prune |
| Android SDK | Android Studio | `~/Library/Android/sdk` | Review-only | Platforms and system images. Remove them in the SDK Manager. |
| Android emulators | Android Studio | `~/.android/avd` | Review-only | Virtual devices and their disks. Delete them in Device Manager. |

### Package stores

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| Rust toolchains | rustup | `~/.rustup/toolchains` | Review-only | Installed compilers. Remove old ones with: rustup toolchain uninstall <name> |
| GHC installs | Stack | `~/.stack/programs` | Review-only | Haskell compilers. Remove versions you no longer build against. |
| pnpm global store | pnpm | `~/Library/pnpm` | Review-only | Your node_modules hard-link into this. Prune it properly with: pnpm store prune |
| Go module cache | Go | `~/go/pkg/mod` | Review-only | Read-only module cache. Clear it with: go clean -modcache |
| Julia artifacts | Julia | `~/.julia/artifacts` | Review-only | Binary dependencies of installed packages. Use Pkg.gc() instead. |
| Homebrew packages | Homebrew | `/opt/homebrew/Cellar` | Review-only | Installed formulae. Trim old versions with: brew cleanup --prune=all |
| Bazel output base | Bazel | `/private/var/tmp/_bazel_sabeur` | Review-only | Build outputs outside your home folder. Clear with: bazel clean --expunge |

### Backups & archives

| Location | Owner | Path | Kind | What happens if it goes |
|---|---|---|---|---|
| Xcode Archives | Xcode | `~/Library/Developer/Xcode/Archives` | Review-only | Shipped builds and their dSYMs. You may need these to symbolicate crash reports. |
| iPhone backups | Finder | `~/Library/Application Support/MobileSync/Backup` | Review-only | Device backups. Delete them from Finder, not here. |

