import Foundation
import CoreData

// Utility class for consistent sorting across all views
struct SortingUtils {
    
    // Consistent sorting implementation that can be used by all views
    static func sortWhiskeys(_ whiskeys: [Whiskey], by sortOption: SortOption) -> [Whiskey] {
        whiskeys.sorted { first, second in
            switch sortOption {
            case .nameAsc:
                return (first.name ?? "") < (second.name ?? "")
            case .nameDesc:
                return (first.name ?? "") > (second.name ?? "")
            case .proofHigh:
                return first.proof > second.proof
            case .proofLow:
                return first.proof < second.proof
            case .priceHigh:
                return first.price > second.price
            case .priceLow:
                return first.price < second.price
            case .typeAsc:
                return (first.type ?? "") < (second.type ?? "")
            case .ageDesc:
                return (first.age ?? "") > (second.age ?? "")
            case .ageAsc:
                return (first.age ?? "") < (second.age ?? "")
            case .openFirst:
                // Sort open bottles first, then by name
                if first.isOpen != second.isOpen {
                    return first.isOpen
                }
                return (first.name ?? "") < (second.name ?? "")
            case .sealedFirst:
                // Sort sealed (not open) bottles first, then by name
                if first.isOpen != second.isOpen {
                    return !first.isOpen
                }
                return (first.name ?? "") < (second.name ?? "")
            case .dateAdded:
                // Compare modification dates if available, otherwise fallback to name
                if let date1 = first.modificationDate, let date2 = second.modificationDate {
                    return date1 > date2  // Newest first
                } else {
                    return (first.name ?? "") < (second.name ?? "")
                }
            }
        }
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