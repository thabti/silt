import Foundation

/// The complete list of locations Silt knows about.
///
/// This catalog is the app's allow-list: `Cleaner` refuses any path that did not come
/// from here, so a bug elsewhere in the UI can never widen what gets deleted.
///
/// Paths are the documented macOS defaults for each tool. Anything a tool can relocate
/// with an environment variable (`PUB_CACHE`, `DENO_DIR`, `GRADLE_USER_HOME`,
/// `POETRY_CACHE_DIR`, …) is listed at its default only — a moved cache simply will not
/// be found, which is the safe way to be wrong.
enum Catalog {

    static let trashID = "system.trash"

    private static let home = FileManager.default.homeDirectoryForCurrentUser

    private static func t(
        _ id: String,
        _ name: String,
        _ owner: String,
        _ group: String,
        _ rel: String,
        _ kind: CleanKind,
        _ why: String,
        _ category: CleanCategory = .developer
    ) -> CleanTarget {
        CleanTarget(
            id: id, name: name, owner: owner, group: group,
            path: home.appendingPathComponent(rel),
            category: category, kind: kind, consequence: why
        )
    }

    private static func absolute(
        _ id: String, _ name: String, _ owner: String, _ group: String,
        _ path: String, _ why: String
    ) -> CleanTarget {
        CleanTarget(
            id: id, name: name, owner: owner, group: group,
            path: URL(fileURLWithPath: path),
            category: .review, kind: .review, consequence: why
        )
    }

    // MARK: - JavaScript & Node

    private static let javascript: [CleanTarget] = [
        t("dev.npm", "npm cache", "npm", "JavaScript & Node", ".npm/_cacache", .prunable,
          "Packages re-download on the next install. Safe equivalent: npm cache clean --force"),
        t("dev.yarn1", "Yarn cache", "Yarn Classic", "JavaScript & Node", "Library/Caches/Yarn", .prunable,
          "Packages re-download on the next install."),
        t("dev.yarnberry", "Yarn Berry cache", "Yarn 2+", "JavaScript & Node", ".yarn/berry/cache", .prunable,
          "Zip archives of every dependency. Re-downloads unless a project uses zero-installs."),
        t("dev.pnpm.cache", "pnpm metadata cache", "pnpm", "JavaScript & Node", "Library/Caches/pnpm", .prunable,
          "Registry metadata and tarballs re-download. This is not the content store."),
        t("dev.bun", "Bun cache", "Bun", "JavaScript & Node", ".bun/install/cache", .prunable,
          "Packages re-download on the next bun install."),
        t("dev.deno", "Deno cache", "Deno", "JavaScript & Node", "Library/Caches/deno", .prunable,
          "Remote modules and compiled TypeScript re-download on the next run."),
        t("dev.nodegyp", "node-gyp headers", "node-gyp", "JavaScript & Node", "Library/Caches/node-gyp", .prunable,
          "Node headers re-download when a native module builds."),
        t("dev.typescript", "TypeScript type cache", "TypeScript", "JavaScript & Node", "Library/Caches/typescript", .safe,
          "Auto-acquired type definitions come back when needed."),
        t("dev.electron", "Electron binaries", "Electron", "JavaScript & Node", "Library/Caches/electron", .prunable,
          "Electron runtimes re-download on the next build — hundreds of MB each."),
        t("dev.electronbuilder", "electron-builder cache", "electron-builder", "JavaScript & Node", "Library/Caches/electron-builder", .prunable,
          "Packaging tools and app images re-download on the next package run."),
        t("dev.playwright", "Playwright browsers", "Playwright", "JavaScript & Node", "Library/Caches/ms-playwright", .prunable,
          "Test browsers re-download — around 1 GB."),
        t("dev.puppeteer", "Puppeteer browsers", "Puppeteer", "JavaScript & Node", ".cache/puppeteer", .prunable,
          "Chromium re-downloads on the next run."),
        t("dev.cypress", "Cypress binaries", "Cypress", "JavaScript & Node", "Library/Caches/Cypress", .prunable,
          "Cypress re-downloads on the next run."),
        t("dev.selenium", "Selenium drivers", "Selenium", "JavaScript & Node", ".cache/selenium", .prunable,
          "Drivers re-download on the next run."),
    ]

    // MARK: - JVM & Android

    private static let jvm: [CleanTarget] = [
        t("dev.maven", "Maven repository", "Maven", "JVM & Android", ".m2/repository", .prunable,
          "Your local copy of every Java dependency. Re-downloads on the next mvn build — often slow."),
        t("dev.gradle.caches", "Gradle caches", "Gradle", "JVM & Android", ".gradle/caches", .prunable,
          "Dependencies re-download and build fingerprints rebuild on the next build."),
        t("dev.gradle.wrapper", "Gradle distributions", "Gradle", "JVM & Android", ".gradle/wrapper", .prunable,
          "Gradle itself re-downloads on the next build."),
        t("dev.gradle.daemon", "Gradle daemon logs", "Gradle", "JVM & Android", ".gradle/daemon", .safe,
          "Logs from past daemon runs."),
        t("dev.gradle.native", "Gradle native bits", "Gradle", "JVM & Android", ".gradle/native", .safe,
          "Small platform helpers Gradle re-extracts on demand."),
        t("dev.ivy", "Ivy cache", "Ivy / sbt", "JVM & Android", ".ivy2/cache", .prunable,
          "Scala and Ant dependencies re-download on the next build."),
        t("dev.coursier", "Coursier cache", "Coursier / sbt", "JVM & Android", "Library/Caches/Coursier", .prunable,
          "Scala artifacts re-download. Modern sbt and Scala CLI use this."),
        t("dev.sbtboot", "sbt boot files", "sbt", "JVM & Android", ".sbt/boot", .prunable,
          "sbt re-downloads its launcher and Scala versions."),
        t("dev.konan", "Kotlin/Native dependencies", "Kotlin", "JVM & Android", ".konan", .prunable,
          "Native toolchains re-download — large, and slow to fetch again."),
        t("dev.android.build", "Android build cache", "Android", "JVM & Android", ".android/build-cache", .safe,
          "Rebuilt on the next Android build."),
        t("dev.android.cache", "Android SDK cache", "Android", "JVM & Android", ".android/cache", .safe,
          "SDK metadata refetches on the next sync."),
    ]

    // MARK: - Apple & Xcode

    private static let apple: [CleanTarget] = [
        t("dev.xcode.derived", "Xcode DerivedData", "Xcode", "Apple & Xcode", "Library/Developer/Xcode/DerivedData", .safe,
          "Xcode re-indexes and rebuilds on the next build. Usually the biggest win on a dev Mac."),
        t("dev.xcode.previews", "Xcode Previews cache", "Xcode", "Apple & Xcode", "Library/Developer/Xcode/UserData/Previews", .safe,
          "SwiftUI previews rebuild themselves."),
        t("dev.xcode.docs", "Xcode documentation cache", "Xcode", "Apple & Xcode", "Library/Developer/Xcode/DocumentationCache", .safe,
          "Docs re-download when you open the documentation window."),
        t("dev.xcode.devicesupport", "iOS DeviceSupport symbols", "Xcode", "Apple & Xcode", "Library/Developer/Xcode/iOS DeviceSupport", .prunable,
          "Re-created the next time you plug in a device on that iOS version."),
        t("dev.simulator.caches", "Simulator caches", "Xcode", "Apple & Xcode", "Library/Developer/CoreSimulator/Caches", .safe,
          "Runtimes re-extract on next launch. Your simulators stay."),
        t("dev.swiftpm", "Swift Package Manager cache", "SwiftPM", "Apple & Xcode", "Library/Caches/org.swift.swiftpm", .prunable,
          "Packages re-clone on the next resolve."),
        t("dev.cocoapods.cache", "CocoaPods cache", "CocoaPods", "Apple & Xcode", "Library/Caches/CocoaPods", .prunable,
          "Pods re-download on the next pod install."),
        t("dev.cocoapods.repos", "CocoaPods spec repos", "CocoaPods", "Apple & Xcode", ".cocoapods/repos", .prunable,
          "The spec repo re-clones on the next pod install — slow, several minutes."),
        t("dev.carthage", "Carthage cache", "Carthage", "Apple & Xcode", "Library/Caches/org.carthage.CarthageKit", .prunable,
          "Frameworks rebuild or re-download."),
    ]

    // MARK: - Python

    private static let python: [CleanTarget] = [
        t("dev.pip", "pip cache", "pip", "Python", "Library/Caches/pip", .prunable,
          "Wheels re-download on the next install. Safe equivalent: pip cache purge"),
        t("dev.uv", "uv cache", "uv", "Python", ".cache/uv", .prunable,
          "Packages re-download on the next sync. Safe equivalent: uv cache clean"),
        t("dev.poetry.cache", "Poetry cache", "Poetry", "Python", "Library/Caches/pypoetry/cache", .prunable,
          "Downloaded distributions re-fetch. Your virtualenvs are left alone."),
        t("dev.poetry.artifacts", "Poetry artifacts", "Poetry", "Python", "Library/Caches/pypoetry/artifacts", .prunable,
          "Built wheels re-download or rebuild."),
        t("dev.pipenv", "Pipenv cache", "Pipenv", "Python", "Library/Caches/pipenv", .prunable,
          "Dependency resolution cache. Rebuilt on the next lock."),
        t("dev.pdm", "PDM cache", "PDM", "Python", "Library/Caches/pdm", .prunable,
          "Packages re-download on the next install."),
        t("dev.conda.user", "Conda package cache", "Conda", "Python", ".conda/pkgs", .prunable,
          "Extracted packages re-download. Safe equivalent: conda clean --all"),
        t("dev.miniconda", "Miniconda package cache", "Miniconda", "Python", "miniconda3/pkgs", .prunable,
          "Extracted packages re-download. Existing environments keep working."),
        t("dev.anaconda", "Anaconda package cache", "Anaconda", "Python", "anaconda3/pkgs", .prunable,
          "Extracted packages re-download. Existing environments keep working."),
    ]

    // MARK: - Ruby, PHP, Rust, Go, .NET

    private static let ruby: [CleanTarget] = [
        t("dev.bundler", "Bundler cache", "Bundler", "Ruby", ".bundle/cache", .prunable,
          "Gems re-download on the next bundle install."),
        t("dev.gemspecs", "RubyGems spec cache", "RubyGems", "Ruby", ".gem/specs", .safe,
          "Index of available gems. Refetched on the next gem command."),
    ]

    private static let php: [CleanTarget] = [
        t("dev.composer", "Composer cache", "Composer", "PHP", "Library/Caches/composer", .prunable,
          "Packages re-download on the next composer install."),
        t("dev.composer.home", "Composer cache (legacy path)", "Composer", "PHP", ".composer/cache", .prunable,
          "Older Composer layout. Same effect — packages re-download."),
    ]

    private static let rust: [CleanTarget] = [
        t("dev.cargo.cache", "Cargo registry cache", "Rust", "Rust", ".cargo/registry/cache", .prunable,
          "Crate archives re-download on the next build."),
        t("dev.cargo.src", "Cargo unpacked sources", "Rust", "Rust", ".cargo/registry/src", .prunable,
          "Re-extracted from the archives, or re-downloaded."),
        t("dev.cargo.git", "Cargo git checkouts", "Rust", "Rust", ".cargo/git", .prunable,
          "Git dependencies re-clone on the next build."),
        t("dev.sccache", "sccache", "sccache", "Rust", "Library/Caches/Mozilla.sccache", .safe,
          "Compiler output cache. Rebuilt as you compile."),
    ]

    private static let golang: [CleanTarget] = [
        t("dev.gobuild", "Go build cache", "Go", "Go", "Library/Caches/go-build", .safe,
          "Go rebuilds packages on the next build. Safe equivalent: go clean -cache"),
    ]

    private static let dotnet: [CleanTarget] = [
        t("dev.nuget", "NuGet packages", "NuGet", ".NET", ".nuget/packages", .prunable,
          "Your global package folder. Re-downloads on the next restore."),
        t("dev.nuget.http", "NuGet HTTP cache", "NuGet", ".NET", ".local/share/NuGet/v3-cache", .safe,
          "Registry responses. Refetched on the next restore."),
        t("dev.nuget.plugins", "NuGet plugins cache", "NuGet", ".NET", ".local/share/NuGet/plugins-cache", .safe,
          "Rebuilt automatically."),
    ]

    // MARK: - C & C++

    private static let native: [CleanTarget] = [
        t("dev.ccache.home", "ccache", "ccache", "C & C++", ".ccache", .prunable,
          "Compiler output cache. The next build is slower, then back to normal."),
        t("dev.ccache.xdg", "ccache (XDG path)", "ccache", "C & C++", "Library/Caches/ccache", .prunable,
          "Same as above, newer default location."),
        t("dev.conan2", "Conan 2 packages", "Conan", "C & C++", ".conan2/p", .prunable,
          "Binary packages re-download or rebuild on the next conan install."),
        t("dev.conan1", "Conan 1 data", "Conan", "C & C++", ".conan/data", .prunable,
          "Older Conan layout. Packages re-download or rebuild."),
        t("dev.vcpkg", "vcpkg binary cache", "vcpkg", "C & C++", ".cache/vcpkg/archives", .prunable,
          "Prebuilt ports rebuild from source — this one can cost real time."),
    ]

    // MARK: - Mobile & cross-platform

    private static let mobile: [CleanTarget] = [
        t("dev.pubcache", "Pub cache", "Dart / Flutter", "Mobile & cross-platform", ".pub-cache", .prunable,
          "Dart and Flutter packages re-download on the next pub get."),
        t("dev.expo", "Expo simulator builds", "Expo", "Mobile & cross-platform", ".expo/ios-simulator-app-cache", .prunable,
          "Expo Go re-downloads for the simulator."),
        t("dev.expogo", "Expo Go cache", "Expo", "Mobile & cross-platform", ".expo/expo-go", .prunable,
          "Re-downloads on the next expo start."),
        t("dev.unity", "Unity asset cache", "Unity", "Mobile & cross-platform", "Library/Unity/cache", .prunable,
          "Imported assets re-import — slow for big projects, but nothing is lost."),
    ]

    // MARK: - Other languages

    private static let others: [CleanTarget] = [
        t("dev.hex", "Hex package cache", "Elixir", "Other languages", ".hex/packages", .prunable,
          "Packages re-download on the next mix deps.get."),
        t("dev.rebar3", "rebar3 cache", "Erlang", "Other languages", ".cache/rebar3", .prunable,
          "Hex packages and plugins re-download."),
        t("dev.opam", "opam download cache", "OCaml", "Other languages", ".opam/download-cache", .prunable,
          "Source archives re-download on the next opam install."),
        t("dev.cabal.xdg", "Cabal package cache", "Haskell", "Other languages", ".cache/cabal/packages", .prunable,
          "Hackage archives re-download."),
        t("dev.cabal.home", "Cabal cache (legacy path)", "Haskell", "Other languages", ".cabal/packages", .prunable,
          "Older Cabal layout. Same effect."),
        t("dev.stack.pantry", "Stack package index", "Haskell", "Other languages", ".stack/pantry", .prunable,
          "The package index re-downloads — large, and slow to fetch again."),
        t("dev.luarocks", "LuaRocks cache", "Lua", "Other languages", ".cache/luarocks", .prunable,
          "Rocks re-download on the next install."),
        t("dev.cpanm", "cpanm work directory", "Perl", "Other languages", ".cpanm/work", .safe,
          "Build logs and unpacked sources from past installs."),
        t("dev.nimble", "Nimble package cache", "Nim", "Other languages", ".nimble/pkgcache", .prunable,
          "Packages re-download on the next nimble install."),
        t("dev.shards", "Shards cache", "Crystal", "Other languages", ".cache/shards", .prunable,
          "Dependencies re-clone on the next shards install."),
        t("dev.zig", "Zig global cache", "Zig", "Other languages", ".cache/zig", .safe,
          "Compilation artifacts. Rebuilt on the next build."),
        t("dev.julia", "Julia precompiled cache", "Julia", "Other languages", ".julia/compiled", .prunable,
          "Packages precompile again on first use — noticeably slow once, then fine."),
        t("dev.renv", "renv cache", "R", "Other languages", "Library/Caches/org.R-project.R/R/renv", .prunable,
          "R packages re-install into projects from CRAN."),
        t("dev.elm", "Elm package cache", "Elm", "Other languages", ".elm", .prunable,
          "Packages re-download on the next elm make."),
    ]

    // MARK: - Build & infra

    private static let infra: [CleanTarget] = [
        t("dev.homebrew", "Homebrew downloads", "Homebrew", "Build & infra", "Library/Caches/Homebrew", .prunable,
          "Bottles re-download on the next install. Safe equivalent: brew cleanup --prune=all"),
        t("dev.terraform", "Terraform plugin cache", "Terraform", "Build & infra", ".terraform.d/plugin-cache", .prunable,
          "Providers re-download on the next terraform init."),
        t("dev.helm", "Helm cache", "Helm", "Build & infra", "Library/Caches/helm", .safe,
          "Chart index and archives refetch on the next repo update."),
        t("dev.precommit", "pre-commit environments", "pre-commit", "Build & infra", ".cache/pre-commit", .prunable,
          "Hook environments rebuild on the next commit — slow once."),
    ]

    // MARK: - Browsers

    private static let browsers: [CleanTarget] = [
        t("web.chrome", "Chrome cache", "Google Chrome", "Browsers", "Library/Caches/Google", .safe,
          "Pages re-download. You stay signed in — logins and history live elsewhere.", .browsers),
        t("web.safari", "Safari cache", "Safari", "Browsers", "Library/Caches/com.apple.Safari", .safe,
          "Pages re-download. Bookmarks and history are untouched.", .browsers),
        t("web.arc", "Arc cache", "Arc", "Browsers", "Library/Caches/Arc", .safe,
          "Pages re-download. Spaces and tabs are untouched.", .browsers),
        t("web.dia", "Dia cache", "Dia", "Browsers", "Library/Caches/company.thebrowser.dia", .safe,
          "Pages re-download.", .browsers),
        t("web.firefox", "Firefox cache", "Firefox", "Browsers", "Library/Caches/Firefox", .safe,
          "Pages re-download. Profiles are untouched.", .browsers),
        t("web.brave", "Brave cache", "Brave", "Browsers", "Library/Caches/BraveSoftware", .safe,
          "Pages re-download.", .browsers),
        t("web.edge", "Edge cache", "Microsoft Edge", "Browsers", "Library/Caches/Microsoft Edge", .safe,
          "Pages re-download.", .browsers),
    ]

    // MARK: - Apps

    private static let applications: [CleanTarget] = [
        t("app.vscode", "VS Code cache", "VS Code", "Editors", "Library/Application Support/Code/Cache", .safe,
          "Rebuilt on the next launch. Extensions and settings are untouched.", .applications),
        t("app.vscodedata", "VS Code cached data", "VS Code", "Editors", "Library/Application Support/Code/CachedData", .safe,
          "Compiled JS cache, rebuilt on the next launch.", .applications),
        t("app.cursor", "Cursor cache", "Cursor", "Editors", "Library/Application Support/Cursor/Cache", .safe,
          "Rebuilt on the next launch. Settings are untouched.", .applications),
        t("app.cursordata", "Cursor cached data", "Cursor", "Editors", "Library/Application Support/Cursor/CachedData", .safe,
          "Rebuilt on the next launch.", .applications),
        t("app.jetbrains", "JetBrains caches", "JetBrains", "Editors", "Library/Caches/JetBrains", .prunable,
          "The IDE re-indexes your projects on next open — slow but harmless.", .applications),
        t("app.slack", "Slack cache", "Slack", "Chat & meetings", "Library/Application Support/Slack/Cache", .safe,
          "Slack refetches avatars and files. You stay signed in.", .applications),
        t("app.slackservice", "Slack service worker cache", "Slack", "Chat & meetings", "Library/Application Support/Slack/Service Worker/CacheStorage", .safe,
          "Rebuilt on the next launch.", .applications),
        t("app.discord", "Discord cache", "Discord", "Chat & meetings", "Library/Application Support/discord/Cache", .safe,
          "Media refetches. You stay signed in.", .applications),
        t("app.zoom", "Zoom cache", "Zoom", "Chat & meetings", "Library/Caches/us.zoom.xos", .safe,
          "Rebuilt on the next meeting.", .applications),
        t("app.figma", "Figma cache", "Figma", "Design", "Library/Caches/com.figma.Desktop", .safe,
          "Files re-download from Figma's servers.", .applications),
        t("app.adobe", "Adobe caches", "Adobe", "Design", "Library/Caches/Adobe", .prunable,
          "Media caches and previews regenerate.", .applications),
        t("app.spotify", "Spotify cache", "Spotify", "Media", "Library/Caches/com.spotify.client", .prunable,
          "Downloaded audio re-streams. Offline playlists re-sync.", .applications),
        t("app.ollama", "Ollama cache", "Ollama", "Media", "Library/Caches/ollama", .prunable,
          "Cached blobs re-download. Pulled models live elsewhere.", .applications),
        t("app.loom", "Loom updater downloads", "Loom", "Updaters", "Library/Caches/loom-updater", .safe,
          "Installer downloads that already ran.", .applications),
    ]

    // MARK: - System

    private static let system: [CleanTarget] = [
        t("system.logs", "User logs", "macOS", "System", "Library/Logs", .safe,
          "Diagnostic logs from apps. New ones are written as needed.", .system),
        t("system.quicklook", "Quick Look thumbnails", "macOS", "System", "Library/Caches/com.apple.QuickLook.thumbnailcache", .safe,
          "Finder previews regenerate as you browse.", .system),
        t("system.iconservices", "Icon cache", "macOS", "System", "Library/Caches/com.apple.IconServices", .safe,
          "App icons redraw automatically.", .system),
        t(trashID, "Trash", "macOS", "System", ".Trash", .prunable,
          "Permanently erases what you already threw away. This one cannot be undone.", .system),
    ]

    // MARK: - Review only — never deleted by the app

    private static let review: [CleanTarget] = [
        t("review.simulators", "iOS Simulators", "Xcode", "Runtimes & VMs", "Library/Developer/CoreSimulator/Devices", .review,
          "Delete unused ones with: xcrun simctl delete unavailable", .review),
        t("review.docker", "Docker data", "Docker", "Runtimes & VMs", "Library/Containers/com.docker.docker", .review,
          "Images and volumes. Reclaim space with: docker system prune", .review),
        t("review.colima", "Colima VMs", "Colima", "Runtimes & VMs", ".colima", .review,
          "VM disk images. Remove one with: colima delete <profile>", .review),
        t("review.containers", "Podman container storage", "Podman", "Runtimes & VMs", ".local/share/containers", .review,
          "Image layers. Reclaim with: podman system prune", .review),
        t("review.vagrant", "Vagrant boxes", "Vagrant", "Runtimes & VMs", ".vagrant.d/boxes", .review,
          "Base box images. Remove with: vagrant box prune", .review),
        t("review.androidsdk", "Android SDK", "Android Studio", "Runtimes & VMs", "Library/Android/sdk", .review,
          "Platforms and system images. Remove them in the SDK Manager.", .review),
        t("review.androidavd", "Android emulators", "Android Studio", "Runtimes & VMs", ".android/avd", .review,
          "Virtual devices and their disks. Delete them in Device Manager.", .review),
        t("review.rustup", "Rust toolchains", "rustup", "Package stores", ".rustup/toolchains", .review,
          "Installed compilers. Remove old ones with: rustup toolchain uninstall <name>", .review),
        t("review.stackprograms", "GHC installs", "Stack", "Package stores", ".stack/programs", .review,
          "Haskell compilers. Remove versions you no longer build against.", .review),
        t("review.pnpmstore", "pnpm global store", "pnpm", "Package stores", "Library/pnpm", .review,
          "Your node_modules hard-link into this. Prune it properly with: pnpm store prune", .review),
        t("review.gomod", "Go module cache", "Go", "Package stores", "go/pkg/mod", .review,
          "Read-only module cache. Clear it with: go clean -modcache", .review),
        t("review.juliaartifacts", "Julia artifacts", "Julia", "Package stores", ".julia/artifacts", .review,
          "Binary dependencies of installed packages. Use Pkg.gc() instead.", .review),
        t("review.xcodearchives", "Xcode Archives", "Xcode", "Backups & archives", "Library/Developer/Xcode/Archives", .review,
          "Shipped builds and their dSYMs. You may need these to symbolicate crash reports.", .review),
        t("review.mobilebackups", "iPhone backups", "Finder", "Backups & archives", "Library/Application Support/MobileSync/Backup", .review,
          "Device backups. Delete them from Finder, not here.", .review),
        absolute("review.brew", "Homebrew packages", "Homebrew", "Package stores", "/opt/homebrew/Cellar",
                 "Installed formulae. Trim old versions with: brew cleanup --prune=all"),
        absolute("review.bazel", "Bazel output base", "Bazel", "Package stores", "/private/var/tmp/_bazel_\(NSUserName())",
                 "Build outputs outside your home folder. Clear with: bazel clean --expunge"),
    ]

    static let all: [CleanTarget] =
        javascript + jvm + apple + python + ruby + php + rust + golang + dotnet
        + native + mobile + others + infra
        + browsers + applications + system + review

    /// Only the entries that actually exist on this Mac.
    static func present() -> [CleanTarget] {
        let fm = FileManager.default
        return all.filter { fm.fileExists(atPath: $0.path.path) }
    }
}
