import ServiceManagement
import XCTest
@testable import GemUsageLens

/// The launch-at-login toggle's pure rules. The service call itself needs a
/// real .app bundle and is not exercised here.
final class LoginItemTests: XCTestCase {
    // `.notFound` is what a never-registered copy reports: it must read as
    // "not yet", never as a state that disables the switch.
    func testStatusMapping() {
        XCTAssertEqual(LoginItem.state(from: .enabled), .enabled)
        XCTAssertEqual(LoginItem.state(from: .requiresApproval), .requiresApproval)
        XCTAssertEqual(LoginItem.state(from: .notRegistered), .notEnabled)
        XCTAssertEqual(LoginItem.state(from: .notFound), .notEnabled)
    }

    func testToggleMirrorsState() {
        XCTAssertTrue(LoginItem.isOn(.enabled))
        XCTAssertTrue(LoginItem.isOn(.requiresApproval))
        XCTAssertFalse(LoginItem.isOn(.notEnabled))
    }

    // After a call that threw nothing, the status is read back; a silent
    // no-change is reported, never swallowed.
    func testVerifyMessages() {
        XCTAssertNil(LoginItem.verifyMessage(on: true, after: .enabled))
        XCTAssertNil(LoginItem.verifyMessage(on: false, after: .notEnabled))
        XCTAssertTrue(LoginItem.verifyMessage(on: true, after: .requiresApproval)!.contains("Login Items"))
        XCTAssertTrue(LoginItem.verifyMessage(on: true, after: .notEnabled)!.contains("did not register"))
        XCTAssertTrue(LoginItem.verifyMessage(on: false, after: .enabled)!.contains("did not remove"))
        XCTAssertTrue(LoginItem.verifyMessage(on: false, after: .requiresApproval)!.contains("did not remove"))
    }

    func testFailureMessages() {
        let bare = LoginItem.failureMessage(on: true, error: "x", bundled: false)
        XCTAssertTrue(bare.contains("not a bundled app"))
        let real = LoginItem.failureMessage(on: false, error: "Operation not permitted", bundled: true)
        XCTAssertTrue(real.contains("disable") && real.contains("Operation not permitted"))
    }
}
