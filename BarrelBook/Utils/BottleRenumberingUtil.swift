import Foundation
import CoreData

// Utility for bottle renumbering
struct BottleRenumberingUtil {
    
    /// Renumbers bottle instances for a whiskey to ensure consecutive numbering within status groups
    /// - Parameters:
    ///   - whiskey: The whiskey whose bottles need renumbering
    ///   - context: The managed object context (optional - defaults to whiskey's context)
    static func renumberBottles(for whiskey: Whiskey, in context: NSManagedObjectContext? = nil) {
        let ctx = context ?? whiskey.managedObjectContext
        guard let ctx = ctx else {
            print("ERROR: Cannot renumber bottles - no managed object context available")
            return
        }
        
        // Safety check to prevent potential crashes if whiskey is not fully initialized
        if whiskey.objectID.isTemporaryID {
            print("WARNING: Whiskey has temporary ID, skipping renumbering")
            do {
                try ctx.obtainPermanentIDs(for: [whiskey])
            } catch {
                print("ERROR: Failed to obtain permanent ID for whiskey: \(error)")
                return
            }
        }
        
        // Fetch all bottle instances for this whiskey
        let fetchRequest: NSFetchRequest<BottleInstance> = BottleInstance.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "whiskey == %@", whiskey)
        
        do {
            let allBottles = try ctx.fetch(fetchRequest)
            
            // Guard against empty results to prevent range issues
            guard !allBottles.isEmpty else {
                print("DEBUG: No bottles found for \(whiskey.name ?? "unknown whiskey"), skipping renumbering")
                return
            }
            
            // Split into active and dead groups with safety checks
            let activeBottles = allBottles.filter { !$0.isDead }
                                .sorted { ($0.dateAdded ?? Date.distantPast) < ($1.dateAdded ?? Date.distantPast) }
            let deadBottles = allBottles.filter { $0.isDead }
                              .sorted { ($0.dateFinished ?? Date.distantPast) < ($1.dateFinished ?? Date.distantPast) }
            
            print("DEBUG: Renumbering bottles for \(whiskey.name ?? "unknown whiskey")")
            print("DEBUG: Active bottles: \(activeBottles.count), Dead bottles: \(deadBottles.count)")
            
            // Renumber active bottles consecutively starting from 1
            // Only process when there are bottles to avoid range errors
            if !activeBottles.isEmpty {
                for (index, bottle) in activeBottles.enumerated() {
                    let newNumber = Int16(index + 1)
                    // Avoid unnecessary updates
                    if bottle.bottleNumber != newNumber {
                        print("DEBUG: Renumbering active bottle from \(bottle.bottleNumber) to \(newNumber)")
                        bottle.bottleNumber = newNumber
                    }
                }
            }
            
            // The key fix: Renumber dead bottles consecutively starting from 1
            // Only process when there are bottles to avoid range errors
            if !deadBottles.isEmpty {
                for (index, bottle) in deadBottles.enumerated() {
                    let newNumber = Int16(index + 1)
                    // Avoid unnecessary updates
                    if bottle.bottleNumber != newNumber {
                        print("DEBUG: Renumbering dead bottle from \(bottle.bottleNumber) to \(newNumber)")
                        bottle.bottleNumber = newNumber
                    }
                }
            }
            
            // Ensure whiskey counts match bottle instances
            let activeCount = Int16(activeBottles.count)
            let deadCount = Int16(deadBottles.count)
            
            // Safety check to avoid negative values that could cause ranges to fail
            if activeCount >= 0 && whiskey.numberOfBottles != activeCount {
                whiskey.numberOfBottles = activeCount
            }
            
            if deadCount >= 0 && whiskey.isFinished != deadCount {
                whiskey.isFinished = deadCount
            }
            
            // Save changes
            if ctx.hasChanges {
                try ctx.save()
                print("DEBUG: Successfully saved bottle renumbering changes")
            } else {
                print("DEBUG: No bottle renumbering changes needed")
            }
            
        } catch {
            print("ERROR: Failed to renumber bottles: \(error)")
        }
    }
}

extension Whiskey {
    func renumberBottles() {
        BottleRenumberingUtil.renumberBottles(for: self)
    }
}