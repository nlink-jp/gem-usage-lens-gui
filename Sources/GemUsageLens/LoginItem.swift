import Foundation
import ServiceManagement

/// "Launch at login" over `SMAppService.mainApp`.
///
/// The service is the source of truth: the toggle mirrors its status, there
/// is no persisted flag of our own, and every change is verified by reading
/// the status back — "no error but the switch snaps back" must never happen
/// silently. Registration only works from a proper `.app` bundle; a bare
/// `swift run` binary reports the failure in the settings window.
enum LoginItem {
    /// What the UI needs to know — not the raw `SMAppService.Status`.
    enum State: Equatable {
        /// Registered and active.
        case enabled
        /// Not active. Covers `.notRegistered` AND `.notFound`: a copy that
        /// has never been registered reports `.notFound`, which is "not yet",
        /// never "impossible" — disabling the switch on it would remove the
        /// only way to register.
        case notEnabled
        /// Registered, but the user has to approve it in System Settings ›
        /// General › Login Items before it takes effect.
        case requiresApproval
    }

    /// Pure mapping from the service's status enum.
    static func state(from status: SMAppService.Status) -> State {
        switch status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered, .notFound: return .notEnabled
        @unknown default: return .notEnabled
        }
    }

    static var current: State { state(from: SMAppService.mainApp.status) }

    /// What the toggle shows for a state: on for enabled AND for registered-
    /// awaiting-approval (the user did turn it on; macOS is what is pending),
    /// off otherwise.
    static func isOn(_ state: State) -> Bool {
        state == .enabled || state == .requiresApproval
    }

    /// Register or unregister, then read the status back. Returns the message
    /// to show beside the toggle: nil when the service now reports what was
    /// asked, otherwise the reason (thrown error, or a silent no-change).
    static func setEnabled(_ on: Bool) -> String? {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            return failureMessage(on: on, error: error.localizedDescription, bundled: Bundle.main.bundleIdentifier != nil)
        }
        return verifyMessage(on: on, after: current)
    }

    /// The line under the toggle for a failed call. Pure.
    static func failureMessage(on: Bool, error: String, bundled: Bool) -> String {
        let verb = on ? "enable" : "disable"
        if !bundled {
            return "Couldn't \(verb) launch at login: this is not a bundled app (run the .app, not the bare binary)."
        }
        return "Couldn't \(verb) launch at login: \(error)"
    }

    /// The line under the toggle after a call that threw nothing. Pure: nil
    /// when the service agrees with the request, a sentence otherwise.
    static func verifyMessage(on: Bool, after state: State) -> String? {
        switch (on, state) {
        case (true, .enabled), (false, .notEnabled):
            return nil
        case (true, .requiresApproval):
            return "Registered — approve it in System Settings › General › Login Items to take effect."
        case (true, .notEnabled):
            return "macOS did not register the login item. Try again from the installed copy in Applications."
        case (false, _):
            return "macOS did not remove the login item. Check System Settings › General › Login Items."
        }
    }

    /// Where macOS keeps the Login Items list.
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension")!
}
