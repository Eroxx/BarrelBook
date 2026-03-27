import Foundation
import CoreData
import SwiftUI

// MARK: - Hierarchical Sort Models

// Represents a single sort criterion with ID for list manipulation
struct SortCriterionIdentifiable: Identifiable, Equatable {
    let id: UUID
    let option: SortOption
    
    init(id: UUID = UUID(), option: SortOption) {
        self.id = id
        self.option = option
    }
    
    static func == (lhs: SortCriterionIdentifiable, rhs: SortCriterionIdentifiable) -> Bool {
        return lhs.option == rhs.option
    }
}

// Manual Codable conformance
extension SortCriterionIdentifiable: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case option
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        option = try container.decode(SortOption.self, forKey: .option)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(option, forKey: .option)
    }
}

// Hierarchical sort configuration for whiskeys
struct HierarchicalSortConfig {
    var activeSorts: [SortCriterionIdentifiable]
    
    // Get all available sort options that aren't active and don't conflict
    func availableSorts(allOptions: [SortOption]) -> [SortOption] {
        let activeOptions = Set(activeSorts.map { $0.option })
        return allOptions.filter { option in
            !activeOptions.contains(option) && !hasConflict(with: option, in: activeSorts)
        }
    }
    
    // Check if a sort option conflicts with any active sorts
    private func hasConflict(with option: SortOption, in activeSorts: [SortCriterionIdentifiable]) -> Bool {
        for active in activeSorts {
            if areConflicting(option, active.option) {
                return true
            }
        }
        return false
    }
    
    // Define which sort options are conflicting (opposing directions of same attribute)
    private func areConflicting(_ option1: SortOption, _ option2: SortOption) -> Bool {
        let conflicts: [(SortOption, SortOption)] = [
            (.nameAsc, .nameDesc),
            (.proofHigh, .proofLow),
            (.priceHigh, .priceLow),
            (.ageDesc, .ageAsc),
            (.openFirst, .sealedFirst)
        ]
        
        for (a, b) in conflicts {
            if (option1 == a && option2 == b) || (option1 == b && option2 == a) {
                return true
            }
        }
        return false
    }
}

// Utility class for consistent sorting across all views
struct SortingUtils {
    
    // Hierarchical sorting for whiskeys - applies multiple sort criteria in order
    static func sortWhiskeysHierarchically(_ whiskeys: [Whiskey], by sortConfig: HierarchicalSortConfig) -> [Whiskey] {
        guard !sortConfig.activeSorts.isEmpty else {
            // Fallback to name ascending if no sorts
            return whiskeys.sorted { ($0.name ?? "") < ($1.name ?? "") }
        }
        
        return whiskeys.sorted { first, second in
            // Apply each sort criterion in order until we find a difference
            for criterion in sortConfig.activeSorts {
                let comparison = compareWhiskeys(first, second, by: criterion.option)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
            }
            // If all criteria are equal, maintain stable sort
            return false
        }
    }
    
    // Compare two whiskeys based on a single sort option
    private static func compareWhiskeys(_ first: Whiskey, _ second: Whiskey, by sortOption: SortOption) -> ComparisonResult {
        switch sortOption {
        case .nameAsc:
            return (first.name ?? "").compare(second.name ?? "")
        case .nameDesc:
            return (second.name ?? "").compare(first.name ?? "")
        case .proofHigh:
            return first.proof > second.proof ? .orderedAscending : first.proof < second.proof ? .orderedDescending : .orderedSame
        case .proofLow:
            return first.proof < second.proof ? .orderedAscending : first.proof > second.proof ? .orderedDescending : .orderedSame
        case .priceHigh:
            return first.price > second.price ? .orderedAscending : first.price < second.price ? .orderedDescending : .orderedSame
        case .priceLow:
            return first.price < second.price ? .orderedAscending : first.price > second.price ? .orderedDescending : .orderedSame
        case .typeAsc:
            return (first.type ?? "").compare(second.type ?? "")
        case .ageDesc:
            return compareAge(first.age, second.age, ascending: false)
        case .ageAsc:
            return compareAge(first.age, second.age, ascending: true)
        case .openFirst:
            if first.isOpen != second.isOpen {
                return first.isOpen ? .orderedAscending : .orderedDescending
            }
            return .orderedSame
        case .sealedFirst:
            if first.isOpen != second.isOpen {
                return !first.isOpen ? .orderedAscending : .orderedDescending
            }
            return .orderedSame
        case .dateAdded:
            if let date1 = first.modificationDate, let date2 = second.modificationDate {
                return date1 > date2 ? .orderedAscending : date1 < date2 ? .orderedDescending : .orderedSame
            }
            return .orderedSame
        }
    }
    
    // Helper to compare age strings
    private static func compareAge(_ age1: String?, _ age2: String?, ascending: Bool) -> ComparisonResult {
        let num1 = extractAgeNumber(age1)
        let num2 = extractAgeNumber(age2)
        
        if ascending {
            return num1 < num2 ? .orderedAscending : num1 > num2 ? .orderedDescending : .orderedSame
        } else {
            return num1 > num2 ? .orderedAscending : num1 < num2 ? .orderedDescending : .orderedSame
        }
    }
    
    // Extract numeric value from age string
    private static func extractAgeNumber(_ age: String?) -> Double {
        guard let age = age else { return 0 }
        let numbers = age.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Double(numbers) ?? 0
    }
    
    // Legacy single-sort method for backward compatibility
    static func sortWhiskeys(_ whiskeys: [Whiskey], by sortOption: SortOption) -> [Whiskey] {
        let config = HierarchicalSortConfig(activeSorts: [SortCriterionIdentifiable(option: sortOption)])
        return sortWhiskeysHierarchically(whiskeys, by: config)
    }
    
    // Group by sort criteria or alphabetically by first letter for CollectionView
    static func groupByFirstLetter(_ whiskeys: [Whiskey], sortedBy sortOption: SortOption) -> [(key: String, whiskeys: [Whiskey])] {
        // Only use alphabetical grouping for name-based sorts
        if sortOption == .nameAsc || sortOption == .nameDesc {
            // For name-based sorts, maintain alphabetical grouping
            // First group by first letter
            let grouped = Dictionary(grouping: whiskeys) { whiskey in
                String(whiskey.name?.prefix(1).uppercased() ?? "#")
            }
            
            // Sort the groups alphabetically
            let sortedGroups = grouped.map { (key: $0.key, whiskeys: $0.value) }
                .sorted { $0.key < $1.key }
            
            // Sort the whiskeys within each group
            return sortedGroups.map { group in
                let sortedWhiskeys = sortWhiskeys(group.whiskeys, by: sortOption)
                return (key: group.key, whiskeys: sortedWhiskeys)
            }
        } else {
            // For all other sorts, use a single section
            // Sort all whiskeys by the selected sort option
            let allSortedWhiskeys = sortWhiskeys(whiskeys, by: sortOption)
            
            // Use a single section for all whiskeys
            return [("All Whiskeys", allSortedWhiskeys)]
        }
    }
}

// MARK: - Wishlist Hierarchical Sort

// Similar structures for Wishlist
struct WishlistSortCriterionIdentifiable: Identifiable, Equatable {
    let id: UUID
    let option: WishlistSortOption
    
    init(id: UUID = UUID(), option: WishlistSortOption) {
        self.id = id
        self.option = option
    }
    
    static func == (lhs: WishlistSortCriterionIdentifiable, rhs: WishlistSortCriterionIdentifiable) -> Bool {
        return lhs.option == rhs.option
    }
}

// Manual Codable conformance
extension WishlistSortCriterionIdentifiable: Codable {
    enum CodingKeys: String, CodingKey {
        case id
        case option
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        option = try container.decode(WishlistSortOption.self, forKey: .option)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(option, forKey: .option)
    }
}

struct WishlistHierarchicalSortConfig {
    var activeSorts: [WishlistSortCriterionIdentifiable]
    
    func availableSorts(allOptions: [WishlistSortOption]) -> [WishlistSortOption] {
        let activeOptions = Set(activeSorts.map { $0.option })
        return allOptions.filter { option in
            !activeOptions.contains(option) && !hasConflict(with: option, in: activeSorts)
        }
    }
    
    private func hasConflict(with option: WishlistSortOption, in activeSorts: [WishlistSortCriterionIdentifiable]) -> Bool {
        for active in activeSorts {
            if areConflicting(option, active.option) {
                return true
            }
        }
        return false
    }
    
    private func areConflicting(_ option1: WishlistSortOption, _ option2: WishlistSortOption) -> Bool {
        let conflicts: [(WishlistSortOption, WishlistSortOption)] = [
            (.nameAsc, .nameDesc),
            (.targetPriceLow, .targetPriceHigh),
            (.rarityLow, .rarityHigh)
        ]
        
        for (a, b) in conflicts {
            if (option1 == a && option2 == b) || (option1 == b && option2 == a) {
                return true
            }
        }
        return false
    }
}

// Extension to SortingUtils for wishlist sorting
extension SortingUtils {
    static func sortWishlistHierarchically(_ whiskeys: [Whiskey], by sortConfig: WishlistHierarchicalSortConfig) -> [Whiskey] {
        guard !sortConfig.activeSorts.isEmpty else {
            return whiskeys.sorted { ($0.name ?? "") < ($1.name ?? "") }
        }
        
        return whiskeys.sorted { first, second in
            for criterion in sortConfig.activeSorts {
                let comparison = compareWhiskeysWishlist(first, second, by: criterion.option)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
            }
            return false
        }
    }
    
    private static func compareWhiskeysWishlist(_ first: Whiskey, _ second: Whiskey, by sortOption: WishlistSortOption) -> ComparisonResult {
        switch sortOption {
        case .nameAsc:
            return (first.name ?? "").compare(second.name ?? "")
        case .nameDesc:
            return (second.name ?? "").compare(first.name ?? "")
        case .priorityHigh:
            return first.priority > second.priority ? .orderedAscending : first.priority < second.priority ? .orderedDescending : .orderedSame
        case .targetPriceLow:
            return first.targetPrice < second.targetPrice ? .orderedAscending : first.targetPrice > second.targetPrice ? .orderedDescending : .orderedSame
        case .targetPriceHigh:
            return first.targetPrice > second.targetPrice ? .orderedAscending : first.targetPrice < second.targetPrice ? .orderedDescending : .orderedSame
        case .rarityLow:
            let rarity1 = WhiskeyRarity(rawValue: first.rarity ?? "") ?? .notSure
            let rarity2 = WhiskeyRarity(rawValue: second.rarity ?? "") ?? .notSure
            return rarity1.sortOrder < rarity2.sortOrder ? .orderedAscending : rarity1.sortOrder > rarity2.sortOrder ? .orderedDescending : .orderedSame
        case .rarityHigh:
            let rarity1 = WhiskeyRarity(rawValue: first.rarity ?? "") ?? .notSure
            let rarity2 = WhiskeyRarity(rawValue: second.rarity ?? "") ?? .notSure
            return rarity1.sortOrder > rarity2.sortOrder ? .orderedAscending : rarity1.sortOrder < rarity2.sortOrder ? .orderedDescending : .orderedSame
        }
    }
}

// MARK: - Journal Hierarchical Sort

// Import JournalSortOption (assuming it's accessible)
struct JournalSortCriterionIdentifiable: Identifiable, Equatable, Codable {
    let id: UUID
    let option: String  // We'll use String rawValue for JournalSortOption
    
    init(id: UUID = UUID(), optionRawValue: String) {
        self.id = id
        self.option = optionRawValue
    }
    
    static func == (lhs: JournalSortCriterionIdentifiable, rhs: JournalSortCriterionIdentifiable) -> Bool {
        return lhs.option == rhs.option
    }
}

struct JournalHierarchicalSortConfig {
    var activeSorts: [JournalSortCriterionIdentifiable]
    
    func availableSorts(allOptions: [String]) -> [String] {
        let activeOptions = Set(activeSorts.map { $0.option })
        return allOptions.filter { option in
            !activeOptions.contains(option) && !hasConflict(with: option, in: activeSorts)
        }
    }
    
    private func hasConflict(with option: String, in activeSorts: [JournalSortCriterionIdentifiable]) -> Bool {
        for active in activeSorts {
            if areConflicting(option, active.option) {
                return true
            }
        }
        return false
    }
    
    private func areConflicting(_ option1: String, _ option2: String) -> Bool {
        let conflicts: [(String, String)] = [
            ("dateDesc", "dateAsc"),
            ("ratingDesc", "ratingAsc")
        ]
        
        for (a, b) in conflicts {
            if (option1 == a && option2 == b) || (option1 == b && option2 == a) {
                return true
            }
        }
        return false
    }
}

// Extension to SortingUtils for journal entry sorting
extension SortingUtils {
    static func sortJournalEntriesHierarchically(_ entries: [JournalEntry], by sortConfig: JournalHierarchicalSortConfig) -> [JournalEntry] {
        guard !sortConfig.activeSorts.isEmpty else {
            return entries.sorted { ($0.date ?? Date()) > ($1.date ?? Date()) }
        }
        
        return entries.sorted { first, second in
            for criterion in sortConfig.activeSorts {
                let comparison = compareJournalEntries(first, second, by: criterion.option)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }
            }
            return false
        }
    }
    
    private static func compareJournalEntries(_ first: JournalEntry, _ second: JournalEntry, by sortOption: String) -> ComparisonResult {
        switch sortOption {
        case "dateDesc":
            let date1 = first.date ?? Date()
            let date2 = second.date ?? Date()
            return date1 > date2 ? .orderedAscending : date1 < date2 ? .orderedDescending : .orderedSame
        case "dateAsc":
            let date1 = first.date ?? Date()
            let date2 = second.date ?? Date()
            return date1 < date2 ? .orderedAscending : date1 > date2 ? .orderedDescending : .orderedSame
        case "ratingDesc":
            return first.overallRating > second.overallRating ? .orderedAscending : first.overallRating < second.overallRating ? .orderedDescending : .orderedSame
        case "ratingAsc":
            return first.overallRating < second.overallRating ? .orderedAscending : first.overallRating > second.overallRating ? .orderedDescending : .orderedSame
        default:
            return .orderedSame
        }
    }
} 