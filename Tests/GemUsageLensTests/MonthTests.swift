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
}
