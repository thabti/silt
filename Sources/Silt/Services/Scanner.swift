import Foundation

struct ScanProgress: Equatable {
    var completed: Int
    var total: Int
    var currentName: String

    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
}

/// Measures how big each catalog bucket is. Read-only: the scanner never writes or deletes.
///
/// Work is flattened before it runs. Every bucket's direct children become one flat list of
/// jobs, and that list is fed through a single task group — so a 12 GB DerivedData folder and
/// 40 empty caches share all cores instead of one giant bucket blocking a worker while the
/// rest sit idle. Buckets are handed back the moment their own children are all measured,
/// which lets the UI fill in progressively instead of waiting for the slowest one.
enum Scanner {

    /// Metadata we ask the file system for. Built once — `Set(...)` per file was showing up
    /// in traces on trees with hundreds of thousands of entries.
    /// Deliberately minimal: every extra key is fetched for every file in the tree, and
    /// dropping the two fallbacks measured 1–11% faster on trees of 100k+ files.
    private static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey,
    ]
    private static let resourceKeyList = Array(resourceKeys)

    /// I/O-bound, so a little above the core count. Clamped so a laptop stays responsive.
    private static var concurrency: Int {
        max(4, min(12, ProcessInfo.processInfo.activeProcessorCount + 2))
    }

    private struct Job {
        let bucket: Int
        let url: URL
    }

    private struct ChildResult {
        let bucket: Int
        let entry: ChildEntry
        let files: Int
        let unreadable: Bool
    }

    /// Measures `targets`, calling `onBucket` once per bucket as soon as it is finished.
    static func stream(
        targets: [CleanTarget],
        onBucket: @escaping (ScannedTarget) -> Void
    ) async {
        guard !targets.isEmpty else { return }

        let fm = FileManager.default

        // Phase 1 — shallow listing. One directory read per bucket, so this is quick.
        var jobs: [Job] = []
        var remaining = [Int](repeating: 0, count: targets.count)
        var unreadable = [Bool](repeating: false, count: targets.count)
        var children: [[ChildEntry]] = Array(repeating: [], count: targets.count)
        var fileCounts = [Int](repeating: 0, count: targets.count)

        for (index, target) in targets.enumerated() {
            let listing = try? fm.contentsOfDirectory(
                at: target.path,
                includingPropertiesForKeys: nil,
                options: []
            )
            let entries = listing ?? []
            if entries.isEmpty {
                unreadable[index] = listing == nil || !fm.isReadableFile(atPath: target.path.path)
                onBucket(ScannedTarget(
                    target: target, bytes: 0, fileCount: 0, children: [], unreadable: unreadable[index]
                ))
                continue
            }
            remaining[index] = entries.count
            for child in entries {
                jobs.append(Job(bucket: index, url: child))
            }
        }

        guard !jobs.isEmpty else { return }

        // Phase 2 — one flat, load-balanced pass over every child of every bucket.
        await withTaskGroup(of: ChildResult?.self) { group in
            var next = 0

            func submit(_ index: Int) {
                let job = jobs[index]
                group.addTask {
                    if Task.isCancelled { return nil }
                    let measured = size(of: job.url)
                    return ChildResult(
                        bucket: job.bucket,
                        entry: ChildEntry(url: job.url, bytes: measured.bytes),
                        files: measured.files,
                        unreadable: measured.unreadable
                    )
                }
            }

            let initial = min(concurrency, jobs.count)
            while next < initial {
                submit(next)
                next += 1
            }

            while let result = await group.next() {
                if next < jobs.count, !Task.isCancelled {
                    submit(next)
                    next += 1
                }

                guard let result else { continue }
                let bucket = result.bucket

                children[bucket].append(result.entry)
                fileCounts[bucket] += result.files
                unreadable[bucket] = unreadable[bucket] || result.unreadable
                remaining[bucket] -= 1

                // Bucket finished — hand it over immediately.
                if remaining[bucket] == 0 {
                    var finished = children[bucket]
                    finished.sort { $0.bytes > $1.bytes }
                    onBucket(ScannedTarget(
                        target: targets[bucket],
                        bytes: finished.reduce(0) { $0 + $1.bytes },
                        fileCount: fileCounts[bucket],
                        children: finished,
                        unreadable: unreadable[bucket]
                    ))
                    children[bucket] = []   // release the memory as we go
                }
            }
        }
    }

    /// Disk usage of one file or folder, following no symlinks.
    static func size(of url: URL) -> (bytes: Int64, files: Int, unreadable: Bool) {
        guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
            return (0, 0, true)
        }
        if values.isSymbolicLink == true { return (0, 1, false) }
        if values.isRegularFile == true { return (allocated(values), 1, false) }

        var bytes: Int64 = 0
        var files = 0
        var unreadable = false

        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeyList,
            options: [],
            errorHandler: { _, _ in
                unreadable = true
                return true   // one unreadable folder should not stop the scan
            }
        )

        var sinceCancelCheck = 0
        while let entry = enumerator?.nextObject() as? URL {
            // Checking cancellation is cheap but not free; every 512 entries is plenty.
            sinceCancelCheck += 1
            if sinceCancelCheck >= 512 {
                sinceCancelCheck = 0
                if Task.isCancelled { break }
            }
            guard let entryValues = try? entry.resourceValues(forKeys: resourceKeys) else {
                unreadable = true
                continue
            }
            guard entryValues.isSymbolicLink != true, entryValues.isRegularFile == true else { continue }
            bytes += allocated(entryValues)
            files += 1
        }

        return (bytes, files, unreadable)
    }

    private static func allocated(_ values: URLResourceValues) -> Int64 {
        Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }

    /// Buckets a normal scan measures. Review-only locations are excluded because they are
    /// both huge and irrelevant to what can be reclaimed: profiling this Mac showed the
    /// review buckets were 98% of a 96-second scan, and the pnpm store alone — 26 GB of
    /// hard-linked files — was 80 seconds of it. Without them the same scan takes ~1s.
    static func quickTargets(_ targets: [CleanTarget]) -> [CleanTarget] {
        targets.filter { $0.kind != .review }
    }

    static func reviewTargets(_ targets: [CleanTarget]) -> [CleanTarget] {
        targets.filter { $0.kind == .review }
    }
}
