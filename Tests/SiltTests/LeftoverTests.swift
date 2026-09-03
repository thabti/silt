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

/// Regression tests for the Group Containers bypass: `group.com.apple.mail` and friends
/// were classified as removable orphans, putting Mail, Notes, Calendar, Contacts and
/// iCloud Drive data one click from the Trash.
final class AppleIdentifierTests: XCTestCase {

    func testAppleIdentifiersAreRecognisedInEveryWrapping() {
        let apple = [
            "com.apple.mail",
            "group.com.apple.mail",
            "groups.com.apple.podcasts",
            "UBF8T346G9.group.com.apple.notes",
            "243LU875E5.groups.com.apple.podcasts",
            "group.com.apple.CloudDocs",
        ]
        for id in apple {
            XCTAssertTrue(SafetyGuard.isAppleIdentifier(id), "\(id) must be recognised as Apple's")
        }
    }

    func testNonAppleIdentifiersStillPass() {
        let others = [
            "com.spotify.client",
            "group.com.google.drivefs",
            "EQHXZ8M8AV.group.com.google.drivefs",
            "com.applepie.notreally",   // "apple" only as part of a longer label
            "org.mozilla.firefox",
        ]
        for id in others {
            XCTAssertFalse(SafetyGuard.isAppleIdentifier(id), "\(id) must not be treated as Apple's")
        }
    }

    func testGuardBlocksAppleGroupContainers() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent("Library/Group Containers/group.com.apple.mail")
        let verdict = SafetyGuard.verdictForAppLeftover(url, matchedOrphanID: "group.com.apple.mail")
        XCTAssertFalse(verdict.isAllowed, "Apple group containers must never be removable")
    }

    func testNormalisationStripsTeamAndGroupWrappers() {
        XCTAssertEqual(SafetyGuard.normalizedLeftoverIdentifier("UBF8T346G9.group.com.microsoft.office"),
                       "com.microsoft.office")
        XCTAssertEqual(SafetyGuard.normalizedLeftoverIdentifier("groups.com.vendor.app"), "com.vendor.app")
        XCTAssertEqual(SafetyGuard.normalizedLeftoverIdentifier("com.vendor.app"), "com.vendor.app")
    }
}
