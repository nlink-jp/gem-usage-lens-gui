import AppKit
import SwiftUI

struct GemUsageLensApp: App {
    @StateObject private var model = Self.makeModel()
    @AppStorage("menuBarMode") private var menuBarMode: MenuBarMode = .price

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(model)
        } label: {
            // The App holds `model` as a @StateObject and reads `menuBarMode`
            // via @AppStorage, so a change to either (incl. the budget state)
            // re-evaluates this label live.
            menuBarLabel
        }
        .menuBarExtraStyle(.window)

        Window("Usage Analysis", id: "analysis") {
            AnalysisView()
                .environmentObject(model)
                .frame(minWidth: 620, minHeight: 500)
        }
        .windowResizability(.contentMinSize)

        // A plain Window (not the Settings scene): a menu-bar (LSUIElement) app
        // can open + focus it reliably via openWindow + NSApp.activate, whereas
        // the Settings scene / SettingsLink often opens unfocused or not at all.
        Window("Monthly Budget", id: "settings") {
            SettingsView()
                .environmentObject(model)
        }
        .windowResizability(.contentSize)
    }

    /// Menu-bar content per the chosen display mode, tinted by the budget
    /// state (orange = warning, red = critical) so a low balance is visible
    /// regardless of what the label shows.
    @ViewBuilder
    private var menuBarLabel: some View {
        let state = model.budget?.watched?.state ?? .normal
        // A warning mark rides along while the store holds unpriced calls: the
        // number is then an undercount, and the popover says by how much.
        let unpriced = model.unpriced != nil
        switch menuBarMode {
        case .price:
            colored(Text(UsageModel.menuLabel(model.todayPrice, unpriced: unpriced)), Self.color(state))
        case .tokens:
            colored(Text(UsageModel.menuLabel(model.todayTokens, unpriced: unpriced)), Self.color(state))
        case .monthly:
            colored(Text(UsageModel.menuLabel(model.monthlyRemainingLabel, unpriced: unpriced)), Self.color(state))
        case .both:
            Image(nsImage: Self.twoLineImage(
                top: UsageModel.menuLabel(model.todayPrice, unpriced: unpriced), bottom: model.todayTokens,
                color: Self.menuNSColor(state)))
        }
    }

    @ViewBuilder
    private func colored(_ text: Text, _ color: Color?) -> some View {
        if let color { text.foregroundStyle(color) } else { text }
    }

    /// Menu-bar / popover tint for a budget state; nil = default.
    static func color(_ state: BudgetState) -> Color? {
        switch state {
        case .unset, .normal: return nil
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private static func menuNSColor(_ state: BudgetState) -> NSColor? {
        switch state {
        case .unset, .normal: return nil
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    /// Build the model and kick off its refresh loop at launch.
    private static func makeModel() -> UsageModel {
        let m = UsageModel()
        m.start()
        return m
    }

    /// Render two stacked, right-aligned lines to an NSImage sized to fit the
    /// menu bar. With no color it's a template image (auto-tints for light /
    /// dark); with a color (budget warning / critical) it's rendered in that
    /// tint.
    static func twoLineImage(top: String, bottom: String, color: NSColor? = nil) -> NSImage {
        let fg = color ?? .black
        let topFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let botFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

        let topPara = NSMutableParagraphStyle()
        topPara.alignment = .right
        topPara.minimumLineHeight = 10
        topPara.maximumLineHeight = 10
        topPara.paragraphSpacing = 3
        let botPara = NSMutableParagraphStyle()
        botPara.alignment = .right
        botPara.minimumLineHeight = 10
        botPara.maximumLineHeight = 10

        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: top + "\n", attributes: [
            .font: topFont, .paragraphStyle: topPara, .foregroundColor: fg,
        ]))
        s.append(NSAttributedString(string: bottom, attributes: [
            .font: botFont, .paragraphStyle: botPara, .foregroundColor: fg,
        ]))

        let bounds = s.size()
        let topMargin: CGFloat = 2
        let textH = ceil(bounds.height)
        let size = NSSize(width: ceil(bounds.width) + 2, height: textH + topMargin)
        let img = NSImage(size: size)
        img.lockFocus()
        s.draw(in: NSRect(x: 0, y: 0, width: size.width, height: textH))
        img.unlockFocus()
        img.isTemplate = (color == nil)
        return img
    }
}
