import Foundation
import CoreData

// This category avoids conflicts with generated Core Data code by using a proper extension pattern
extension Whiskey {
    // MARK: - Custom Formatting Properties
    
    // Computed property to get formatted age if available
    var formattedAge: String? {
        guard let ageValue = age as? Int, ageValue > 0 else { return nil }
        return "\(ageValue) yr"
    }
    
    // Formatted proof with the degree symbol
    var formattedProof: String {
        guard let proofValue = proof as? Double, proofValue > 0 else {
            return "N/A"
        }
        return String(format: "%.1f°", proofValue)
    }
    
    // Formatted ABV with percentage
    var formattedABV: String {
        guard let proofValue = proof as? Double, proofValue > 0 else {
            return "N/A"
        }
        let abv = proofValue / 2
        return String(format: "%.1f%%", abv)
    }
    
    // MARK: - Replacement Status
    
    var replacementStatusEnum: WhiskeyReplacementStatus {
        get {
            guard let status = replacementStatus,
                  let enumStatus = WhiskeyReplacementStatus(rawValue: status) else {
                return .none
            }
            return enumStatus
        }
        set {
            replacementStatus = newValue.rawValue
        }
    }
    
    var wantsToBeReplaced: Bool {
        return replacementStatusEnum == .wantToReplace
    }
    
    var isReplacementBottle: Bool {
        return replacementStatusEnum == .isReplacement
    }
}

// MARK: - Value Tracking Extensions
extension Whiskey {
    // Calculate the current value of this whiskey
    var currentValue: Double {
        // If this whiskey is finished and has a replacement,
        // it has no current value
        if isFinished > 0 && replacedBy != nil {
            return 0
        }
        
        // If this whiskey is finished with no replacement,
        // it has no current value
        if isFinished > 0 {
            return 0
        }
        
        // For active bottles, sum their prices
        guard let bottleInstances = bottleInstances as? Set<BottleInstance> else { return 0 }
        return bottleInstances.filter { !$0.isDead }.reduce(0) { $0 + $1.price }
    }
    
    // Add a property to check if a whiskey has any dead bottles (for filtering)
    var hasAnyDeadBottles: Bool {
        guard let bottleInstances = bottleInstances as? Set<BottleInstance> else { return false }
        return bottleInstances.contains { $0.isDead }
    }
    
    // Update the isCompletelyDead property to check if all bottles of a whiskey are dead
    var isCompletelyDead: Bool {
        guard let bottleInstances = bottleInstances as? Set<BottleInstance>, !bottleInstances.isEmpty else { 
            // If there are no bottle instances but isFinished > 0, consider it dead
            return isFinished > 0 
        }
        
        // Check if there are any active bottles
        let activeBottles = bottleInstances.filter { !$0.isDead }
        return activeBottles.isEmpty
    }
    
    // Add a property to check if whiskey has at least one active bottle
    var hasActiveBottles: Bool {
        guard let bottleInstances = bottleInstances as? Set<BottleInstance>, !bottleInstances.isEmpty else {
            // If there are no bottle instances or they're all finished, it has no active bottles
            return isFinished < numberOfBottles
        }
        
        let activeBottles = bottleInstances.filter { !$0.isDead }
        return !activeBottles.isEmpty
    }
    
    // Helper to update isFinished value based on bottle instances
    func updateFinishedStatus() {
        guard let bottleInstances = bottleInstances as? Set<BottleInstance> else {
            isFinished = 0
            return
        }
        
        // Count dead bottles and set isFinished to that count
        let deadBottles = bottleInstances.filter { $0.isDead }
        isFinished = Int16(deadBottles.count)
        
        // Debug log
        print("DEBUG: updateFinishedStatus - deadBottles.count: \(deadBottles.count), isFinished: \(isFinished)")
        
        // Save the changes if possible
        if let context = managedObjectContext {
            do {
                try context.save()
            } catch {
                print("Error saving updateFinishedStatus: \(error)")
            }
        }
    }
    
    // Calculate the historical value (total spent on this whiskey including replacements)
    var historicalValue: Double {
        // Sum all bottle prices (including dead ones)
        guard let bottleInstances = bottleInstances as? Set<BottleInstance> else { return 0 }
        var total = bottleInstances.reduce(0) { $0 + $1.price }
        
        // Add the value of any replacement bottles
        if let replacement = replacedBy {
            total += replacement.historicalValue
        }
        
        return total
    }
    
    // Get the price trend for this whiskey over time
    var priceTrend: [PriceTrendPoint] {
        guard let bottleInstances = bottleInstances as? Set<BottleInstance> else { return [] }
        
        // Sort bottles by date added
        let sortedBottles = bottleInstances.sorted { ($0.dateAdded ?? Date.distantPast) < ($1.dateAdded ?? Date.distantPast) }
        
        // Create trend points for each bottle
        return sortedBottles.map { bottle in
            PriceTrendPoint(
                date: bottle.dateAdded ?? Date.distantPast,
                price: bottle.price
            )
        }
    }
    
    // Get the average price of all bottles (active and dead)
    var averagePrice: Double {
        guard let bottleInstances = bottleInstances as? Set<BottleInstance> else { return 0 }
        // Include all bottles, not just active ones
        guard !bottleInstances.isEmpty else { return 0 }
        return bottleInstances.reduce(0) { $0 + $1.price } / Double(bottleInstances.count)
    }
    
    // Get the average price of only active bottles
    var averageActivePrice: Double {
        guard let bottleInstances = bottleInstances as? Set<BottleInstance> else { return 0 }
        let activeBottles = bottleInstances.filter { !$0.isDead }
        guard !activeBottles.isEmpty else { return 0 }
        return activeBottles.reduce(0) { $0 + $1.price } / Double(activeBottles.count)
    }

    // Get the count of open bottles
    var openBottleCount: Int16 {
        guard let bottleInstances = bottleInstances as? Set<BottleInstance> else { return 0 }
        return Int16(bottleInstances.filter { !$0.isDead && $0.isOpen }.count)
    }

    // Get the count of dead/finished bottles
    var deadBottleCount: Int16 {
        guard let bottleInstances = bottleInstances as? Set<BottleInstance> else { return 0 }
        return Int16(bottleInstances.filter { $0.isDead }.count)
    }

    // Get the count of active bottles
    var activeBottleCount: Int16 {
        guard let bottleInstances = bottleInstances as? Set<BottleInstance> else { return 0 }
        return Int16(bottleInstances.filter { !$0.isDead }.count)
    }

    // Get the bottle history sorted by date
    var bottleHistory: [(date: Date, type: String, details: String)] {
        guard let bottleInstances = bottleInstances as? Set<BottleInstance> else { return [] }
        var history: [(date: Date, type: String, details: String)] = []
        
        for bottle in bottleInstances {
            if let dateAdded = bottle.dateAdded {
                history.append((date: dateAdded, type: "added", details: "Bottle \(bottle.bottleNumber) added"))
            }
            if let dateOpened = bottle.dateOpened {
                history.append((date: dateOpened, type: "opened", details: "Bottle \(bottle.bottleNumber) opened"))
            }
            if let dateFinished = bottle.dateFinished {
                history.append((date: dateFinished, type: "finished", details: "Bottle \(bottle.bottleNumber) finished"))
            }
        }
        
        return history.sorted { $0.date > $1.date }
    }

    // Get personal rating (average of journal entry ratings)
    var personalRating: Double {
        guard let journalEntries = journalEntries as? Set<JournalEntry>, 
              !journalEntries.isEmpty else { return 0 }
        
        let validRatings = journalEntries.compactMap { entry -> Double? in
            let rating = entry.overallRating
            return rating > 0 ? rating : nil
        }
        
        guard !validRatings.isEmpty else { return 0 }
        return validRatings.reduce(0, +) / Double(validRatings.count)
    }
    
    // Get the replacement chain (original bottle and all replacements)
    var replacementChain: [Whiskey] {
        var chain: [Whiskey] = [self]
        var current: Whiskey? = self
        
        while let next = current?.replacedBy {
            chain.append(next)
            current = next
        }
        
        return chain
    }
    
    // Check if this is the most recent bottle in the chain
    var isCurrentBottle: Bool {
        return replacedBy == nil
    }
    
    // Get the original bottle in the chain
    var originalBottle: Whiskey? {
        var current: Whiskey? = self
        while let previous = current?.replaces {
            current = previous
        }
        return current
    }
    
    var isReplacementNeeded: Bool {
        // Check if this is a finished bottle with a replacement
        if isFinished > 0 && replacedBy != nil {
            return false
        }
        
        // Check if this is a finished bottle without a replacement
        if isFinished > 0 {
            return true
        }
        
        return false
    }
}

// MARK: - Collection Value Extensions
extension Collection where Element == Whiskey {
    var totalCurrentValue: Double {
        // Sum of all unfinished bottles' current values
        self.reduce(0) { $0 + $1.currentValue }
    }
    
    var totalHistoricalValue: Double {
        // Total amount spent on all bottles including replacements
        self.reduce(0) { $0 + $1.historicalValue }
    }
    
    var averageReplacementCost: Double {
        let replacements = self.filter { $0.replaces != nil }
        return replacements.isEmpty ? 0 :
            replacements.reduce(0) { $0 + $1.price } / Double(replacements.count)
    }
    
    // Get frequently replaced whiskeys (more than one replacement)
    var frequentlyReplaced: [Whiskey] {
        self.filter { whiskey in
            var count = 0
            var current: Whiskey? = whiskey
            while current?.replacedBy != nil {
                count += 1
                current = current?.replacedBy
            }
            return count > 1
        }
    }
}

// MARK: - Supporting Types
struct PriceTrendPoint: Identifiable {
    let id = UUID()
    let date: Date
    let price: Double
} 