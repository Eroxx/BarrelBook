import Foundation

enum WhiskeyRarity: String, CaseIterable, Identifiable {
    case notSure = "not_sure"
    case common = "common"
    case uncommon = "uncommon"
    case rare = "rare"
    case unicorn = "unicorn"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .notSure:
            return "Not Sure"
        case .common:
            return "Common"
        case .uncommon:
            return "Uncommon"
        case .rare:
            return "Rare"
        case .unicorn:
            return "Unicorn"
        }
    }
    
    // Sort order for rarity (higher number = more rare)
    // Not Sure < 1 < 2 < 3 < 4
    var sortOrder: Int {
        switch self {
        case .notSure:
            return 0  // Not Sure (when people don't know the rarity)
        case .common:
            return 1  // Rarity level 1
        case .uncommon:
            return 2  // Rarity level 2
        case .rare:
            return 3  // Rarity level 3
        case .unicorn:
            return 4  // Rarity level 4
        }
    }
} 