import Foundation

/// Where a page-local scan is in its life.
///
/// Deliberately three cases. The clean lifecycle (`AppModel.Phase`) is a different state
/// machine, and a page that only scans must not be able to express `.cleaning` or
/// `.finished`. Leftovers used to borrow the five-case type, which forced a `default:`
/// arm in its view and silently switched off exhaustiveness checking on the one page
/// that had drifted furthest.
enum ScanPhase: Equatable {
    case idle
    case scanning
    case ready
}
