import XCTest
@testable import GemUsageLens

/// Contract tests against the CLI's `--json` shapes (gem-usage-lens v0.1).
final class DecodeTests: XCTestCase {
    func testDecodeRows() throws {
        let json = """
        [{"key":"gemini-3.7-flash","records":10,"prompt_tokens":1000,"output_tokens":50,
          "thoughts_tokens":20,"cached_tokens":600,"total_tokens":1070,"cost_usd":1.25,"partial_records":2}]
        """.data(using: .utf8)!
        let rows = try CLIJSON.decoder().decode([Row].self, from: json)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].id, "gemini-3.7-flash")
        XCTAssertEqual(rows[0].cachedTokens, 600)
        XCTAssertEqual(rows[0].totalTokens, 1070)
        XCTAssertEqual(rows[0].partialRecords, 2)
        XCTAssertEqual(rows[0].costUSD, 1.25, accuracy: 0.001)

        XCTAssertNil(rows[0].toolPromptTokens) // v0.1.0 row: field absent
        let v011 = """
        [{"key":"web_fetch","records":1,"prompt_tokens":1200,"output_tokens":900,"thoughts_tokens":40,
          "cached_tokens":0,"tool_prompt_tokens":7000,"total_tokens":9140,"cost_usd":0.01,"partial_records":0}]
        """.data(using: .utf8)!
        XCTAssertEqual(try CLIJSON.decoder().decode([Row].self, from: v011)[0].toolPromptTokens, 7000)
        // A row from an older CLI without partial_records still decodes.
        let old = """
        [{"key":"x","records":1,"prompt_tokens":1,"output_tokens":1,"thoughts_tokens":0,"cached_tokens":0,"total_tokens":2,"cost_usd":0.1}]
        """.data(using: .utf8)!
        XCTAssertNil(try CLIJSON.decoder().decode([Row].self, from: old)[0].partialRecords)
    }

    func testDecodeSummary() throws {
        let json = """
        {"first_day":"2026-09-01","last_day":"2026-09-03","active_days":2,"records":30,
         "prompt_tokens":150,"output_tokens":15,"thoughts_tokens":5,"cached_tokens":60,"total_tokens":170,
         "total_usd":1.5,"daily_avg_usd":0.75,"peak_day":"2026-09-01","peak_usd":1.0,"projection_30d_usd":22.5,
         "unpriced_records":1,"unpriced_models":{"gemini-99":1},"partial_records":3,"checksum_mismatches":0}
        """.data(using: .utf8)!
        let s = try CLIJSON.decoder().decode(Summary.self, from: json)
        XCTAssertEqual(s.activeDays, 2)
        XCTAssertEqual(s.totalTokens, 170)
        XCTAssertEqual(s.unpricedRecords, 1)
        XCTAssertEqual(s.unpricedModels, ["gemini-99": 1])
        XCTAssertEqual(s.partialRecords, 3)

        // A summary from a CLI that predates the optional fields still decodes.
        let minimal = """
        {"first_day":"","last_day":"","active_days":0,"records":0,"prompt_tokens":0,"output_tokens":0,
         "thoughts_tokens":0,"cached_tokens":0,"total_tokens":0,"total_usd":0,"daily_avg_usd":0,
         "peak_day":"","peak_usd":0,"projection_30d_usd":0}
        """.data(using: .utf8)!
        let m = try CLIJSON.decoder().decode(Summary.self, from: minimal)
        XCTAssertNil(m.unpricedRecords)
        XCTAssertNil(m.partialRecords)
    }

    func testDecodeBudgetStatus() throws {
        let json = """
        {"window_start":"2026-09-01T00:00:00+09:00","window_end":"2026-10-01T00:00:00+09:00",
         "next_reset":"2026-10-01T00:00:00+09:00","elapsed_fraction":0.5,
         "cost":{"limit":200,"used":150,"remaining":50,"percent":75,"state":"normal",
                 "forecast":{"projected":300,"percent":150,"exhaustion_at":"2026-09-21T00:00:00+09:00","reliable":true,"state":"critical"}},
         "tokens":{"limit":0,"used":123456,"remaining":0,"percent":0,"state":"unset","forecast":null},
         "partial_records":2}
        """.data(using: .utf8)!
        let b = try CLIJSON.decoder().decode(BudgetStatus.self, from: json)
        XCTAssertEqual(b.windowEnd.timeIntervalSince(b.windowStart), 30 * 86_400, accuracy: 1)
        XCTAssertEqual(b.cost.state, .normal)
        XCTAssertEqual(b.cost.forecast?.state, .critical)
        XCTAssertNotNil(b.cost.forecast?.exhaustionAt)
        XCTAssertEqual(b.tokens.state, .unset)
        XCTAssertNil(b.tokens.forecast)
        XCTAssertEqual(b.partialRecords, 2)
        XCTAssertEqual(b.watched, b.cost)
        XCTAssertEqual(b.watchedBasis, .cost)
    }

    func testDecodeToleratesFractionalSeconds() throws {
        let json = """
        {"window_start":"2026-09-01T00:00:00.123456+09:00","window_end":"2026-10-01T00:00:00+09:00",
         "next_reset":"2026-10-01T00:00:00+09:00","elapsed_fraction":0.1,
         "cost":{"limit":0,"used":0,"remaining":0,"percent":0,"state":"unset","forecast":null},
         "tokens":{"limit":0,"used":0,"remaining":0,"percent":0,"state":"unset","forecast":null},
         "partial_records":0}
        """.data(using: .utf8)!
        let b = try CLIJSON.decoder().decode(BudgetStatus.self, from: json)
        XCTAssertNil(b.watched)
        XCTAssertNil(b.watchedBasis)
    }

    func testCompactFormatting() {
        XCTAssertEqual(PopoverView.compact(500), "500")
        XCTAssertEqual(PopoverView.compact(12_345), "12.3K")
        XCTAssertEqual(PopoverView.compact(1_234_567), "1.2M")
    }

    func testAxisDayLabels() {
        let week = (1...7).map { String(format: "2026-09-%02d", $0) }
        XCTAssertEqual(AnalysisView.axisDayLabels(week), week)
        let quarter = (1...90).map { String(format: "d%02d", $0) }
        let thinned = AnalysisView.axisDayLabels(quarter, maxLabels: 12)
        XCTAssertLessThanOrEqual(thinned.count, 14)
        XCTAssertGreaterThan(thinned.count, 8)
        XCTAssertEqual(thinned.first, quarter.first)
        XCTAssertEqual(thinned.last, quarter.last)
    }

    func testUniqueShortLabels() {
        let keys = [
            "/Users/you/src/example-org/util-series/gem-agent",
            "/Users/you/src/example-org/_wip/gem-agent",
            "/Users/you/src/example-org",
            "gemini-3.7-flash",
            "web_search",
        ]
        let labels = AnalysisView.uniqueShortLabels(keys)
        XCTAssertEqual(labels[keys[0]], "util-series/gem-agent")
        XCTAssertEqual(labels[keys[1]], "_wip/gem-agent")
        XCTAssertEqual(labels[keys[2]], "example-org")
        XCTAssertEqual(labels[keys[3]], "gemini-3.7-flash")
        XCTAssertEqual(labels[keys[4]], "web_search")
        XCTAssertEqual(Set(labels.values).count, keys.count)
    }

    func testShortDay() {
        XCTAssertEqual(AnalysisView.shortDay("2026-09-05"), "09-05")
        XCTAssertEqual(AnalysisView.shortDay("unknown"), "unknown")
    }

    func testCalendarSince() {
        let utc = TimeZone(identifier: "UTC")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 18))!
        XCTAssertEqual(UsageModel.calendarSince("7d", from: now, tz: utc), "2026-08-30")
        XCTAssertEqual(UsageModel.calendarSince("1d", from: now, tz: utc), "2026-09-05")
        XCTAssertEqual(UsageModel.calendarSince("today", from: now, tz: utc), "today")
        let jst = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(UsageModel.calendarSince("1d", from: now, tz: jst), "2026-09-06")
    }
}

/// The version shown in the popover — a menu-bar app's only way to say which
/// build it is.
final class AppVersionTests: XCTestCase {
    func testShownVerbatim() {
        XCTAssertEqual(AppVersion.display("v0.1.0"), "v0.1.0")
        XCTAssertEqual(AppVersion.display("v0.1.0-3-gabc1234"), "v0.1.0-3-gabc1234")
        XCTAssertEqual(AppVersion.display("v0.1.0-dirty"), "v0.1.0-dirty")
    }

    func testFallsBackToDev() {
        XCTAssertEqual(AppVersion.display(nil), "dev")
        XCTAssertEqual(AppVersion.display(""), "dev")
        XCTAssertEqual(AppVersion.display("${VERSION}"), "dev")
    }
}
