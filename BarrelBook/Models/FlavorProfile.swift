import Foundation
import SwiftUI

// Main flavor categories
enum FlavorCategory: String, CaseIterable, Codable {
    case fruity = "Fruity"
    case floral = "Floral"
    case spicy = "Spicy"
    case woody = "Woody"
    case sweet = "Sweet"
    case smoky = "Smoky"
    case nutty = "Nutty"
    case earthy = "Earthy"
    
    var color: Color {
        switch self {
        case .fruity: return Color(red: 0.8, green: 0.0, blue: 0.2) // Dark crimson red (AA compliant)
        case .floral: return Color(red: 0.7, green: 0.1, blue: 0.6) // Deep magenta (AA compliant)
        case .spicy: return Color(red: 0.8, green: 0.3, blue: 0.0) // Dark orange (AA compliant)
        case .woody: return Color(red: 0.4, green: 0.2, blue: 0.0) // Dark brown (AA compliant)
        case .sweet: return Color(red: 0.7, green: 0.6, blue: 0.0) // Dark gold (AA compliant)
        case .smoky: return Color(red: 0.2, green: 0.2, blue: 0.2) // Dark gray (AA compliant)
        case .nutty: return Color(red: 0.6, green: 0.3, blue: 0.0) // Dark amber (AA compliant)
        case .earthy: return Color(red: 0.1, green: 0.5, blue: 0.1) // Dark forest green (AA compliant)
        }
    }
    
    var subflavors: [String] {
        switch self {
        case .fruity:
            return ["Apple", "Pear", "Citrus", "Berry", "Stone Fruit", "Tropical"]
        case .floral:
            return ["Rose", "Lavender", "Honeysuckle", "Violet", "Orange Blossom"]
        case .spicy:
            return ["Cinnamon", "Clove", "Black Pepper", "Nutmeg", "Ginger"]
        case .woody:
            return ["Oak", "Cedar", "Pine", "Mahogany", "Sandalwood"]
        case .sweet:
            return ["Vanilla", "Caramel", "Honey", "Maple", "Toffee"]
        case .smoky:
            return ["Peat", "Charcoal", "Tobacco", "Leather", "Campfire"]
        case .nutty:
            return ["Almond", "Walnut", "Pecan", "Hazelnut", "Cashew"]
        case .earthy:
            return ["Mushroom", "Truffle", "Mineral", "Grass", "Hay"]
        }
    }
}

// Individual flavor intensity
struct FlavorIntensity: Codable {
    var category: FlavorCategory
    var intensity: Double // 0.0 to 1.0
    var selectedSubflavors: Set<String>
    
    init(category: FlavorCategory, intensity: Double = 0.0, selectedSubflavors: Set<String> = []) {
        self.category = category
        self.intensity = intensity
        self.selectedSubflavors = selectedSubflavors
    }
}

// Complete flavor profile for a tasting
struct FlavorProfile: Codable {
    var nose: [FlavorIntensity]
    var palate: [FlavorIntensity]
    var finish: [FlavorIntensity]
    
    init() {
        self.nose = FlavorCategory.allCases.map { FlavorIntensity(category: $0) }
        self.palate = FlavorCategory.allCases.map { FlavorIntensity(category: $0) }
        self.finish = FlavorCategory.allCases.map { FlavorIntensity(category: $0) }
    }
    
    // Helper to get intensity for a specific category and phase
    func intensity(for category: FlavorCategory, in phase: TastingPhase) -> Double {
        let intensities = phase == .nose ? nose : (phase == .palate ? palate : finish)
        return intensities.first { $0.category == category }?.intensity ?? 0.0
    }
    
    // Helper to get selected subflavors for a specific category and phase
    func subflavors(for category: FlavorCategory, in phase: TastingPhase) -> Set<String> {
        let intensities = phase == .nose ? nose : (phase == .palate ? palate : finish)
        return intensities.first { $0.category == category }?.selectedSubflavors ?? []
    }
}

// Tasting phases for the flavor wheel
enum TastingPhase: String, CaseIterable, Codable {
    case nose = "Nose"
    case palate = "Palate"
    case finish = "Finish"
} 