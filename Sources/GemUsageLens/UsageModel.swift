import Foundation
import UserNotifications

/// UsageModel drives the UI: it periodically ingests and pulls today's summary
/// for the menu-bar label + popover, asks the CLI for the monthly-budget state,
/// and loads the richer breakdowns for the analysis window on demand. All CLI
/// work runs off the main thread; @Published mutations are hopped back to main.
final class UsageModel: ObservableObject {
    @Published var todaySummary: Summary?
    @Published var last30USD: Double?        // actual last-30-days total (matches the analysis panel)
    @Published var last30Partial: Int = 0    // calls from pre-ADR-0057 transcripts in the last 30 days
    @Published var budget: BudgetStatus?     // monthly-budget monitor (nil = disabled/unavailable)
    @Published var lastError: String?        // short, user-facing summary
    @Published var lastErrorDetail: String?  // raw CLI output, shown smaller
    @Published var lastUpdated: Date?
    @Published var unpriced: UnpricedUsage?  // $0-but-billable calls in the last 30 days (nil = none)
    @Published var repricePhase: RepricePhase = .idle  // the Reprice button's own state, per badge episode

    private var lastNotifiedRank = 0         // highest state we've already notified, this window
    private var notifiedWindowStart: Date?   // the window that rank belongs to

    // Analysis window state
    @Published var period: String = "7d"
    @Published var periodSummary: Summary?
    @Published var dailyRows: [Row] = []
    @Published var dailyByModelRows: [Row] = []
    @Published var modelRows: [Row] = []
    @Published var projectRows: [Row] = []
    @Published var sourceRows: [Row] = []

    private var timer: Timer?
    private var activity: NSObjectProtocol?  // App Nap opt-out (retain for the app's lifetime)
    private let queue = DispatchQueue(label: "jp.nlink.gem-usage-lens-gui.cli", qos: .utility)
    private let notificationDelegate = ForegroundBannerDelegate()

    /// Today's cost as "$12.34" (menu-bar / popover).
    var todayPrice: String {
        if let s = todaySummary { return String(format: "$%.2f", s.totalUSD) }
        if lastError != nil { return "—" }
        return "…"
    }

    /// Today's billed tokens (prompt + output + thoughts) as "277M".
    var todayTokens: String {
        guard let s = todaySummary else { return lastError != nil ? "—" : "…" }
        return PopoverView.compact(s.totalTokens)
    }

    /// The monthly-remaining menu-bar label — the amount left plus the same
    /// figure as a share of the budget ("$116 · 58%"), since a bare amount says
    /// nothing about how much of the month it covers. Falls back to today's
    /// cost when the monitor is off.
    var monthlyRemainingLabel: String {
        guard let b = budget, let w = b.watched, let basis = b.watchedBasis else { return todayPrice }
        let amount: String
        switch basis {
        case .cost: amount = String(format: "$%.0f", w.remaining)   // menu bar: no cents
        case .tokens: amount = PopoverView.compact(Int(w.remaining))
        }
        return "\(amount) · \(Self.percentPair(w.percent).remaining)%"
    }

    // MARK: - Monthly budget

    /// Whole percents for display, derived as a pair so "42% used · 58% left"
    /// always sums to 100 — rounding the two independently would show 42/57.
    /// Over budget the used side keeps counting past 100 and the remainder
    /// pins at 0. Same rule as the CLI's PercentPair.
    static func percentPair(_ percent: Double) -> (used: Int, remaining: Int) {
        let used = max(0, Int((percent + 0.5).rounded(.down)))
        return (used, max(0, 100 - used))
    }

    /// Query the budget state for the current settings. nil when the monitor
    /// is off; a CLI error is surfaced through lastError by the caller.
    private func fetchBudget() throws -> BudgetStatus? {
        let s = BudgetSettings.current()
        guard s.enabled else { return nil }
        return try CLIRunner.budget(s)
    }

    /// Set the status, notifying once when severity rises — only `notify: true`
    /// (the periodic refresh), never while the user tunes settings. A new
    /// window (the 1st) resets the notified rank. Main thread.
    private func applyBudget(_ b: BudgetStatus?, notify: Bool) {
        budget = b
        if let b, notifiedWindowStart != b.windowStart {
            notifiedWindowStart = b.windowStart
            lastNotifiedRank = 0
        }
        let rank = b?.watched?.state.rank ?? 0
        if notify, BudgetSettings.current().notificationsEnabled,
           let b, let w = b.watched, let basis = b.watchedBasis, rank > lastNotifiedRank {
            notifyBudget(b, w, basis)
        }
        lastNotifiedRank = rank
    }

    /// Re-query the budget for changed settings (limit, basis, thresholds,
    /// enable). Background CLI call; no notification (user-initiated).
    func refreshBudget() {
        queue.async { [weak self] in
            guard let self else { return }
            let b = try? self.fetchBudget()
            DispatchQueue.main.async { self.applyBudget(b, notify: false) }
        }
    }

    /// Ask for notification permission at the moment the user turns the
    /// feature on — not when the first alert would fire, which may be never.
    func requestNotificationAuth() {
        let center = UNUserNotificationCenter.current()
        center.delegate = notificationDelegate
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if !granted || error != nil {
                let why = error?.localizedDescription ?? "not granted"
                FileHandle.standardError.write(Data("gem-usage-lens-gui: notifications \(why) — enable them in System Settings › Notifications\n".utf8))
            }
        }
    }

    private func notifyBudget(_ b: BudgetStatus, _ w: BudgetBasis, _ basis: BudgetBasisChoice) {
        let content = UNMutableNotificationContent()
        content.title = w.state == .critical ? "Monthly budget critical" : "Monthly budget warning"
        content.body = "Used \(Self.amount(w.used, basis)) of \(Self.amount(w.limit, basis)) "
            + "(\(Self.percentPair(w.percent).used)%). Resets \(Self.resetLabel(b.nextReset))."
        content.sound = .default
        let req = UNNotificationRequest(
            identifier: "monthly-\(w.state.rank)-\(Int(b.windowStart.timeIntervalSince1970))",
            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    /// Format an amount per basis: "$123.45" or a compact token count.
    static func amount(_ v: Double, _ basis: BudgetBasisChoice) -> String {
        basis == .cost ? String(format: "$%.2f", v) : PopoverView.compact(Int(v))
    }

    /// One-line answer to "am I going to blow through the budget?", from the
    /// CLI's pace forecast. nil when there is no projection to show; the
    /// early-window case says so out loud rather than going quiet.
    static func forecastLabel(_ w: BudgetBasis, _ basis: BudgetBasisChoice) -> String? {
        guard let f = w.forecast else { return nil }
        guard f.reliable else { return "Too early this month to project a pace" }
        let projected = "\(amount(f.projected, basis)) (\(Int(f.percent.rounded()))%)"
        if w.used >= w.limit { return "Over budget — on pace for \(projected)" }
        if let hit = f.exhaustionAt {
            return "On pace for \(projected) — budget gone \(resetLabel(hit))"
        }
        return "On pace for \(projected) by the reset"
    }

    /// SF Symbol for the pace line, matching `forecastLabel`.
    static func forecastIcon(_ w: BudgetBasis) -> String {
        guard let f = w.forecast, f.reliable else { return "clock" }
        switch f.state {
        case .critical: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle"
        case .normal, .unset: return "checkmark.circle"
        }
    }

    /// A short "Oct 1 00:00" label for a reset / exhaustion instant.
    static func resetLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d HH:mm"
        return f.string(from: d)
    }

    /// Turn a "Nd" period into a calendar start date (today − (N−1) days) as
    /// YYYY-MM-DD in `tz`, so a dense daily series spans exactly N calendar
    /// days aligned to the CLI's day buckets. Non-"Nd" periods pass through.
    static func calendarSince(_ period: String, from now: Date = Date(), tz: TimeZone = .current) -> String {
        guard period.hasSuffix("d"), let n = Int(period.dropLast()), n > 0 else { return period }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz
        let start = cal.date(byAdding: .day, value: -(n - 1), to: cal.startOfDay(for: now)) ?? now
        let f = DateFormatter()
        f.calendar = cal
        f.timeZone = tz
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: start)
    }

    func start() {
        SettingsKey.registerDefaults()
        // Opt out of App Nap so the refresh timer keeps firing while the app
        // sits in the menu bar (otherwise the menu-bar value freezes when macOS
        // naps this windowless background app). System sleep is allowed.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep], reason: "usage monitoring")
        let s = BudgetSettings.current()
        if s.enabled && s.notificationsEnabled { requestNotificationAuth() }
        refreshToday()
        // .common mode: keep ticking while a menu or popover is being tracked
        // — the moment the user is actually looking.
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refreshToday()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Ingest (keep the store fresh), then pull today's summary, the 30-day
    /// context and the budget state.
    func refreshToday() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try CLIRunner.ingest()
                let s = try CLIRunner.summary(since: "today")
                let last30 = try CLIRunner.summary(since: Self.calendarSince("30d"))
                let b = try self.fetchBudget()
                DispatchQueue.main.async {
                    self.todaySummary = s
                    self.last30USD = last30.totalUSD
                    self.last30Partial = last30.partialRecords ?? 0
                    self.unpriced = Self.unpricedUsage(last30)
                    // A cleared badge ends the episode: the next one starts
                    // with a fresh Reprice, whatever happened last time.
                    if self.unpriced == nil { self.repricePhase = .idle }
                    self.applyBudget(b, notify: true)
                    self.lastError = nil
                    self.lastErrorDetail = nil
                    self.lastUpdated = Date()
                }
            } catch {
                self.setError(error)
            }
        }
    }

    // MARK: - Unpriced usage

    /// Apply the bundled CLI's current rates to the stored history (`reprice`),
    /// then refresh. Every phase of the attempt is shown in the badge itself.
    func reprice() {
        DispatchQueue.main.async { self.repricePhase = .running }
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try CLIRunner.reprice()
                DispatchQueue.main.async { self.repricePhase = .done }
                self.refreshToday()
            } catch {
                let summary = (error as? LocalizedError)?.errorDescription ?? "\(error)"
                DispatchQueue.main.async { self.repricePhase = .failed(summary) }
            }
        }
    }

    /// The badge state from a summary: nil when nothing is unpriced (or the CLI
    /// predates the field), otherwise the count and its per-model split.
    static func unpricedUsage(_ s: Summary) -> UnpricedUsage? {
        guard let n = s.unpricedRecords, n > 0 else { return nil }
        return UnpricedUsage(records: n, models: s.unpricedModels ?? [:])
    }

    /// The badge's headline: how many calls, on what, are counted at $0.
    static func unpricedLabel(_ u: UnpricedUsage) -> String {
        let calls = u.records == 1 ? "1 call" : "\(u.records) calls"
        switch u.models.count {
        case 0: return "\(calls) counted at $0"
        case 1: return "\(calls) on \(u.models.keys.first!) counted at $0"
        default: return "\(calls) on \(u.models.count) models counted at $0"
        }
    }

    /// The badge's second line: the consequence and the way out, per phase.
    static func unpricedHint(phase: RepricePhase) -> String {
        switch phase {
        case .idle:
            return "Missing from every figure shown (last 30 days). Reprice applies the current rates to stored history."
        case .running:
            return "Repricing stored history…"
        case .done:
            return "Still unpriced after repricing: this build's rates don't know the model. Update the app, or price it in the CLI config and reprice again."
        case .failed(let reason):
            return "Reprice failed: \(reason)"
        }
    }

    /// The menu-bar text with a warning mark appended while unpriced usage
    /// exists, so an understated number is never shown as if it were complete.
    static func menuLabel(_ base: String, unpriced: Bool) -> String {
        unpriced ? base + " ⚠︎" : base
    }

    /// A one-line note for calls from pre-ADR-0057 transcripts in the window.
    static func partialLabel(_ n: Int) -> String? {
        guard n > 0 else { return nil }
        return "\(n) call\(n == 1 ? "" : "s") from older gem-agent transcripts — figures are a lower bound"
    }

    private func setError(_ error: Error) {
        let summary = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        let detail = (error as? CLIError)?.failureReason
        DispatchQueue.main.async { [weak self] in
            self?.lastError = summary
            self?.lastErrorDetail = detail
        }
    }

    /// Load the breakdowns for the analysis window over the current period.
    func loadAnalysis() {
        let period = self.period
        queue.async { [weak self] in
            do {
                let since = Self.calendarSince(period)
                let summary = try CLIRunner.summary(since: since)
                let daily = try CLIRunner.rows(groupBy: "day", since: since, dense: true)
                let dailyByModel = try CLIRunner.rows(groupBy: "day,model", since: since)
                let models = try CLIRunner.rows(groupBy: "model", since: since, sort: "cost")
                let projects = try CLIRunner.rows(groupBy: "project", since: since, sort: "cost", top: 8)
                let sources = try CLIRunner.rows(groupBy: "source", since: since, sort: "cost")
                DispatchQueue.main.async {
                    self?.periodSummary = summary
                    self?.dailyRows = daily
                    self?.dailyByModelRows = dailyByModel
                    self?.modelRows = models
                    self?.projectRows = projects
                    self?.sourceRows = sources
                    self?.lastError = nil
                    self?.lastErrorDetail = nil
                }
            } catch {
                self?.setError(error)
            }
        }
    }
}

/// Without a delegate, macOS suppresses banners while the app is frontmost
/// (which a menu-bar app briefly is while its popover or a window is open).
final class ForegroundBannerDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
