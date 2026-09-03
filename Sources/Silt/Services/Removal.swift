import Foundation

/// One thing to remove, flattened out of whatever page produced it.
///
/// The gate is a closure rather than a precomputed verdict, so it still runs immediately
/// before the removal — the invariant the whole app is built on. Four pages had each
/// hand-rolled this loop, and they had already drifted apart in refusal wording, refusal
/// caps and dedupe behaviour.
struct RemovalUnit {
    let url: URL
    let bytes: Int64
    /// What a refusal is attributed to: the file's name, the app's name, the group's name.
    /// Never the path — the path is already on screen.
    let label: String
    /// Reason text for when the guard blocks without giving one.
    var blockedFallback: String = "blocked"
    let verdict: () -> SafetyGuard.Verdict
    /// Performs the removal. Returns true when a fallback route did it (Finder).
    let remove: () throws -> Bool
}

/// What a run of removals achieved. Deliberately not `CleanReport`, which is per catalog
/// bucket and feeds `ReportSheet`.
struct RemovalTally {
    private(set) var removedURLs: [URL] = []
    private(set) var freed: Int64 = 0
    private(set) var viaFallback = 0
    private(set) var refused: [String] = []

    var removed: Int { removedURLs.count }

    mutating func merge(_ other: RemovalTally) {
        removedURLs += other.removedURLs
        freed += other.freed
        viaFallback += other.viaFallback
        // Order is preserved deliberately: refusals read per job, interleaved, and only
        // the first few are shown.
        refused += other.refused
    }

    /// One app can refuse eleven support files for the same reason. Keeps the first.
    mutating func dedupeRefusals() {
        var seen = Set<String>()
        refused = refused.filter { seen.insert($0).inserted }
    }

    func refusalSuffix(max limit: Int = 2) -> String {
        refused.isEmpty
            ? ""
            : " \(refused.count) left alone: \(refused.prefix(limit).joined(separator: "; "))"
    }

    /// "Moved 3 artifacts to the Trash — 1.2 GB." Applications writes its own headline
    /// because it counts two kinds of thing.
    func notice(verb: String, noun: String, toTrash: Bool, maxRefusals: Int = 2) -> String {
        let subject = "\(removed) \(removed == 1 ? noun : noun + "s")"
        let head = toTrash
            ? "\(verb) \(subject) to the Trash — \(freed.byteLabel)."
            : "\(verb) \(subject) — \(freed.byteLabel)."
        return head + refusalSuffix(max: maxRefusals)
    }

    fileprivate mutating func record(_ url: URL, bytes: Int64, viaFallback used: Bool) {
        removedURLs.append(url)
        freed += bytes
        if used { viaFallback += 1 }
    }

    fileprivate mutating func refuse(_ text: String) { refused.append(text) }
}

enum Removal {
    /// Runs `units` in order. Every failure, whether a guard block or a thrown error, is
    /// attributed to its unit's label; nothing is swallowed.
    ///
    /// - Parameter describeFailure: how a thrown error is worded. Applications maps
    ///   permission codes onto the App Management hint.
    /// - Parameter onFailure: fires only on a *thrown* failure, never on a guard block, so
    ///   a blocked path cannot raise the permissions banner.
    @MainActor
    static func run(_ units: [RemovalUnit],
                    describeFailure: (Error) -> String = { $0.localizedDescription },
                    onFailure: (Error) -> Void = { _ in }) -> RemovalTally {
        var tally = RemovalTally()
        for unit in units {
            let verdict = unit.verdict()
            guard verdict.isAllowed else {
                tally.refuse("\(unit.label): \(verdict.reason ?? unit.blockedFallback)")
                continue
            }
            do {
                let usedFallback = try unit.remove()
                tally.record(unit.url, bytes: unit.bytes, viaFallback: usedFallback)
            } catch {
                tally.refuse("\(unit.label): \(describeFailure(error))")
                onFailure(error)
            }
        }
        return tally
    }
}
