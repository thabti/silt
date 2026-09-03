import Foundation

enum DeletionMode: String, CaseIterable, Identifiable {
    case trash
    case permanent

    var id: String { rawValue }
    var title: String { self == .trash ? "Move to Trash" : "Delete now" }
    var shortTitle: String { self == .trash ? "Trash" : "Delete" }
    var explanation: String {
        self == .trash
            ? "Recoverable — everything lands in the Trash until you empty it."
            : "Not recoverable. Frees the space immediately."
    }
}

struct CleanOutcome: Identifiable {
    let targetID: String
    let name: String
    var bytesFreed: Int64
    var itemsRemoved: Int
    var failures: [String]
    var id: String { targetID }
}

struct CleanReport {
    var outcomes: [CleanOutcome] = []
    var blocked: [String] = []

    var bytesFreed: Int64 { outcomes.reduce(0) { $0 + $1.bytesFreed } }
    var itemsRemoved: Int { outcomes.reduce(0) { $0 + $1.itemsRemoved } }
    var failureCount: Int { outcomes.reduce(0) { $0 + $1.failures.count } }
}

struct CleanProgress: Equatable {
    var completed: Int
    var total: Int
    var currentName: String
    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
}

/// Removes what is *inside* a bucket and leaves the bucket folder itself alone,
/// because apps expect their own cache folder to exist.
///
/// Three independent gates stand in front of every delete:
///   1. the item came from `Catalog` (the caller can only pass `ScannedTarget`s),
///   2. the bucket is not marked `.review`,
///   3. `SafetyGuard` approves the exact path.
enum Cleaner {

    static func clean(
        _ scanned: [ScannedTarget],
        mode: DeletionMode,
        onProgress: @escaping (CleanProgress) -> Void
    ) async -> CleanReport {

        var report = CleanReport()
        let catalogIDs = Set(Catalog.all.map(\.id))
        let total = scanned.count

        for (index, bucket) in scanned.enumerated() {
            // Without this, a cancelled run still appended an empty outcome per remaining
            // bucket, which the report then presented as a cleaned location.
            if Task.isCancelled { break }
            let target = bucket.target
            onProgress(CleanProgress(completed: index, total: total, currentName: target.name))

            guard catalogIDs.contains(target.id) else {
                report.blocked.append("\(target.name): not a known location")
                continue
            }
            guard target.kind.isDeletable else {
                report.blocked.append("\(target.name): review-only, left untouched")
                continue
            }
            guard SafetyGuard.verdictForBucketRoot(target.path).isAllowed else {
                report.blocked.append("\(target.name): \(SafetyGuard.verdictForBucketRoot(target.path).reason ?? "blocked")")
                continue
            }

            // The Trash cannot be moved to the Trash.
            let effectiveMode: DeletionMode = target.id == Catalog.trashID ? .permanent : mode
            var outcome = CleanOutcome(targetID: target.id, name: target.name, bytesFreed: 0, itemsRemoved: 0, failures: [])

            for child in bucket.children {
                if Task.isCancelled { break }

                let verdict = SafetyGuard.verdict(for: child.url)
                guard verdict.isAllowed else {
                    report.blocked.append("\(child.name): \(verdict.reason ?? "blocked")")
                    continue
                }
                guard FileManager.default.fileExists(atPath: child.url.path) else { continue }

                do {
                    switch effectiveMode {
                    case .trash:
                        try FileManager.default.trashItem(at: child.url, resultingItemURL: nil)
                    case .permanent:
                        try FileManager.default.removeItem(at: child.url)
                    }
                    outcome.bytesFreed += child.bytes
                    outcome.itemsRemoved += 1
                } catch {
                    outcome.failures.append("\(child.name): \(error.localizedDescription)")
                }
            }

            report.outcomes.append(outcome)
            onProgress(CleanProgress(completed: index + 1, total: total, currentName: target.name))
        }

        return report
    }
}
