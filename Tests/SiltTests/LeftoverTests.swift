import XCTest

final class LeftoverTests: XCTestCase {
    func testAssociatedFilesMatchOnlyBundleIDFamily() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = home.appendingPathComponent("Library/Application Support")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("com.example.code.helper"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Code"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let items = LeftoverScanner.items(forBundleID: "com.example.code", appName: "Code", homeDirectory: home)
        XCTAssertEqual(items.map { $0.url.lastPathComponent }, ["com.example.code.helper"])
    }
    func testMatchingLogic() {
        XCTAssertTrue(LeftoverScanner.isReverseDNS("com.example.app"))
        XCTAssertFalse(LeftoverScanner.isReverseDNS("Sublime Text"))
        XCTAssertTrue(LeftoverScanner.owns("com.spotify.client.helper", "com.spotify.client"))
        XCTAssertEqual(LeftoverScanner.strippingTeamID("ABC123DE45.com.example.app"), "com.example.app")
        let census = InstalledAppCensus(bundleIDs: [], names: [])
        XCTAssertEqual(LeftoverScanner.classify("Sublime Text", mode: .idOrName, census: census)?.1, .low)
    }

    func testLeftoverGuardShape() throws {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = home.appendingPathComponent("Library/Application Support")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: home) }
        let valid = root.appendingPathComponent("com.example.orphan")
        try fm.createDirectory(at: valid, withIntermediateDirectories: false)
        XCTAssertTrue(SafetyGuard.verdictForAppLeftover(valid, matchedOrphanID: "com.example.orphan", homeDirectory: home, verifyInstalled: false).isAllowed)
        XCTAssertFalse(SafetyGuard.verdictForAppLeftover(valid, matchedOrphanID: "com.apple.test", homeDirectory: home, verifyInstalled: false).isAllowed)
        let nested = valid.appendingPathComponent("child"); try fm.createDirectory(at: nested, withIntermediateDirectories: false)
        XCTAssertFalse(SafetyGuard.verdictForAppLeftover(nested, matchedOrphanID: "com.example.orphan", homeDirectory: home, verifyInstalled: false).isAllowed)
        XCTAssertFalse(SafetyGuard.verdictForAppLeftover(valid, matchedOrphanID: "com.other.app", homeDirectory: home, verifyInstalled: false).isAllowed)
        let link = root.appendingPathComponent("com.example.link"); try fm.createSymbolicLink(at: link, withDestinationURL: valid)
        XCTAssertFalse(SafetyGuard.verdictForAppLeftover(link, matchedOrphanID: "com.example.link", homeDirectory: home, verifyInstalled: false).isAllowed)
    }

    func testInstalledAppIsBlocked() {
        let safari = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/com.apple.Safari")
        XCTAssertFalse(SafetyGuard.verdictForAppLeftover(safari, matchedOrphanID: "com.apple.Safari").isAllowed)
    }
}
