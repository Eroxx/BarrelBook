import Foundation
import SwiftUI

// Utility class to manage filter persistence
class FilterSettingsManager {
    // UserDefaults keys
    private static let currentSortKey = "currentSort"
    private static let selectedTypesKey = "selectedTypes" // New key for type persistence
    // Three-state toggles keys
    private static let bibStateKey = "bibState"
    private static let sibStateKey = "sibState"
    private static let storePickStateKey = "storePickState"
    private static let openStateKey = "openState"
    private static let finishStateKey = "finishState"
    private static let deadBottleStateKey = "deadBottleState"
    private static let reviewStateKey = "reviewState"
    private static let tastedStateKey = "tastedState"
    // Legacy keys (kept for backwards compatibility)
    private static let bibEnabledKey = "bibEnabled"
    private static let sibEnabledKey = "sibEnabled"
    private static let storePickEnabledKey = "storePickEnabled"
    private static let priceRangeOptionKey = "priceRangeOption"
    private static let customMinPriceKey = "customMinPrice"
    private static let customMaxPriceKey = "customMaxPrice"
    private static let minProofKey = "minProof"
    private static let maxProofKey = "maxProof"
    
    // MARK: - Privacy Settings
    private static let hidePricesKey = "hidePrices"
    
    // Save current sort option
    static func saveCurrentSort(_ sort: SortOption) {
        UserDefaults.standard.set(sort.rawValue, forKey: currentSortKey)
    }
    
    // Load current sort option
    static func loadCurrentSort() -> SortOption {
        if let savedSortString = UserDefaults.standard.string(forKey: currentSortKey),
           let savedSort = SortOption.allCases.first(where: { $0.rawValue == savedSortString }) {
            return savedSort
        }
        return .nameAsc
    }
    
    // Save filter options
    static func saveFilterOptions(_ options: FilterOptions) {
        // Save selected types
        let typesArray = Array(options.selectedTypes)
        UserDefaults.standard.set(typesArray, forKey: selectedTypesKey)
        
        // Save three-state toggles
        UserDefaults.standard.set(options.bibState.rawValue, forKey: bibStateKey)
        UserDefaults.standard.set(options.sibState.rawValue, forKey: sibStateKey)
        UserDefaults.standard.set(options.storePickState.rawValue, forKey: storePickStateKey)
        UserDefaults.standard.set(options.openState.rawValue, forKey: openStateKey)
        UserDefaults.standard.set(options.finishState.rawValue, forKey: finishStateKey)
        UserDefaults.standard.set(options.deadBottleState.rawValue, forKey: deadBottleStateKey)
        UserDefaults.standard.set(options.reviewState.rawValue, forKey: reviewStateKey)
        UserDefaults.standard.set(options.tastedState.rawValue, forKey: tastedStateKey)
        
        // Save legacy boolean filters (for backwards compatibility)
        UserDefaults.standard.set(options.isBiB, forKey: bibEnabledKey)
        UserDefaults.standard.set(options.isSiB, forKey: sibEnabledKey)
        UserDefaults.standard.set(options.isStorePick, forKey: storePickEnabledKey)
        
        // Save price range option
        UserDefaults.standard.set(options.priceRangeOption.rawValue, forKey: priceRangeOptionKey)
        
        // Save custom price range if it exists
        if let customPriceRange = options.customPriceRange {
            UserDefaults.standard.set(customPriceRange.lowerBound, forKey: customMinPriceKey)
            UserDefaults.standard.set(customPriceRange.upperBound, forKey: customMaxPriceKey)
        } else {
            // Clear custom price range
            UserDefaults.standard.removeObject(forKey: customMinPriceKey)
            UserDefaults.standard.removeObject(forKey: customMaxPriceKey)
        }
        
        // Save proof range if it exists
        if let proofRange = options.proofRange {
            UserDefaults.standard.set(proofRange.lowerBound, forKey: minProofKey)
            UserDefaults.standard.set(proofRange.upperBound, forKey: maxProofKey)
        } else {
            // Clear proof range
            UserDefaults.standard.removeObject(forKey: minProofKey)
            UserDefaults.standard.removeObject(forKey: maxProofKey)
        }
    }
    
    // Load filter options
    static func loadFilterOptions() -> FilterOptions {
        var options = FilterOptions()
        
        // Load selected types
        if let savedTypes = UserDefaults.standard.array(forKey: selectedTypesKey) as? [String] {
            options.selectedTypes = Set(savedTypes)
        }
        
        // Load three-state toggles with fallback to legacy boolean values
        if let bibState = UserDefaults.standard.string(forKey: bibStateKey),
           let state = ToggleState.allCases.first(where: { $0.rawValue == bibState }) {
            options.bibState = state
        } else {
            // Fallback to legacy boolean value
            options.isBiB = UserDefaults.standard.bool(forKey: bibEnabledKey)
        }
        
        if let sibState = UserDefaults.standard.string(forKey: sibStateKey),
           let state = ToggleState.allCases.first(where: { $0.rawValue == sibState }) {
            options.sibState = state
        } else {
            // Fallback to legacy boolean value
            options.isSiB = UserDefaults.standard.bool(forKey: sibEnabledKey)
        }
        
        if let storePickState = UserDefaults.standard.string(forKey: storePickStateKey),
           let state = ToggleState.allCases.first(where: { $0.rawValue == storePickState }) {
            options.storePickState = state
        } else {
            // Fallback to legacy boolean value
            options.isStorePick = UserDefaults.standard.bool(forKey: storePickEnabledKey)
        }
        
        // For new toggles, just use defaults if not found
        if let openState = UserDefaults.standard.string(forKey: openStateKey),
           let state = ToggleState.allCases.first(where: { $0.rawValue == openState }) {
            options.openState = state
        }
        
        if let finishState = UserDefaults.standard.string(forKey: finishStateKey),
           let state = ToggleState.allCases.first(where: { $0.rawValue == finishState }) {
            options.finishState = state
        }
        
        if let deadBottleState = UserDefaults.standard.string(forKey: deadBottleStateKey),
           let state = ToggleState.allCases.first(where: { $0.rawValue == deadBottleState }) {
            options.deadBottleState = state
        }
        
        if let reviewState = UserDefaults.standard.string(forKey: reviewStateKey),
           let state = ToggleState.allCases.first(where: { $0.rawValue == reviewState }) {
            options.reviewState = state
        }
        
        if let tastedState = UserDefaults.standard.string(forKey: tastedStateKey),
           let state = ToggleState.allCases.first(where: { $0.rawValue == tastedState }) {
            options.tastedState = state
        }
        
        // Load price range option
        if let savedPriceRangeOption = UserDefaults.standard.string(forKey: priceRangeOptionKey),
           let priceOption = PriceRangeOption.allCases.first(where: { $0.rawValue == savedPriceRangeOption }) {
            options.priceRangeOption = priceOption
        }
        
        // Load custom price range if it exists
        if UserDefaults.standard.object(forKey: customMinPriceKey) != nil,
           UserDefaults.standard.object(forKey: customMaxPriceKey) != nil {
            let minPrice = UserDefaults.standard.double(forKey: customMinPriceKey)
            let maxPrice = UserDefaults.standard.double(forKey: customMaxPriceKey)
            options.customPriceRange = minPrice...maxPrice
        }
        
        // Load proof range if it exists
        if UserDefaults.standard.object(forKey: minProofKey) != nil,
           UserDefaults.standard.object(forKey: maxProofKey) != nil {
            let minProof = UserDefaults.standard.double(forKey: minProofKey)
            let maxProof = UserDefaults.standard.double(forKey: maxProofKey)
            options.proofRange = minProof...maxProof
        }
        
        return options
    }
    
    // Save privacy setting for hiding prices
    static func saveHidePricesSetting(_ hidePrices: Bool) {
        UserDefaults.standard.set(hidePrices, forKey: hidePricesKey)
    }
    
    // Load privacy setting for hiding prices
    static func loadHidePricesSetting() -> Bool {
        return UserDefaults.standard.bool(forKey: hidePricesKey)
    }
} 