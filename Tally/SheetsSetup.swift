import Foundation

/// One-time setup for "make my sheet".
///
/// Paste the copy link of your tally template sheet below, then rebuild. It looks like
/// https://docs.google.com/spreadsheets/d/…/copy
/// Leave it empty and the button is hidden; people set up their own sheet with the script instead.
enum SheetsSetup {
    static let templateURL = ""

    static var template: URL? {
        let s = templateURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, let url = URL(string: s), url.scheme == "https" else { return nil }
        return url
    }

    /// The script version this build of tally ships with (matches SCRIPT_VERSION in Code.gs).
    static let scriptVersion = 3
}
