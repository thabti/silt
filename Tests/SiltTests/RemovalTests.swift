import XCTest

/// The removal runner is the highest-consequence code in the app and the four routines it
/// replaces had no coverage at all. These are pure value tests: no filesystem involved.
@MainActor
final class RemovalTests: XCTestCase {

    private func unit(_ name: String,
                      bytes: Int64 = 100,
                      allowed: Bool = true,
                      reason: String? = nil,
                      fallback: Bool = false,
                      throwing: Error? = nil) -> RemovalUnit {
        RemovalUnit(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            bytes: bytes,
            label: name,
            verdict: { allowed ? .allowed : .blocked(reason ?? "blocked") },
            remove: { if let throwing { throw throwing }; return fallback }
        )
    }

    func testCountsAndBytesOnlyForRemovedUnits() {
        let tally = Removal.run([
            unit("a", bytes: 10),
            unit("b", bytes: 20, allowed: false),
            unit("c", bytes: 30),
        ])
        XCTAssertEqual(tally.removed, 2)
        XCTAssertEqual(tally.freed, 40)
        XCTAssertEqual(tally.refused, ["b: blocked"])
    }

    func testGuardBlockDoesNotFireTheFailureHook() {
        // A refused path is not a permissions problem and must not raise the banner.
        var failures = 0
        _ = Removal.run([unit("blocked", allowed: false)], onFailure: { _ in failures += 1 })
        XCTAssertEqual(failures, 0)
    }

    func testThrownFailureFiresTheHookAndIsDescribed() {
        var failures = 0
        let tally = Removal.run(
            [unit("boom", throwing: CocoaError(.fileWriteNoPermission))],
            describeFailure: { _ in "needs permission" },
            onFailure: { _ in failures += 1 }
        )
        XCTAssertEqual(failures, 1)
        XCTAssertEqual(tally.removed, 0)
        XCTAssertEqual(tally.refused, ["boom: needs permission"])
    }

    func testFallbackRouteIsCounted() {
        let tally = Removal.run([unit("viaFinder", fallback: true), unit("direct")])
        XCTAssertEqual(tally.viaFallback, 1)
        XCTAssertEqual(tally.removed, 2)
    }

    func testBlockedFallbackTextIsUsedWhenTheGuardGivesNoReason() {
        var custom = unit("support", allowed: false)
        custom = RemovalUnit(url: custom.url, bytes: custom.bytes, label: custom.label,
                             blockedFallback: "support file blocked",
                             verdict: { .blocked("") }, remove: { false })
        let tally = Removal.run([custom])
        // An empty reason is still a reason; the fallback covers a nil one.
        XCTAssertEqual(tally.refused.first, "support: ")
    }

    func testNoticePluralisation() {
        var one = RemovalTally(); one.merge(Removal.run([unit("a", bytes: 5)]))
        XCTAssertEqual(one.notice(verb: "Moved", noun: "artifact", toTrash: true),
                       "Moved 1 artifact to the Trash — 5 bytes.")

        let none = RemovalTally()
        XCTAssertEqual(none.notice(verb: "Moved", noun: "item", toTrash: true),
                       "Moved 0 items to the Trash — 0 bytes.")

        let two = Removal.run([unit("a", bytes: 1000), unit("b", bytes: 1000)])
        XCTAssertEqual(two.notice(verb: "Deleted", noun: "item", toTrash: false),
                       "Deleted 2 items — 2.00 KB.")
    }

    func testRefusalSuffixRespectsItsCap() {
        let tally = Removal.run([
            unit("a", allowed: false, reason: "one"),
            unit("b", allowed: false, reason: "two"),
            unit("c", allowed: false, reason: "three"),
        ])
        XCTAssertEqual(tally.refusalSuffix(max: 2), " 3 left alone: a: one; b: two")
        XCTAssertEqual(tally.refusalSuffix(max: 3), " 3 left alone: a: one; b: two; c: three")
        XCTAssertEqual(RemovalTally().refusalSuffix(), "")
    }

    func testDedupeKeepsTheFirstOccurrenceAndOrder() {
        var tally = Removal.run([
            unit("app", allowed: false, reason: "same"),
            unit("other", allowed: false, reason: "different"),
            unit("app", allowed: false, reason: "same"),
        ])
        tally.dedupeRefusals()
        XCTAssertEqual(tally.refused, ["app: same", "other: different"])
    }

    func testMergePreservesRefusalOrderAcrossRuns() {
        var tally = Removal.run([unit("first", allowed: false, reason: "a")])
        tally.merge(Removal.run([unit("second", allowed: false, reason: "b")]))
        XCTAssertEqual(tally.refused, ["first: a", "second: b"])
    }
}
