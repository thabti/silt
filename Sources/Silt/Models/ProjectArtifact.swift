import Foundation

struct ProjectArtifact: Identifiable, Hashable, Sendable {
    let url: URL
    let projectName: String
    let projectPath: URL
    let pattern: ArtifactPattern
    let bytes: Int64
    let lastTouched: Date?

    var id: String { url.standardizedFileURL.path }
    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

struct ArtifactScanProgress: Equatable {
    var visited: Int
    var found: Int
    var currentFolder: String
}
