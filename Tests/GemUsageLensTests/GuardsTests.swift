import XCTest
@testable import GemUsageLens

final class SingleInstanceTests: XCTestCase {
    func testBareDevBinaryAlwaysProceeds() {
        XCTAssertEqual(singleInstanceDecision(bundleID: nil, ownPID: 1, instancePIDs: [2, 3]), .proceed)
    }

    func testNoRunningInstancesProceeds() {
        XCTAssertEqual(singleInstanceDecision(bundleID: "jp.nlink.gem-usage-lens-gui", ownPID: 42, instancePIDs: []), .proceed)
    }

    func testOwnPIDAloneProceeds() {
        XCTAssertEqual(singleInstanceDecision(bundleID: "jp.nlink.gem-usage-lens-gui", ownPID: 42, instancePIDs: [42]), .proceed)
    }

    func testAnotherInstanceExits() {
        guard case .exitDuplicate(let message) = singleInstanceDecision(
            bundleID: "jp.nlink.gem-usage-lens-gui", ownPID: 42, instancePIDs: [97316]
        ) else {
            return XCTFail("expected exitDuplicate")
        }
        XCTAssertTrue(message.contains("97316"))
        XCTAssertTrue(message.contains("already running"))
    }
}

/// Trust-boundary tests for CLI binary resolution: the bundled binary is the
/// trust anchor and a poisoned $GEM_USAGE_LENS_BIN cannot take precedence in
/// a release build.
final class BinaryResolutionTests: XCTestCase {
    private let bundled = "/Applications/GemUsageLens.app/Contents/Resources/gem-usage-lens"
    private let brew = "/opt/homebrew/bin/gem-usage-lens"
    private let usrLocal = "/usr/local/bin/gem-usage-lens"

    func testReleaseIgnoresEnvOverride() {
        let got = CLIRunner.resolveBinary(
            env: ["GEM_USAGE_LENS_BIN": "/tmp/evil"], allowEnvOverride: false,
            bundled: bundled, devPaths: [],
            isExecutable: { $0 == "/tmp/evil" || $0 == self.bundled })
        XCTAssertEqual(got, bundled)
    }

    func testDebugHonorsEnvOverride() {
        let got = CLIRunner.resolveBinary(
            env: ["GEM_USAGE_LENS_BIN": "/tmp/override"], allowEnvOverride: true,
            bundled: bundled, devPaths: [],
            isExecutable: { $0 == "/tmp/override" || $0 == self.bundled })
        XCTAssertEqual(got, "/tmp/override")
    }

    func testBundledPreferredOverPath() {
        let got = CLIRunner.resolveBinary(env: [:], allowEnvOverride: false, bundled: bundled, devPaths: [], isExecutable: { _ in true })
        XCTAssertEqual(got, bundled)
    }

    func testFallsBackToPathWhenBundleMissing() {
        let got = CLIRunner.resolveBinary(env: [:], allowEnvOverride: false, bundled: bundled, devPaths: [], isExecutable: { $0 == self.brew })
        XCTAssertEqual(got, brew)
    }

    func testUsrLocalBeforeHomebrew() {
        let got = CLIRunner.resolveBinary(env: [:], allowEnvOverride: false, bundled: nil, devPaths: [], isExecutable: { $0 == self.usrLocal || $0 == self.brew })
        XCTAssertEqual(got, usrLocal)
    }

    func testNilWhenNothingExecutable() {
        XCTAssertNil(CLIRunner.resolveBinary(env: ["GEM_USAGE_LENS_BIN": "/tmp/evil"], allowEnvOverride: true, bundled: bundled, devPaths: ["/dev/path"], isExecutable: { _ in false }))
    }
}

/// The CLI-failure → friendly-summary mapping.
final class CLIErrorTests: XCTestCase {
    func testCrashSummary() {
        XCTAssertTrue(CLIError.summarize(exitCode: -1, crashed: true, stderr: "signal: killed").lowercased().contains("unexpectedly"))
    }

    func testPermissionSummary() {
        XCTAssertTrue(CLIError.summarize(exitCode: 1, crashed: false, stderr: "open /x: permission denied").lowercased().contains("permission"))
    }

    func testNoTranscriptsSummary() {
        let s = CLIError.summarize(exitCode: 1, crashed: false, stderr: "error: no transcripts found under /x")
        XCTAssertTrue(s.contains("gem-agent"), s)
    }

    func testEmptyStderrMentionsExitCode() {
        XCTAssertTrue(CLIError.summarize(exitCode: 2, crashed: false, stderr: "").contains("2"))
    }

    func testGenericLeadsWithFirstLine() {
        let s = CLIError.summarize(exitCode: 1, crashed: false, stderr: "unknown flag --wat\nusage: ...")
        XCTAssertTrue(s.contains("unknown flag --wat"))
        XCTAssertFalse(s.contains("usage:"))
    }

    func testFailureReasonCarriesRawDetail() {
        let e = CLIError.runFailed(summary: "friendly", detail: "raw stderr here")
        XCTAssertEqual(e.errorDescription, "friendly")
        XCTAssertEqual(e.failureReason, "raw stderr here")
        XCTAssertNil(CLIError.binaryNotFound.failureReason)
    }
}
