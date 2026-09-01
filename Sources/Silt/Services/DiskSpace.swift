import Foundation

struct DiskSnapshot: Equatable {
    var volumeName: String
    var total: Int64
    var free: Int64

    var used: Int64 { max(0, total - free) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static let empty = DiskSnapshot(volumeName: "Macintosh HD", total: 0, free: 0)
}

enum DiskSpace {
    /// Free space as macOS reports it to apps — the same number the Storage pane shows,
    /// which already accounts for purgeable content.
    static func snapshot() -> DiskSnapshot {
        let url = FileManager.default.homeDirectoryForCurrentUser
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey,
        ]

        guard let values = try? url.resourceValues(forKeys: keys) else { return .empty }

        let total = Int64(values.volumeTotalCapacity ?? 0)
        let free = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)

        return DiskSnapshot(
            volumeName: values.volumeName ?? "Macintosh HD",
            total: total,
            free: free
        )
    }
}
