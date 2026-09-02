import Foundation

/// Row mirrors one JSON object from `gem-usage-lens report --json`.
struct Row: Codable, Identifiable {
    let key: String
    let records: Int
    let promptTokens: Int
    let outputTokens: Int
    let thoughtsTokens: Int
    let cachedTokens: Int   // the share of prompt served from cache (not an addition)
    let totalTokens: Int    // prompt + output + thoughts — the billed count
    let costUSD: Double
    let partialRecords: Int

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, records
        case promptTokens = "prompt_tokens"
        case outputTokens = "output_tokens"
        case thoughtsTokens = "thoughts_tokens"
        case cachedTokens = "cached_tokens"
        case totalTokens = "total_tokens"
        case costUSD = "cost_usd"
        case partialRecords = "partial_records"
    }
}

/// Summary mirrors `gem-usage-lens report --summary --json`.
struct Summary: Codable {
    let firstDay: String
    let lastDay: String
    let activeDays: Int
    let records: Int
    let promptTokens: Int
    let outputTokens: Int
    let thoughtsTokens: Int
    let cachedTokens: Int
    let totalTokens: Int
    let totalUSD: Double
    let dailyAvgUSD: Double
    let peakDay: String
    let peakUSD: Double
    let projection30USD: Double

    /// Records in the period that carry tokens yet are stored at $0 — a model
    /// the CLI could not price when it ingested them, or a rate table updated
    /// since without a `reprice`. Optional so a summary from a CLI that
    /// predates a field still decodes.
    let unpricedRecords: Int?
    let unpricedModels: [String: Int]?
    /// Records from transcripts written before gem-agent ADR-0057: their files
    /// never recorded risk/compaction spend, so the totals are a lower bound.
    let partialRecords: Int?
    let checksumMismatches: Int?

    enum CodingKeys: String, CodingKey {
        case firstDay = "first_day"
        case lastDay = "last_day"
        case activeDays = "active_days"
        case records
        case promptTokens = "prompt_tokens"
        case outputTokens = "output_tokens"
        case thoughtsTokens = "thoughts_tokens"
        case cachedTokens = "cached_tokens"
        case totalTokens = "total_tokens"
        case totalUSD = "total_usd"
        case dailyAvgUSD = "daily_avg_usd"
        case peakDay = "peak_day"
        case peakUSD = "peak_usd"
        case projection30USD = "projection_30d_usd"
        case unpricedRecords = "unpriced_records"
        case unpricedModels = "unpriced_models"
        case partialRecords = "partial_records"
        case checksumMismatches = "checksum_mismatches"
    }
}

/// The threshold state of one budget basis, as the CLI names it.
enum BudgetState: String, Codable {
    case unset, normal, warning, critical

    /// Severity, for detecting upward transitions (to notify once per crossing).
    var rank: Int {
        switch self {
        case .unset, .normal: return 0
        case .warning: return 1
        case .critical: return 2
        }
    }
}

/// BudgetForecast mirrors the `forecast` object of `gem-usage-lens budget --json`.
struct BudgetForecast: Codable, Equatable {
    let projected: Double
    let percent: Double
    let exhaustionAt: Date?
    let reliable: Bool
    let state: BudgetState

    enum CodingKeys: String, CodingKey {
        case projected, percent, reliable, state
        case exhaustionAt = "exhaustion_at"
    }
}

/// BudgetBasis mirrors one basis (`cost` / `tokens`) of `budget --json`.
struct BudgetBasis: Codable, Equatable {
    let limit: Double
    let used: Double
    let remaining: Double
    let percent: Double
    let state: BudgetState
    let forecast: BudgetForecast?
}

/// BudgetStatus mirrors `gem-usage-lens budget --json`: the calendar-month
/// window and both bases. The CLI does every calculation; this is a view.
struct BudgetStatus: Codable, Equatable {
    let windowStart: Date
    let windowEnd: Date
    let nextReset: Date
    let elapsedFraction: Double
    let cost: BudgetBasis
    let tokens: BudgetBasis
    let partialRecords: Int

    enum CodingKeys: String, CodingKey {
        case cost, tokens
        case windowStart = "window_start"
        case windowEnd = "window_end"
        case nextReset = "next_reset"
        case elapsedFraction = "elapsed_fraction"
        case partialRecords = "partial_records"
    }

    /// The basis the user chose to watch: whichever one carries a limit.
    /// Both unset ⇒ nil (the monitor is off or misconfigured).
    var watched: BudgetBasis? {
        if cost.state != .unset { return cost }
        if tokens.state != .unset { return tokens }
        return nil
    }

    /// Which basis `watched` is, for formatting amounts.
    var watchedBasis: BudgetBasisChoice? {
        if cost.state != .unset { return .cost }
        if tokens.state != .unset { return .tokens }
        return nil
    }
}

/// Usage the store holds at $0 although it should have cost something: calls
/// on a model the bundled CLI's rate table did not know when they were
/// ingested, or that a newer table now prices but `reprice` has not yet
/// touched. Every figure the app shows understates by these calls.
struct UnpricedUsage: Equatable {
    let records: Int
    let models: [String: Int]   // model id → record count
}

/// Where the Reprice button's attempt stands, for the current badge episode.
/// A Bool cannot say "running" or "failed", and both must be named on screen.
enum RepricePhase: Equatable {
    case idle
    case running
    case done                 // reprice completed; the badge (if still up) is beyond it
    case failed(String)       // the CLI failed; the reason, as the user should read it
}

/// Decoding for the CLI's JSON: RFC 3339 timestamps, whole seconds by
/// contract, but tolerated with fractions too.
enum CLIJSON {
    static func decoder() -> JSONDecoder {
        let dec = JSONDecoder()
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        dec.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let d = plain.date(from: s) ?? fractional.date(from: s) { return d }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not an RFC 3339 date: \(s)"))
        }
        return dec
    }
}
