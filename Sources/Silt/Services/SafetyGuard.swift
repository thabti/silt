import Foundation
import AppKit

enum ArtifactPattern: String, CaseIterable, Identifiable, Sendable {
    case nodeModules = "node_modules"
    case dotVenv = ".venv"
    case venv
    case pods = "Pods"
    case target
    case vendor
    case next = ".next"
    case nuxt = ".nuxt"
    case turbo = ".turbo"
    case elmStuff = "elm-stuff"
    case build = "_build"
    case dartTool = ".dart_tool"

    var id: String { rawValue }
    var title: String { rawValue }

    var markers: [String] {
        switch self {
        case .nodeModules, .next, .nuxt, .turbo: ["package.json"]
        case .dotVenv, .venv: ["pyproject.toml", "requirements.txt", "setup.py"]
        case .pods: ["Podfile"]
        case .target: ["Cargo.toml"]
        case .vendor: ["composer.json"]
        case .elmStuff: ["elm.json"]
        case .build: ["mix.exs"]
        case .dartTool: ["pubspec.yaml"]
        }
    }

    static func matching(_ url: URL, fileManager: FileManager = .default) -> ArtifactPattern? {
        guard let pattern = Self(rawValue: url.lastPathComponent) else { return nil }
        let project = url.deletingLastPathComponent()
        return pattern.markers.contains { fileManager.fileExists(atPath: project.appendingPathComponent($0).path) }
            ? pattern : nil
    }
}

/// The last line of defence before anything is removed.
///
/// Every single file or folder handed to `Cleaner` passes through `verdict(for:)`.
/// The rules are deliberately blunt and independent of the catalog, so a typo in a
/// catalog entry, or a future bug in the UI, still cannot reach anything that matters.
enum SafetyGuard {

    /// User-facing escape hatch for the personal-folder denylist. All structural gates
    /// remain active when this is disabled.
    nonisolated(unsafe) static var protectedLocationsEnabled = true

    enum Verdict: Equatable {
        case allowed
        case blocked(String)

        var isAllowed: Bool { self == .allowed }
        var reason: String? {
            if case let .blocked(why) = self { return why }
            return nil
        }
    }

    static let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL

    /// Folders that hold irreplaceable data. Nothing at or below these is ever touched.
    static let protectedRelativePaths: [String] = [
        "Documents", "Desktop", "Downloads", "Pictures", "Movies", "Music", "Public",
        "Applications", "Library/Keychains", "Library/Mobile Documents", "Library/CloudStorage",
        "Library/Preferences", "Library/Containers", "Library/Group Containers",
        "Library/Messages", "Library/Mail", "Library/Safari", "Library/Photos",
        "Library/Application Support/MobileSync", "Library/Application Support/AddressBook",
        "Library/Application Support/com.apple.sharedfilelist",
        "Library/Developer/Xcode/Archives", "Library/Developer/CoreSimulator/Devices",
        "Library/pnpm", "go/pkg/mod",
        ".ssh", ".gnupg", ".aws", ".config", ".kube", ".docker", ".git",
        ".android/avd", ".password-store", ".local/share/keyrings",
    ]

    /// Artifact discovery intentionally searches normal work areas. Its marker, shape,
    /// containment, depth, and symlink checks remain independent deletion gates.
    private static let artifactProtectedRelativePaths = protectedRelativePaths.filter {
        !["Documents", "Desktop", "Downloads"].contains($0)
    }

    private static let protectedPaths: [String] = protectedRelativePaths.map {
        home.appendingPathComponent($0).standardizedFileURL.path
    }

    /// How deep below the home folder a deletable path must sit.
    /// `~/Library/Caches/Foo` is depth 3; the minimum of 2 stops anything like `~/Library`.
    private static let minimumDepth = 2

    static func verdict(for url: URL) -> Verdict {
        let standardized = url.standardizedFileURL
        let path = standardized.path

        guard path.hasPrefix("/") else { return .blocked("Not an absolute path") }
        guard path != "/" else { return .blocked("The startup disk itself") }
        guard !path.contains("..") else { return .blocked("Path escapes with ..") }

        // 1. Must live inside this user's home folder — never /System, /Library, /usr, /Applications.
        guard path == home.path || path.hasPrefix(home.path + "/") else {
            return .blocked("Outside your home folder")
        }
        guard path != home.path else { return .blocked("Your home folder itself") }

        // 2. Must be deep enough that a whole top-level folder can never be the target.
        let relative = String(path.dropFirst(home.path.count + 1))
        let depth = relative.split(separator: "/").count
        guard depth >= minimumDepth else {
            return .blocked("Too close to the top of your home folder")
        }

        // 3. Never inside a protected folder.
        if protectedLocationsEnabled {
            for guarded in protectedPaths where path == guarded || path.hasPrefix(guarded + "/") {
                return .blocked("Protected location")
            }
        }

        // 4. Never follow a link out of the allowed area — delete the link, not its target.
        let values = try? standardized.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values?.isSymbolicLink == true {
            return .blocked("Symbolic link")
        }

        // 5. If the real path differs from the given one, it has to pass the same checks.
        let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
        if resolved.path != path {
            guard resolved.path.hasPrefix(home.path + "/") else {
                return .blocked("Resolves outside your home folder")
            }
            if protectedLocationsEnabled {
                for guarded in protectedPaths where resolved.path == guarded || resolved.path.hasPrefix(guarded + "/") {
                    return .blocked("Resolves into a protected location")
                }
            }
        }

        return .allowed
    }

    /// Rules for a file you picked yourself in the Files list.
    ///
    /// Looser than `verdict(for:)` — you are allowed to throw away your own big files
    /// anywhere in your home folder — but still refuses credentials, keychains, cloud
    /// placeholders, system preferences, and media libraries, and the caller may only
    /// ever move these to the Trash, never delete them outright.
    static func verdictForUserFile(_ url: URL, isBundle: Bool) -> Verdict {
        let standardized = url.standardizedFileURL
        let path = standardized.path

        guard path.hasPrefix("/") else { return .blocked("Not an absolute path") }
        guard !path.contains("..") else { return .blocked("Path escapes with ..") }
        guard path.hasPrefix(home.path + "/") else { return .blocked("Outside your home folder") }

        let values = try? standardized.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isPackageKey])
        if values?.isSymbolicLink == true { return .blocked("Symbolic link") }

        // Only files, or a bundle treated as one file. Never a plain folder.
        if values?.isDirectory == true, values?.isPackage != true {
            return .blocked("Folders are not removed from this list")
        }

        if protectedLocationsEnabled {
            for guarded in fileProtectedPaths where path == guarded || path.hasPrefix(guarded + "/") {
                return .blocked("Protected location")
            }
        }

        // A media library is somebody's entire photo or music history.
        let libraryBundles: Set<String> = [
            "photoslibrary", "imovielibrary", "tvlibrary", "musiclibrary", "aplibrary",
            "photolibrary", "migrationreport",
        ]
        if isBundle, libraryBundles.contains(standardized.pathExtension.lowercased()) {
            return .blocked("Media library — manage it in the app that owns it")
        }

        return .allowed
    }

    /// Independent rules for marker-validated, regenerable project artifact directories.
    /// Callers may only move an allowed directory to the Trash.
    static func verdictForProjectArtifact(_ url: URL, homeDirectory: URL = home) -> Verdict {
        let artifactHome = homeDirectory.standardizedFileURL
        let artifactProtectedPaths = artifactProtectedRelativePaths.map {
            artifactHome.appendingPathComponent($0).standardizedFileURL.path
        }
        let standardized = url.standardizedFileURL
        let path = standardized.path

        guard path.hasPrefix("/") else { return .blocked("Not an absolute path") }
        guard !path.contains("..") else { return .blocked("Path escapes with ..") }
        guard path.hasPrefix(artifactHome.path + "/") else { return .blocked("Outside your home folder") }

        let relative = String(path.dropFirst(artifactHome.path.count + 1))
        guard relative.split(separator: "/").count >= minimumDepth else {
            return .blocked("Too close to the top of your home folder")
        }
        if protectedLocationsEnabled {
            for guarded in artifactProtectedPaths where path == guarded || path.hasPrefix(guarded + "/") {
                return .blocked("Protected location")
            }
        }

        let values = try? standardized.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        if values?.isSymbolicLink == true { return .blocked("Symbolic link") }
        guard values?.isDirectory == true else { return .blocked("Not a directory") }
        guard ArtifactPattern.matching(standardized) != nil else {
            return .blocked("Not a marker-validated project artifact")
        }

        let resolved = standardized.resolvingSymlinksInPath().standardizedFileURL
        guard resolved.path == path else { return .blocked("Contains a symbolic link") }
        return .allowed
    }

    static func verdictForAppLeftover(_ url: URL, matchedOrphanID: String, homeDirectory: URL = home,
                                      verifyInstalled: Bool = true) -> Verdict {
        let standardized = url.standardizedFileURL, leftoverHome = homeDirectory.standardizedFileURL
        let id = matchedOrphanID.lowercased()
        guard !id.hasPrefix("com.apple.") else { return .blocked("Apple system data") }
        let roots = ["Application Support", "Caches", "Preferences", "Containers", "Group Containers",
                     "Saved Application State", "HTTPStorages", "WebKit", "Logs", "LaunchAgents", "Application Scripts"]
            .map { leftoverHome.appendingPathComponent("Library/\($0)").standardizedFileURL }
        guard let root = roots.first(where: { standardized.deletingLastPathComponent() == $0 }) else {
            return .blocked("Not directly inside an app-data location")
        }
        guard standardized.path.hasPrefix(leftoverHome.appendingPathComponent("Library").path + "/") else { return .blocked("Outside Library") }
        let values = try? standardized.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values?.isSymbolicLink == true { return .blocked("Symbolic link") }
        var name = standardized.lastPathComponent.lowercased()
        if name.hasSuffix(".savedstate") { name.removeLast(11) }
        if name.hasSuffix(".plist") { name.removeLast(6) }
        if root.lastPathComponent == "Group Containers" {
            let parts = name.split(separator: ".", maxSplits: 1).map(String.init)
            if parts.count == 2, parts[0].count == 10, parts[0].allSatisfy({ $0.isLetter || $0.isNumber }) { name = parts[1] }
        }
        guard name == id || name.hasPrefix(id + ".") else { return .blocked("Name does not match the orphan app") }
        if verifyInstalled, NSWorkspace.shared.urlForApplication(withBundleIdentifier: matchedOrphanID) != nil {
            return .blocked("App is installed")
        }
        return .allowed
    }

    /// The subset of protected locations that also applies to hand-picked files.
    private static let fileProtectedPaths: [String] = [
        "Library/Keychains", "Library/Preferences", "Library/Mobile Documents",
        "Library/CloudStorage", "Library/Application Support/com.apple.sharedfilelist",
        ".ssh", ".gnupg", ".aws", ".config", ".kube", ".password-store",
        ".local/share/keyrings",
    ].map { home.appendingPathComponent($0).standardizedFileURL.path }

    /// A bucket root may sit one level higher than its children (`~/.Trash`), so it is
    /// checked with the containment and protection rules but a relaxed depth of 1.
    static func verdictForBucketRoot(_ url: URL) -> Verdict {
        let standardized = url.standardizedFileURL
        let path = standardized.path

        guard path == home.path || path.hasPrefix(home.path + "/") else {
            return .blocked("Outside your home folder")
        }
        guard path != home.path else { return .blocked("Your home folder itself") }

        if protectedLocationsEnabled {
            for guarded in protectedPaths where path == guarded || path.hasPrefix(guarded + "/") {
                return .blocked("Protected location")
            }
        }
        return .allowed
    }
}
