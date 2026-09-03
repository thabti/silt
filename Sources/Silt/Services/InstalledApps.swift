import Foundation
import CoreServices

struct InstalledApp: Identifiable, Sendable, Hashable {
    let url: URL
    let bundleID: String
    let name: String
    let version: String
    let bytes: Int64
    let lastUsed: Date?
    let isAppleApp: Bool
    let isSelf: Bool
    var id: String { url.path }
    var isRemovable: Bool { !isAppleApp && !isSelf }
}

struct InstalledAppCensus: Sendable {
    let bundleIDs: Set<String>
    let names: Set<String>
}

enum InstalledApps {
    static func inventory(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                          onFound: @escaping @Sendable (InstalledApp) -> Void) async -> [InstalledApp] {
        let urls = applicationURLs(homeDirectory: homeDirectory)
        return await withTaskGroup(of: InstalledApp?.self, returning: [InstalledApp].self) { group in
            for url in urls { group.addTask {
                guard !Task.isCancelled, let metadata = metadata(at: url) else { return nil }
                let measured = Scanner.size(of: url).bytes
                guard !Task.isCancelled else { return nil }
                let app = InstalledApp(url: url, bundleID: metadata.id, name: metadata.name,
                    version: metadata.version, bytes: measured, lastUsed: lastUsed(url),
                    isAppleApp: metadata.id.lowercased().hasPrefix("com.apple.") || url.path.hasPrefix("/System/"),
                    isSelf: metadata.id == Bundle.main.bundleIdentifier)
                onFound(app); return app
            }}
            var result: [InstalledApp] = []
            for await app in group { if let app { result.append(app) } }
            return result.sorted { $0.bytes > $1.bytes }
        }
    }

    static func census(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> InstalledAppCensus {
        var ids = Set<String>(), names = Set<String>()
        for app in applicationURLs(homeDirectory: homeDirectory) {
            guard let value = metadata(at: app) else { continue }
            ids.insert(value.id.lowercased()); names.insert(value.name.lowercased())
        }
        return InstalledAppCensus(bundleIDs: ids, names: names)
    }

    private static func applicationURLs(homeDirectory: URL) -> Set<URL> {
        let fm = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications"), homeDirectory.appendingPathComponent("Applications"),
                     URL(fileURLWithPath: "/System/Applications"), URL(fileURLWithPath: "/System/Applications/Utilities")]
        var apps = Set<URL>()
        for root in roots {
            guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for child in children {
                if child.pathExtension.lowercased() == "app" { apps.insert(child); continue }
                guard child.pathExtension.isEmpty, root.path == "/Applications" else { continue }
                let nested = (try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil)) ?? []
                apps.formUnion(nested.filter { $0.pathExtension.lowercased() == "app" })
            }
        }
        return apps
    }

    private static func metadata(at app: URL) -> (id: String, name: String, version: String)? {
        guard let bundle = Bundle(url: app), let id = bundle.bundleIdentifier else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? app.deletingPathExtension().lastPathComponent
        return (id, name, bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
    }

    private static func lastUsed(_ url: URL) -> Date? {
        if let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
           let value = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date { return value }
        return try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
