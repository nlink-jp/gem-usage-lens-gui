import Charts
import SwiftUI

/// Which metric the daily chart plots. Persisted via @AppStorage.
enum DailyMetric: String, CaseIterable, Identifiable {
    case cost, tokens
    var id: String { rawValue }
    var label: String { self == .cost ? "Cost" : "Tokens" }
    var title: String { self == .cost ? "Daily cost (USD)" : "Daily billed tokens (prompt + output + thoughts)" }

    /// The plotted value for a row.
    func value(_ r: Row) -> Double {
        switch self {
        case .cost: return r.costUSD
        case .tokens: return Double(r.totalTokens)
        }
    }

    /// A compact y-axis label for a tick value.
    func axisLabel(_ d: Double) -> String {
        switch self {
        case .cost: return d >= 1000 ? "$" + PopoverView.compact(Int(d)) : String(format: "$%.0f", d)
        case .tokens: return PopoverView.compact(Int(d))
        }
    }
}

/// The expanded analysis window: daily cost trend, per-model / per-source /
/// top-project breakdowns, over a selectable period. Data comes from the
/// CLI's report --json.
struct AnalysisView: View {
    @EnvironmentObject var model: UsageModel
    @AppStorage("dailyMetric") private var dailyMetric: DailyMetric = .cost
    @AppStorage("stackByModel") private var stackByModel = false
    @State private var hoverKey: String?
    @State private var hoverPoint: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > 700
            VStack(spacing: 14) {
                periodHeader

                dailyBox
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                breakdowns(wide: wide)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let err = model.lastError {
                    Text(err).font(.caption).foregroundStyle(.orange).lineLimit(3)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Period", selection: $model.period) {
                    Text("7 days").tag("7d")
                    Text("30 days").tag("30d")
                    Text("90 days").tag("90d")
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Button { model.loadAnalysis() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
        .onChange(of: model.period) { _, _ in model.loadAnalysis() }
        .onAppear { model.loadAnalysis() }
    }

    // MARK: - Period total

    private var periodHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(periodLabel).font(.headline)
            if let s = model.periodSummary, let note = UsageModel.partialLabel(s.partialRecords ?? 0) {
                Text(note).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if let s = model.periodSummary {
                Text("\(PopoverView.compact(s.totalTokens)) billed tokens")
                    .font(.callout).foregroundStyle(.secondary)
                Text(String(format: "$%.2f", s.totalUSD))
                    .font(.title3.weight(.semibold)).monospacedDigit()
            }
        }
    }

    private var periodLabel: String {
        if model.period.hasSuffix("d"), let n = Int(model.period.dropLast()) {
            return "Last \(n) days"
        }
        return "Selected period"
    }

    // MARK: - Boxes

    private var dailyBox: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text(dailyMetric.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("By model", isOn: $stackByModel)
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                    Picker("", selection: $dailyMetric) {
                        ForEach(DailyMetric.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .controlSize(.small)
                }
                .padding(.bottom, 2)
                dailyChart
            }
        }
    }

    @ViewBuilder
    private var dailyChart: some View {
        if model.dailyRows.isEmpty {
            emptyChart
        } else if stackByModel {
            stackedChart
        } else {
            totalChart
        }
    }

    /// Contiguous daily totals (dense), with a cursor-following hover tooltip.
    private var totalChart: some View {
        Chart {
            ForEach(model.dailyRows) { row in
                BarMark(
                    x: .value("Day", row.key),
                    y: .value(dailyMetric.label, dailyMetric.value(row))
                )
                .foregroundStyle(Color.accentColor.gradient)
                .opacity(hoverKey == nil || hoverKey == row.key ? 1 : 0.35)
            }
            if let key = hoverKey {
                RuleMark(x: .value("Day", key))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXAxis { dayAxis(model.dailyRows.map(\.key)) }
        .chartYAxis { metricYAxis }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            guard let plot = proxy.plotFrame else { clearHover(); return }
                            let x = point.x - geo[plot].minX
                            if let key: String = proxy.value(atX: x, as: String.self) {
                                hoverKey = key
                                hoverPoint = point
                            }
                        case .ended:
                            clearHover()
                        }
                    }
                if let key = hoverKey,
                   let row = model.dailyRows.first(where: { $0.key == key }),
                   let pt = hoverPoint {
                    tooltip(row)
                        .fixedSize()
                        .position(Self.tooltipPosition(near: pt, in: geo.size))
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Each day's bar split into per-model segments (day,model composite).
    private var stackedChart: some View {
        let days = model.dailyRows.map(\.key)
        let ranked = rankedModels()
        let rank = Dictionary(uniqueKeysWithValues: ranked.enumerated().map { ($1, $0) })
        let points = dailyByModelPoints.sorted {
            $0.day != $1.day ? $0.day < $1.day : (rank[$0.model] ?? 0) < (rank[$1.model] ?? 0)
        }
        return Chart {
            ForEach(points) { p in
                BarMark(
                    x: .value("Day", p.day),
                    y: .value(dailyMetric.label, dailyMetric == .cost ? p.cost : p.tokens)
                )
                .foregroundStyle(by: .value("Model", p.model))
                .opacity(hoverKey == nil || hoverKey == p.day ? 1 : 0.3)
            }
            if let key = hoverKey {
                RuleMark(x: .value("Day", key))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartForegroundStyleScale(domain: ranked)
        .chartXScale(domain: days)
        .chartXAxis { dayAxis(days) }
        .chartYAxis { metricYAxis }
        .chartLegend(position: .bottom, spacing: 8)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            guard let plot = proxy.plotFrame else { clearHover(); return }
                            let x = point.x - geo[plot].minX
                            if let key: String = proxy.value(atX: x, as: String.self) {
                                hoverKey = key
                                hoverPoint = point
                            }
                        case .ended:
                            clearHover()
                        }
                    }
                if let key = hoverKey, let pt = hoverPoint {
                    let pts = dailyByModelPoints.filter { $0.day == key }
                    stackTooltip(day: key, points: pts)
                        .fixedSize()
                        .position(Self.tooltipPosition(near: pt, in: geo.size, tip: CGSize(width: 200, height: 170)))
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stackTooltip(day: String, points: [DayModelPoint]) -> some View {
        let sorted = points.sorted { metricOf($0) > metricOf($1) }
        return VStack(alignment: .leading, spacing: 3) {
            Text(day).font(.caption.bold())
            if points.isEmpty {
                Text("no activity").font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(sorted) { p in
                    HStack(spacing: 10) {
                        Text(p.model).font(.caption2)
                        Spacer()
                        Text(metricString(metricOf(p))).font(.caption2).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Divider()
                HStack(spacing: 10) {
                    Text("Total").font(.caption2.bold())
                    Spacer()
                    Text(metricString(points.reduce(0) { $0 + metricOf($1) }))
                        .font(.caption2.bold()).monospacedDigit()
                }
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.regularMaterial))
        .shadow(radius: 2)
        .frame(minWidth: 130)
    }

    private func metricOf(_ p: DayModelPoint) -> Double { dailyMetric == .cost ? p.cost : p.tokens }

    private func rankedModels() -> [String] {
        var total: [String: Double] = [:]
        for p in dailyByModelPoints { total[p.model, default: 0] += metricOf(p) }
        return total.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }.map(\.key)
    }

    private func metricString(_ v: Double) -> String {
        dailyMetric == .cost ? String(format: "$%.2f", v) : PopoverView.compact(Int(v))
    }

    private func clearHover() {
        hoverKey = nil
        hoverPoint = nil
    }

    @AxisContentBuilder
    private func dayAxis(_ keys: [String]) -> some AxisContent {
        AxisMarks(values: Self.axisDayLabels(keys)) { value in
            AxisGridLine()
            AxisTick()
            if let key = value.as(String.self) {
                AxisValueLabel(Self.shortDay(key), orientation: .vertical)
            }
        }
    }

    @AxisContentBuilder
    private var metricYAxis: some AxisContent {
        AxisMarks { value in
            AxisGridLine()
            if let d = value.as(Double.self) {
                AxisValueLabel(dailyMetric.axisLabel(d))
            }
        }
    }

    /// Hover tooltip: the day plus its cost, billed tokens, and call count.
    private func tooltip(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.key).font(.caption.bold())
            Text(String(format: "$%.2f", row.costUSD)).font(.caption).monospacedDigit()
            Text("\(PopoverView.compact(row.totalTokens)) billed tokens")
                .font(.caption2).foregroundStyle(.secondary)
            Text("\(row.records) calls").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 6).fill(.regularMaterial))
        .shadow(radius: 2)
        .fixedSize()
    }

    @ViewBuilder
    private func breakdowns(wide: Bool) -> some View {
        if wide {
            HStack(spacing: 14) { modelBox; sourceBox; projectBox }
        } else {
            VStack(spacing: 14) { modelBox; sourceBox; projectBox }
        }
    }

    private var modelBox: some View {
        GroupBox("By model") { barList(model.modelRows) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sourceBox: some View {
        GroupBox("By call source") { barList(model.sourceRows) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var projectBox: some View {
        GroupBox("Top projects") { barList(model.projectRows) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Charts

    @ViewBuilder
    private func barList(_ rows: [Row]) -> some View {
        if rows.isEmpty {
            emptyChart
        } else {
            let labels = Self.uniqueShortLabels(rows.map(\.key))
            Chart(rows) { row in
                BarMark(
                    x: .value("Cost", row.costUSD),
                    y: .value("Item", row.key)
                )
                .foregroundStyle(Color.accentColor.gradient)
                .annotation(position: .trailing) {
                    Text(String(format: "$%.2f", row.costUSD))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    if let k = value.as(String.self) {
                        AxisValueLabel(labels[k] ?? k)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyChart: some View {
        HStack { Spacer(); Text("No data").foregroundStyle(.secondary); Spacer() }
            .frame(maxWidth: .infinity, minHeight: 80, maxHeight: .infinity)
    }

    static func lastPathComponent(_ p: String) -> String {
        (p as NSString).lastPathComponent.isEmpty ? p : (p as NSString).lastPathComponent
    }

    /// Map each key to a short axis label: its basename, or "parent/basename"
    /// when two keys would otherwise share the same basename. Non-path keys
    /// (model ids, sources) pass through.
    static func uniqueShortLabels(_ keys: [String]) -> [String: String] {
        var baseCount: [String: Int] = [:]
        for k in keys { baseCount[lastPathComponent(k), default: 0] += 1 }
        var out: [String: String] = [:]
        for k in keys {
            let base = lastPathComponent(k)
            out[k] = (baseCount[base] ?? 0) > 1 ? lastTwoComponents(k) : base
        }
        return out
    }

    /// "/a/b/c" → "b/c"; fewer than two components → the basename.
    static func lastTwoComponents(_ p: String) -> String {
        let parts = (p as NSString).pathComponents.filter { $0 != "/" }
        guard parts.count >= 2 else { return lastPathComponent(p) }
        return parts[parts.count - 2] + "/" + parts[parts.count - 1]
    }

    // MARK: - Stacked (by model) data

    struct DayModelPoint: Identifiable {
        let id: String
        let day: String
        let model: String
        let cost: Double
        let tokens: Double
    }

    /// Split the "day|model" composite rows into typed points for stacking.
    private var dailyByModelPoints: [DayModelPoint] {
        model.dailyByModelRows.map { r in
            let parts = r.key.split(separator: "|", maxSplits: 1).map(String.init)
            return DayModelPoint(
                id: r.key,
                day: parts.first ?? r.key,
                model: parts.count > 1 ? parts[1] : "unknown",
                cost: r.costUSD,
                tokens: Double(r.totalTokens)
            )
        }
    }

    /// Place the hover tooltip near the cursor and clamp it inside `size`.
    static func tooltipPosition(near pt: CGPoint, in size: CGSize,
                                tip: CGSize = CGSize(width: 150, height: 86)) -> CGPoint {
        let w = tip.width, h = tip.height
        let gap: CGFloat = 14, margin: CGFloat = 6
        var cx = pt.x + gap + w / 2
        if cx + w / 2 > size.width - margin { cx = pt.x - gap - w / 2 }
        cx = min(max(cx, w / 2 + margin), size.width - w / 2 - margin)
        var cy = pt.y - gap - h / 2
        cy = min(max(cy, h / 2 + margin), size.height - h / 2 - margin)
        return CGPoint(x: cx, y: cy)
    }

    /// A readable subset of day keys for the x-axis: ~`maxLabels` evenly
    /// spaced labels, always keeping the first and last.
    static func axisDayLabels(_ keys: [String], maxLabels: Int = 12) -> [String] {
        guard keys.count > maxLabels else { return keys }
        let step = Int(ceil(Double(keys.count) / Double(maxLabels)))
        var picked: [String] = []
        var i = 0
        while i < keys.count {
            picked.append(keys[i])
            i += step
        }
        if let last = keys.last, picked.last != last {
            picked.append(last)
        }
        return picked
    }

    /// "2026-09-05" → "09-05"; anything not a Y-M-D key is left unchanged.
    static func shortDay(_ key: String) -> String {
        let parts = key.split(separator: "-")
        return parts.count == 3 ? "\(parts[1])-\(parts[2])" : key
    }
}
