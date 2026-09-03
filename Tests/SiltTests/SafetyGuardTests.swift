import XCTest

final class SafetyGuardTests: XCTestCase {
    func testApplicationBundleGuard() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let home = root.appendingPathComponent("Home")
        let apps = home.appendingPathComponent("Applications")
        let valid = apps.appendingPathComponent("Foo.app")
        try FileManager.default.createDirectory(at: valid, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(SafetyGuard.verdictForApplicationBundle(valid, bundleID: "com.example.foo", homeDirectory: home).isAllowed)
        XCTAssertFalse(SafetyGuard.verdictForApplicationBundle(URL(fileURLWithPath: "/System/Applications/Safari.app"), bundleID: "com.example.safari", homeDirectory: home).isAllowed)
        XCTAssertFalse(SafetyGuard.verdictForApplicationBundle(valid, bundleID: "com.apple.foo", homeDirectory: home).isAllowed)
        if let ownID = Bundle.main.bundleIdentifier {
            XCTAssertFalse(SafetyGuard.verdictForApplicationBundle(valid, bundleID: ownID, homeDirectory: home).isAllowed)
        }
        XCTAssertFalse(SafetyGuard.verdictForApplicationBundle(apps.appendingPathComponent("Foo"), bundleID: "com.example.foo", homeDirectory: home).isAllowed)
        let deep = apps.appendingPathComponent("One/Two/Foo.app")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        XCTAssertFalse(SafetyGuard.verdictForApplicationBundle(deep, bundleID: "com.example.foo", homeDirectory: home).isAllowed)
        let link = apps.appendingPathComponent("Link.app")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: valid)
        XCTAssertFalse(SafetyGuard.verdictForApplicationBundle(link, bundleID: "com.example.foo", homeDirectory: home).isAllowed)
    }

    private let home = FileManager.default.homeDirectoryForCurrentUser

    override func setUp() {
        super.setUp()
        SafetyGuard.protectedLocationsEnabled = true
    }

    override func tearDown() {
        SafetyGuard.protectedLocationsEnabled = true
        super.tearDown()
    }

    private func url(_ relative: String) -> URL {
        home.appendingPathComponent(relative)
    }

    // MARK: - Things that must never be deletable

    func testBlocksHomeItself() {
        XCTAssertFalse(SafetyGuard.verdict(for: home).isAllowed)
    }

    func testBlocksTopLevelFolders() {
        for name in ["Library", "Documents", "Desktop", "Downloads", ".cache", ".npm"] {
            XCTAssertFalse(SafetyGuard.verdict(for: url(name)).isAllowed, "\(name) must not be deletable")
        }
    }

    func testBlocksPersonalData() {
        let cases = [
            "Documents/taxes/2025.pdf",
            "Desktop/screenshot.png",
            "Downloads/installer.dmg",
            "Pictures/Photos Library.photoslibrary",
            "Movies/wedding.mov",
            "Music/library.musiclibrary",
            ".ssh/id_ed25519",
            ".gnupg/pubring.kbx",
            ".aws/credentials",
            ".config/gh/hosts.yml",
            "Library/Keychains/login.keychain-db",
            "Library/Mobile Documents/com~apple~CloudDocs/notes.txt",
            "Library/Containers/com.docker.docker/Data/vms",
            "Library/Application Support/MobileSync/Backup/abc",
            "Library/pnpm/store/v3",
            "go/pkg/mod/github.com",
            "Library/Developer/Xcode/Archives/2026-01-01",
            "Library/Developer/CoreSimulator/Devices/ABC",
        ]
        for path in cases {
            XCTAssertFalse(SafetyGuard.verdict(for: url(path)).isAllowed, "\(path) must be protected")
        }
    }

    func testDisablingProtectionAllowsPersonalPathsButKeepsStructuralRules() {
        SafetyGuard.protectedLocationsEnabled = false

        XCTAssertTrue(SafetyGuard.verdict(for: url("Documents/taxes/2025.pdf")).isAllowed)
        XCTAssertTrue(SafetyGuard.verdictForUserFile(url(".ssh/id_ed25519"), isBundle: false).isAllowed)
        XCTAssertFalse(SafetyGuard.verdict(for: URL(fileURLWithPath: "/etc/passwd")).isAllowed)
        XCTAssertFalse(SafetyGuard.verdict(for: url("Documents")).isAllowed)
        XCTAssertFalse(SafetyGuard.verdictForUserFile(url("Pictures/Photos Library.photoslibrary"), isBundle: true).isAllowed)
    }

    func testBlocksOutsideHome() {
        for path in ["/", "/System/Library", "/usr/bin", "/Applications/Safari.app", "/opt/homebrew/Cellar", "/etc/passwd"] {
            XCTAssertFalse(SafetyGuard.verdict(for: URL(fileURLWithPath: path)).isAllowed, "\(path) must be blocked")
        }
    }

    func testBlocksPathTraversal() {
        let sneaky = url("Library/Caches/../../Documents/secret.txt")
        XCTAssertFalse(SafetyGuard.verdict(for: sneaky).isAllowed)
    }

    // MARK: - Things that should be deletable

    func testAllowsCacheContents() {
        let cases = [
            "Library/Caches/Google/Chrome/Default/Cache",
            "Library/Caches/pip/wheels",
            "Library/Logs/DiagnosticReports/report.crash",
            "Library/Developer/Xcode/DerivedData/MyApp-abc123",
            ".cache/uv/wheels",
            ".npm/_cacache/index-v5",
            ".gradle/caches/modules-2",
            ".Trash/old-file.zip",
        ]
        for path in cases {
            XCTAssertTrue(SafetyGuard.verdict(for: url(path)).isAllowed, "\(path) should be cleanable")
        }
    }

    func testBucketRootRuleAllowsTrashButNotHome() {
        XCTAssertTrue(SafetyGuard.verdictForBucketRoot(url(".Trash")).isAllowed)
        XCTAssertFalse(SafetyGuard.verdictForBucketRoot(home).isAllowed)
        XCTAssertFalse(SafetyGuard.verdictForBucketRoot(url("Documents")).isAllowed)
    }

    // MARK: - Catalog integrity

    func testEveryDeletableCatalogEntryPassesTheGuard() {
        for target in Catalog.all where target.kind.isDeletable {
            XCTAssertTrue(
                SafetyGuard.verdictForBucketRoot(target.path).isAllowed,
                "\(target.id) at \(target.path.path) is marked deletable but the guard rejects it"
            )
        }
    }

    func testDeletableCatalogChildrenPassTheGuard() {
        // A bucket is cleaned by removing its direct children, so a representative
        // child of every deletable bucket has to survive the full rule set.
        for target in Catalog.all where target.kind.isDeletable {
            let child = target.path.appendingPathComponent("sample-item")
            XCTAssertTrue(
                SafetyGuard.verdict(for: child).isAllowed,
                "\(target.id): child \(child.path) would be blocked, so this bucket could never be cleaned"
            )
        }
    }

    func testReviewEntriesAreNeverDeletable() {
        for target in Catalog.all where target.category == .review {
            XCTAssertEqual(target.kind, .review, "\(target.id) is in Review but not marked review-only")
            XCTAssertFalse(target.kind.isDeletable)
        }
    }

    func testCatalogIDsAreUnique() {
        let ids = Catalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "duplicate catalog ids")
    }

    // MARK: - Hand-picked files (Files list)

    func testUserFileRulesAllowYourOwnBigFiles() {
        let cases = [
            "Downloads/ubuntu.iso",
            "Documents/wedding-master.mov",
            "Movies/export.mp4",
            "Desktop/archive.zip",
            "Library/Caches/some-tool/blob.bin",
        ]
        for path in cases {
            XCTAssertTrue(
                SafetyGuard.verdictForUserFile(url(path), isBundle: false).isAllowed,
                "\(path) should be trashable from the Files list"
            )
        }
    }

    func testUserFileRulesBlockCredentialsAndCloud() {
        let cases = [
            "Library/Keychains/login.keychain-db",
            "Library/Preferences/com.apple.finder.plist",
            "Library/Mobile Documents/com~apple~CloudDocs/report.pdf",
            "Library/CloudStorage/GoogleDrive/file.pdf",
            ".ssh/id_ed25519",
            ".gnupg/pubring.kbx",
            ".aws/credentials",
            ".config/gh/hosts.yml",
            ".kube/config",
        ]
        for path in cases {
            XCTAssertFalse(
                SafetyGuard.verdictForUserFile(url(path), isBundle: false).isAllowed,
                "\(path) must never be trashable from the Files list"
            )
        }
    }

    func testUserFileRulesBlockMediaLibrariesAndOutsideHome() {
        XCTAssertFalse(SafetyGuard.verdictForUserFile(url("Pictures/Photos Library.photoslibrary"), isBundle: true).isAllowed)
        XCTAssertFalse(SafetyGuard.verdictForUserFile(url("Music/Music Library.musiclibrary"), isBundle: true).isAllowed)
        XCTAssertFalse(SafetyGuard.verdictForUserFile(URL(fileURLWithPath: "/etc/passwd"), isBundle: false).isAllowed)
        XCTAssertFalse(SafetyGuard.verdictForUserFile(URL(fileURLWithPath: "/Applications/Safari.app"), isBundle: true).isAllowed)
    }

    func testUserFileRulesRefusePlainFolders() {
        // Documents exists, is a directory, and is not a package.
        XCTAssertFalse(SafetyGuard.verdictForUserFile(url("Documents"), isBundle: false).isAllowed)
    }

    // MARK: - Project artifacts

    private func withTemporaryHomeProject(_ body: (URL, URL) throws -> Void) throws {
        let fakeHome = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".silt-artifact-test-\(UUID().uuidString)")
        let project = fakeHome.appendingPathComponent("Projects/example")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fakeHome) }
        try body(fakeHome, project)
    }

    func testArtifactRulesAllowMarkerValidatedNodeModules() throws {
        try withTemporaryHomeProject { fakeHome, project in
            FileManager.default.createFile(atPath: project.appendingPathComponent("package.json").path, contents: Data())
            let artifact = project.appendingPathComponent("node_modules")
            try FileManager.default.createDirectory(at: artifact, withIntermediateDirectories: false)
            XCTAssertTrue(SafetyGuard.verdictForProjectArtifact(artifact, homeDirectory: fakeHome).isAllowed)
        }
    }

    func testArtifactRulesRequireKnownNameAndMarker() throws {
        try withTemporaryHomeProject { fakeHome, project in
            let unmarked = project.appendingPathComponent("node_modules")
            try FileManager.default.createDirectory(at: unmarked, withIntermediateDirectories: false)
            XCTAssertFalse(SafetyGuard.verdictForProjectArtifact(unmarked, homeDirectory: fakeHome).isAllowed)

            FileManager.default.createFile(atPath: project.appendingPathComponent("package.json").path, contents: Data())
            let unknown = project.appendingPathComponent("dependencies")
            try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: false)
            XCTAssertFalse(SafetyGuard.verdictForProjectArtifact(unknown, homeDirectory: fakeHome).isAllowed)
        }
    }

    func testArtifactRulesAllowDocumentsWorkArea() throws {
        let fakeHome = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".silt-artifact-test-\(UUID().uuidString)")
        let project = fakeHome.appendingPathComponent("Documents/work/example")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fakeHome) }
        FileManager.default.createFile(atPath: project.appendingPathComponent("package.json").path, contents: Data())
        let artifact = project.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: artifact, withIntermediateDirectories: false)
        XCTAssertTrue(SafetyGuard.verdictForProjectArtifact(artifact, homeDirectory: fakeHome).isAllowed)
    }

    func testArtifactRulesBlockSensitivePaths() throws {
        for protectedRoot in ["Library/Keychains/projects", ".ssh/projects"] {
            let fakeHome = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(".silt-artifact-test-\(UUID().uuidString)")
            let project = fakeHome.appendingPathComponent(protectedRoot).appendingPathComponent("example")
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: fakeHome) }
            FileManager.default.createFile(atPath: project.appendingPathComponent("package.json").path, contents: Data())
            let artifact = project.appendingPathComponent("node_modules")
            try FileManager.default.createDirectory(at: artifact, withIntermediateDirectories: false)
            XCTAssertFalse(SafetyGuard.verdictForProjectArtifact(artifact, homeDirectory: fakeHome).isAllowed)
        }
    }

    func testArtifactProtectionCanBeDisabledButMarkerRuleRemains() throws {
        SafetyGuard.protectedLocationsEnabled = false
        let fakeHome = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".silt-artifact-test-\(UUID().uuidString)")
        let project = fakeHome.appendingPathComponent(".ssh/projects/example")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fakeHome) }

        let artifact = project.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: artifact, withIntermediateDirectories: false)
        XCTAssertFalse(SafetyGuard.verdictForProjectArtifact(artifact, homeDirectory: fakeHome).isAllowed)

        FileManager.default.createFile(atPath: project.appendingPathComponent("package.json").path, contents: Data())
        XCTAssertTrue(SafetyGuard.verdictForProjectArtifact(artifact, homeDirectory: fakeHome).isAllowed)
    }

    func testArtifactRulesBlockSymlinks() throws {
        try withTemporaryHomeProject { fakeHome, project in
            FileManager.default.createFile(atPath: project.appendingPathComponent("package.json").path, contents: Data())
            let target = project.appendingPathComponent("real")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            let link = project.appendingPathComponent("node_modules")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            XCTAssertFalse(SafetyGuard.verdictForProjectArtifact(link, homeDirectory: fakeHome).isAllowed)
        }
    }

    // MARK: - File classification

    func testFileKindClassification() {
        func kind(_ name: String, package: Bool = false, exec: Bool = false) -> FileKind {
            FileKind.classify(URL(fileURLWithPath: "/tmp/\(name)"), isPackage: package, isExecutable: exec)
        }
        XCTAssertEqual(kind("clip.mov"), .video)
        XCTAssertEqual(kind("song.flac"), .audio)
        XCTAssertEqual(kind("shot.heic"), .image)
        XCTAssertEqual(kind("bundle.zip"), .archive)
        XCTAssertEqual(kind("Ventura.dmg"), .diskImage)
        XCTAssertEqual(kind("libfoo.dylib"), .binary)
        XCTAssertEqual(kind("Xcode.app", package: true), .appPackage)
        XCTAssertEqual(kind("Photos Library.photoslibrary", package: true), .appPackage)
        XCTAssertEqual(kind("model.safetensors"), .appPackage)
        XCTAssertEqual(kind("data.sqlite"), .data)
        XCTAssertEqual(kind("notes.pdf"), .document)
        // No extension but the executable bit set — treated as a binary.
        XCTAssertEqual(kind("some-tool", exec: true), .binary)
        XCTAssertEqual(kind("mystery.qqq"), .other)
    }
}
