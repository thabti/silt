import Foundation

struct FileScanProgress: Equatable {
    var visited: Int
    var found: Int
    var currentFolder: String
}

/// Finds the biggest things in your home folder. Read-only.
///
/// Bundles (`.app`, `.photoslibrary`, `.xcarchive`, …) are measured as one item rather than
/// thousands of parts, which is both faster and how you actually think about them.
///
/// The walk is split by top-level folder and run concurrently — one worker per subtree — so
/// `~/Library` and `~/Documents` are traversed at the same time instead of one after the other.
enum FileScanner {

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey,
        .isExecutableKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .fileSizeKey, .contentModificationDateKey,
    ]
    private static let resourceKeyList = Array(resourceKeys)

    /// Keeps one runaway subtree from eating all the memory.
    private static let perSubtreeCap = 2_000

    private static var concurrency: Int {
        max(4, min(10, ProcessInfo.processInfo.activeProcessorCount))
    }

    /// iCloud Drive and other cloud providers keep placeholder files that would be
    /// downloaded just by being measured. Never walk into them.
    private static var skippedFolders: Set<String> {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Set([
            "Library/Mobile Documents",
            "Library/CloudStorage",
            "Library/Application Support/FileProvider",
        ].map { home.appendingPathComponent($0).standardizedFileURL.path })
    }

    /// `onProgress` receives *deltas*, because it is called from several workers at once —
    /// the caller adds them up on the main actor, where that is safe.
    static func scan(
        minimumBytes: Int64,
        limit: Int,
        onProgress: @escaping @Sendable (_ visitedDelta: Int, _ foundDelta: Int, _ folder: String) -> Void
    ) async -> [FileEntry] {

        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let skip = skippedFolders

        guard let top = try? fm.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: resourceKeyList,
            options: []
        ) else { return [] }

        var results: [FileEntry] = []
        var subtrees: [URL] = []

        // Top level first: files and bundles land straight in the result, folders get a worker.
        for url in top {
            guard let values = try? url.resourceValues(forKeys: resourceKeys) else { continue }
            if values.isSymbolicLink == true { continue }

            let path = url.standardizedFileURL.path
            if skip.contains(path) { continue }

            let isPackage = values.isPackage == true
            if values.isDirectory == true, !isPackage {
                subtrees.append(url)
                continue
            }
            if let entry = entry(for: url, values: values, isPackage: isPackage, minimumBytes: minimumBytes) {
                results.append(entry)
            }
        }

        await withTaskGroup(of: [FileEntry].self) { group in
            var next = 0

            func submit(_ index: Int) {
                let root = subtrees[index]
                group.addTask {
                    if Task.isCancelled { return [] }
                    return walk(root, minimumBytes: minimumBytes, skip: skip, onProgress: onProgress)
                }
            }

            let initial = min(concurrency, subtrees.count)
            while next < initial {
                submit(next)
                next += 1
            }

            while let found = await group.next() {
                if next < subtrees.count, !Task.isCancelled {
                    submit(next)
                    next += 1
                }
                results.append(contentsOf: found)
            }
        }

        return Array(results.sorted { $0.bytes > $1.bytes }.prefix(limit))
    }

    // MARK: - One subtree

    private static func walk(
        _ root: URL,
        minimumBytes: Int64,
        skip: Set<String>,
        onProgress: @escaping @Sendable (Int, Int, String) -> Void
    ) -> [FileEntry] {

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeyList,
            options: [.skipsPackageDescendants],   // a bundle arrives as one item
            errorHandler: { _, _ in true }
        ) else { return [] }

        var found: [FileEntry] = []
        var visitedSinceReport = 0
        var foundSinceReport = 0

        while let url = enumerator.nextObject() as? URL {
            visitedSinceReport += 1
            if visitedSinceReport >= 500 {
                if Task.isCancelled { break }
                onProgress(visitedSinceReport, foundSinceReport, root.lastPathComponent)
                visitedSinceReport = 0
                foundSinceReport = 0
            }

            guard let values = try? url.resourceValues(forKeys: resourceKeys) else { continue }
            if values.isSymbolicLink == true { continue }

            let path = url.standardizedFileURL.path
            if skip.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                enumerator.skipDescendants()
                continue
            }

            let isPackage = values.isPackage == true
            if values.isDirectory == true, !isPackage { continue }

            if let entry = entry(for: url, values: values, isPackage: isPackage, minimumBytes: minimumBytes) {
                found.append(entry)
                foundSinceReport += 1
                if found.count >= perSubtreeCap { break }
            }
        }

        onProgress(visitedSinceReport, foundSinceReport, root.lastPathComponent)
        return found
    }

    private static func entry(
        for url: URL,
        values: URLResourceValues,
        isPackage: Bool,
        minimumBytes: Int64
    ) -> FileEntry? {

        let bytes: Int64
        if isPackage {
            bytes = Scanner.size(of: url).bytes
        } else if values.isRegularFile == true {
            bytes = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        } else {
            return nil
        }

        guard bytes >= minimumBytes else { return nil }

        return FileEntry(
            url: url,
            bytes: bytes,
            modified: values.contentModificationDate,
            kind: FileKind.classify(url, isPackage: isPackage, isExecutable: values.isExecutable == true),
            isBundle: isPackage
        )
    }
}
