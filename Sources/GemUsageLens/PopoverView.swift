import AppKit
import SwiftUI

/// The dropdown shown when the menu-bar item is clicked: today's cost + tokens,
/// the last 30 days, the monthly budget, and buttons to open the analysis
/// window / settings / refresh / quit.
struct PopoverView: View {
    @EnvironmentObject var model: UsageModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("menuBarMode") private var menuBarMode: MenuBarMode = .price

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today").font(.headline)

            if let s = model.todaySummary {
                Text(String(format: "$%.2f", s.totalUSD))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
                    tokenRow("Prompt", s.promptTokens, note: s.cachedTokens > 0 ? "\(Self.compact(s.cachedTokens)) cached" : nil)
                    tokenRow("Output", s.outputTokens, note: nil)
                    tokenRow("Thoughts", s.thoughtsTokens, note: nil)
                    tokenRow("Billed", s.totalTokens, note: nil)
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Divider()
                HStack {
                    Text("Last 30 days").foregroundStyle(.secondary)
                    Spacer()
                    Text(model.last30USD.map { String(format: "$%.2f", $0) } ?? "—").monospacedDigit()
                }
                .font(.callout)
                if let note = UsageModel.partialLabel(model.last30Partial) {
                    Text(note)
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let alarm = UsageModel.checksumLabel(model.last30Checksum) {
                    Label(alarm, systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let u = model.unpriced {
                    unpricedSection(u)
                }

                // A failure after the first successful load (a budget query,
                // a later refresh) must not hide behind the stale numbers.
                if let err = model.lastError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption2).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let err = model.lastError {
                Label("Couldn't load usage", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(err)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = model.lastErrorDetail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }.frame(height: 60)
            }

            if let b = model.budget, let w = b.watched, let basis = b.watchedBasis {
                Divider()
                monthlySection(b, w, basis)
            }

            HStack {
                if let ts = model.lastUpdated {
                    Text("Updated \(ts.formatted(date: .omitted, time: .shortened))")
                }
                Spacer()
                // The only place the running build identifies itself.
                Text(AppVersion.current).textSelection(.enabled)
            }
            .font(.caption2).foregroundStyle(.tertiary)

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Menu bar").font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $menuBarMode) {
                    ForEach(MenuBarMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                Button("Analysis…") {
                    model.loadAnalysis()
                    openWindow(id: "analysis")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Button("Settings…") {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Refresh") { model.refreshToday() }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 300)
        // MenuBarExtra sizes the window to the content's ideal height; claim
        // the height this stack actually needs so nothing gets squeezed.
        .fixedSize(horizontal: false, vertical: true)
        // Always show fresh numbers when the popover is opened.
        .onAppear { model.refreshToday() }
    }

    /// Monthly-budget progress: used / limit, a colored bar, the used/left
    /// split in both amount and percent, the reset, and where the month is
    /// headed at the current pace.
    @ViewBuilder
    private func monthlySection(_ b: BudgetStatus, _ w: BudgetBasis, _ basis: BudgetBasisChoice) -> some View {
        let pair = UsageModel.percentPair(w.percent)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("This month").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Text("\(UsageModel.amount(w.used, basis)) / \(UsageModel.amount(w.limit, basis))")
                    .font(.callout).monospacedDigit()
                    .foregroundStyle(GemUsageLensApp.color(w.state) ?? .primary)
            }
            ProgressView(value: min(w.percent, 100), total: 100)
                .tint(GemUsageLensApp.color(w.state) ?? .accentColor)
            HStack {
                Text("\(pair.used)% used · \(UsageModel.amount(w.remaining, basis)) left (\(pair.remaining)%)")
                    .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Text("resets \(UsageModel.resetLabel(b.nextReset))").font(.caption2).foregroundStyle(.tertiary)
            }
            if let pace = UsageModel.forecastLabel(w, basis) {
                Label(pace, systemImage: UsageModel.forecastIcon(w))
                    .font(.caption2)
                    .foregroundStyle(Self.forecastColor(w))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            if let note = UsageModel.partialLabel(b.partialRecords) {
                Text(note).font(.caption2).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Calls the store holds at $0 although they should have cost something —
    /// the figures above understate by these. Names the count and the model,
    /// then offers the way out: Reprice, or an update.
    @ViewBuilder
    private func unpricedSection(_ u: UnpricedUsage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(UsageModel.unpricedLabel(u), systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top) {
                Text(UsageModel.unpricedHint(phase: model.repricePhase))
                    .font(.caption2)
                    .foregroundStyle(Self.hintColor(model.repricePhase))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Reprice") { model.reprice() }
                    .controlSize(.mini)
                    .disabled(model.repricePhase == .running)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.08)))
    }

    private static func hintColor(_ phase: RepricePhase) -> Color {
        if case .failed = phase { return .orange }
        return .secondary
    }

    /// Tint for the pace line: the projection's own severity, muted while the
    /// window is too young for the extrapolation to mean anything.
    static func forecastColor(_ w: BudgetBasis) -> Color {
        guard let f = w.forecast, f.reliable else { return .secondary }
        return GemUsageLensApp.color(f.state) ?? .secondary
    }

    private func tokenRow(_ label: String, _ n: Int, note: String?) -> some View {
        GridRow {
            Text(label)
            Spacer()
            HStack(spacing: 6) {
                if let note {
                    Text(note).font(.caption2).foregroundStyle(.tertiary)
                }
                Text(Self.compact(n)).monospacedDigit()
            }
            .gridColumnAlignment(.trailing)
        }
    }

    /// 1_234_567 → "1.2M", 12_345 → "12.3K".
    static func compact(_ n: Int) -> String {
        let v = Double(n)
        switch v {
        case 1_000_000...: return String(format: "%.1fM", v / 1_000_000)
        case 1_000...: return String(format: "%.1fK", v / 1_000)
        default: return "\(n)"
        }
    }
}
