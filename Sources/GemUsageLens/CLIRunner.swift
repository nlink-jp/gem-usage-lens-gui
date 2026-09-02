import Foundation

enum CLIError: LocalizedError {
    case binaryNotFound
    case launchFailed(detail: String)
    case runFailed(summary: String, detail: String)

    /// A short, user-facing summary (shown prominently).
    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "gem-usage-lens CLI not found. Reinstall GemUsageLens.app (the CLI ships bundled), or install gem-usage-lens on your PATH."
        case .launchFailed:
            return "Couldn't start the gem-usage-lens CLI. Reinstall the app if this keeps happening."
        case .runFailed(let summary, _):
            return summary
        }
    }

    /// The raw CLI output (shown as smaller secondary detail), if any.
    var failureReason: String? {
        switch self {
        case .binaryNotFound: return nil
        case .launchFailed(let d): return d.isEmpty ? nil : d
        case .runFailed(_, let d): return d.isEmpty ? nil : d
        }
    }

    /// Translate a CLI failure into a short, actionable summary. Pure (testable):
    /// the raw stderr stays available separately as the detail.
    static func summarize(exitCode: Int32, crashed: Bool, stderr: String) -> String {
        let s = stderr.lowercased()
        if crashed {
            return "The usage CLI stopped unexpectedly. Try Refresh; if it keeps happening, reinstall the app."
        }
        if s.contains("permission denied") || s.contains("operation not permitted") {
            return "Couldn't read the gem-agent transcripts (permission denied). Check that the app can access ~/.local/state/gem-agent."
        }
        if s.contains("no such file") || s.contains("cannot find") || s.contains("no transcripts found") {
            return "No gem-agent transcripts were found. Run gem-agent first, or check the sessions root (gem-usage-lens doctor)."
        }
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "The usage CLI exited with an error (code \(exitCode))."
        }
        let firstLine = trimmed.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? trimmed
        return "The usage CLI reported: \(firstLine)"
    }
}

/// CLIRunner locates and invokes the gem-usage-lens CLI, decoding its --json
/// output. The CLI is the single source of truth for parsing, pricing,
/// aggregation and the budget arithmetic; this GUI is a thin front-end.
enum CLIRunner {
    static let binaryName = "gem-usage-lens"

    /// Resolve the CLI binary. The **bundled** copy in the .app's Resources is
    /// the trust anchor: it ships Developer-ID signed + notarized, so it can't
    /// be swapped without invalidating the signature. In a release build that
    /// comes first and an environment variable can't redirect execution; the
    /// only fallbacks are the conventional install locations. In DEBUG builds
    /// the `$GEM_USAGE_LENS_BIN` override and the local dev path are honored.
    static func findBinary() -> String? {
        var allowEnvOverride = false
        var devPaths: [String] = []
        #if DEBUG
        allowEnvOverride = true
        devPaths = [
            NSHomeDirectory() + "/works/nlink-jp/util-series/gem-usage-lens/dist/gem-usage-lens",
            NSHomeDirectory() + "/works/nlink-jp/_wip/gem-usage-lens/dist/gem-usage-lens",
        ]
        #endif
        return resolveBinary(
            env: ProcessInfo.processInfo.environment,
            allowEnvOverride: allowEnvOverride,
            bundled: Bundle.main.resourceURL?.appendingPathComponent(binaryName).path,
            devPaths: devPaths,
            isExecutable: { FileManager.default.isExecutableFile(atPath: $0) }
        )
    }

    /// Pure resolution logic (injectable for tests). Order:
    ///   [env, only if `allowEnvOverride`] → bundled → /usr/local, /opt/homebrew → [devPaths]
    static func resolveBinary(
        env: [String: String],
        allowEnvOverride: Bool,
        bundled: String?,
        devPaths: [String],
        isExecutable: (String) -> Bool
    ) -> String? {
        var order: [String] = []
        if allowEnvOverride, let p = env["GEM_USAGE_LENS_BIN"] {
            order.append(p)
        }
        if let bundled {
            order.append(bundled)
        }
        order += ["/usr/local/bin/\(binaryName)", "/opt/homebrew/bin/\(binaryName)"]
        order += devPaths
        return order.first(where: isExecutable)
    }

    @discardableResult
    static func run(_ args: [String]) throws -> Data {
        guard let bin = findBinary() else { throw CLIError.binaryNotFound }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
        } catch {
            throw CLIError.launchFailed(detail: error.localizedDescription)
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let stderr = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let crashed = proc.terminationReason == .uncaughtSignal
            throw CLIError.runFailed(
                summary: CLIError.summarize(exitCode: proc.terminationStatus, crashed: crashed, stderr: stderr),
                detail: stderr
            )
        }
        return data
    }

    // MARK: - Typed queries

    static func ingest() throws {
        _ = try run(["ingest"])
    }

    /// Recompute stored costs with the CLI's current rate table — the fix for
    /// rows a previous build stored at $0.
    static func reprice() throws {
        _ = try run(["reprice"])
    }

    static func summary(since: String) throws -> Summary {
        let data = try run(["report", "--since", since, "--summary", "--tz", "local", "--json"])
        return try CLIJSON.decoder().decode(Summary.self, from: data)
    }

    /// The calendar-month budget state for the given settings. The CLI owns
    /// the window, the consumption and the forecast.
    static func budget(_ s: BudgetSettings) throws -> BudgetStatus {
        try CLIJSON.decoder().decode(BudgetStatus.self, from: try run(s.cliArguments))
    }

    static func rows(groupBy: String, since: String? = nil, sort: String? = nil, top: Int? = nil, dense: Bool = false) throws -> [Row] {
        var args = ["report", "--group-by", groupBy, "--tz", "local", "--json"]
        if let since { args += ["--since", since] }
        if let sort { args += ["--sort", sort] }
        if let top { args += ["--top", String(top)] }
        if dense { args += ["--dense"] }
        return try CLIJSON.decoder().decode([Row].self, from: try run(args))
    }
}
