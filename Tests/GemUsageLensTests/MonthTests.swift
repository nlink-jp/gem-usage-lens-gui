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
}
