import AppKit
import Foundation

/// Moves things to the Trash, with a fallback for the case macOS blocks.
///
/// `FileManager.trashItem` is the direct route, but since macOS 13 a plain app cannot move
/// anything out of `/Applications` without the App Management permission — and the error it
/// returns says nothing about that. Finder, however, is always allowed to trash an app, so
/// when the direct move fails we ask Finder to do it via Apple Events. That turns a dead end
/// into a familiar one-time "Silt wants to control Finder" prompt.
///
/// Order matters: try the quiet path first, and only involve Finder when there is no
/// alternative, so ordinary removals never trigger an automation prompt.
enum TrashService {

    enum Route {
        case direct
        case finder
    }

    enum Failure: Error, LocalizedError {
        case blocked(String)

        var errorDescription: String? {
            if case let .blocked(reason) = self { return reason }
            return nil
        }
    }

    /// - Returns: which route succeeded, so callers can explain what happened.
    @discardableResult
    static func trash(_ url: URL, allowFinderFallback: Bool = true) throws -> Route {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            return .direct
        } catch {
            guard allowFinderFallback else { throw error }
            if let scriptError = trashViaFinder(url) {
                // Report the original failure — it is the one that describes the real
                // problem; the Finder attempt is a fallback, not the headline.
                throw Failure.blocked("\(error.localizedDescription) Finder could not do it either: \(scriptError)")
            }
            return .finder
        }
    }

    /// Asks Finder to move the item to the Trash. Returns an error string on failure.
    private static func trashViaFinder(_ url: URL) -> String? {
        let source = """
        tell application "Finder"
            delete POSIX file "\(url.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))"
        end tell
        """
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return "could not build the request" }
        script.executeAndReturnError(&errorInfo)

        guard let errorInfo else { return nil }
        let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown error"
        let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
        // -1743 is "not authorised to send Apple events" — the automation prompt was denied.
        if code == -1743 {
            return "Silt is not allowed to control Finder — enable it under Privacy & Security › Automation"
        }
        return message
    }
}
