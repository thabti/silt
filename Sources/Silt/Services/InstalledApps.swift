import Foundation

struct InstalledAppCensus: Sendable {
    let bundleIDs: Set<String>
    let names: Set<String>
}

enum InstalledApps {
    static func census(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> InstalledAppCensus {
        let fm = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications"), homeDirectory.appendingPathComponent("Applications"),
                     URL(fileURLWithPath: "/System/Applications"), URL(fileURLWithPath: "/System/Applications/Utilities")]
        var apps: [URL] = []
        for root in roots {
            guard let children = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for child in children where child.pathExtension.lowercased() == "app" { apps.append(child) }
            for child in children where child.pathExtension.isEmpty {
                if let nested = try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil) {
                    apps.append(contentsOf: nested.filter { $0.pathExtension.lowercased() == "app" })
                }
            }
        }
        var ids = Set<String>(), names = Set<String>()
        for app in Set(apps) {
            let plist = app.appendingPathComponent("Contents/Info.plist")
            guard let data = try? Data(contentsOf: plist),
                  let dictionary = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let id = dictionary["CFBundleIdentifier"] as? String else { continue }
            ids.insert(id.lowercased())
            names.insert(app.deletingPathExtension().lastPathComponent.lowercased())
        }
        return InstalledAppCensus(bundleIDs: ids, names: names)
    }
}
