import Foundation

/// Finds marker-validated dependency/build directories without entering them.
enum ArtifactScanner {
    private static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
    private static let keyList = Array(keys)
    private static var concurrency: Int { max(4, min(10, ProcessInfo.processInfo.activeProcessorCount)) }

    static func scan(
        onProgress: @escaping @Sendable (Int, Int, String) -> Void,
        onFound: @escaping @Sendable (ProjectArtifact) -> Void
    ) async -> [ProjectArtifact] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        guard let top = try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: keyList) else { return [] }

        let roots = top.filter { url in
            guard url.lastPathComponent != "Library",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isDirectory == true, values.isSymbolicLink != true else { return false }
            return true
        }

        return await withTaskGroup(of: [ProjectArtifact].self) { group in
            var results: [ProjectArtifact] = []
            var next = 0
            func submit(_ index: Int) {
                let root = roots[index]
                group.addTask { walk(root, onProgress: onProgress, onFound: onFound) }
            }
            while next < min(concurrency, roots.count) { submit(next); next += 1 }
            while let batch = await group.next() {
                results.append(contentsOf: batch)
                if next < roots.count, !Task.isCancelled { submit(next); next += 1 }
            }
            return results.sorted { $0.bytes > $1.bytes }
        }
    }

    private static func walk(
        _ root: URL,
        onProgress: @escaping @Sendable (Int, Int, String) -> Void,
        onFound: @escaping @Sendable (ProjectArtifact) -> Void
    ) -> [ProjectArtifact] {
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keyList, options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var results: [ProjectArtifact] = []
        var visited = 0
        var found = 0
        while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited >= 400 {
                if Task.isCancelled { break }
                onProgress(visited, found, root.lastPathComponent)
                visited = 0; found = 0
            }
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values.isDirectory == true else { continue }
            guard let pattern = ArtifactPattern.matching(url) else { continue }

            enumerator.skipDescendants()
            if Task.isCancelled { break }
            let project = url.deletingLastPathComponent()
            let artifact = ProjectArtifact(
                url: url, projectName: project.lastPathComponent, projectPath: project,
                pattern: pattern, bytes: Scanner.size(of: url).bytes,
                lastTouched: projectLastTouched(project, excluding: url)
            )
            results.append(artifact); found += 1; onFound(artifact)
        }
        onProgress(visited, found, root.lastPathComponent)
        return results
    }

    private static func projectLastTouched(_ project: URL, excluding artifact: URL) -> Date? {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: project, includingPropertiesForKeys: [.contentModificationDateKey], options: []
        ) else { return nil }
        return children.lazy
            .filter { $0.standardizedFileURL != artifact.standardizedFileURL }
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max()
    }
}
