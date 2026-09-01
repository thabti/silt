import Foundation

/// What a bucket of files is for, used to group the UI and pick an accent colour.
enum CleanCategory: String, CaseIterable, Identifiable, Hashable {
    case developer
    case browsers
    case applications
    case system
    case review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .developer:    "Developer"
        case .browsers:     "Browsers"
        case .applications: "Apps"
        case .system:       "System"
        case .review:       "Review"
        }
    }

    var symbol: String {
        switch self {
        case .developer:    "hammer.fill"
        case .browsers:     "safari.fill"
        case .applications: "square.grid.2x2.fill"
        case .system:       "gearshape.fill"
        case .review:       "eye.fill"
        }
    }

    var blurb: String {
        switch self {
        case .developer:    "Build caches and downloaded packages. Rebuilt on your next build."
        case .browsers:     "Page and media caches. Pages re-download, logins are untouched."
        case .applications: "App caches and updater downloads. Settings are untouched."
        case .system:       "Logs, crash reports and the Trash."
        case .review:       "Big folders Silt will never delete. Look, decide, act yourself."
        }
    }
}

/// How risky a bucket is. `.review` items can never be deleted by the app.
enum CleanKind: String, Hashable {
    case safe      // regenerated automatically, nothing to re-download
    case prunable  // regenerated, but costs a re-download or a rebuild
    case review    // report only — the app refuses to delete these

    var label: String {
        switch self {
        case .safe:     "Safe"
        case .prunable: "Re-downloads"
        case .review:   "Manual"
        }
    }

    var isDeletable: Bool { self != .review }
}

/// One known location. Silt only ever touches paths that came from the catalog:
/// it clears what is *inside* a bucket and always leaves the bucket folder itself in place,
/// because apps expect their cache folder to exist.
struct CleanTarget: Identifiable, Hashable {
    let id: String
    let name: String
    let owner: String          // which tool or app owns it
    let group: String          // sub-heading inside a category, e.g. "Python"
    let path: URL
    let category: CleanCategory
    let kind: CleanKind
    let consequence: String    // plain-language "what happens if this goes"

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.path.hasPrefix(home) ? "~" + path.path.dropFirst(home.count) : path.path
    }
}

/// A direct child of a bucket, measured during the scan so cleaning never has to re-measure.
struct ChildEntry: Identifiable, Hashable {
    let url: URL
    let bytes: Int64
    var id: String { url.path }
    var name: String { url.lastPathComponent }
}

/// A bucket after measuring.
struct ScannedTarget: Identifiable, Hashable {
    let target: CleanTarget
    var bytes: Int64
    var fileCount: Int
    var children: [ChildEntry]
    var unreadable: Bool       // permission denied somewhere in the tree

    var id: String { target.id }
    var isEmpty: Bool { bytes == 0 }
}

extension Int64 {
    /// "12.7 GB" — decimal units, the same convention Finder uses.
    ///
    /// Hand-rolled on purpose: this is called for every visible row on every render, and
    /// `ByteCountFormatter` builds a formatter per call, which showed up while scrolling
    /// a 500-row list.
    var byteLabel: String {
        if self < 1000 { return "\(self) bytes" }

        var value = Double(self)
        var unit = 0
        let units = ["bytes", "KB", "MB", "GB", "TB", "PB"]
        while value >= 1000, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }

        // Finder-style precision: more decimals only where they carry information.
        let digits = value < 10 ? 2 : (value < 100 ? 1 : 0)
        return String(format: "%.\(digits)f %@", value, units[unit])
    }
}
