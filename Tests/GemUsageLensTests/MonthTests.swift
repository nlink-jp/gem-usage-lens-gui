import XCTest
@testable import GemUsageLens

/// The month-to-date consumption display: the bill is counted per calendar
/// month, so the month's running total is shown with or without a budget.
final class MonthTests: XCTestCase {
    // The popover's plain row is the only place the month's cost appears
    // unless the budget section watches cost — then the row would repeat it.
    func testMonthRowShownUnlessBudgetAlreadyPrintsTheCost() {
        XCTAssertTrue(UsageModel.showsMonthRow(watchedBasis: nil))      // monitor off
        XCTAssertTrue(UsageModel.showsMonthRow(watchedBasis: .tokens))  // budget counts tokens, not dollars
        XCTAssertFalse(UsageModel.showsMonthRow(watchedBasis: .cost))
    }

    private func summary(usd: Double) throws -> Summary {
        let json = """
        {"first_day":"2026-11-01","last_day":"2026-11-13","active_days":7,"records":351,
         "prompt_tokens":85061262,"output_tokens":315813,"thoughts_tokens":110456,
         "cached_tokens":51403865,"total_tokens":85487531,"total_usd":\(usd),
         "daily_avg_usd":10.9,"peak_day":"2026-11-01","peak_usd":46.5,"projection_30d_usd":327.5}
        """
        return try CLIJSON.decoder().decode(Summary.self, from: Data(json.utf8))
    }

    func testMonthPriceLabel() throws {
        XCTAssertEqual(UsageModel.monthPriceLabel(try summary(usd: 76.4198), failed: false), "$76.42")
        // Stale numbers outlive a later failure, as the today figure does.
        XCTAssertEqual(UsageModel.monthPriceLabel(try summary(usd: 0), failed: true), "$0.00")
        XCTAssertEqual(UsageModel.monthPriceLabel(nil, failed: false), "…")
        XCTAssertEqual(UsageModel.monthPriceLabel(nil, failed: true), "—")
    }

    // The stored choice of people who picked the budget-remaining mode before
    // `month` existed must keep meaning the same thing.
    func testMenuBarModeRawValuesAndLabels() {
        XCTAssertEqual(MenuBarMode(rawValue: "monthly"), .monthly)
        XCTAssertEqual(MenuBarMode.monthly.label, "Left")
        XCTAssertEqual(MenuBarMode.month.label, "Month")
        XCTAssertEqual(MenuBarMode.allCases.map(\.rawValue), ["price", "tokens", "both", "month", "monthly"])
    }

    // MARK: - Analysis: the This month period and the cumulative series

    // "month" is the CLI's keyword and must reach it untouched; "Nd" periods
    // are still turned into a calendar date.
    func testMonthPeriodPassesThroughToTheCLI() {
        XCTAssertEqual(UsageModel.calendarSince("month"), "month")
    }

    private func row(_ key: String, usd: Double, tokens: Int) throws -> Row {
        let json = """
        {"key":"\(key)","records":1,"prompt_tokens":\(tokens),"output_tokens":0,"thoughts_tokens":0,
         "cached_tokens":0,"total_tokens":\(tokens),"cost_usd":\(usd)}
        """
        return try CLIJSON.decoder().decode(Row.self, from: Data(json.utf8))
    }

    func testCumulativePointsKeepRunningTotalAndTheDaysOwnShare() throws {
        let rows = [try row("2026-11-01", usd: 46.5, tokens: 100),
                    try row("2026-11-02", usd: 0, tokens: 0),      // a dense, idle day stays flat
                    try row("2026-11-03", usd: 3.5, tokens: 20)]
        typealias P = AnalysisView.CumulativePoint
        XCTAssertEqual(AnalysisView.cumulativePoints(rows, metric: .cost), [
            P(day: "2026-11-01", total: 46.5, added: 46.5),
            P(day: "2026-11-02", total: 46.5, added: 0),
            P(day: "2026-11-03", total: 50, added: 3.5),
        ])
        XCTAssertEqual(AnalysisView.cumulativePoints(rows, metric: .tokens).map(\.total), [100, 100, 120])
        XCTAssertEqual(AnalysisView.cumulativePoints([], metric: .cost), [])
    }

    // Sparse day,model rows become one point per model per day: zero before
    // a model's first call, carried forward across the days it was idle.
    func testCumulativeByModelFillsEveryDay() {
        typealias P = AnalysisView.DayModelPoint
        let days = ["d1", "d2", "d3"]
        let sparse = [P(id: "d1|a", day: "d1", model: "a", cost: 1, tokens: 10),
                      P(id: "d3|a", day: "d3", model: "a", cost: 2, tokens: 20),
                      P(id: "d2|b", day: "d2", model: "b", cost: 5, tokens: 50)]
        let got = AnalysisView.cumulativeByModel(days: days, points: sparse)
        XCTAssertEqual(got.map(\.id), ["d1|a", "d2|a", "d3|a", "d1|b", "d2|b", "d3|b"])
        XCTAssertEqual(got.map(\.cost), [1, 1, 3, 0, 5, 5])
        XCTAssertEqual(got.map(\.tokens), [10, 10, 30, 0, 50, 50])
        // The last day's stack is the period total.
        XCTAssertEqual(got.filter { $0.day == "d3" }.reduce(0) { $0 + $1.cost }, 8)
    }

    private func budget(costLimit: Double, tokenLimit: Double) -> BudgetStatus {
        func basis(_ limit: Double) -> BudgetBasis {
            BudgetBasis(limit: limit, used: 0, remaining: limit, percent: 0,
                        state: limit > 0 ? .normal : .unset, forecast: nil)
        }
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        return BudgetStatus(windowStart: start, windowEnd: start, nextReset: start, elapsedFraction: 0.5,
                            cost: basis(costLimit), tokens: basis(tokenLimit), partialRecords: 0)
    }

    // The limit is drawn only where the chart can be read against it: the
    // budget's own window, in the budget's own measure.
    func testBudgetLimitOnlyForThisMonthInTheSameMeasure() {
        let cost = budget(costLimit: 200, tokenLimit: 0)
        XCTAssertEqual(AnalysisView.budgetLimit(period: "month", metric: .cost, budget: cost), 200)
        XCTAssertNil(AnalysisView.budgetLimit(period: "month", metric: .tokens, budget: cost))
        XCTAssertNil(AnalysisView.budgetLimit(period: "30d", metric: .cost, budget: cost))
        let tokens = budget(costLimit: 0, tokenLimit: 1e8)
        XCTAssertEqual(AnalysisView.budgetLimit(period: "month", metric: .tokens, budget: tokens), 1e8)
        XCTAssertNil(AnalysisView.budgetLimit(period: "month", metric: .cost, budget: tokens))
        XCTAssertNil(AnalysisView.budgetLimit(period: "month", metric: .cost, budget: nil))
    }

    func testChartTitleNamesTheSeries() {
        XCTAssertEqual(DailyMetric.cost.title(.daily), "Daily cost (USD)")
        XCTAssertEqual(DailyMetric.cost.title(.cumulative), "Cumulative cost (USD)")
        XCTAssertEqual(DailyMetric.tokens.title(.cumulative), "Cumulative billed tokens (prompt + output + thoughts)")
    }
}
