import AppKit
import SwiftUI

/// Monthly-budget settings ("Settings…" in the popover). Binds the
/// UserDefaults keys via @AppStorage; UsageModel reads the same keys and
/// hands them to the CLI's `budget` command, which does the arithmetic.
struct SettingsView: View {
    @EnvironmentObject var model: UsageModel

    // Mirrors SMAppService; refreshed on appear and after every change.
    @State private var launchAtLogin = LoginItem.isOn(LoginItem.current)
    @State private var loginItemMessage: String?

    @AppStorage(SettingsKey.budgetEnabled) private var enabled = false
    @AppStorage(SettingsKey.budgetBasis) private var basisRaw = BudgetBasisChoice.cost.rawValue
    @AppStorage(SettingsKey.budgetCost) private var limitCost = 100.0
    @AppStorage(SettingsKey.budgetTokens) private var limitTokens = 100_000_000.0
    @AppStorage(SettingsKey.warnPercent) private var warnPercent = 80.0
    @AppStorage(SettingsKey.criticalPercent) private var criticalPercent = 95.0
    @AppStorage(SettingsKey.notificationsEnabled) private var notificationsEnabled = true

    private var basis: BudgetBasisChoice { BudgetBasisChoice(rawValue: basisRaw) ?? .cost }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        // Ignore the echo of our own read-back below.
                        guard on != LoginItem.isOn(LoginItem.current) else { return }
                        loginItemMessage = LoginItem.setEnabled(on)
                        launchAtLogin = LoginItem.isOn(LoginItem.current)
                    }
                if let msg = loginItemMessage {
                    HStack(alignment: .top) {
                        Text(msg).font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Open Login Items") { NSWorkspace.shared.open(LoginItem.settingsURL) }
                            .controlSize(.small)
                    }
                }
            }

            Section {
                Toggle("Monitor monthly budget", isOn: $enabled)
                    .onChange(of: enabled) { _, on in
                        if on && notificationsEnabled { model.requestNotificationAuth() }
                        model.refreshBudget()
                    }
                Text("Warns as you approach the limit for the calendar month. The month resets on the 1st at 00:00 local time — Vertex AI bills monthly, and there is no rolling quota to calibrate against.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Show notifications", isOn: $notificationsEnabled)
                    .disabled(!enabled)
                    .onChange(of: notificationsEnabled) { _, on in
                        if on && enabled { model.requestNotificationAuth() }
                    }
                Text("Off = colour/bar only, no system notifications.")
                    .font(.caption).foregroundStyle(.secondary)
                if enabled && notificationsEnabled && model.notificationsDenied {
                    // The toggle is ON but macOS will deliver nothing: say so,
                    // and open the only place that can change it.
                    HStack {
                        Text("Notifications are turned off for this app in System Settings.")
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Open Settings") { NSWorkspace.shared.open(UsageModel.notificationSettingsURL) }
                            .controlSize(.small)
                    }
                }
            }

            Section("Budget") {
                Picker("Measure by", selection: $basisRaw) {
                    ForEach(BudgetBasisChoice.allCases) { Text($0.label).tag($0.rawValue) }
                }
                if basis == .cost {
                    TextField("Monthly limit ($)", value: $limitCost, format: .number)
                } else {
                    TextField("Monthly limit (billed tokens)", value: $limitTokens, format: .number)
                }
                Text("Costs are the Vertex AI list price applied to gem-agent's own token counts — a notional figure, not the bill.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!enabled)

            Section("Warning thresholds") {
                Stepper("Warning at \(Int(warnPercent))%", value: $warnPercent, in: 1...100, step: 5)
                Stepper("Critical at \(Int(criticalPercent))%", value: $criticalPercent, in: 1...100, step: 5)
                if warnPercent > criticalPercent {
                    Text("Warning must not exceed critical.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            .disabled(!enabled)

            if enabled, let b = model.budget, let w = b.watched, let wb = b.watchedBasis {
                Section("Current") {
                    let pair = UsageModel.percentPair(w.percent)
                    LabeledContent("This month",
                        value: "\(UsageModel.amount(w.used, wb)) / \(UsageModel.amount(w.limit, wb))  (\(pair.used)%)")
                    LabeledContent("Remaining",
                        value: "\(UsageModel.amount(w.remaining, wb))  (\(pair.remaining)%)")
                    LabeledContent("Resets", value: UsageModel.resetLabel(b.nextReset))
                    if let pace = UsageModel.forecastLabel(w, wb) {
                        LabeledContent("At this pace", value: pace)
                    }
                }
            } else if enabled, let err = model.lastError {
                Section("Current") {
                    Text(err).font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = LoginItem.isOn(LoginItem.current) }
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
        // Every knob is a CLI flag: re-query the budget on change (cheap, and
        // it keeps the arithmetic in one place).
        .onChange(of: basisRaw) { _, _ in model.refreshBudget() }
        .onChange(of: limitCost) { _, _ in model.refreshBudget() }
        .onChange(of: limitTokens) { _, _ in model.refreshBudget() }
        .onChange(of: warnPercent) { _, _ in model.refreshBudget() }
        .onChange(of: criticalPercent) { _, _ in model.refreshBudget() }
    }
}
