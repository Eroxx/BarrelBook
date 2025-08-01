import Foundation
import CoreData
import SwiftUI

enum CSVError: Error {
    case encodingError
    case decodingError
    case invalidData
    case permissionError
}

// Define a protocol that WhiskeyRecord will conform to
protocol CSVExportable {
    var name: String { get }
    var type: String { get }
    var proof: Double { get }
    var age: String { get }
    var distillery: String { get }
    var finish: String { get }
    var isBiB: Bool { get }
    var isSiB: Bool { get }
    var isStorePick: Bool { get }
    var storePickName: String { get }
    var numberOfBottles: Int16 { get }
    var isFinished: Int16 { get }
    var isOpen: Bool { get }
    var price: Double { get }
    var notes: String { get }
    var isCaskStrength: Bool { get }
    var isTasted: Bool { get }
    var externalReviews: String { get }
}

// Define a type for progress reporting
typealias ImportProgress = (Double, String) -> Void

class CSVService {
    static let shared = CSVService()
    
    private let header = "Name,Type,Proof,Age,Distillery,Finish,Cask Strength?,BiB,SiB,SP,SP Name,Current # of Bottles,Open Bottles,Dead Bottles,Bottle Notes,Average Price,Tasted?,External Reviews"
    
    func exportWhiskeys(_ whiskeys: [Whiskey]) throws -> String {
        // Add UTF-8 BOM to ensure proper character encoding in Excel and other apps
        var csvString = "\u{FEFF}" + header + "\n"
        
        // Add diagnostic logging
        let allNames = whiskeys.compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
        print("EXPORT DIAGNOSTIC: Total whiskeys to export: \(whiskeys.count)")
        print("EXPORT DIAGNOSTIC: Unique names (case-sensitive): \(Set(allNames).count)")
        
        let normalizedNames = whiskeys.compactMap { $0.name?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        print("EXPORT DIAGNOSTIC: Unique names (case-insensitive): \(Set(normalizedNames).count)")
        
        // Get names with case or space variations
        let nameCounts = Dictionary(grouping: normalizedNames) { $0 }.mapValues { $0.count }
        print("EXPORT DIAGNOSTIC: Names with duplicates after normalization:")
        for (name, count) in nameCounts where count > 1 {
            let variations = whiskeys.compactMap { 
                if let whiskeyName = $0.name?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), 
                   whiskeyName == name {
                   return $0.name
                }
                return nil
            }
            print("- '\(name)' appears \(count) times with variations: \(variations)")
        }
        
        // Create a composite key using normalized name AND other identifying properties
        // This will ensure whiskeys with identical names but different properties are exported separately
        let groupedWhiskeys = Dictionary(grouping: whiskeys) { whiskey in
            let name = whiskey.name?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let proof = String(format: "%.1f", whiskey.proof)
            let isStorePick = whiskey.isStorePick ? "SP" : ""
            let spName = (whiskey.storePickName ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let type = (whiskey.type ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let distillery = (whiskey.distillery ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Create a composite key that uniquely identifies the whiskey beyond just its name
            return "\(name)|\(proof)|\(type)|\(distillery)|\(isStorePick)|\(spName)"
        }
        print("EXPORT DIAGNOSTIC: Grouped whiskey count: \(groupedWhiskeys.count)")
        
        for (_, whiskeysGroup) in groupedWhiskeys {
            // Skip empty names
            guard let firstWhiskey = whiskeysGroup.first, let name = firstWhiskey.name, !name.isEmpty else { continue }
            
            // Get bottle instances for the whiskey
            let bottles = firstWhiskey.bottleInstances as? Set<BottleInstance> ?? Set<BottleInstance>()
            
            // Add debug logging for bottle counts
            print("DEBUG: Processing whiskey '\(name)'")
            print("DEBUG: Total bottle instances: \(bottles.count)")
            
            // Calculate counts from actual bottle instances and whiskey properties
            let currentBottles = bottles.filter { !$0.isDead }.count
            let openBottles = bottles.filter { !$0.isDead && $0.isOpen }.count
            let deadBottles = Int(firstWhiskey.isFinished) // Use isFinished for dead bottle count
            
            // Debug log the counts
            print("DEBUG: '\(name)' counts - Current: \(currentBottles), Open: \(openBottles), Dead: \(deadBottles)")
            print("DEBUG: isFinished value: \(firstWhiskey.isFinished)")
            
            // Calculate average price from active bottles
            let averagePrice = firstWhiskey.averagePrice
            
            let row = [
                escapeCSV(name),
                escapeCSV(firstWhiskey.type ?? ""),
                String(firstWhiskey.proof),
                escapeCSV(firstWhiskey.age ?? ""),
                escapeCSV(firstWhiskey.distillery ?? ""),
                escapeCSV(firstWhiskey.finish ?? ""),
                firstWhiskey.isCaskStrength ? "Yes" : "No",
                firstWhiskey.isBiB ? "Yes" : "No",
                firstWhiskey.isSiB ? "Yes" : "No",
                firstWhiskey.isStorePick ? "Yes" : "No",
                escapeCSV(firstWhiskey.storePickName ?? ""),
                String(currentBottles),
                String(openBottles),
                String(deadBottles),
                escapeCSV(firstWhiskey.notes ?? ""),
                averagePrice > 0 ? String(format: "%.2f", averagePrice) : "",
                firstWhiskey.isTasted ? "Yes" : "No",
                escapeCSV(firstWhiskey.externalReviews ?? "")
            ]
            csvString += row.joined(separator: ",") + "\n"
        }
        
        return csvString
    }
    
    /**
     * Imports whiskeys from a CSV string into Core Data.
     *
     * This function has two modes:
     * 1. Fresh Import (isFreshImport = true): Deletes all existing whiskeys and bottles, then imports data from the CSV.
     *    This provides a clean slate but loses any changes made in the app.
     *
     * 2. Merge with Existing (isFreshImport = false): Smart-merges data from the CSV with existing whiskeys.
     *    This preserves changes made in both systems using these rules:
     *    - Bottle counts: Uses the maximum from either source
     *    - Dead bottles: Never decreases dead bottle count (dead bottles stay dead)
     *    - Open bottles: Uses the maximum open bottle count
     *    - Boolean properties (tasted, BiB, etc.): Uses logical OR (if either is true, result is true)
     *    - Text fields (notes, reviews): Combines both sources if they differ
     *    - Price: Uses the higher value if both are non-zero
     *
     * @param csvString The CSV string to import
     * @param context The managed object context to import into
     * @param isFreshImport Whether to delete all existing data first
     * @param progressHandler Optional callback for progress updates
     */
    func importWhiskeys(from csvString: String, context: NSManagedObjectContext, isFreshImport: Bool = false, progressHandler: ImportProgress? = nil) async throws {
        print("Starting CSV import process...")
        print("CSV string length: \(csvString.count) characters")
        
        // Add import timeout tracking with increased duration for large imports
        let importStartTime = Date()
        let maxImportDuration: TimeInterval = 600 // 10 minutes max
        
        // Function to check if import is taking too long
        func checkImportTimeout() -> Bool {
            let currentDuration = Date().timeIntervalSince(importStartTime)
            if currentDuration > maxImportDuration {
                print("⚠️ IMPORT TIMEOUT: Import has been running for over \(Int(maxImportDuration)) seconds, may be stuck")
                return true
            }
            return false
        }
        
        // Initial progress update
        await MainActor.run {
            progressHandler?(0.0, "Preparing import...")
        }
        
        // Get reference to persistence controller
        let persistenceController = PersistenceController.shared
        
        // Ensure iCloud sync is completely disabled
        let wasSyncing = persistenceController.container.viewContext.automaticallyMergesChangesFromParent
        persistenceController.container.viewContext.automaticallyMergesChangesFromParent = false
        
        // Wait for any pending sync operations to complete
        try await Task.sleep(nanoseconds: 500_000_000) // Wait 0.5 seconds - reduced from 1s
        
        // Double check sync is disabled
        if persistenceController.container.viewContext.automaticallyMergesChangesFromParent {
            print("❌ iCloud sync could not be disabled, aborting import")
            throw CSVError.permissionError
        }
        
        // Use defer to ensure iCloud sync is re-enabled even if an error occurs
        defer {
            // Re-enable iCloud sync in all cases - even if import fails or crashes
            print("Re-enabling iCloud sync before function exit")
            persistenceController.container.viewContext.automaticallyMergesChangesFromParent = wasSyncing
            
            // Force a sync after import completes
            if wasSyncing {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    persistenceController.forceSync()
                }
            }
        }
        
        // If this is a fresh import, clear all existing data first
        if isFreshImport {
            print("Starting fresh import - clearing whiskey collection data")
            
            await MainActor.run {
                progressHandler?(0.05, "Clearing existing data...")
            }
            
            do {
                // Create a private queue context for the deletion
                let deleteContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                deleteContext.parent = context
                
                try await deleteContext.perform {
                    // First delete all bottle instances
                    let bottleFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "BottleInstance")
                    let bottleDeleteRequest = NSBatchDeleteRequest(fetchRequest: bottleFetchRequest)
                    bottleDeleteRequest.resultType = .resultTypeObjectIDs
                    
                    // Execute in smaller batches if there are many bottles
                    let batchSize = 1000
                    
                    // First count how many bottles we have
                    let countRequest = NSFetchRequest<NSNumber>(entityName: "BottleInstance")
                    countRequest.resultType = .countResultType
                    
                    if let countResult = try? deleteContext.fetch(countRequest).first?.intValue, countResult > batchSize {
                        // If we have a lot of bottles, delete in batches
                        print("🔄 Large collection detected (\(countResult) bottles) - using batched deletion")
                        
                        for offset in stride(from: 0, to: countResult, by: batchSize) {
                            let batchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "BottleInstance")
                            batchRequest.fetchLimit = batchSize
                            batchRequest.fetchOffset = offset
                            
                            let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: batchRequest)
                            batchDeleteRequest.resultType = .resultTypeObjectIDs
                            
                            let batchResult = try deleteContext.execute(batchDeleteRequest) as? NSBatchDeleteResult
                            let batchChanges = [NSDeletedObjectsKey: batchResult?.result as? [NSManagedObjectID] ?? []]
                            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: batchChanges, into: [context])
                            
                            print("Deleted bottles batch \(offset/batchSize + 1) of \(countResult/batchSize + 1)")
                            
                            // Release memory pressure after each batch
                            autoreleasepool { }
                        }
                    } else {
                        // For smaller collections, delete all at once
                        let bottleResult = try deleteContext.execute(bottleDeleteRequest) as? NSBatchDeleteResult
                        let bottleChanges = [NSDeletedObjectsKey: bottleResult?.result as? [NSManagedObjectID] ?? []]
                        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: bottleChanges, into: [context])
                    }
                    
                    print("Deleted all bottle instances")
                    
                    // Save the intermediate progress
                    try deleteContext.save()
                    try context.save()
                    
                    // Then delete all whiskeys
                    let whiskeyFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Whiskey")
                    let whiskeyDeleteRequest = NSBatchDeleteRequest(fetchRequest: whiskeyFetchRequest)
                    whiskeyDeleteRequest.resultType = .resultTypeObjectIDs
                    let whiskeyResult = try deleteContext.execute(whiskeyDeleteRequest) as? NSBatchDeleteResult
                    let whiskeyChanges = [NSDeletedObjectsKey: whiskeyResult?.result as? [NSManagedObjectID] ?? []]
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: whiskeyChanges, into: [context])
                    print("Deleted all whiskeys")
                    
                    // Save the deletion context
                    try deleteContext.save()
                    
                    // Save the parent context to persist changes
                    try context.save()
                    
                    // Reset the context to clear any cached objects
                    context.reset()
                    
                    // Force a refresh of the context
                    try context.performAndWait {
                        try context.save()
                    }
                }
                
                print("Whiskey collection data cleared successfully")
                
                // Add a delay after clearing data to let the system catch up
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            } catch {
                print("Error during fresh import cleanup: \(error)")
                throw CSVError.permissionError
            }
        } else {
            // If not a fresh import, we should still clean up any dead bottles
            // Add this cleanup to ensure we don't have unwanted dead bottles from previous imports
            print("🧹 Cleaning up any existing dead bottles before import...")
            
            await MainActor.run {
                progressHandler?(0.05, "Cleaning up existing data...")
            }
            
            do {
                // Create a private queue context for the cleanup
                let cleanupContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
                cleanupContext.parent = context
                
                try await cleanupContext.perform {
                    // Find all dead bottles
                    let bottleFetchRequest = NSFetchRequest<BottleInstance>(entityName: "BottleInstance")
                    bottleFetchRequest.predicate = NSPredicate(format: "isDead == %@", NSNumber(value: true))
                    
                    if let deadBottles = try? cleanupContext.fetch(bottleFetchRequest) {
                        print("🧹 Found \(deadBottles.count) dead bottles to clean up")
                        
                        // Delete all dead bottles
                        for bottle in deadBottles {
                            cleanupContext.delete(bottle)
                        }
                        
                        // Save the cleanup context
                        try cleanupContext.save()
                        
                        // Save the parent context to persist changes
                        try context.save()
                        
                        print("✅ Successfully cleaned up \(deadBottles.count) dead bottles")
                    }
                    
                    // Fix isFinished property on all whiskeys
                    let whiskeyFetchRequest = NSFetchRequest<Whiskey>(entityName: "Whiskey")
                    if let whiskeys = try? cleanupContext.fetch(whiskeyFetchRequest) {
                        var fixedCount = 0
                        for whiskey in whiskeys {
                            if whiskey.isFinished > 0 {
                                print("🧹 Resetting isFinished for \(whiskey.name ?? "unknown")")
                                whiskey.isFinished = 0
                                fixedCount += 1
                            }
                        }
                        
                        if fixedCount > 0 {
                            // Save the changes
                            try cleanupContext.save()
                            try context.save()
                            print("✅ Reset isFinished property for \(fixedCount) whiskeys")
                        }
                    }
                }
            } catch {
                print("⚠️ Warning during dead bottle cleanup: \(error)")
                // Continue with import even if cleanup fails
            }
        }
        
        // Remove BOM if present
        var processedCSV = csvString
        if processedCSV.hasPrefix("\u{FEFF}") {
            processedCSV = String(processedCSV.dropFirst())
        }
        
        // Split into rows and clean up
        let rows = processedCSV.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        guard rows.count > 1 else { 
            print("Error: CSV file is empty or only contains header")
            throw CSVError.invalidData 
        }
        
        print("Processing CSV with \(rows.count) rows (including header)")
        
        await MainActor.run {
            progressHandler?(0.1, "Parsing CSV data...")
        }
        
        // Log progress markers for large files
        if rows.count > 500 {
            print("⚠️ Large import detected: \(rows.count) rows - this may take several minutes")
        }
        
        print("First few rows for verification:")
        for (index, row) in rows.prefix(5).enumerated() {
            print("Row \(index): \(row)")
        }
        
        // Process header row
        let headerRow = rows[0]
        let headerFields = parseCSVRow(headerRow)
        print("Header fields: \(headerFields)")
        
        // Find column indices - updated to match correct order
        let nameIndex = headerFields.firstIndex(of: "Name") ?? 0
        let typeIndex = headerFields.firstIndex(of: "Type") ?? 1
        let proofIndex = headerFields.firstIndex(of: "Proof") ?? 2
        let ageIndex = headerFields.firstIndex(of: "Age") ?? 3
        let distilleryIndex = headerFields.firstIndex(of: "Distillery") ?? 4
        let finishIndex = headerFields.firstIndex(of: "Finish") ?? 5
        let caskStrengthIndex = headerFields.firstIndex(of: "Cask Strength?") ?? 6
        let bibIndex = headerFields.firstIndex(of: "BiB") ?? 7
        let sibIndex = headerFields.firstIndex(of: "SiB") ?? 8
        let spIndex = headerFields.firstIndex(of: "SP") ?? 9
        let spNameIndex = headerFields.firstIndex(of: "SP Name") ?? 10
        let currentBottlesIndex = headerFields.firstIndex(of: "Current # of Bottles") ?? 11
        let openBottlesIndex = headerFields.firstIndex(of: "Open Bottles") ?? 12
        let deadBottlesIndex = headerFields.firstIndex(of: "Dead Bottles") ?? 13
        let notesIndex = headerFields.firstIndex(of: "Bottle Notes") ?? 14
        let priceIndex = headerFields.firstIndex(of: "Average Price") ?? 15
        let tastedIndex = headerFields.firstIndex(of: "Tasted?") ?? 16
        let reviewsIndex = headerFields.firstIndex(of: "External Reviews") ?? 17
        
        // CRITICAL DEBUG: Verify the dead bottles index is correct
        print("🔍 HEADER VERIFICATION:")
        print("  - Dead Bottles field index: \(deadBottlesIndex)")
        if deadBottlesIndex < headerFields.count {
            print("  - Field at that index: '\(headerFields[deadBottlesIndex])'")
            
            // Double-check this is really the Dead Bottles field
            if headerFields[deadBottlesIndex] != "Dead Bottles" {
                // Try to find it by substring
                for (index, field) in headerFields.enumerated() {
                    if field.contains("Dead") || field.contains("Finished") {
                        print("  ⚠️ Possible alternative 'Dead Bottles' field found at index \(index): '\(field)'")
                    }
                }
            }
        } else {
            print("  ⚠️ Dead Bottles index \(deadBottlesIndex) is out of bounds (fields count: \(headerFields.count))")
        }
        
        print("🔍 CSV STRUCTURE ANALYSIS:")
        print("  - Total header fields: \(headerFields.count)")
        print("  - First row field count: \(rows.count > 1 ? parseCSVRow(rows[1]).count : 0)")
        for (index, field) in headerFields.enumerated() {
            print("  - Field \(index): '\(field)'")
        }
        
        // Create arrays to store changes
        var existingWhiskeysToUpdate: [(Whiskey, [String])] = []
        var newWhiskeysToCreate: [(String, [String])] = []
        var totalBottlesImported = 0
        var totalWhiskeysImported = 0
        
        // Calculate batch size based on total rows
        // Use smaller batches for larger imports to prevent timeout
        let firstPassBatchSize: Int
        if rows.count > 500 {
            firstPassBatchSize = 100  // Increased for speed
        } else if rows.count > 200 {
            firstPassBatchSize = 150  // Increased for speed
        } else {
            firstPassBatchSize = 200
        }
        
        print("Using first pass batch size of \(firstPassBatchSize) for \(rows.count) rows")
        
        // Build a dictionary of existing whiskeys using the composite key
        let fetchAllRequest = NSFetchRequest<Whiskey>(entityName: "Whiskey")
        let allWhiskeys = (try? context.fetch(fetchAllRequest)) ?? []
        let existingWhiskeyDict: [String: Whiskey] = Dictionary(uniqueKeysWithValues: allWhiskeys.compactMap { whiskey in
            guard let name = whiskey.name?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
            let proof = String(format: "%.1f", whiskey.proof)
            let isStorePick = whiskey.isStorePick ? "SP" : ""
            let spName = (whiskey.storePickName ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let type = (whiskey.type ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let distillery = (whiskey.distillery ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let key = "\(name)|\(proof)|\(type)|\(distillery)|\(isStorePick)|\(spName)"
            return (key, whiskey)
        })
        
        // FIRST PASS: Analyze CSV data, determine existing vs new whiskeys
        for batch in stride(from: 1, to: rows.count, by: firstPassBatchSize) {
            let endIndex = min(batch + firstPassBatchSize, rows.count)
            
            print("Processing first pass batch \(batch/firstPassBatchSize + 1) of \(rows.count/firstPassBatchSize + 1)")
            
            // Report progress on first pass (15-30%)
            let firstPassProgress = 0.15 + (Double(batch) / Double(rows.count) * 0.15)
            await MainActor.run {
                progressHandler?(firstPassProgress, "Analyzing CSV data (rows \(batch)-\(endIndex-1) of \(rows.count-1))")
            }
            
            // Add a small delay before processing each batch
            try? await Task.sleep(nanoseconds: 100_000_000) // Reduced from 200ms to 100ms
            
            for i in batch..<endIndex {
                let row = rows[i]
                let fields = parseCSVRow(row)
                
                // Skip only if no name field
                if fields.count <= nameIndex { 
                    print("⚠️ Skipping row \(i): insufficient fields (only \(fields.count) fields)")
                    continue 
                }
                
                let whiskeyName = fields[nameIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                if whiskeyName.isEmpty { 
                    print("⚠️ Skipping row \(i): empty name field")
                    continue 
                }
                // Build composite key for this CSV row
                let proof = fields.count > proofIndex ? fields[proofIndex].replacingOccurrences(of: ",", with: ".") : "0.0"
                let proofKey = String(format: "%.1f", Double(proof) ?? 0.0)
                let isStorePick = (fields.count > spIndex ? parseBooleanField(fields[spIndex], initials: "SP") : false) ? "SP" : ""
                let spName = fields.count > spNameIndex ? fields[spNameIndex].lowercased().trimmingCharacters(in: .whitespacesAndNewlines) : ""
                let type = fields.count > typeIndex ? fields[typeIndex].lowercased().trimmingCharacters(in: .whitespacesAndNewlines) : ""
                let distillery = fields.count > distilleryIndex ? fields[distilleryIndex].lowercased().trimmingCharacters(in: .whitespacesAndNewlines) : ""
                let key = "\(whiskeyName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))|\(proofKey)|\(type)|\(distillery)|\(isStorePick)|\(spName)"
                if let existingWhiskey = existingWhiskeyDict[key] {
                    existingWhiskeysToUpdate.append((existingWhiskey, fields))
                } else {
                    newWhiskeysToCreate.append((whiskeyName, fields))
                }
                
                // Check if we need to release memory pressure
                if i % 20 == 0 {
                    autoreleasepool {
                        // Just forces autorelease
                    }
                }
            }
            
            // Save checkpoint after each batch to avoid keeping too many objects in memory
            try safeSave(context: context)
            
            // Add a slightly longer delay between batches
            try? await Task.sleep(nanoseconds: 200_000_000) // Reduced from 500ms to 200ms
        }
        
        print("First pass completed:")
        print("- Total rows processed: \(rows.count - 1)")
        print("- Existing whiskeys to update: \(existingWhiskeysToUpdate.count)")
        print("- New whiskeys to create: \(newWhiskeysToCreate.count)")
        
        await MainActor.run {
            progressHandler?(0.3, "Updating \(existingWhiskeysToUpdate.count) existing whiskeys...")
        }
        
        // Use much smaller batch size for actual processing
        let batchSize = 10  // Increased from 5 to 10 for speed
        
        // SECOND PASS: Apply updates to existing whiskeys in smaller batches
        print("Starting second pass to update existing whiskeys")
        var secondPassCount = 0
        
        // Helper function for smart merging
        func smartMergeWhiskey(existingWhiskey: Whiskey, fields: [String]) {
            print("🔄 Smart merging whiskey: \(existingWhiskey.name ?? "unknown")")
            
            // BOTTLE STATE MERGING
            // Get bottle counts from CSV
            let csvCurrentBottles = fields.count > currentBottlesIndex ? Int16(fields[currentBottlesIndex]) ?? 0 : 0
            let csvOpenBottles = fields.count > openBottlesIndex ? Int16(fields[openBottlesIndex]) ?? 0 : 0
            let csvDeadBottles = fields.count > deadBottlesIndex ? Int16(fields[deadBottlesIndex]) ?? 0 : 0
            
            print("📊 Bottle counts from CSV - Current: \(csvCurrentBottles), Open: \(csvOpenBottles), Dead: \(csvDeadBottles)")
            
            // Get existing bottle instances
            let bottles = existingWhiskey.bottleInstances as? Set<BottleInstance> ?? []
            let aliveBottles = bottles.filter { !$0.isDead }
            let deadBottles = bottles.filter { $0.isDead }
            let openBottles = aliveBottles.filter { $0.isOpen }
            
            print("📊 Current bottle counts - Alive: \(aliveBottles.count), Open: \(openBottles.count), Dead: \(deadBottles.count)")
            
            // RULE 1: Dead bottles must stay dead
            let finalDeadBottleCount = max(csvDeadBottles, Int16(deadBottles.count))
            
            // RULE 2: Total alive bottles (use larger of the two numbers)
            let finalAliveBottleCount = max(csvCurrentBottles, Int16(aliveBottles.count))
            
            // RULE 3: Open bottles (use larger number, can't exceed alive bottles)
            let finalOpenBottleCount = min(
                max(csvOpenBottles, Int16(openBottles.count)),
                finalAliveBottleCount
            )
            
            print("📊 Final bottle counts - Alive: \(finalAliveBottleCount), Open: \(finalOpenBottleCount), Dead: \(finalDeadBottleCount)")
            
            // Update the whiskey properties
            existingWhiskey.numberOfBottles = finalAliveBottleCount
            existingWhiskey.isFinished = finalDeadBottleCount
            
            // Update bottle instances to match these counts
            updateBottleInstances(
                whiskey: existingWhiskey,
                context: context,
                aliveCount: Int(finalAliveBottleCount),
                openCount: Int(finalOpenBottleCount),
                deadCount: Int(finalDeadBottleCount)
            )
            
            // NOTES MERGING
            if fields.count > notesIndex {
                let csvNotes = fields[notesIndex]
                let existingNotes = existingWhiskey.notes ?? ""
                
                // If CSV has notes and they're different from existing
                if !csvNotes.isEmpty && csvNotes != existingNotes {
                    if !existingNotes.isEmpty {
                        // Combine both, marking CSV notes
                        existingWhiskey.notes = existingNotes + "\n\n[From CSV]: " + csvNotes
                    } else {
                        // No existing notes, just use CSV notes
                        existingWhiskey.notes = csvNotes
                    }
                }
            }
            
            // TASTED STATUS
            if fields.count > tastedIndex {
                let csvTasted = parseBooleanField(fields[tastedIndex], initials: "Tasted")
                // RULE: Once tasted, always tasted
                if csvTasted || existingWhiskey.isTasted {
                    existingWhiskey.isTasted = true
                }
            }
            
            // EXTERNAL REVIEWS
            if fields.count > reviewsIndex {
                let csvReviews = fields[reviewsIndex]
                let existingReviews = existingWhiskey.externalReviews ?? ""
                
                // If CSV has reviews and they're different
                if !csvReviews.isEmpty && csvReviews != existingReviews {
                    if !existingReviews.isEmpty {
                        // Combine both sets of reviews
                        existingWhiskey.externalReviews = existingReviews + "\n\n[From CSV]: " + csvReviews
                    } else {
                        // No existing reviews, just use CSV
                        existingWhiskey.externalReviews = csvReviews
                    }
                }
            }
            
            // PRICE MERGING
            if fields.count > priceIndex {
                let csvPrice = parsePrice(fields[priceIndex])
                // If both have non-zero prices
                if csvPrice > 0 && existingWhiskey.price > 0 {
                    // Use higher value
                    existingWhiskey.price = max(csvPrice, existingWhiskey.price)
                } 
                // If only CSV has price
                else if csvPrice > 0 {
                    existingWhiskey.price = csvPrice
                }
            }
            
            // BASIC PROPERTIES - prefer non-empty values from CSV
            if fields.count > typeIndex && !fields[typeIndex].isEmpty {
                existingWhiskey.type = fields[typeIndex]
            }
            
            if fields.count > proofIndex {
                let csvProof = Double(fields[proofIndex].replacingOccurrences(of: ",", with: ".")) ?? 0.0
                if csvProof > 0 {
                    existingWhiskey.proof = csvProof
                }
            }
            
            if fields.count > ageIndex && !fields[ageIndex].isEmpty {
                existingWhiskey.age = fields[ageIndex]
            }
            
            if fields.count > distilleryIndex && !fields[distilleryIndex].isEmpty {
                existingWhiskey.distillery = fields[distilleryIndex]
            }
            
            if fields.count > finishIndex && !fields[finishIndex].isEmpty {
                existingWhiskey.finish = fields[finishIndex]
            }
            
            // For boolean properties, use logical OR
            if fields.count > caskStrengthIndex {
                let csvCaskStrength = parseBooleanField(fields[caskStrengthIndex], initials: "CS")
                if csvCaskStrength {
                    existingWhiskey.isCaskStrength = true
                }
            }
            
            if fields.count > bibIndex {
                let csvBiB = parseBooleanField(fields[bibIndex], initials: "BiB")
                if csvBiB {
                    existingWhiskey.isBiB = true
                }
            }
            
            if fields.count > sibIndex {
                let csvSiB = parseBooleanField(fields[sibIndex], initials: "SiB")
                if csvSiB {
                    existingWhiskey.isSiB = true
                }
            }
            
            if fields.count > spIndex {
                let csvSP = parseBooleanField(fields[spIndex], initials: "SP")
                if csvSP {
                    existingWhiskey.isStorePick = true
                }
            }
            
            if fields.count > spNameIndex && !fields[spNameIndex].isEmpty {
                existingWhiskey.storePickName = fields[spNameIndex]
            }
            
            // Update modification date
            existingWhiskey.modificationDate = Date()
        }
        
        // Helper function to update bottle instances for a whiskey with improved accuracy
        func updateBottleInstances(whiskey: Whiskey, context: NSManagedObjectContext, aliveCount: Int, openCount: Int, deadCount: Int) {
            print("🔄 Starting bottle update for \(whiskey.name ?? "unknown")")
            
            // First make sure the whiskey is valid in the context
            guard isWhiskeyValid(whiskey, in: context) else {
                print("❌ Cannot update bottles: whiskey is not valid in context")
                return
            }
            
            do {
                // Get a fresh reference to the whiskey
                guard let validWhiskey = try context.existingObject(with: whiskey.objectID) as? Whiskey else {
                    print("❌ Cannot get valid whiskey reference")
                    return
                }
                
                // CRITICAL FIX: Delete ALL existing bottles first to prevent duplicates and miscounts
                let fetchRequest: NSFetchRequest<BottleInstance> = BottleInstance.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "whiskey == %@", validWhiskey)
                
                if let existingBottles = try? context.fetch(fetchRequest) {
                    print("DEBUG: Deleting \(existingBottles.count) existing bottles to recreate exact count")
                    for bottle in existingBottles {
                        context.delete(bottle)
                    }
                }
                
                // Save after deleting to avoid conflicts - removed for speed optimization
                // try context.save()
                
                // Now recreate bottles with the exact counts from the CSV
                
                // Step 1: Create alive bottles
                for i in 0..<aliveCount {
                    let newBottle = BottleInstance(context: context)
                    newBottle.id = UUID()
                    newBottle.dateAdded = Date()
                    newBottle.price = validWhiskey.price
                    newBottle.isOpen = i < openCount // Mark as open if needed
                    newBottle.isDead = false
                    newBottle.bottleNumber = Int16(i + 1)
                    newBottle.whiskey = validWhiskey
                }
                
                // Step 2: Create dead bottles - only if explicitly requested
                if deadCount > 0 {
                    for i in 0..<deadCount {
                        let newBottle = BottleInstance(context: context)
                        newBottle.id = UUID()
                        newBottle.dateAdded = Date()
                        newBottle.price = validWhiskey.price
                        newBottle.isOpen = true
                        newBottle.isDead = true
                        newBottle.bottleNumber = Int16(aliveCount + i + 1)
                        newBottle.whiskey = validWhiskey
                    }
                }
                
                // Save with all bottles created - not saving here, will save at batch level
                // try context.save()
                
                // Update whiskey properties to match the CSV
                validWhiskey.numberOfBottles = Int16(aliveCount)
                validWhiskey.isFinished = Int16(deadCount)
                
            } catch {
                print("❌ Error updating bottle instances: \(error)")
            }
        }
        
        // Helper to renumber bottles after changes
        func renumberBottles(for whiskey: Whiskey, context: NSManagedObjectContext) throws {
            // Get a fresh reference to the whiskey
            guard let validWhiskey = try context.existingObject(with: whiskey.objectID) as? Whiskey else {
                print("❌ Cannot renumber bottles: whiskey is not valid in context")
                return
            }
            
            let bottles = validWhiskey.bottleInstances as? Set<BottleInstance> ?? []
            let aliveBottles = bottles.filter { !$0.isDead }.sorted { $0.bottleNumber < $1.bottleNumber }
            let deadBottles = bottles.filter { $0.isDead }.sorted { $0.bottleNumber < $1.bottleNumber }
            
            // Number alive bottles first
            for (index, bottle) in aliveBottles.enumerated() {
                bottle.bottleNumber = Int16(index + 1)
            }
            
            // Number dead bottles next
            let startDeadNumber = aliveBottles.count + 1
            for (index, bottle) in deadBottles.enumerated() {
                bottle.bottleNumber = Int16(startDeadNumber + index)
            }
            
            // Save the changes
            try context.save()
            
            // Update whiskey counts to match reality
            validWhiskey.numberOfBottles = Int16(aliveBottles.count)
            validWhiskey.isFinished = Int16(deadBottles.count)
            try context.save()
        }
        
        for batch in stride(from: 0, to: existingWhiskeysToUpdate.count, by: batchSize) {
            // Get the current batch
            let endIndex = min(batch + batchSize, existingWhiskeysToUpdate.count)
            let currentBatch = Array(existingWhiskeysToUpdate[batch..<endIndex])
            
            print("📊 Processing batch \(batch/batchSize + 1) of \(existingWhiskeysToUpdate.count/batchSize + 1) (items \(batch+1)-\(endIndex))")
            
            // Report progress on second pass (30-65%)
            if existingWhiskeysToUpdate.count > 0 {
                let secondPassProgress = 0.3 + (Double(batch) / Double(existingWhiskeysToUpdate.count) * 0.35)
                await MainActor.run {
                    progressHandler?(secondPassProgress, "Updating existing whiskeys (\(batch+1)-\(endIndex) of \(existingWhiskeysToUpdate.count))")
                }
            }
            
            // Process each whiskey in the batch
            for (existingWhiskey, fields) in currentBatch {
                // Check for timeout every 5 whiskeys
                secondPassCount += 1
                if secondPassCount % 5 == 0 && checkImportTimeout() {
                    print("🛑 Import timeout detected during second pass, aborting after processing \(secondPassCount) whiskeys")
                    throw NSError(domain: "com.barrelbook", code: -1, 
                                  userInfo: [NSLocalizedDescriptionKey: "Import took too long and was aborted during whiskey updates"])
                }
                
                do {
                    // Use our smart merge logic for existing whiskeys instead of just replacing data
                    print("📝 Applying smart merge for existing whiskey: \(existingWhiskey.name ?? "unknown")")
                    smartMergeWhiskey(existingWhiskey: existingWhiskey, fields: fields)
                    
                    // Save changes after each whiskey to avoid large batches
                    try safeSave(context: context)
                    
                    // Count this whiskey's bottles for stats
                    let currentBottles = fields.count > currentBottlesIndex ? Int16(fields[currentBottlesIndex]) ?? existingWhiskey.numberOfBottles : existingWhiskey.numberOfBottles
                    totalBottlesImported += Int(currentBottles)
                } catch {
                    print("❌ Error during smart merge for whiskey '\(existingWhiskey.name ?? "unknown")': \(error)")
                    print("⚠️ Continuing with next whiskey...")
                    
                    // Try to recover the context if possible
                    if context.hasChanges {
                        context.rollback()
                    }
                }
            }
            
            // Save after each batch is processed
            try safeSave(context: context)
            print("✅ Saved batch \(batch/batchSize + 1)")
            
            // Add a longer delay between batches to reduce memory pressure
            try await Task.sleep(nanoseconds: 300_000_000) // Reduced from 500ms to 300ms
        }
        
        await MainActor.run {
            progressHandler?(0.65, "Creating \(newWhiskeysToCreate.count) new whiskeys...")
        }
        
        // Use a tiny batch size for creating new whiskeys (which is the most memory intensive)
        let createBatchSize = 10 // Increased from 3 to 10 for speed
        
        // THIRD PASS: Create new whiskeys in smaller batches
        print("Starting third pass to create new whiskeys")
        var thirdPassCount = 0
        
        for batch in stride(from: 0, to: newWhiskeysToCreate.count, by: createBatchSize) {
            // Get the current batch
            let endIndex = min(batch + createBatchSize, newWhiskeysToCreate.count)
            let currentBatch = Array(newWhiskeysToCreate[batch..<endIndex])
            
            print("📊 Processing batch \(batch/createBatchSize + 1) of \(newWhiskeysToCreate.count/createBatchSize + 1) (items \(batch+1)-\(endIndex))")
            
            // Report progress on third pass (65-95%)
            if newWhiskeysToCreate.count > 0 {
                let thirdPassProgress = 0.65 + (Double(batch) / Double(newWhiskeysToCreate.count) * 0.30)
                await MainActor.run {
                    progressHandler?(thirdPassProgress, "Creating new whiskeys (\(batch+1)-\(endIndex) of \(newWhiskeysToCreate.count))")
                }
            }
            
            // Process each whiskey in the batch
            for (whiskeyName, fields) in currentBatch {
                // Check for timeout every 5 whiskeys
                thirdPassCount += 1
                if thirdPassCount % 5 == 0 && checkImportTimeout() {
                    print("🛑 Import timeout detected during third pass, aborting after processing \(thirdPassCount) whiskeys")
                    throw NSError(domain: "com.barrelbook", code: -1, 
                                  userInfo: [NSLocalizedDescriptionKey: "Import took too long and was aborted during whiskey creation"])
                }
                
                do {
                    // Create a new whiskey entity
                    let newWhiskey = Whiskey(context: context)
                    newWhiskey.id = UUID()
                    newWhiskey.name = whiskeyName
                    newWhiskey.type = fields.count > typeIndex ? fields[typeIndex] : ""
                    newWhiskey.proof = fields.count > proofIndex ? Double(fields[proofIndex].replacingOccurrences(of: ",", with: ".")) ?? 0.0 : 0.0
                    newWhiskey.age = fields.count > ageIndex ? fields[ageIndex] : ""
                    newWhiskey.distillery = fields.count > distilleryIndex ? fields[distilleryIndex] : ""
                    newWhiskey.finish = fields.count > finishIndex ? fields[finishIndex] : ""
                    newWhiskey.isBiB = fields.count > bibIndex ? parseBooleanField(fields[bibIndex], initials: "BiB") : false
                    newWhiskey.isSiB = fields.count > sibIndex ? parseBooleanField(fields[sibIndex], initials: "SiB") : false
                    newWhiskey.isStorePick = fields.count > spIndex ? parseBooleanField(fields[spIndex], initials: "SP") : false
                    newWhiskey.storePickName = fields.count > spNameIndex ? fields[spNameIndex] : ""
                    newWhiskey.isOpen = fields.count > openBottlesIndex ? Int16(fields[openBottlesIndex]) ?? 0 > 0 : false
                    newWhiskey.notes = fields.count > notesIndex ? fields[notesIndex] : ""
                    newWhiskey.price = fields.count > priceIndex ? parsePrice(fields[priceIndex]) : 0.0
                    newWhiskey.isCaskStrength = fields.count > caskStrengthIndex ? parseBooleanField(fields[caskStrengthIndex], initials: "CS") : false
                    newWhiskey.externalReviews = fields.count > reviewsIndex ? fields[reviewsIndex] : ""
                    newWhiskey.status = "owned"
                    newWhiskey.addedDate = Date()
                    newWhiskey.modificationDate = Date()
                    
                    // Get bottle counts
                    let currentBottles = fields.count > currentBottlesIndex ? Int16(fields[currentBottlesIndex]) ?? 1 : 1
                    let openBottles = fields.count > openBottlesIndex ? Int16(fields[openBottlesIndex]) ?? 0 : 0
                    
                    // CRITICAL DEBUGGING: Log everything about the dead bottles field
                    let rawDeadBottleValue = fields.count > deadBottlesIndex ? fields[deadBottlesIndex] : "FIELD NOT PRESENT"
                    print("🔍 NEW WHISKEY DEAD BOTTLE DEBUG for '\(whiskeyName)':")
                    print("  - CSV field index: \(deadBottlesIndex)")
                    print("  - Field count: \(fields.count)")
                    print("  - Raw value: '\(rawDeadBottleValue)'")
                    print("  - Trimmed value: '\(rawDeadBottleValue.trimmingCharacters(in: .whitespacesAndNewlines))'")
                    if let asInt = Int16(rawDeadBottleValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        print("  - Parsed as Int16: \(asInt)")
                    } else {
                        print("  - Could not parse as Int16")
                    }
                    
                    // Extremely careful dead bottle parsing
                    let deadBottlesCount: Int16
                    if fields.count > deadBottlesIndex {
                        let trimmedValue = fields[deadBottlesIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedValue.isEmpty || trimmedValue == "0" {
                            deadBottlesCount = 0
                            print("  - FINAL DECISION: Empty or zero value, setting dead bottles to 0")
                        } else if let parsed = Int16(trimmedValue), parsed > 0 {
                            deadBottlesCount = parsed
                            print("  - FINAL DECISION: Valid positive number, setting dead bottles to \(parsed)")
                        } else {
                            deadBottlesCount = 0
                            print("  - FINAL DECISION: Invalid or non-positive number, setting dead bottles to 0")
                        }
                    } else {
                        deadBottlesCount = 0
                        print("  - FINAL DECISION: Field not present, setting dead bottles to 0")
                    }
                    
                    // Set total bottle count - CRITICAL FIX: Set exact values from CSV
                    newWhiskey.numberOfBottles = currentBottles
                    newWhiskey.isFinished = deadBottlesCount
                    
                    // PERFORMANCE IMPROVEMENT: Don't save after each whiskey
                    // try safeSave(context: context)
                    
                    // Now create bottle instances in a separate step - REWRITTEN FOR ACCURACY AND SPEED
                    if isWhiskeyValid(newWhiskey, in: context) {
                        print("Creating \(currentBottles) active + \(deadBottlesCount) dead bottles for \(whiskeyName)")
                        
                        // Create current bottles
                        for i in 0..<Int(currentBottles) {
                            let bottle = BottleInstance(context: context)
                            bottle.id = UUID()
                            bottle.dateAdded = Date()
                            bottle.price = newWhiskey.price
                            bottle.isOpen = i < Int(openBottles)
                            bottle.isDead = false
                            bottle.bottleNumber = Int16(i + 1)
                            bottle.whiskey = newWhiskey
                        }
                        
                        // Create dead bottles if needed
                        if deadBottlesCount > 0 {
                            for i in 0..<Int(deadBottlesCount) {
                                let bottle = BottleInstance(context: context)
                                bottle.id = UUID()
                                bottle.dateAdded = Date()
                                bottle.price = newWhiskey.price
                                bottle.isOpen = true
                                bottle.isDead = true
                                bottle.bottleNumber = Int16(Int(currentBottles) + i + 1)
                                bottle.whiskey = newWhiskey
                            }
                        }
                    }
                    
                    totalBottlesImported += Int(currentBottles) + Int(deadBottlesCount)
                    totalWhiskeysImported += 1
                } catch {
                    print("Error creating new whiskey '\(whiskeyName)': \(error)")
                    continue
                }
            }
            
            // Save only every few batches (or at the end) to improve performance
            if batch % (createBatchSize * 5) == 0 || batch + createBatchSize >= newWhiskeysToCreate.count {
                try safeSave(context: context)
                print("✅ Saved batch \(batch/createBatchSize + 1)")
                
                // Add a shorter delay between savepoints
                try await Task.sleep(nanoseconds: 200_000_000) // Reduced to improve speed
                
                // Force a more aggressive memory cleanup after big batches
                autoreleasepool { }
            } else {
                // Just a tiny pause between batches that don't save
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        
        await MainActor.run {
            progressHandler?(0.95, "Finalizing import...")
        }
        
        // Final save to ensure all changes are persisted
        try safeSave(context: context)
        
        // Validate and fix any invalid relationships before finishing
        _ = validateBottleRelationships(context: context)
        
        // Perform a manual checkpoint to ensure WAL file is processed
        performDatabaseCheckpoint(context: context)
        
        // Calculate and log the total import time
        let importDuration = Date().timeIntervalSince(importStartTime)
        print("Import completed successfully in \(String(format: "%.1f", importDuration)) seconds:")
        print("- Total whiskeys imported: \(totalWhiskeysImported)")
        print("- Total bottles imported: \(totalBottlesImported)")
        
        // Log the actual counts for verification
        if let whiskeys = try? context.fetch(Whiskey.fetchRequest()) {
            print("VERIFICATION - Total whiskeys in database after import: \(whiskeys.count)")
            let bottleFetchRequest = NSFetchRequest<BottleInstance>(entityName: "BottleInstance")
            if let bottles = try? context.fetch(bottleFetchRequest) {
                let activeBottles = bottles.filter { !$0.isDead }
                print("VERIFICATION - Total active bottles in database: \(activeBottles.count)")
                print("VERIFICATION - Total dead bottles in database: \(bottles.count - activeBottles.count)")
            }
        }
        
        // Fix bottle numbering after import
        fixBottleNumbering(in: context)
        
        // Wait for any pending operations to complete
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        
        // Force sync after import completes
        if persistenceController.container.viewContext.automaticallyMergesChangesFromParent {
            DispatchQueue.main.async {
                persistenceController.forceSync()
            }
        }
        
        // Final progress update
        await MainActor.run {
            progressHandler?(1.0, "Import complete!")
        }
        
        // FINAL STEP: Run a cleanup to catch any unexpected dead bottles
        // This is a safety net in case something went wrong earlier
        do {
            print("🧹 Running final cleanup to catch any unexpected dead bottles...")
            
            // Create a cleanup context
            let cleanupContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            cleanupContext.parent = context
            
            // Function to check whether a whiskey should have dead bottles
            let shouldHaveDeadBottles = { (whiskey: Whiskey) -> Bool in
                // A whiskey should have dead bottles only if isFinished > 0
                return whiskey.isFinished > 0
            }
            
            try await cleanupContext.perform {
                // Fetch all whiskeys that should NOT have dead bottles (isFinished = 0)
                let whiskeyRequest = NSFetchRequest<Whiskey>(entityName: "Whiskey")
                whiskeyRequest.predicate = NSPredicate(format: "isFinished == 0")
                
                if let whiskeys = try? cleanupContext.fetch(whiskeyRequest) {
                    print("🔍 Found \(whiskeys.count) whiskeys that should NOT have any dead bottles")
                    
                    var fixedCount = 0
                    for whiskey in whiskeys {
                        // Get all bottles for this whiskey
                        let bottleRequest = NSFetchRequest<BottleInstance>(entityName: "BottleInstance")
                        bottleRequest.predicate = NSPredicate(format: "whiskey == %@ AND isDead == %@", whiskey, NSNumber(value: true))
                        
                        if let deadBottles = try? cleanupContext.fetch(bottleRequest), !deadBottles.isEmpty {
                            print("⚠️ Found \(deadBottles.count) unexpected dead bottles for '\(whiskey.name ?? "unknown")' - cleaning up")
                            
                            // Delete these unexpected dead bottles
                            for bottle in deadBottles {
                                cleanupContext.delete(bottle)
                            }
                            
                            fixedCount += 1
                        }
                    }
                    
                    // Save the changes
                    if fixedCount > 0 {
                        try cleanupContext.save()
                        try context.save()
                        print("✅ Fixed \(fixedCount) whiskeys with unexpected dead bottles")
                    } else {
                        print("✅ No unexpected dead bottles found")
                    }
                }
            }
        } catch {
            print("⚠️ Warning during final cleanup: \(error.localizedDescription)")
            // Don't throw here - this is just a final safety check
        }
    }
    
    // Helper method to safely perform a context save with retries and improved error handling
    private func safeSave(context: NSManagedObjectContext, retries: Int = 5) throws {
        var attempts = 0
        var lastError: Error?
        
        while attempts < retries {
            do {
                try context.save()
                return
            } catch let error as NSError {
                attempts += 1
                lastError = error
                
                // If database is busy or locked, wait and retry
                if error.domain == NSCocoaErrorDomain && 
                   (error.code == NSCoreDataError || 
                    error.localizedDescription.contains("database is locked") || 
                    error.localizedDescription.contains("SQLite error")) {
                    print("⚠️ Database busy on save attempt \(attempts), waiting and retrying...")
                    // Increase wait time for each retry attempt
                    Thread.sleep(forTimeInterval: Double(attempts) * 0.5) // Incremental backoff
                } else {
                    // For other errors, log details and rethrow
                    print("❌ Error during context save: \(error.localizedDescription)")
                    if let detailedError = error.userInfo["NSDetailedErrors"] as? [NSError] {
                        print("Detailed errors: \(detailedError)")
                    }
                    throw error
                }
            }
        }
        
        // If we got here, all retries failed
        if let lastError = lastError {
            throw lastError
        } else {
            throw NSError(domain: "com.barrelbook", code: -1, 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to save context after \(retries) attempts"])
        }
    }
    
    // Helper function to perform a clean database checkpoint
    private func performDatabaseCheckpoint(context: NSManagedObjectContext) {
        print("Performing manual database checkpoint...")
        
        guard let psc = context.persistentStoreCoordinator else {
            print("⚠️ Could not access persistent store coordinator for checkpoint")
            return
        }
        
        // Get the persistence controller to manage CloudKit sync
        let persistenceController = PersistenceController.shared
        
        // Temporarily disable CloudKit sync during checkpoint
        let wasSyncing = persistenceController.container.viewContext.automaticallyMergesChangesFromParent
        persistenceController.container.viewContext.automaticallyMergesChangesFromParent = false
        
        // Pause to let any pending operations complete
        Thread.sleep(forTimeInterval: 0.5)
        
        do {
                // First save any pending changes
                try context.save()
                
            // Let's skip the actual checkpoint as it's causing CloudKit issues
            // and Core Data should handle WAL checkpoints automatically
            print("✅ Successfully saved changes without explicit checkpoint")
                
            // Sleep a bit to let any background operations complete
            Thread.sleep(forTimeInterval: 0.5)
        } catch {
            // Not critical if this fails, just log it
            print("⚠️ Error during save: \(error.localizedDescription)")
        }
        
        // Re-enable CloudKit sync after checkpoint is complete
        print("Restoring sync state after checkpoint")
        persistenceController.container.viewContext.automaticallyMergesChangesFromParent = wasSyncing
    }
    
    // Helper to validate relationships between whiskeys and bottle instances
    private func validateBottleRelationships(context: NSManagedObjectContext) -> Bool {
        do {
            print("🔍 Validating whiskey-bottle relationships...")
            
            // Check for any bottle instances with invalid whiskey relationships
            let bottleFetchRequest: NSFetchRequest<BottleInstance> = BottleInstance.fetchRequest()
            let bottles = try context.fetch(bottleFetchRequest)
            
            var invalidBottles = 0
            var orphanedBottles: [BottleInstance] = []
            
            for bottle in bottles {
                if bottle.whiskey == nil {
                    // This bottle has a nil whiskey, which would trigger the error
                    print("⚠️ Found bottle with nil whiskey relationship: \(bottle.id?.uuidString ?? "unknown")")
                    orphanedBottles.append(bottle)
                    invalidBottles += 1
                } else if bottle.whiskey?.managedObjectContext == nil {
                    // This bottle has a whiskey reference, but that whiskey is no longer in the context
                    print("⚠️ Found bottle with invalid whiskey (not in context): \(bottle.id?.uuidString ?? "unknown")")
                    orphanedBottles.append(bottle)
                    invalidBottles += 1
                }
            }
            
            if invalidBottles > 0 {
                print("🔄 Found \(invalidBottles) bottles with invalid whiskey relationships, cleaning up...")
                
                // Delete the orphaned bottles
                for bottle in orphanedBottles {
                    context.delete(bottle)
                }
                
                try context.save()
                print("✅ Successfully removed \(invalidBottles) orphaned bottles")
                return true
            }
            
            print("✅ All whiskey-bottle relationships are valid")
            return true
        } catch {
            print("❌ Error during relationship validation: \(error)")
            return false
        }
    }
    
    // Helper to validate a whiskey before creating bottles for it
    private func isWhiskeyValid(_ whiskey: Whiskey, in context: NSManagedObjectContext) -> Bool {
        // First check if this whiskey is still in the context
        guard whiskey.managedObjectContext != nil else {
            print("⚠️ Whiskey \(whiskey.name ?? "unknown") is no longer in a managed object context")
            return false
        }
        
        // Check if the whiskey has a valid object ID
        if whiskey.objectID.isTemporaryID {
            do {
                // Try to obtain a permanent ID
                print("🔄 Obtaining permanent ID for whiskey \(whiskey.name ?? "unknown")")
                try context.obtainPermanentIDs(for: [whiskey])
            } catch {
                print("❌ Failed to obtain permanent ID: \(error)")
                return false
            }
        }
        
        // Verify the whiskey still exists in the context
        do {
            if let _ = try context.existingObject(with: whiskey.objectID) as? Whiskey {
                return true
            } else {
                print("⚠️ Whiskey \(whiskey.name ?? "unknown") doesn't exist in context")
                return false
            }
        } catch {
            print("❌ Error validating whiskey: \(error)")
            return false
        }
    }
    
    private func createBottles(
        context: NSManagedObjectContext,
        fields: [String],
        indices: (
            name: Int,
            type: Int,
            proof: Int,
            age: Int,
            distillery: Int,
            finish: Int,
            caskStrength: Int,
            bib: Int,
            sib: Int,
            sp: Int,
            spName: Int,
            notes: Int,
            price: Int,
            tasted: Int,
            reviews: Int
        ),
        currentBottles: Int,
        openBottles: Int,
        deadBottles: Int
    ) async throws {
        let price = Double(fields[indices.price]) ?? 0.0
        
        // Create arrays to store new whiskeys
        var newCurrentBottles: [Whiskey] = []
        var newDeadBottles: [Whiskey] = []
        
        // Create current bottles
        for i in 0..<currentBottles {
            let whiskey = Whiskey(context: context)
            whiskey.id = UUID()
            whiskey.name = fields[indices.name]
            whiskey.type = fields[indices.type]
            whiskey.proof = Double(fields[indices.proof]) ?? 0.0
            whiskey.age = fields[indices.age]
            whiskey.distillery = fields[indices.distillery]
            whiskey.finish = fields[indices.finish]
            whiskey.isCaskStrength = parseBooleanField(fields[indices.caskStrength], initials: "CS")
            whiskey.isBiB = parseBooleanField(fields[indices.bib], initials: "BiB")
            whiskey.isSiB = parseBooleanField(fields[indices.sib], initials: "SiB")
            whiskey.isStorePick = parseBooleanField(fields[indices.sp], initials: "SP")
            whiskey.storePickName = fields[indices.spName]
            whiskey.notes = fields[indices.notes]
            whiskey.price = price
            whiskey.isTasted = parseBooleanField(fields[indices.tasted], initials: "Tasted")
            whiskey.externalReviews = fields[indices.reviews]
            whiskey.modificationDate = Date()
            
            // Mark as open if within the open bottles count
            whiskey.isOpen = i < openBottles
            whiskey.isFinished = 0
            
            newCurrentBottles.append(whiskey)
        }
        
        // Create dead bottles
        for _ in 0..<deadBottles {
            guard deadBottles > 0 else {
                print("DEBUG: Skipping dead bottle creation as count is 0")
                break
            }
            
            let whiskey = Whiskey(context: context)
            whiskey.id = UUID()
            whiskey.name = fields[indices.name]
            whiskey.type = fields[indices.type]
            whiskey.proof = Double(fields[indices.proof]) ?? 0.0
            whiskey.age = fields[indices.age]
            whiskey.distillery = fields[indices.distillery]
            whiskey.finish = fields[indices.finish]
            whiskey.isCaskStrength = parseBooleanField(fields[indices.caskStrength], initials: "CS")
            whiskey.isBiB = parseBooleanField(fields[indices.bib], initials: "BiB")
            whiskey.isSiB = parseBooleanField(fields[indices.sib], initials: "SiB")
            whiskey.isStorePick = parseBooleanField(fields[indices.sp], initials: "SP")
            whiskey.storePickName = fields[indices.spName]
            whiskey.notes = fields[indices.notes]
            whiskey.price = price
            whiskey.isTasted = parseBooleanField(fields[indices.tasted], initials: "Tasted")
            whiskey.externalReviews = fields[indices.reviews]
            whiskey.modificationDate = Date()
            
            // Mark as dead
            whiskey.isOpen = true
            whiskey.isFinished = 1
            
            newDeadBottles.append(whiskey)
        }
        
        // Save all changes at once
        try context.save()
    }
    
    // Emergency method to fix prices if all else fails
    private func emergencyPriceRepair(rows: [String], context: NSManagedObjectContext, detectedPriceIndex: Int? = nil) {
        guard rows.count > 1 else { return }
        
        print("Starting emergency price repair from CSV data")
        
        // First row is header, so we skip it
        let headerRow = rows[0]
        let headerFields = parseCSVRow(headerRow)
        
        // Get name index and price index
        let nameIndex = 0 // Assuming name is always first column
        
        // Auto-detect the price index from the header or use the provided one
        var priceIndex = detectedPriceIndex ?? 13 // Use detected index if provided, otherwise default
        
        // If no detected index was provided, try to find it in the header
        if detectedPriceIndex == nil {
            for (index, field) in parseCSVRow(headerRow).enumerated() {
                if field.contains("Price") {
                    priceIndex = index
                    print("🔍 REPAIR: Auto-detected price column at index \(priceIndex)")
                    break
                }
            }
        } else {
            print("🔍 REPAIR: Using provided price column at index \(priceIndex)")
        }
        
        // Get all whiskeys from Core Data
        guard let whiskeys = try? context.fetch(NSFetchRequest<Whiskey>(entityName: "Whiskey")) else {
            print("❌ Could not fetch whiskeys for emergency repair")
            return
        }
        
        var repairCount = 0
        
        // Process each data row
        for rowIdx in 1..<rows.count {
            let row = rows[rowIdx]
            let fields = parseCSVRow(row)
            
            // Skip invalid rows
            guard fields.count > priceIndex, !fields[nameIndex].isEmpty else { continue }
            
            let name = fields[nameIndex]
            let priceStr = fields[priceIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Find matching whiskey by name
            if let whiskey = whiskeys.first(where: { ($0.name ?? "").lowercased() == name.lowercased() }) {
                // Parse price - try various methods
                var price: Double = 0.0
                
                // First try - remove $ and parse
                if priceStr.hasPrefix("$") {
                    if let parsed = Double(priceStr.dropFirst()) {
                        price = parsed
                    }
                }
                
                // Second try - clean and parse
                if price == 0.0 {
                    let cleaned = priceStr
                        .replacingOccurrences(of: "$", with: "")
                        .replacingOccurrences(of: " ", with: "")
                        .replacingOccurrences(of: ",", with: ".")
                    if let parsed = Double(cleaned), parsed > 0 {
                        price = parsed
                    }
                }
                
                // If we got a price, update the whiskey
                if price > 0 {
                    print("🔄 EMERGENCY REPAIR: Setting price for '\(name)' to $\(price)")
                    whiskey.price = price
                    whiskey.setValue(price, forKey: "price")
                    whiskey.setPrimitiveValue(price, forKey: "price")
                    repairCount += 1
                }
            }
        }
        
        // Save context after all repairs
        if repairCount > 0 {
            do {
                try context.save()
                print("✅ EMERGENCY REPAIR COMPLETE: Fixed \(repairCount) whiskey prices")
            } catch {
                print("❌ EMERGENCY REPAIR FAILED: \(error.localizedDescription)")
            }
        } else {
            print("❌ EMERGENCY REPAIR FAILED: Could not repair any prices")
        }
    }
    
    private func parseBooleanField(_ value: String, initials: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespaces).lowercased()
        
        // First try to parse as a number
        if let numericValue = Int16(trimmedValue) {
            return numericValue > 0
        }
        
        // If not a number, check for standard boolean values
        return trimmedValue == "yes" || 
               trimmedValue == "y" ||
               trimmedValue == "true" || 
               trimmedValue == "1" ||
               trimmedValue == "finished" ||
               (!initials.isEmpty && (trimmedValue == initials.lowercased() || trimmedValue == "bib" || trimmedValue == "sib" || trimmedValue == "sp"))
    }
    
    func parseNumericField(_ value: String) -> Int16 {
        let trimmedValue = value.trimmingCharacters(in: .whitespaces)
        
        // First try to parse as a number
        if let numericValue = Int16(trimmedValue) {
            return numericValue
        }
        
        // If not a number, check for boolean-like values
        let lowercased = trimmedValue.lowercased()
        if lowercased == "yes" || lowercased == "y" || lowercased == "true" || lowercased == "1" || lowercased == "finished" {
            return 1
        }
        
        return 0
    }
    
    private func escapeCSV(_ string: String) -> String {
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            return "\"\(string.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return string
    }
    
    func parseCSVRow(_ row: String) -> [String] {
        // Handle empty rows
        if row.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }
        
        var fields: [String] = []
        var currentField = ""
        var insideQuotes = false
        
        // Convert to character array for easier processing
        let chars = Array(row)
        var i = 0
        
        while i < chars.count {
            let char = chars[i]
            
            // Handle quoted fields
            if char == "\"" {
                // Check for escaped quotes (two double quotes in sequence)
                if insideQuotes && i + 1 < chars.count && chars[i + 1] == "\"" {
                    currentField.append("\"")
                    i += 2 // Skip both quotes
                    continue
                } else {
                    insideQuotes.toggle()
                    i += 1
                    continue
                }
            }
            
            // Handle field separator (comma)
            if char == "," && !insideQuotes {
                fields.append(currentField)
                currentField = ""
                i += 1
                continue
            }
            
            // Handle all other characters
            currentField.append(char)
            i += 1
        }
        
        // Add the last field
        fields.append(currentField)
        
        // Clean up each field
        return fields.map { field in
            var cleaned = field.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Remove surrounding quotes if present
            if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count >= 2 {
                cleaned = String(cleaned.dropFirst().dropLast())
            }
            
            return cleaned
        }
    }
    
    // Helper to properly escape CSV fields
    private func escapeCSVField(_ field: String) -> String {
        // If the field contains a comma, quote, or newline, it needs to be quoted
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            // Double any quotes in the field
            let escapedField = field.replacingOccurrences(of: "\"", with: "\"\"")
            // Wrap the field in quotes
            return "\"\(escapedField)\""
        }
        return field
    }
    
    // Add helper function for robust price parsing
    private func parsePrice(_ priceStr: String) -> Double {
        // Remove any currency symbols and whitespace
        let cleaned = priceStr
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Try to parse the cleaned string
        if let price = Double(cleaned), price > 0 {
            return price
        }
        
        // If parsing fails, try removing any non-numeric characters except decimal point
        let numericOnly = cleaned.filter { $0.isNumber || $0 == "." }
        if let price = Double(numericOnly), price > 0 {
            return price
        }
        
        // If all parsing attempts fail, return 0
        return 0.0
    }
    
    // Helper function to safely create a bottle instance with validation
    private func createBottleInstance(for whiskey: Whiskey, 
                                    context: NSManagedObjectContext,
                                    isOpen: Bool = false,
                                    isDead: Bool = false,
                                    bottleNumber: Int16 = 1) -> BottleInstance? {
        // Double check the whiskey is still valid
        guard isWhiskeyValid(whiskey, in: context) else {
            print("⚠️ Attempted to create bottle for invalid whiskey: \(whiskey.name ?? "unknown")")
            return nil
        }
        
        // Create the bottle instance - no need for extra validation that slows things down
        let bottle = BottleInstance(context: context)
        bottle.id = UUID()
        bottle.dateAdded = Date()
        bottle.price = whiskey.price
        bottle.isOpen = isOpen
        bottle.isDead = isDead
        bottle.bottleNumber = bottleNumber
        bottle.whiskey = whiskey
        
        return bottle
    }
    
    // Important: Simplified fixBottleNumbering function to be much faster
    private func fixBottleNumbering(in context: NSManagedObjectContext) {
        print("Starting quick bottle numbering validation...")
        
        do {
            // This is a much lighter verification that only checks for and fixes major inconsistencies
            let fetchRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
            let whiskeys = try context.fetch(fetchRequest)
            var fixCount = 0
            
            // Use an array to track any whiskeys that need saving to avoid context conflicts
            var whiskeyIdsToSave = [NSManagedObjectID]()
            
            for whiskey in whiskeys {
                // Count the actual bottles
                let bottleFetchRequest: NSFetchRequest<BottleInstance> = BottleInstance.fetchRequest()
                bottleFetchRequest.predicate = NSPredicate(format: "whiskey == %@", whiskey)
                
                if let bottles = try? context.fetch(bottleFetchRequest) {
                    // Create copies of bottles to avoid modifying a collection while iterating
                    let aliveBottles = bottles.filter { !$0.isDead }.sorted { $0.bottleNumber < $1.bottleNumber }
                    let deadBottles = bottles.filter { $0.isDead }.sorted { $0.bottleNumber < $1.bottleNumber }
                    
                    let alive = aliveBottles.count
                    let dead = deadBottles.count
                    
                    // Only fix if the counts don't match the expected counts
                    if alive != Int(whiskey.numberOfBottles) || dead != Int(whiskey.isFinished) {
                        print("Fixing count mismatch for \(whiskey.name ?? "unknown")")
                        fixCount += 1
                        
                        // Create a new array with updated bottle numbers for alive bottles
                        for (index, bottle) in aliveBottles.enumerated() {
                            let newNumber = Int16(index + 1)
                            if bottle.bottleNumber != newNumber {
                                bottle.bottleNumber = newNumber
                            }
                    }
                    
                        // Create a new array with updated bottle numbers for dead bottles
                        let startNumberForDeadBottles = aliveBottles.count + 1
                        for (index, bottle) in deadBottles.enumerated() {
                            let newNumber = Int16(startNumberForDeadBottles + index)
                            if bottle.bottleNumber != newNumber {
                                bottle.bottleNumber = newNumber
                            }
                        }
                        
                        // Update the whiskey's counts to match reality - but don't save yet
                        whiskey.numberOfBottles = Int16(aliveBottles.count)
                        whiskey.isFinished = Int16(deadBottles.count)
                        
                        // Track this whiskey for saving
                        whiskeyIdsToSave.append(whiskey.objectID)
                    
                        // Save periodically to avoid large batch changes
                        if whiskeyIdsToSave.count >= 10 {
                            try saveWhiskeys(with: whiskeyIdsToSave, in: context)
                            whiskeyIdsToSave.removeAll()
                        }
                    }
                }
            }
            
            // Save any remaining whiskeys
            if !whiskeyIdsToSave.isEmpty {
                try saveWhiskeys(with: whiskeyIdsToSave, in: context)
            }
            
            if fixCount > 0 {
                print("Fixed bottle numbering for \(fixCount) whiskeys")
            } else {
                print("No bottle numbering issues found")
            }
        } catch {
            print("Error during bottle numbering check: \(error)")
        }
    }
    
    // Helper to safely save whiskeys by ID
    private func saveWhiskeys(with ids: [NSManagedObjectID], in context: NSManagedObjectContext) throws {
        // Use a separate context for saving to avoid conflicts
        let saveContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        saveContext.parent = context
        
        // Process each whiskey in the save context
        for id in ids {
            if let whiskey = try? saveContext.existingObject(with: id) as? Whiskey {
                // The whiskey is already updated in the parent context, we just need to save
                print("Saving whiskey: \(whiskey.name ?? "unknown")")
                
                // Ensure bottles are properly renumbered
                whiskey.renumberBottles()
            }
        }
        
        // Save the child context
        try saveContext.save()
        
        // Then save the parent context
        try context.save()
    }
    
    // Fix for existing whiskeys - this is where the duplicate bottle issue is occurring
    private func updateExistingWhiskey(_ existingWhiskey: Whiskey, 
                                     with fields: [String], 
                                     context: NSManagedObjectContext,
                                     currentBottlesIndex: Int,
                                     openBottlesIndex: Int,
                                     deadBottlesIndex: Int) throws {
        // Get current bottle counts from CSV
        let currentBottles = fields.count > currentBottlesIndex 
            ? Int16(fields[currentBottlesIndex]) ?? existingWhiskey.numberOfBottles 
            : existingWhiskey.numberOfBottles
        
        let openBottles = fields.count > openBottlesIndex 
            ? Int16(fields[openBottlesIndex]) ?? (existingWhiskey.isOpen ? 1 : 0) 
            : (existingWhiskey.isOpen ? 1 : 0)
                    
        // IMPORTANT: Explicitly check for dead bottles and ensure it's 0 if not provided
        // Get the raw dead bottle field value for debugging
        let rawDeadBottleValue = fields.count > deadBottlesIndex ? fields[deadBottlesIndex] : ""
        
        // Parse dead bottles count more carefully
        let deadBottlesCount: Int16
        if fields.count > deadBottlesIndex && !fields[deadBottlesIndex].isEmpty {
            // If the field value is "0" or equals to 0, ensure we use 0
            if fields[deadBottlesIndex].trimmingCharacters(in: .whitespaces) == "0" {
                deadBottlesCount = 0
            } else {
                // Only set non-zero value if explicitly provided
                let parsed = Int16(fields[deadBottlesIndex].trimmingCharacters(in: .whitespaces)) ?? 0
                deadBottlesCount = parsed
            }
        } else {
            // If no value provided, default to 0 (no dead bottles)
            deadBottlesCount = 0
        }
        
        print("DEBUG: Processing whiskey '\(existingWhiskey.name ?? "unknown")'")
        print("DEBUG: CSV values - Current: \(currentBottles), Open: \(openBottles), Dead: \(deadBottlesCount)")
        print("DEBUG: Raw dead bottle value from CSV: '\(rawDeadBottleValue)'")
        
        // Check if we need to update bottles
        let needToUpdateBottles = currentBottles != existingWhiskey.numberOfBottles || 
                              openBottles != (existingWhiskey.isOpen ? 1 : 0) || 
                              deadBottlesCount != existingWhiskey.isFinished
        
        // Set total bottle count on the whiskey
        existingWhiskey.numberOfBottles = currentBottles
        existingWhiskey.isFinished = deadBottlesCount
        
        // Only recreate bottles if counts have changed
        if needToUpdateBottles {
            print("DEBUG: Updating bottles for \(existingWhiskey.name ?? "unknown")")
            
            // Delete all existing bottles first to prevent duplicates
            let fetchRequest: NSFetchRequest<BottleInstance> = BottleInstance.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "whiskey == %@", existingWhiskey)
            
            if let existingBottles = try? context.fetch(fetchRequest) {
                print("DEBUG: Deleting \(existingBottles.count) existing bottles")
                for bottle in existingBottles {
                    context.delete(bottle)
                        }
                    }
                    
            // Save after deleting to avoid conflicts
            try context.save()
            
            // Create new current bottles - but only if count > 0
            if currentBottles > 0 {
                for i in 0..<Int(currentBottles) {
                    let bottle = BottleInstance(context: context)
                    bottle.id = UUID()
                    bottle.dateAdded = Date()
                    bottle.price = existingWhiskey.price
                    bottle.isOpen = i < Int(openBottles)
                    bottle.isDead = false
                    bottle.bottleNumber = Int16(i + 1)
                    bottle.whiskey = existingWhiskey
                    print("DEBUG: Created current bottle \(i + 1) for \(existingWhiskey.name ?? "unknown")")
                }
                
                // Save after creating current bottles
                try context.save()
                    }
                    
            // Extra verification for dead bottles count
            print("DEBUG: Final dead bottles count: \(deadBottlesCount) (from '\(rawDeadBottleValue)')")
            
            // Create new dead bottles - but only if count > 0
            if deadBottlesCount > 0 {
                for i in 0..<Int(deadBottlesCount) {
                    let bottle = BottleInstance(context: context)
                    bottle.id = UUID()
                    bottle.dateAdded = Date()
                    bottle.price = existingWhiskey.price
                    bottle.isOpen = true
                    bottle.isDead = true
                    bottle.bottleNumber = Int16(Int(currentBottles) + i + 1)
                    bottle.whiskey = existingWhiskey
                    print("DEBUG: Created dead bottle \(Int(currentBottles) + i + 1) for \(existingWhiskey.name ?? "unknown")")
                    }
                    
                // Save after creating dead bottles
                        try context.save()
            }
        }
    }
    
    // Function to create bottles for a new whiskey
    private func createBottlesForNewWhiskey(_ newWhiskey: Whiskey,
                                         with fields: [String],
                                         context: NSManagedObjectContext,
                                         currentBottlesIndex: Int,
                                         openBottlesIndex: Int,
                                         deadBottlesIndex: Int) throws {
        // Get bottle counts
        let currentBottles = fields.count > currentBottlesIndex 
            ? Int16(fields[currentBottlesIndex]) ?? 1 
            : 1
        
        let openBottles = fields.count > openBottlesIndex 
            ? Int16(fields[openBottlesIndex]) ?? 0
            : 0
        
        // IMPORTANT: Explicitly check for dead bottles and ensure it's 0 if not provided
        // Get the raw dead bottle field value for debugging
        let rawDeadBottleValue = fields.count > deadBottlesIndex ? fields[deadBottlesIndex] : ""
        
        // Parse dead bottles count more carefully
        let deadBottlesCount: Int16
        if fields.count > deadBottlesIndex && !fields[deadBottlesIndex].isEmpty {
            // If the field value is "0" or equals to 0, ensure we use 0
            if fields[deadBottlesIndex].trimmingCharacters(in: .whitespaces) == "0" {
                deadBottlesCount = 0
            } else {
                // Only set non-zero value if explicitly provided
                let parsed = Int16(fields[deadBottlesIndex].trimmingCharacters(in: .whitespaces)) ?? 0
                deadBottlesCount = parsed
            }
        } else {
            // If no value provided, default to 0 (no dead bottles)
            deadBottlesCount = 0
        }
        
        // Set properties on the whiskey
        newWhiskey.numberOfBottles = currentBottles
        newWhiskey.isFinished = deadBottlesCount
        newWhiskey.isOpen = openBottles > 0
        
        print("DEBUG: Creating bottles for new whiskey '\(newWhiskey.name ?? "unknown")'")
        print("DEBUG: Current: \(currentBottles), Open: \(openBottles), Dead: \(deadBottlesCount)")
        print("DEBUG: Raw dead bottle value from CSV: '\(rawDeadBottleValue)'")
        
        // Save the whiskey first to ensure it has a valid ID
        try context.save()
        
        // Create current bottles if count > 0
        if currentBottles > 0 {
            for i in 0..<Int(currentBottles) {
                let bottle = BottleInstance(context: context)
                bottle.id = UUID()
                bottle.dateAdded = Date()
                bottle.price = newWhiskey.price
                bottle.isOpen = i < Int(openBottles)
                bottle.isDead = false
                bottle.bottleNumber = Int16(i + 1)
                bottle.whiskey = newWhiskey
                print("DEBUG: Created current bottle \(i + 1) for new whiskey \(newWhiskey.name ?? "unknown")")
            }
            
            // Save after creating current bottles
            try context.save()
                    }
        
        // Extra verification for dead bottles count
        print("DEBUG: Final dead bottles count: \(deadBottlesCount) (from '\(rawDeadBottleValue)')")
        
        // Create dead bottles if count > 0 - adding an extra safety check here
        if deadBottlesCount > 0 {
            for i in 0..<Int(deadBottlesCount) {
                let bottle = BottleInstance(context: context)
                bottle.id = UUID()
                bottle.dateAdded = Date()
                bottle.price = newWhiskey.price
                bottle.isOpen = true
                bottle.isDead = true
                bottle.bottleNumber = Int16(Int(currentBottles) + i + 1)
                bottle.whiskey = newWhiskey
                print("DEBUG: Created dead bottle \(Int(currentBottles) + i + 1) for new whiskey \(newWhiskey.name ?? "unknown")")
            }
            
            // Save after creating dead bottles
            try context.save()
        }
    }
}

// MARK: - Notifications
extension Notification.Name {
    static let csvImportConflict = Notification.Name("csvImportConflict")
}

// Public extension to expose the bottle numbering fix for manual use
extension CSVService {
    // Public method to allow manual fixing of bottle numbering
    func fixBottleNumberingPublic(in context: NSManagedObjectContext) {
        print("Manual bottle numbering fix initiated")
        
        // Safety measure: make sure changes are saved before starting fix
        do {
            if context.hasChanges {
                try context.save()
            }
        } catch {
            print("Warning: Could not save changes before numbering fix: \(error)")
        }
        
        // Fetch all whiskeys
        let whiskeyFetchRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
        do {
            let whiskeys = try context.fetch(whiskeyFetchRequest)
            print("Renumbering bottles for \(whiskeys.count) whiskeys")
            
            // Apply renumbering to each whiskey
            for whiskey in whiskeys {
                whiskey.renumberBottles()
            }
            
            // Final save to ensure all changes are persisted
            if context.hasChanges {
                try context.save()
                print("Successfully saved all bottle numbering changes")
            }
        } catch {
            print("Error during bottle numbering fix: \(error)")
        }
    }
    
    // Advanced repair function to fix unwanted dead bottles
    func repairUnwantedDeadBottles(in context: NSManagedObjectContext) {
        print("Starting deep repair for unwanted dead bottles...")
        
        do {
            // Fetch all whiskeys
            let whiskeyFetchRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
            let whiskeys = try context.fetch(whiskeyFetchRequest)
            var repairCount = 0
            
            for whiskey in whiskeys {
                // Get all bottles for this whiskey
                let bottleFetchRequest: NSFetchRequest<BottleInstance> = BottleInstance.fetchRequest()
                bottleFetchRequest.predicate = NSPredicate(format: "whiskey == %@", whiskey)
                
                guard let bottles = try? context.fetch(bottleFetchRequest) else { continue }
                
                // Find all alive and dead bottles
                let aliveBottles = bottles.filter { !$0.isDead }
                let deadBottles = bottles.filter { $0.isDead }
                
                print("Whiskey '\(whiskey.name ?? "unknown")' has \(aliveBottles.count) alive and \(deadBottles.count) dead bottles")
                
                // Check if isFinished is 0 but we have dead bottles
                if whiskey.isFinished == 0 && deadBottles.count > 0 {
                    print("⚠️ Found unwanted dead bottles for '\(whiskey.name ?? "unknown")' - Repairing")
                    repairCount += 1
                    
                    // Delete all dead bottles
                    for bottle in deadBottles {
                        print("Deleting unwanted dead bottle \(bottle.bottleNumber)")
                        context.delete(bottle)
                    }
                    
                    // Update bottle numbering for alive bottles
                    for (index, bottle) in aliveBottles.enumerated() {
                        bottle.bottleNumber = Int16(index + 1)
                    }
                    
                    // Make sure whiskey properties are correct
                    whiskey.isFinished = 0 // No dead bottles
                    whiskey.numberOfBottles = Int16(aliveBottles.count)
                    
                    // Save periodically
                    if repairCount % 10 == 0 {
                        try context.save()
                    }
                }
                
                // Also check for other inconsistencies
                if whiskey.isFinished != Int16(deadBottles.count) || whiskey.numberOfBottles != Int16(aliveBottles.count) {
                    print("⚠️ Found bottle count mismatch for '\(whiskey.name ?? "unknown")' - Repairing")
                    repairCount += 1
                    
                    // Fix the counts
                    whiskey.isFinished = Int16(deadBottles.count)
                    whiskey.numberOfBottles = Int16(aliveBottles.count)
                }
            }
            
            // Final save
            if repairCount > 0 {
                try context.save()
                print("✅ Repaired \(repairCount) whiskeys with unwanted dead bottles")
            } else {
                print("✅ No unwanted dead bottles found, no repairs needed")
            }
        } catch {
            print("❌ Error during deep repair: \(error)")
        }
    }
    
    // EMERGENCY: One-click method to delete all dead bottles
    func emergencyDeleteAllDeadBottles(in context: NSManagedObjectContext) async throws -> Int {
        print("🚨 EMERGENCY: Deleting all dead bottles...")
        
        // Create a background context for the operation
        let backgroundContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        backgroundContext.parent = context
        
        var deletedCount = 0
        
        try await backgroundContext.perform {
            // Find all dead bottles
            let bottleFetchRequest = NSFetchRequest<BottleInstance>(entityName: "BottleInstance")
            bottleFetchRequest.predicate = NSPredicate(format: "isDead == %@", NSNumber(value: true))
            
            if let deadBottles = try? backgroundContext.fetch(bottleFetchRequest) {
                print("🚨 Found \(deadBottles.count) dead bottles to delete")
                deletedCount = deadBottles.count
                
                // Delete all dead bottles
                for bottle in deadBottles {
                    backgroundContext.delete(bottle)
                }
                
                // Find all whiskeys and reset isFinished
                let whiskeyFetchRequest = NSFetchRequest<Whiskey>(entityName: "Whiskey")
                if let whiskeys = try? backgroundContext.fetch(whiskeyFetchRequest) {
                    for whiskey in whiskeys {
                        if whiskey.isFinished > 0 {
                            whiskey.isFinished = 0
                        }
                    }
                }
                
                // Save the changes
                try backgroundContext.save()
                try context.save()
                
                print("✅ EMERGENCY FIX COMPLETE: Deleted \(deletedCount) dead bottles")
            } else {
                print("✅ No dead bottles found")
            }
        }
        
        return deletedCount
    }
} 