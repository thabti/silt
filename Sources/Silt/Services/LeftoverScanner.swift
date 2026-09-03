import Foundation

enum LeftoverScanner {
    struct Location: Sendable { let relative: String; let mode: Mode; enum Mode: Sendable { case id, idOrName, group } }
    static let locations = [
        Location(relative: "Library/Application Support", mode: .idOrName), Location(relative: "Library/Caches", mode: .id),
        Location(relative: "Library/Preferences", mode: .id), Location(relative: "Library/Containers", mode: .id),
        Location(relative: "Library/Group Containers", mode: .group), Location(relative: "Library/Saved Application State", mode: .id),
        Location(relative: "Library/HTTPStorages", mode: .id), Location(relative: "Library/WebKit", mode: .id),
        Location(relative: "Library/Logs", mode: .idOrName), Location(relative: "Library/LaunchAgents", mode: .id),
        Location(relative: "Library/Application Scripts", mode: .id)
    ]
    static let internalNames: Set<String> = ["apple", "coreservices", "system", "shared", "diagnosticreports"]

    static func isReverseDNS(_ value: String) -> Bool {
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 3, !value.contains(" "), (2...6).contains(labels[0].count) else { return false }
        return labels[0].allSatisfy { $0.isLetter || $0.isNumber }
    }
    static func owns(_ candidate: String, _ installed: String) -> Bool {
        let a = candidate.lowercased(), b = installed.lowercased()
        return a == b || a.hasPrefix(b + ".") || b.hasPrefix(a + ".")
    }
    static func strippingTeamID(_ value: String) -> String {
        let parts = value.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2, parts[0].count == 10, parts[0].allSatisfy({ $0.isLetter || $0.isNumber }) else { return value }
        return parts[1]
    }
    static func classify(_ raw: String, mode: Location.Mode, census: InstalledAppCensus) -> (String, LeftoverConfidence)? {
        var key = raw.lowercased()
        if key.hasSuffix(".savedstate") { key.removeLast(11) }
        if key.hasSuffix(".plist") { key.removeLast(6) }
        if mode == .group { key = SafetyGuard.normalizedLeftoverIdentifier(key) }
        // Test the raw name too: `group.com.apple.mail` survives team-ID stripping and
        // does not start with "com.apple.".
        guard !SafetyGuard.isAppleIdentifier(raw), !SafetyGuard.isAppleIdentifier(key),
              !internalNames.contains(key) else { return nil }
        if isReverseDNS(key) {
            return census.bundleIDs.contains(where: { owns(key, $0) }) ? nil : (key, .high)
        }
        guard mode == .idOrName,
              !census.names.contains(key),
              !census.bundleIDs.contains(where: { $0.split(separator: ".").last.map(String.init) == key }) else { return nil }
        return (key, .low)
    }

    static func scan(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                     onProgress: @escaping @Sendable (Int, Int, String) -> Void,
                     onFound: @escaping @Sendable (AppLeftoverGroup) -> Void) async -> [AppLeftoverGroup] {
        let census = InstalledApps.census(homeDirectory: homeDirectory), fm = FileManager.default
        var items: [AppLeftoverItem] = []; var checked = 0
        for location in locations {
            if Task.isCancelled { break }
            let root = homeDirectory.appendingPathComponent(location.relative)
            let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
            for entry in entries {
                checked += 1
                if let (id, confidence) = classify(entry.lastPathComponent, mode: location.mode, census: census) {
                    items.append(AppLeftoverItem(url: entry, matchedID: id, location: location.relative.replacingOccurrences(of: "Library/", with: ""), bytes: Scanner.size(of: entry).bytes, confidence: confidence))
                }
            }
            onProgress(checked, items.count, location.relative)
        }
        let families = items.sorted { $0.matchedID.count < $1.matchedID.count }
        var grouped: [String: [AppLeftoverItem]] = [:]
        for item in families {
            let root = grouped.keys.filter { owns(item.matchedID, $0) }.max(by: { $0.count < $1.count }) ?? item.matchedID
            grouped[root, default: []].append(item)
        }
        let results = grouped.map { id, children in
            let labels = id.split(separator: "."); let label = labels.count > 1 ? labels[labels.count - 2] : labels[0]
            return AppLeftoverGroup(id: id, name: String(label).capitalized,
                                    confidence: children.contains(where: { $0.confidence == .low }) ? .low : .high, items: children)
        }.sorted { $0.bytes > $1.bytes }
        results.forEach(onFound); return results
    }

    static func items(forBundleID bundleID: String, appName: String,
                      homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [AppLeftoverItem] {
        let fm = FileManager.default, id = bundleID.lowercased()
        return locations.flatMap { location -> [AppLeftoverItem] in
            let root = homeDirectory.appendingPathComponent(location.relative)
            let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey])) ?? []
            return entries.compactMap { entry in
                var key = entry.lastPathComponent.lowercased()
                if key.hasSuffix(".savedstate") { key.removeLast(11) }
                if key.hasSuffix(".plist") { key.removeLast(6) }
                if location.mode == .group { key = strippingTeamID(key) }
                guard key == id || key.hasPrefix(id + ".") else { return nil }
                return AppLeftoverItem(url: entry, matchedID: bundleID,
                    location: location.relative.replacingOccurrences(of: "Library/", with: ""),
                    bytes: Scanner.size(of: entry).bytes, confidence: .high)
            }
        }
    }
}
