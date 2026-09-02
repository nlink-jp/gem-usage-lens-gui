import XCTest
@testable import GemUsageLens

/// The unpriced badge: calls the store holds at $0 that should have cost
/// something. Pure state → text rules, so the wording never goes silent.
final class UnpricedTests: XCTestCase {
    private func summary(unpriced: Int?, models: [String: Int]?) -> Summary {
        let base = """
        {"first_day":"2026-09-02","last_day":"2026-09-02","active_days":1,"records":1,
         "prompt_tokens":1,"output_tokens":1,"thoughts_tokens":0,"cached_tokens":0,"total_tokens":2,
         "total_usd":1,"daily_avg_usd":1,"peak_day":"2026-09-02","peak_usd":1,"projection_30d_usd":30
        """
        var extra = ""
        if let unpriced { extra += ",\"unpriced_records\":\(unpriced)" }
        if let models {
            let body = models.map { "\"\($0.key)\":\($0.value)" }.joined(separator: ",")
            extra += ",\"unpriced_models\":{\(body)}"
        }
        let data = (base + extra + "}").data(using: .utf8)!
        return try! CLIJSON.decoder().decode(Summary.self, from: data)
    }

    func testStateFromSummary() {
        XCTAssertNil(UsageModel.unpricedUsage(summary(unpriced: nil, models: nil)))
        XCTAssertNil(UsageModel.unpricedUsage(summary(unpriced: 0, models: [:])))
        XCTAssertEqual(UsageModel.unpricedUsage(summary(unpriced: 3, models: nil)),
                       UnpricedUsage(records: 3, models: [:]))
        XCTAssertEqual(UsageModel.unpricedUsage(summary(unpriced: 67, models: ["gemini-4-flash": 67])),
                       UnpricedUsage(records: 67, models: ["gemini-4-flash": 67]))
    }

    func testLabelNamesCountAndModel() {
        XCTAssertEqual(UsageModel.unpricedLabel(UnpricedUsage(records: 67, models: ["gemini-4-flash": 67])),
                       "67 calls on gemini-4-flash counted at $0")
        XCTAssertEqual(UsageModel.unpricedLabel(UnpricedUsage(records: 1, models: ["gemini-4-flash": 1])),
                       "1 call on gemini-4-flash counted at $0")
        XCTAssertEqual(UsageModel.unpricedLabel(UnpricedUsage(records: 5, models: ["a": 2, "b": 3])),
                       "5 calls on 2 models counted at $0")
        XCTAssertEqual(UsageModel.unpricedLabel(UnpricedUsage(records: 3, models: [:])),
                       "3 calls counted at $0")
    }

    func testHintNamesEveryPhaseAndItsWayOut() {
        let phases: [RepricePhase] = [.idle, .running, .done, .failed("gem-usage-lens crashed (exit 2)")]
        let hints = phases.map { UsageModel.unpricedHint(phase: $0) }
        XCTAssertTrue(hints.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(hints).count, hints.count)
        XCTAssertTrue(hints[0].contains("Reprice"))
        XCTAssertTrue(hints[1].contains("Repricing"))
        XCTAssertTrue(hints[2].contains("Update the app"))
        XCTAssertTrue(hints[3].contains("crashed (exit 2)"))
    }

    func testMenuLabelMark() {
        XCTAssertEqual(UsageModel.menuLabel("$12.34", unpriced: false), "$12.34")
        XCTAssertEqual(UsageModel.menuLabel("$12.34", unpriced: true), "$12.34 ⚠︎")
    }
}
