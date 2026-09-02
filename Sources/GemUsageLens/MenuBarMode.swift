import Foundation

/// What the menu-bar item shows. Persisted via @AppStorage.
enum MenuBarMode: String, CaseIterable, Identifiable {
    case price    // today's cost, "$12.34"
    case tokens   // today's billed tokens, "277M"
    case both     // two rows: price over tokens
    case monthly  // monthly budget remaining, "$120 · 60%"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .price: return "Price"
        case .tokens: return "Tokens"
        case .both: return "Both"
        case .monthly: return "Monthly"
        }
    }
}
