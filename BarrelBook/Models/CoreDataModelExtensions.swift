import Foundation
import CoreData

// MARK: - InfinityBottle Extensions
extension InfinityBottle {
    // Current calculated proof of the bottle based on all additions
    var calculatedProof: Double {
        guard let additions = additions as? Set<BottleAddition>, !additions.isEmpty else {
            return 0.0
        }
        
        let totalVolume = additions.reduce(0) { $0 + $1.amount }
        let weightedProof = additions.reduce(0) { $0 + ($1.amount * $1.proof) }
        
        return totalVolume > 0 ? weightedProof / totalVolume : 0
    }
    
    // Total volume in ounces
    var totalVolume: Double {
        guard let additions = additions as? Set<BottleAddition> else { return 0.0 }
        return additions.reduce(0) { $0 + $1.amount }
    }
    
    // Sorted additions by date (newest first)
    var sortedAdditions: [BottleAddition] {
        guard let additions = additions as? Set<BottleAddition> else { return [] }
        return additions.sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
    }
    
    // Sorted tastings by date (newest first)
    var sortedTastings: [BottleTasting] {
        guard let tastings = tastings as? Set<BottleTasting> else { return [] }
        return tastings.sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
    }
    
    // Add a whiskey to the bottle
    func addWhiskey(_ whiskey: Whiskey, amount: Double, notes: String? = nil, context: NSManagedObjectContext) {
        let newAddition = BottleAddition(context: context)
        newAddition.id = UUID()
        newAddition.whiskey = whiskey
        newAddition.amount = amount  // In ounces
        newAddition.proof = whiskey.proof
        newAddition.date = Date()
        newAddition.notes = notes
        newAddition.infinityBottle = self
        
        // Update the currentVolume property in the Core Data model
        // even though we primarily use totalVolume computed property now
        self.currentVolume += amount
        // Ensure currentVolume stays in sync with remainingVolume
        syncCurrentVolume()
        modificationDate = Date()
    }
    
    // Record a tasting for this bottle
    func recordTasting(nose: String?, palate: String?, finish: String?, notes: String?, rating: Double, context: NSManagedObjectContext) {
        let newTasting = BottleTasting(context: context)
        newTasting.id = UUID()
        newTasting.infinityBottle = self
        newTasting.date = Date()
        newTasting.nose = nose
        newTasting.palate = palate
        newTasting.finish = finish
        newTasting.notes = notes
        newTasting.rating = rating
        newTasting.volumeConsumed = 0.0 // Default to 0 for backward compatibility
        
        modificationDate = Date()
    }
    
    // Record a tasting with volume consumption tracking
    func recordTastingWithConsumption(nose: String?, palate: String?, finish: String?, notes: String?, rating: Double, volumeConsumed: Double, context: NSManagedObjectContext) {
        let newTasting = BottleTasting(context: context)
        newTasting.id = UUID()
        newTasting.infinityBottle = self
        newTasting.date = Date()
        newTasting.nose = nose
        newTasting.palate = palate
        newTasting.finish = finish
        newTasting.notes = notes
        newTasting.rating = rating
        newTasting.volumeConsumed = volumeConsumed
        
        // Subtract consumed volume from current volume
        if volumeConsumed > 0 {
            self.currentVolume = max(0, self.currentVolume - volumeConsumed)
            // Ensure currentVolume stays in sync with remainingVolume
            syncCurrentVolume()
        }
        
        modificationDate = Date()
    }
    
    // Total volume consumed from all tastings
    var totalVolumeConsumed: Double {
        guard let tastings = tastings as? Set<BottleTasting> else { return 0.0 }
        return tastings.reduce(0) { $0 + $1.volumeConsumed }
    }
    
    // Calculated remaining volume (total volume added minus consumed)
    var remainingVolume: Double {
        return max(0, totalVolume - totalVolumeConsumed)
    }
    
    // Sync the stored currentVolume with the computed remainingVolume
    func syncCurrentVolume() {
        self.currentVolume = remainingVolume
    }
}

// MARK: - BottleAddition Extensions
extension BottleAddition {
    // Formatted date string
    var formattedDate: String {
        guard let date = date else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // Whiskey name with fallback
    var whiskeyName: String {
        return whiskey?.name ?? "Unknown Whiskey"
    }
    
    // Distillery name with fallback
    var distilleryName: String {
        return whiskey?.distillery ?? "Unknown Distillery"
    }
}

// MARK: - BottleTasting Extensions
extension BottleTasting {
    // Formatted date string
    var formattedDate: String {
        guard let date = date else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // Formatted volume consumed string
    var formattedVolumeConsumed: String {
        if volumeConsumed > 0 {
            return String(format: "%.1f oz", volumeConsumed)
        } else {
            return "Not recorded"
        }
    }
    
    // Rating as stars (1-5)
    var ratingStars: String {
        let fullStars = Int(rating)
        let halfStar = (rating - Double(fullStars)) >= 0.5
        
        var stars = ""
        for i in 1...5 {
            if i <= fullStars {
                stars += "★" // Full star
            } else if i == fullStars + 1 && halfStar {
                stars += "⯨" // Half star (approximation)
            } else {
                stars += "☆" // Empty star
            }
        }
        
        return stars
    }
} 