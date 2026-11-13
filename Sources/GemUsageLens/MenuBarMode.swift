import Foundation

/// What the menu-bar item shows. Persisted via @AppStorage.
enum MenuBarMode: String, CaseIterable, Identifiable {
    case price    // today's cost, "$12.34"
    case tokens   // today's billed tokens, "277M"
    case both     // two rows: price over tokens
    case month    // this calendar month's cost so far, "$76.42"
    case monthly  // monthly budget remaining, "$120 · 60%" (raw value kept from before `month` existed)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .price: return "Price"
        case .tokens: return "Tokens"
        case .both: return "Both"
        case .month: return "Month"
        // "Left", not "Monthly": beside "Month" (what was spent) the picker
        // has to say this one is what remains of the budget.
        case .monthly: return "Left"
        }
    }
}
