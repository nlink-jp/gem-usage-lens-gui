import Foundation

/// The app's own version, for display. A menu-bar (LSUIElement) app has no
/// `--version` to run, so if the number isn't on screen there is no way at all
/// to tell which build is running — which is what a bug report needs first.
enum AppVersion {
    /// The running build's version, from the bundle's Info.plist.
    static var current: String {
        display(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
    }

    /// The display rule, split from the bundle lookup so it can be tested.
    /// Shown **verbatim** — the leading `v` and any `-N-g<sha>` / `-dirty`
    /// suffix from `git describe` are what make a report precise, so they stay.
    /// "dev" covers the two non-release cases: running outside an `.app`
    /// (`swift run`, tests), and a bundle whose `${VERSION}` placeholder was
    /// never substituted by `make build-app`.
    static func display(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty, !raw.hasPrefix("$") else { return "dev" }
        return raw
    }
}
