import XCTest
@testable import GemUsageLens

/// The settings → CLI flags contract, and the pure display rules over the
/// CLI's budget payload. The arithmetic itself lives (and is tested) in the
/// CLI; nothing here recomputes a window or a forecast.
final class BudgetTests: XCTestCase {
    private func settings(basis: BudgetBasisChoice, cost: Double = 100, tokens: Double = 5_000_000,
                          warn: Double = 80, critical: Double = 95) -> BudgetSettings {
        BudgetSettings(enabled: true, basis: basis, limitCost: cost, limitTokens: tokens,
                       warnPercent: warn, criticalPercent: critical, notificationsEnabled: true)
    }

    func testCLIArgumentsPerBasis() {
        XCTAssertEqual(settings(basis: .cost).cliArguments,
                       ["budget", "--tz", "local", "--json", "--warn", "80", "--critical", "95",
                        "--limit-usd", "100", "--limit-tokens", "0"])
        XCTAssertEqual(settings(basis: .tokens).cliArguments,
                       ["budget", "--tz", "local", "--json", "--warn", "80", "--critical", "95",
                        "--limit-usd", "0", "--limit-tokens", "5000000"])
        // Fractions survive as plain decimals, never scientific notation.
        XCTAssertEqual(BudgetSettings.number(12.5), "12.5000")
        XCTAssertEqual(BudgetSettings.number(100_000_000), "100000000")
    }

    private func basis(used: Double, limit: Double, forecast: BudgetForecast? = nil, state: BudgetState = .normal) -> BudgetBasis {
        BudgetBasis(limit: limit, used: used, remaining: max(0, limit - used),
                    percent: limit > 0 ? used / limit * 100 : 0, state: state, forecast: forecast)
    }

    private func status(cost: BudgetBasis, tokens: BudgetBasis? = nil, partial: Int = 0) -> BudgetStatus {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        return BudgetStatus(windowStart: start, windowEnd: start.addingTimeInterval(30 * 86_400),
                            nextReset: start.addingTimeInterval(30 * 86_400), elapsedFraction: 0.5,
                            cost: cost,
                            tokens: tokens ?? basis(used: 0, limit: 0, state: .unset),
                            partialRecords: partial)
    }

    // The used/left percents are shown side by side, so they must sum to 100.
    func testPercentPairSumsTo100() {
        for used in stride(from: 0.0, through: 200.0, by: 0.37) {
            let p = UsageModel.percentPair(used / 200 * 100)
            if used <= 200 { XCTAssertEqual(p.used + p.remaining, 100, "used=\(used)") }
        }
        let over = UsageModel.percentPair(162)
        XCTAssertEqual(over.used, 162)
        XCTAssertEqual(over.remaining, 0)
    }

    func testMenuBarMonthlyLabelCarriesPercent() {
        let m = UsageModel()
        m.budget = status(cost: basis(used: 84, limit: 200))
        XCTAssertEqual(m.monthlyRemainingLabel, "$116 · 58%")
        m.budget = status(cost: basis(used: 0, limit: 0, state: .unset),
                          tokens: basis(used: 20_000_000, limit: 50_000_000))
        XCTAssertEqual(m.monthlyRemainingLabel, "30.0M · 60%")
        // Monitor off → today's price (which is "…" before the first refresh).
        m.budget = nil
        XCTAssertEqual(m.monthlyRemainingLabel, "…")
    }

    func testForecastLabels() {
        let hit = Date(timeIntervalSince1970: 1_781_000_000)
        let over = basis(used: 150, limit: 200,
                         forecast: BudgetForecast(projected: 300, percent: 150, exhaustionAt: hit, reliable: true, state: .critical))
        XCTAssertEqual(UsageModel.forecastLabel(over, .cost),
                       "On pace for $300.00 (150%) — budget gone \(UsageModel.resetLabel(hit))")
        let fine = basis(used: 50, limit: 200,
                         forecast: BudgetForecast(projected: 100, percent: 50, exhaustionAt: nil, reliable: true, state: .normal))
        XCTAssertEqual(UsageModel.forecastLabel(fine, .cost), "On pace for $100.00 (50%) by the reset")
        let spent = basis(used: 250, limit: 200,
                          forecast: BudgetForecast(projected: 500, percent: 250, exhaustionAt: nil, reliable: true, state: .critical))
        XCTAssertEqual(UsageModel.forecastLabel(spent, .cost), "Over budget — on pace for $500.00 (250%)")
        let early = basis(used: 20, limit: 200,
                          forecast: BudgetForecast(projected: 9999, percent: 4999, exhaustionAt: nil, reliable: false, state: .critical))
        XCTAssertEqual(UsageModel.forecastLabel(early, .cost), "Too early this month to project a pace")
        XCTAssertNil(UsageModel.forecastLabel(basis(used: 10, limit: 200), .cost))
        // Token basis formats compactly.
        let tok = basis(used: 1_000_000, limit: 4_000_000,
                        forecast: BudgetForecast(projected: 2_000_000, percent: 50, exhaustionAt: nil, reliable: true, state: .normal))
        XCTAssertEqual(UsageModel.forecastLabel(tok, .tokens), "On pace for 2.0M (50%) by the reset")
    }

    func testForecastIcons() {
        let f = { (state: BudgetState, reliable: Bool) in
            self.basis(used: 1, limit: 2, forecast: BudgetForecast(projected: 1, percent: 50, exhaustionAt: nil, reliable: reliable, state: state))
        }
        XCTAssertEqual(UsageModel.forecastIcon(f(.critical, true)), "exclamationmark.triangle.fill")
        XCTAssertEqual(UsageModel.forecastIcon(f(.warning, true)), "exclamationmark.circle")
        XCTAssertEqual(UsageModel.forecastIcon(f(.normal, true)), "checkmark.circle")
        XCTAssertEqual(UsageModel.forecastIcon(f(.critical, false)), "clock")
    }

    func testStateRanksAndColors() {
        XCTAssertLessThan(BudgetState.normal.rank, BudgetState.warning.rank)
        XCTAssertLessThan(BudgetState.warning.rank, BudgetState.critical.rank)
        XCTAssertEqual(BudgetState.unset.rank, 0)
        XCTAssertNil(GemUsageLensApp.color(.normal))
        XCTAssertNil(GemUsageLensApp.color(.unset))
        XCTAssertNotNil(GemUsageLensApp.color(.warning))
        XCTAssertNotNil(GemUsageLensApp.color(.critical))
    }

    func testPartialLabel() {
        XCTAssertNil(UsageModel.partialLabel(0))
        XCTAssertEqual(UsageModel.partialLabel(1), "1 call from older gem-agent transcripts — figures are a lower bound")
        XCTAssertTrue(UsageModel.partialLabel(7)!.hasPrefix("7 calls"))
    }
}
