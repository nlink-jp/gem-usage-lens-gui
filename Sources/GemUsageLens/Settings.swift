import Foundation

/// UserDefaults keys for the monthly-budget settings, plus their defaults.
enum SettingsKey {
    static let budgetEnabled = "budgetEnabled"
    static let budgetBasis = "budgetBasis"           // BudgetBasisChoice rawValue
    static let budgetCost = "budgetCostUSD"          // Double, dollars per calendar month
    static let budgetTokens = "budgetTokens"         // Double, billed tokens per calendar month
    static let warnPercent = "warnPercent"
    static let criticalPercent = "criticalPercent"
    static let notificationsEnabled = "budgetNotificationsEnabled"

    static func registerDefaults(_ d: UserDefaults = .standard) {
        d.register(defaults: [
            budgetEnabled: false,
            budgetBasis: BudgetBasisChoice.cost.rawValue,
            budgetCost: 100.0,
            budgetTokens: 100_000_000.0,
            warnPercent: 80.0,
            criticalPercent: 95.0,
            notificationsEnabled: true,
        ])
    }
}

/// What the monthly budget is measured in.
enum BudgetBasisChoice: String, CaseIterable, Identifiable {
    case cost, tokens
    var id: String { rawValue }
    var label: String { self == .cost ? "Cost ($)" : "Tokens (billed)" }
}

/// A snapshot of the monthly-budget settings, read from UserDefaults.
/// UsageModel isn't a View, so it can't use @AppStorage — it reads through
/// this. SettingsView binds the same keys via @AppStorage. The values become
/// the CLI's `budget` flags: the arithmetic lives in the CLI, not here.
struct BudgetSettings: Equatable {
    let enabled: Bool
    let basis: BudgetBasisChoice
    let limitCost: Double
    let limitTokens: Double
    let warnPercent: Double
    let criticalPercent: Double
    let notificationsEnabled: Bool

    static func current(_ d: UserDefaults = .standard) -> BudgetSettings {
        BudgetSettings(
            enabled: d.bool(forKey: SettingsKey.budgetEnabled),
            basis: BudgetBasisChoice(rawValue: d.string(forKey: SettingsKey.budgetBasis) ?? "cost") ?? .cost,
            limitCost: d.double(forKey: SettingsKey.budgetCost),
            limitTokens: d.double(forKey: SettingsKey.budgetTokens),
            warnPercent: d.double(forKey: SettingsKey.warnPercent),
            criticalPercent: d.double(forKey: SettingsKey.criticalPercent),
            notificationsEnabled: d.bool(forKey: SettingsKey.notificationsEnabled)
        )
    }

    /// The `budget` invocation for these settings: only the chosen basis gets
    /// a limit (the other stays unset in the CLI's answer), thresholds always.
    /// Pure, so the contract with the CLI is pinned by a test.
    var cliArguments: [String] {
        var args = ["budget", "--tz", "local", "--json",
                    "--warn", Self.number(warnPercent), "--critical", Self.number(criticalPercent)]
        switch basis {
        case .cost: args += ["--limit-usd", Self.number(limitCost), "--limit-tokens", "0"]
        case .tokens: args += ["--limit-usd", "0", "--limit-tokens", Self.number(limitTokens)]
        }
        return args
    }

    /// A plain decimal for a flag value — never scientific notation, never a
    /// locale separator.
    static func number(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1e15 { return String(Int64(v)) }
        return String(format: "%.4f", v)
    }
}
