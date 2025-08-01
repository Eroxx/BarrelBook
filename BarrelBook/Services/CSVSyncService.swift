import Foundation
import CoreData
import Combine

// Helper class to manage file access coordination
private class FileAccessCoordinator {
    private let fileCoordinator = NSFileCoordinator()
    private let queue = DispatchQueue(label: "com.barrelbook.fileaccess")
    
    func coordinateReading(at url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        queue.async {
            var error: NSError?
            var result: Result<String, Error> = .failure(NSError(domain: "com.barrelbook", code: -1, userInfo: [NSLocalizedDescriptionKey: "Reading not performed"]))
            
            self.fileCoordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { url in
                do {
                    let data = try Data(contentsOf: url, options: [.uncached])
                    if let content = String(data: data, encoding: .utf8) {
                        result = .success(content)
                    } else {
                        // Try other encodings if UTF-8 fails
                        for encoding in [String.Encoding.ascii, .isoLatin1, .windowsCP1252] {
                            if let content = String(data: data, encoding: encoding) {
                                result = .success(content)
                                break
                            }
                        }
                        if case .failure = result {
                            result = .failure(CSVError.encodingError)
                        }
                    }
                } catch {
                    result = .failure(error)
                }
            }
            
            if let error = error {
                completion(.failure(error))
                return
            }
            
            completion(result)
        }
    }
    
    func coordinateWriting(at url: URL, content: String, completion: @escaping (Error?) -> Void) {
        queue.async {
            var error: NSError?
            var writeError: Error?
            
            self.fileCoordinator.coordinate(writingItemAt: url, options: [], error: &error) { url in
                do {
                    // First write to a temporary file
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try content.write(to: tempURL, atomically: true, encoding: .utf8)
                    
                    // Then move it to the final location
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.removeItem(at: url)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: url)
                } catch {
                    writeError = error
                }
            }
            
            completion(error ?? writeError)
        }
    }
    
    // Add a new method for handling conflicting writes with basic conflict resolution
    func coordinateWritingWithConflictResolution(at url: URL, content: String, lastReadVersion: String?, completion: @escaping (Result<ConflictResolutionStatus, Error>) -> Void) {
        queue.async {
            // First, read the current file content for comparison
            var readError: NSError?
            var currentContent: String?
            
            // Read the current file content
            self.fileCoordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &readError) { url in
                do {
                    let data = try Data(contentsOf: url, options: [.uncached])
                    currentContent = String(data: data, encoding: .utf8)
                    
                    // If UTF-8 fails, try other encodings
                    if currentContent == nil {
                        for encoding in [String.Encoding.ascii, .isoLatin1, .windowsCP1252] {
                            if let content = String(data: data, encoding: encoding) {
                                currentContent = content
                                break
                            }
                        }
                    }
                } catch {
                    // File might not exist yet, which is fine for new files
                    if !((error as NSError).domain == NSCocoaErrorDomain && 
                         (error as NSError).code == NSFileReadNoSuchFileError) {
                        print("Error reading file for conflict check: \(error)")
                    }
                }
            }
            
            if let readError = readError {
                if readError.domain == NSCocoaErrorDomain && readError.code == NSFileReadNoSuchFileError {
                    // File doesn't exist yet, so it's a new file - no conflict possible
                    self.coordinateWriting(at: url, content: content) { writeError in
                        if let writeError = writeError {
                            completion(.failure(writeError))
                        } else {
                            completion(.success(.newFile))
                        }
                    }
                    return
                } else {
                    completion(.failure(readError))
                    return
                }
            }
            
            // Check for conflicts by comparing with the last read version
            if let lastReadVersion = lastReadVersion, let current = currentContent {
                if current != lastReadVersion {
                    // File has been modified since last read - conflict detected
                    print("Conflict detected: File has been modified since last read")
                    
                    // Create conflict versions of the file
                    let conflictURL = url.deletingPathExtension().appendingPathExtension("conflict.csv")
                    
                    // Write our version to the conflict file
                    do {
                        try content.write(to: conflictURL, atomically: true, encoding: .utf8)
                        print("Wrote conflict version to: \(conflictURL.path)")
                        
                        // Create a merged version using simple CSV merging strategy
                        if let mergedContent = self.mergeCSVContents(original: current, modified: content) {
                            // Write the merged content to the original file
                            var writeError: NSError?
                            var internalWriteError: Error?
                            
                            self.fileCoordinator.coordinate(writingItemAt: url, options: [], error: &writeError) { url in
                                do {
                                    // Write to a temporary file first
                                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                                    try mergedContent.write(to: tempURL, atomically: true, encoding: .utf8)
                                    
                                    // Move to final location
                                    if FileManager.default.fileExists(atPath: url.path) {
                                        try FileManager.default.removeItem(at: url)
                                    }
                                    try FileManager.default.moveItem(at: tempURL, to: url)
                                    
                            } catch {
                                    internalWriteError = error
                                }
                            }
                            
                            if let error = writeError ?? internalWriteError {
                                completion(.failure(error))
                            } else {
                                completion(.success(.mergedWithConflict))
                            }
                        } else {
                            // Could not merge, just inform of the conflict
                            completion(.success(.conflictDetected))
                        }
                    } catch {
                        print("Failed to write conflict file: \(error)")
                        completion(.failure(error))
                    }
                    return
                }
            }
            
            // No conflict detected, proceed with normal write
            self.coordinateWriting(at: url, content: content) { writeError in
                if let writeError = writeError {
                    completion(.failure(writeError))
                } else {
                    completion(.success(.noConflict))
                }
            }
        }
    }
    
    // Basic CSV merging strategy - combines records from both files
    private func mergeCSVContents(original: String, modified: String) -> String? {
        // Split both files into lines
        let originalLines = original.components(separatedBy: .newlines)
        let modifiedLines = modified.components(separatedBy: .newlines)
        
        guard let originalHeader = originalLines.first, let modifiedHeader = modifiedLines.first else {
            return nil
        }
        
        // Verify headers match (basic validation)
        if originalHeader != modifiedHeader {
            print("Headers do not match, cannot merge safely")
            return nil
        }
        
        // Create a set of unique lines (by combining both files)
        var uniqueLines = Set<String>()
        uniqueLines.insert(originalHeader) // Add header
        
        // Add remaining lines from both files
        for i in 1..<originalLines.count {
            let line = originalLines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                uniqueLines.insert(line)
            }
        }
        
        for i in 1..<modifiedLines.count {
            let line = modifiedLines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                uniqueLines.insert(line)
            }
        }
        
        // Rebuild the CSV file
        var result = originalHeader + "\n"
        uniqueLines.forEach { line in
            if line != originalHeader && !line.isEmpty {
                result += line + "\n"
            }
        }
        
        return result
    }
}

// Define an enum to represent the conflict resolution status
enum ConflictResolutionStatus {
    case noConflict        // No conflict detected, write succeeded
    case newFile           // New file created (didn't exist before)
    case conflictDetected  // Conflict detected, conflict file created but no merge attempted
    case mergedWithConflict // Conflict detected and a merge was attempted
}

class CSVSyncService {
    static let shared = CSVSyncService()
    
    // MARK: - Properties
    
    // URL and file information
    private(set) var syncFileURL: URL?
    private(set) var originalFilename: String = ""
    private(set) var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: "csvLastSyncDate") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "csvLastSyncDate") }
    }
    
    // Sync status tracking
    private var isCurrentlySyncing = false
    private var syncInProgress: Bool {
        get { UserDefaults.standard.bool(forKey: "csvSyncInProgress") }
        set { UserDefaults.standard.set(newValue, forKey: "csvSyncInProgress") }
    }
    
    // Deletion tracking
    private var deletedWhiskeyIDs: Set<String> = []
    private var deletedWhiskeyNames: Set<String> = []
    
    // Additional properties needed for file handling
    private var originalURL: URL?
    private var needsSecurityAccess: Bool = false
    
    // File coordination
    private let fileCoordinator = FileAccessCoordinator()
    
    // File monitoring
    private var fileMonitor: NSFilePresenter?
    private var ubiquityIdentityToken: Any?
    private var metadataQuery: NSMetadataQuery?
    
    private var cancellables = Set<AnyCancellable>()
    private let userDefaults = UserDefaults.standard
    
    // Keys for UserDefaults
    private let syncFileURLKey = "csvSyncFileURL"
    private let syncFileBookmarkKey = "csvSyncBookmarkData"
    private let lastSyncDateKey = "lastCSVSyncDate"
    private let deletedWhiskeysKey = "deletedWhiskeysKey"
    private let deletedWhiskeyNamesKey = "com.barrelbook.deletedWhiskeyNames"
    
    // Dictionary for storing CSV records during sync
    private var csvWhiskeyDict: [String: WhiskeyRecord] = [:]
    
    // MARK: - Initialization
    
    init() {
        // Initialize empty sets
        deletedWhiskeyIDs = Set<String>()
        deletedWhiskeyNames = Set<String>()
    }
    
    // MARK: - Public Properties
    
    var isSyncing = false
    
    // MARK: - Public Methods
    
    func configureSyncWithURL(_ url: URL) {
        print("🔄 Configuring sync with URL: \(url.lastPathComponent)")
        
        self.syncFileURL = url
        self.originalFilename = url.lastPathComponent
        
        // Store hasSyncFileConfigured flag
        UserDefaults.standard.set(true, forKey: "hasSyncFileConfigured")
        print("✅ Explicitly set hasSyncFileConfigured to TRUE during configuration")
        print("🔑 UserDefaults state: hasSyncFileConfigured=\(UserDefaults.standard.bool(forKey: "hasSyncFileConfigured")), URL exists=\(UserDefaults.standard.string(forKey: syncFileURLKey) != nil)")
        
        // Check if we need a security bookmark (for files outside the Documents directory)
        if url.startAccessingSecurityScopedResource() {
            print("🔒 Starting security-scoped resource access for: \(url.lastPathComponent)")
            
            // Create a security bookmark for persistent access
            do {
                let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                UserDefaults.standard.set(bookmarkData, forKey: syncFileBookmarkKey)
                UserDefaults.standard.set(url.absoluteString, forKey: syncFileURLKey)
                print("✅ Created and saved security bookmark for file")
                print("💾 Bookmark data saved to UserDefaults: \(bookmarkData.count) bytes")
            } catch {
                print("⚠️ Failed to create bookmark: \(error.localizedDescription)")
            }
            
            url.stopAccessingSecurityScopedResource()
        } else {
            print("⚠️ Could not access security scoped resource for bookmark creation")
        }
        
        // Monitor cloud files if necessary
        setupCloudMonitoring(for: url)
    }
    
    func syncWithFile(at url: URL, context: NSManagedObjectContext) async throws -> SyncResult {
        print("🔄 Starting sync with file at URL: \(url.lastPathComponent)")
        
        // Skip loading deleted whiskeys during import
        // loadDeletedWhiskeysFromUserDefaults()
        
        // Only log deleted whiskey details if there are any
        if !deletedWhiskeyIDs.isEmpty {
            print("📝 Tracking \(deletedWhiskeyIDs.count) deleted whiskey IDs and \(deletedWhiskeyNames.count) names")
        }
        
        isSyncing = true
        defer { isSyncing = false }
        
        // Clear CSV dictionary before starting a new sync
        csvWhiskeyDict.removeAll()
        
        // Store the original file name and path
        let originalFilename = url.lastPathComponent
        let originalURL = url
        
        // Set as the current sync file - but preserve the original filename in UserDefaults
        self.syncFileURL = url
        
        // Store the original filename explicitly
        userDefaults.set(originalFilename, forKey: "csvSyncFileName")
        
        // Determine if file access requires security-scoped access
        let needsSecurityAccess = !url.path.contains("/Documents/")
        
        // Variable to track if security access was granted
        var writeAccessGranted = false
        
        // Handle security access if needed
        if needsSecurityAccess {
            // For security-scoped files, try getting bookmark data first
            if let bookmarkData = UserDefaults.standard.data(forKey: "csvSyncBookmarkData") {
                do {
                    var isStale = false
                    let resolvedURL = try URL(resolvingBookmarkData: bookmarkData,
                                             options: .withoutUI,
                                             relativeTo: nil,
                                             bookmarkDataIsStale: &isStale)
                    
                    // Check if the resolved URL matches the original
                    if resolvedURL.path == originalURL.path {
                        print("✅ Successfully resolved bookmark to: \(resolvedURL.path)")
                        
                        // Try to get security access
                        writeAccessGranted = resolvedURL.startAccessingSecurityScopedResource()
                        
                        if writeAccessGranted {
                            print("✅ Successfully gained security access to file")
                        } else {
                            print("⚠️ Could not gain security access with resolved bookmark")
                        }
                        
                        // Update bookmark if it was stale
                        if isStale && writeAccessGranted {
                            do {
                                let updatedBookmark = try resolvedURL.bookmarkData(options: .minimalBookmark)
                                UserDefaults.standard.set(updatedBookmark, forKey: "csvSyncBookmarkData")
                                UserDefaults.standard.synchronize()
                                print("♻️ Updated stale bookmark")
                            } catch {
                                print("⚠️ Failed to update stale bookmark: \(error)")
                            }
                        }
                    } else {
                        print("⚠️ Resolved URL doesn't match original URL")
                    }
                } catch {
                    print("⚠️ Failed to resolve bookmark: \(error)")
                }
            }
            
            // If still not able to access, try direct access as a fallback
            if !writeAccessGranted {
                writeAccessGranted = originalURL.startAccessingSecurityScopedResource()
                if writeAccessGranted {
                    print("✅ Gained security access via direct access")
                    
                    // Create a fresh bookmark since the stored one failed
                    do {
                        let newBookmark = try originalURL.bookmarkData(options: .minimalBookmark)
                        UserDefaults.standard.set(newBookmark, forKey: "csvSyncBookmarkData")
                        UserDefaults.standard.synchronize()
                        print("✅ Created new security bookmark for file")
                    } catch {
                        print("⚠️ Failed to create new bookmark: \(error)")
                    }
                } else {
                    print("⚠️ Could not access security scoped resource")
                    throw NSError(domain: "com.barrelbook", code: 1, 
                                userInfo: [NSLocalizedDescriptionKey: "Unable to access the CSV file."])
                }
            }
        }
        
        // Ensure we release security access when we're done
        defer {
            if needsSecurityAccess && writeAccessGranted {
                originalURL.stopAccessingSecurityScopedResource()
                print("Stopped accessing security scoped resource")
            }
        }
        
        // Read data from CSV file
        let csvData: String
        do {
            csvData = try readCSVFile(at: url)
            print("Successfully read CSV file")
        } catch {
            print("Failed to read CSV file: \(error)")
            throw error
        }
        
        // Get all whiskeys from Core Data
        let fetchRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
        let localWhiskeys: [Whiskey]
        do {
            localWhiskeys = try context.fetch(fetchRequest)
            print("Fetched \(localWhiskeys.count) whiskeys from Core Data")
        } catch {
            print("Failed to fetch whiskeys: \(error)")
            throw error
        }
        
        // Get count of deleted whiskeys before sync for proper reporting
        let deletedWhiskeyCount = deletedWhiskeyIDs.count
        print("Number of tracked deleted whiskeys: \(deletedWhiskeyCount)")
        
        // Parse CSV data into whiskey records
        let csvWhiskeys: [WhiskeyRecord]
        do {
            csvWhiskeys = try parseCSVToWhiskeyRecords(csvData)
            
            // Check if we have any records to sync
            if csvWhiskeys.isEmpty {
                print("No whiskey records found in CSV, nothing to sync")
                return SyncResult()
            }
            
            print("Parsed \(csvWhiskeys.count) whiskeys from CSV")
        } catch {
            print("Failed to parse CSV: \(error)")
            throw error
        }
        
        // Filter out any CSV whiskeys that match names in our deleted whiskeys list
        var filteredCsvWhiskeys = csvWhiskeys
        var filteredOutCount = 0
        
        // Create a map of deleted whiskey names for easier lookup
        let deletedWhiskeyNameMap = Dictionary(
            uniqueKeysWithValues: self.deletedWhiskeyNames.map { ($0.lowercased(), true) }
        )
        
        // Filter out any CSV whiskeys that have been deleted
        filteredCsvWhiskeys = csvWhiskeys.filter { csvWhiskey in
            let csvName = csvWhiskey.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Check if this CSV whiskey name matches any of our deleted whiskeys
            let isDeleted = deletedWhiskeyNameMap[csvName] != nil || 
                            self.deletedWhiskeyNames.contains { deletedName in
                                csvName.contains(deletedName) || deletedName.contains(csvName)
                            }
            
            if isDeleted {
                print("🗑️ Filtered out deleted whiskey from CSV: \(csvWhiskey.name)")
                filteredOutCount += 1
                return false
            }
            return true
        }
        
        // Create dictionaries for lookup during sync
        var csvWhiskeyDict = [String: WhiskeyRecord]()
        for csvWhiskey in filteredCsvWhiskeys {
            let key = createUniqueKey(name: csvWhiskey.name, 
                                     proof: csvWhiskey.proof,
                                     isStorePick: csvWhiskey.isStorePick,
                                     storePickName: csvWhiskey.storePickName ?? "")
            csvWhiskeyDict[key] = csvWhiskey
        }
        
        if filteredOutCount > 0 {
            print("🔄 Filtered out \(filteredOutCount) deleted whiskeys before processing")
        }
        
        // Perform synchronization
        var syncResult: SyncResult
        do {
            syncResult = try synchronize(csvWhiskeys: filteredCsvWhiskeys, localWhiskeys: localWhiskeys, context: context)
            
            // Add our filtered deletions to the result - IMPORTANT: This is a deletion, not an update!
            if filteredOutCount > 0 {
                // Only count as deletions if this isn't a new sync (has previous sync date)
                if self.lastSyncDate != nil {
                    syncResult.deleted += filteredOutCount
                    print("Added \(filteredOutCount) filtered deletions to the sync result")
                } else {
                    print("Skipping \(filteredOutCount) filtered items from deletion count (initial sync)")
                }
            }
            
            print("Sync completed with result: added=\(syncResult.added), updated=\(syncResult.updated), deleted=\(syncResult.deleted), conflicts=\(syncResult.conflicts)")
        } catch {
            print("Synchronization failed: \(error)")
            throw error
        }
        
        // Only update the CSV file if there were changes OR if they were modified since last sync
        if syncResult.totalChanges > 0 || shouldUpdateForModifiedWhiskeys(context) {
            // Declare writeAccessGranted at the beginning of the if statement to ensure it's available in all scopes
            var writeAccessGranted = false
            
            do {
                print("Changes or modifications detected, updating CSV file...")
                
                // Get all whiskeys from context
                let allWhiskeysFetchRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
                let allWhiskeys: [Whiskey] = try context.fetch(allWhiskeysFetchRequest)
                print("Fetched \(allWhiskeys.count) whiskeys for writing back to CSV")
                
                // *** CRITICAL VALIDATION: Ensure we don't write empty content to the CSV file ***
                if allWhiskeys.isEmpty {
                    print("⚠️ SAFETY CHECK: No whiskeys available to write to CSV. Skipping file update to prevent data loss.")
                    // Still update the sync date for consistency
                    self.lastSyncDate = Date()
                    // Clear the tracked deleted whiskeys since we've completed a sync operation
                    clearTrackedDeletedWhiskeys()
                    return syncResult
                }
                
                // Detect if any whiskeys were modified since the last sync
                let hasRecentModifications = allWhiskeys.contains { whiskey in
                    if let modDate = whiskey.modificationDate, let lastSync = self.lastSyncDate {
                        return modDate > lastSync
                    }
                    return false
                }
                
                if hasRecentModifications {
                    print("⚠️ Detected whiskeys modified since last sync - these changes will be written to CSV")
                }
                
                // Filter out any locally deleted whiskeys before writing back to CSV
                let filteredWhiskeys = allWhiskeys.filter { whiskey in
                    // Check by ID
                    guard let id = whiskey.id?.uuidString else { return true }
                    if self.deletedWhiskeyIDs.contains(id) {
                        return false
                    }
                    
                    // Also check by name match to handle cases where ID might be different
                    guard let name = whiskey.name?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
                          !name.isEmpty else { return true }
                          
                    let nameMatch = self.deletedWhiskeyNames.contains { deletedName in
                        return name == deletedName || name.contains(deletedName) || deletedName.contains(name)
                    }
                    
                    if nameMatch {
                        return false
                    }
                    
                    return true
                }
                
                let filteredCount = allWhiskeys.count - filteredWhiskeys.count
                if filteredCount > 0 {
                    print("🗑️ Filtered out \(filteredCount) previously deleted whiskeys before writing to CSV")
                }
                
                // CRITICAL ADDITION: Check if after filtering we have any whiskeys left
                if filteredWhiskeys.isEmpty {
                    print("⚠️ CRITICAL SAFETY CHECK: All whiskeys were filtered out as deleted. Skipping CSV update to prevent data loss.")
                    // Still update the sync date for consistency
                    self.lastSyncDate = Date()
                    // We still want to keep the deleted whiskeys tracking in this case
                    print("🧹 KEEPING DELETED WHISKEY TRACKING: \(self.deletedWhiskeyIDs.count) IDs and \(self.deletedWhiskeyNames.count) names to prevent re-adding")
                    
                    print("Sync complete! No update to file: \(url.lastPathComponent) (all whiskeys filtered)")
                    print("🔄 Final result: added=\(syncResult.added), updated=\(syncResult.updated), deleted=\(syncResult.deleted), conflicts=\(syncResult.conflicts)")
                    return syncResult
                }
                
                // Create fresh CSV content from the current data
                let updatedCSVString = try CSVService.shared.exportWhiskeys(filteredWhiskeys)
                
                // If any whiskeys were modified within the last hour, log that we're forcing an update
                if hasRecentModifications {
                    print("✅ Including recent local modifications in the CSV update")
                }
                
                // We already have security access from the beginning of the method
                // so we don't need to stop and restart access here
                if needsSecurityAccess {
                    print("✅ Already have security access for writing from earlier")
                }
                
                // Check if we can access the file
                if writeAccessGranted || !needsSecurityAccess {
                    print("Security access is available for writing to: \(originalURL.absoluteString)")
                    
                    // Log file attributes for debugging
                    do {
                        let resources = try originalURL.resourceValues(forKeys: [.isUbiquitousItemKey, .contentModificationDateKey, .fileSizeKey])
                        if let isUbiquitous = resources.isUbiquitousItem {
                            print("File is ubiquitous item: \(isUbiquitous)")
                        }
                        if let modDate = resources.contentModificationDate {
                            print("File modification date: \(modDate)")
                        }
                        if let fileSize = resources.fileSize {
                            print("📄 File info: size=\(fileSize) bytes")
                        }
                    } catch {
                        print("⚠️ Warning: Failed to check resource values: \(error)")
                    }
                    
                    // Use FileAccessCoordinator for coordinated writing with conflict resolution
                    print("Starting coordinated write using FileAccessCoordinator with conflict resolution...")
                    
                    // Get the last tracked version of this file
                    let lastReadVersion = getLastTrackedVersion(for: originalURL)
                    
                    // Use async/await with Task for cleaner code
                    let conflictStatus = try await writeToFileWithConflictResolution(
                        at: originalURL, 
                        content: updatedCSVString,
                        lastReadVersion: lastReadVersion
                    )
                    
                    // Handle different conflict resolution scenarios
                    switch conflictStatus {
                    case .noConflict:
                        print("✅ Successfully wrote to CSV file with no conflicts")
                    case .newFile:
                        print("✅ Created new CSV file")
                    case .conflictDetected:
                        print("⚠️ Conflict detected - created conflict file")
                        // Increment the conflicts counter in the result
                        syncResult.conflicts += 1
                    case .mergedWithConflict:
                        print("✅ Conflict detected but successfully merged changes")
                        // Increment the conflicts counter in the result but note it was resolved
                        syncResult.conflicts += 1
                    }
                    
                    // Update the tracked version with the newly written content
                    trackFileVersion(url: originalURL, content: updatedCSVString)
                        
                        // For cloud files, try to ensure the changes are uploaded
                        do {
                            let resources = try originalURL.resourceValues(forKeys: [.isUbiquitousItemKey])
                            if let isUbiquitous = resources.isUbiquitousItem, isUbiquitous {
                                print("📃 Ensuring cloud file is properly uploaded...")
                                try FileManager.default.evictUbiquitousItem(at: originalURL)
                                print("✅ Evicted old version from cloud")
                            }
                        } catch {
                            print("⚠️ Warning when handling cloud file: \(error)")
                        }
                        
                        // Update the progress in user defaults
                        print("Updating sync date and file info...")
                        
                        // Set the sync date to right now
                        self.lastSyncDate = Date()
                        
                        // Also update file name, URL, and bookmark (if needed)
                        self.syncFileURL = originalURL
                        
                        // Clear the tracked deleted whiskeys since we've completed a successful sync
                        clearTrackedDeletedWhiskeys()
                        
                        // DIRECT VERIFICATION: Ensure URL is properly set in UserDefaults
                        print("🔑 SYNC COMPLETION: Explicitly verifying sync file URL in UserDefaults")
                        UserDefaults.standard.set(originalURL.absoluteString, forKey: "csvSyncFileURL")
                        UserDefaults.standard.synchronize()
                        
                        // Verify the URL was actually set
                        if let storedURL = UserDefaults.standard.string(forKey: "csvSyncFileURL") {
                            print("✅ SYNC VERIFICATION: URL successfully stored in UserDefaults: \(storedURL)")
                        } else {
                            print("‼️ CRITICAL SYNC ERROR: Failed to store URL in UserDefaults!")
                            // Try one more time with direct setting
                            UserDefaults.standard.set(originalURL.absoluteString, forKey: "csvSyncFileURL")
                            UserDefaults.standard.synchronize()
                        }
                        
                        print("Sync complete! Updated file: \(url.lastPathComponent)")
                        print("🔄 Final result: added=\(syncResult.added), updated=\(syncResult.updated), deleted=\(syncResult.deleted), conflicts=\(syncResult.conflicts)")
                        return syncResult
                } else {
                    print("⚠️ Warning: Could not gain security access to update the CSV file")
                    
                    // Try one more time with a fresh attempt from the beginning
                    print("🔄 Attempting to gain fresh security access...")
                    
                    // Release any existing access
                    if writeAccessGranted {
                        originalURL.stopAccessingSecurityScopedResource()
                        writeAccessGranted = false
                    }
                    
                    // Try to get fresh bookmark data
                    if let bookmarkData = UserDefaults.standard.data(forKey: "csvSyncBookmarkData") {
                        do {
                            var isStale = false
                            let resolvedURL = try URL(resolvingBookmarkData: bookmarkData,
                                                     options: .withoutUI,
                                                     relativeTo: nil,
                                                     bookmarkDataIsStale: &isStale)
                            
                            if resolvedURL.path == originalURL.path {
                                print("✅ Successfully re-resolved bookmark to: \(resolvedURL.path)")
                                writeAccessGranted = resolvedURL.startAccessingSecurityScopedResource()
                                
                                if writeAccessGranted {
                                    print("✅ Successfully gained fresh security access to file")
                                    
                                    // Create a fresh file coordinator for the new attempt
                                    print("🔄 Retrying write with fresh security access...")
                                    try await writeToFileWithConflictResolution(
                                        at: originalURL, 
                                        content: updatedCSVString,
                                        lastReadVersion: getLastTrackedVersion(for: originalURL)
                                    )
                                    
                                    // If we get here, we succeeded on retry
                                    print("✅ Successfully wrote to file on retry")
                                    
                                    // Update the tracked version with the newly written content
                                    trackFileVersion(url: originalURL, content: updatedCSVString)
                                    
                                    // Update the last sync date and clear deleted whiskeys
                                    self.lastSyncDate = Date()
                                    clearTrackedDeletedWhiskeys()
                                    
                                    // Explicitly verify sync file URL in UserDefaults
                                    UserDefaults.standard.set(originalURL.absoluteString, forKey: "csvSyncFileURL")
                                    UserDefaults.standard.synchronize()
                                    
                                    // Stop accessing the resource when done
                                    originalURL.stopAccessingSecurityScopedResource()
                                    
                                    print("Sync complete after retry! Updated file: \(url.lastPathComponent)")
                                    print("🔄 Final result: added=\(syncResult.added), updated=\(syncResult.updated), deleted=\(syncResult.deleted), conflicts=\(syncResult.conflicts)")
                                    return syncResult
                                }
                            }
                        } catch {
                            print("⚠️ Failed to re-resolve bookmark on retry: \(error)")
                        }
                    }
                    
                    // If we reach here, both attempts failed
                    throw NSError(domain: "com.barrelbook", code: 3, 
                                 userInfo: [NSLocalizedDescriptionKey: "Could not access the file for writing."])
                }
            } catch {
                // Make sure to stop security scoped access if we're handling an error
                if writeAccessGranted {
                    originalURL.stopAccessingSecurityScopedResource()
                }
                
                print("Failed to write updated CSV: \(error)")
                throw error
            }
        } else {
            // No changes to write back to CSV
            print("No changes to write back to CSV")
            
            // Still update the last sync date
            self.lastSyncDate = Date()
            
            // Clear the tracked deleted whiskeys since we've completed a successful sync
            clearTrackedDeletedWhiskeys()
            
            print("🔄 Final result: added=\(syncResult.added), updated=\(syncResult.updated), deleted=\(syncResult.deleted), conflicts=\(syncResult.conflicts)")
            return syncResult
        }
    }
    
    func createNewSyncFile(at url: URL, with whiskeys: [Whiskey]) async throws {
        print("Creating new sync file at: \(url.lastPathComponent)")
        
        // Export current whiskeys to CSV
        let csvString = try CSVService.shared.exportWhiskeys(whiskeys)
        
        // First create the file in our own app documents directory
        let tempDocumentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let tempExportsDir = tempDocumentsDir.appendingPathComponent("TempExports", isDirectory: true)
        
        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: tempExportsDir.path) {
            try FileManager.default.createDirectory(at: tempExportsDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        // Create a temporary file with the same name
        let tempFilename = url.lastPathComponent
        let tempFileURL = tempExportsDir.appendingPathComponent(tempFilename)
        
        // Write to our temporary file first
        try await writeToFile(at: tempFileURL, content: csvString)
        print("✅ Successfully wrote new sync file to temporary location")
        
        // Configure sync settings using the external URL
        self.syncFileURL = url
        
        // Store the file version for conflict detection
        trackFileVersion(url: url, content: csvString)
        
        // DIRECT METHOD: First explicitly set URL in UserDefaults
        print("🔑 DIRECT: Setting URL directly in UserDefaults: \(url.absoluteString)")
        UserDefaults.standard.set(url.absoluteString, forKey: "csvSyncFileURL")
        UserDefaults.standard.synchronize()
        
        // If this is an external file (not in app Documents), create a bookmark
        if !url.path.contains("/Documents/") {
            configureSyncWithURL(url)
        }
        
        // IMPROVEMENT: Set lastSyncDate when creating a new sync file
        // This establishes the baseline sync state immediately, so the first sync
        // won't treat all items as new additions
        self.lastSyncDate = Date()
        print("✅ Set initial sync date to establish baseline state")
        
        // Reset any tracked deleted whiskeys since we're establishing a fresh baseline
        clearTrackedDeletedWhiskeys()
    }
    
    func clearSyncSettings() {
        print("🧹 SUPER AGGRESSIVE SYNC CLEANUP - BEGIN")
        
        // Clear internal properties
        syncFileURL = nil
        lastSyncDate = nil
        
        // Remove all sync-related keys from UserDefaults
        userDefaults.removeObject(forKey: syncFileBookmarkKey)
        userDefaults.removeObject(forKey: syncFileURLKey)
        userDefaults.removeObject(forKey: "csvSyncFileURL")
        userDefaults.removeObject(forKey: "csvSyncFileName")
        userDefaults.removeObject(forKey: lastSyncDateKey)
        
        // Force UserDefaults to save changes immediately
        userDefaults.synchronize()
        
        // Double check that the keys are actually removed
        if userDefaults.string(forKey: syncFileURLKey) != nil {
            print("⚠️ WARNING: syncFileURLKey still exists in UserDefaults after removal!")
            // Try again with direct key
            UserDefaults.standard.removeObject(forKey: "csvSyncFileURL")
            UserDefaults.standard.synchronize()
        }
        
        print("🧹 SUPER AGGRESSIVE SYNC CLEANUP - COMPLETE")
        print("🧹 Cleared all sync settings - URL and bookmark removed from UserDefaults")
    }
    
    // Track whiskeys that are manually deleted by the user
    func trackDeletedWhiskey(_ whiskey: Whiskey) {
        guard let id = whiskey.id?.uuidString else { return }
        
        // Load current values from UserDefaults
        loadDeletedWhiskeysFromUserDefaults()
        
        // Add this whiskey's ID if not already tracked
        if !deletedWhiskeyIDs.contains(id) {
            // Using insert for Set instead of append (which is for arrays)
            deletedWhiskeyIDs.insert(id)
            
            // Also track the whiskey name for more reliable matching
            if let name = whiskey.name?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
                if !deletedWhiskeyNames.contains(name) {
                    // Using insert for Set instead of append (which is for arrays)
                    deletedWhiskeyNames.insert(name)
                    
                    // Track this deleted whiskey name
                    // deletedWhiskeyNames.insert(name.lowercased()) // Removed duplicate insert
                    // print("📢 DELETION TRACKING: Added name '\(name)' to tracked deletions list")
                    // print("📢 Current tracked names: \(Array(deletedWhiskeyNames).joined(separator: ", "))")
                }
            }
            
            // Save changes to UserDefaults
            saveDeletedWhiskeysToUserDefaults()
            
            print("🗑️ Tracked deleted whiskey: \(whiskey.name ?? "Unknown") (\(id)) - total deleted count: \(deletedWhiskeyIDs.count)")
        }
    }
    
    // MARK: - Private Methods
    
    private func readCSVFile(at url: URL) throws -> String {
        print("Reading CSV file at: \(url.absoluteString)")
        
        // Give the filesystem a moment to ensure latest updates are visible
        Thread.sleep(forTimeInterval: 3.0)  // Increased to 3 seconds for better reliability with external files
        
        // Check if this is a cloud file (iCloud, Dropbox, etc.)
        let isCloudFile = !url.path.contains("/Documents/")
        
        // Force clear any NSURLCache that might have old copies of the file
        URLCache.shared.removeAllCachedResponses()
        
        // Get file modification date and size before reading for debugging
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let modDate = attributes[.modificationDate] as? Date,
               let fileSize = attributes[.size] as? UInt64 {
                print("📄 File info: modified=\(modDate), size=\(fileSize) bytes")
                
                // If file was modified in the last minute, give it a little extra time
                if Date().timeIntervalSince(modDate) < 60 {
                    print("File was modified very recently, waiting additional time...")
                    Thread.sleep(forTimeInterval: 2.0)
                }
            }
        } catch {
            print("Could not get file attributes: \(error)")
        }
        
        // Use FileAccessCoordinator for coordinated reading
        let coordinator = FileAccessCoordinator()
        let semaphore = DispatchSemaphore(value: 0)
        var finalResult: Result<String, Error> = .failure(NSError(domain: "com.barrelbook", code: -1, userInfo: [NSLocalizedDescriptionKey: "Reading not started"]))
        
        coordinator.coordinateReading(at: url) { result in
            finalResult = result
            semaphore.signal()
        }
        
        // Wait for the read operation to complete
        _ = semaphore.wait(timeout: .now() + 30.0) // 30 second timeout
        
        // Handle the result
        switch finalResult {
        case .success(let content):
            // Validate the content
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty {
                            print("⚠️ Warning: CSV content is empty after trimming whitespace")
                throw CSVError.invalidData
                        }
                        
                        // Print the first 150 characters to debug
            let previewLength = min(150, content.count)
            let contentPreview = content.prefix(previewLength)
                        print("CSV first \(previewLength) chars: \(contentPreview)")
                        
                        // Check for typical CSV content
            if !content.contains(",") {
                            print("⚠️ Warning: CSV content doesn't contain commas, may not be valid CSV")
                throw CSVError.invalidData
            }
            
            // Track the file version for conflict detection
            trackFileVersion(url: url, content: content)
            print("Tracked file version for conflict detection")
            
            return content
            
        case .failure(let error):
            print("Failed to read file: \(error)")
            throw error
        }
    }
    
    private func parseCSVToWhiskeyRecords(_ csvString: String) throws -> [WhiskeyRecord] {
        // Remove BOM if present
        var processedCSV = csvString
        if processedCSV.hasPrefix("\u{FEFF}") {
            processedCSV = String(processedCSV.dropFirst())
            print("Removed Byte Order Mark (BOM) from CSV")
        }
        
        // Print raw CSV content for debugging (limited to first 500 chars)
        let previewLength = min(500, processedCSV.count)
        let contentPreview = processedCSV.prefix(previewLength)
        print("🔍 Raw CSV content preview: \n\(contentPreview)\n...")
        
        // Create a hex dump of the first few bytes to check for hidden characters
        if let data = processedCSV.data(using: .utf8) {
            let firstBytes = data.prefix(min(100, data.count))
            let hexString = firstBytes.map { String(format: "%02x", $0) }.joined(separator: " ")
            print("🔍 Hex dump of first 100 bytes: \(hexString)")
        }
        
        // Split into rows
        let rows = processedCSV.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        // Check if we have at least a header row
        if rows.isEmpty {
            print("⚠️ CSV file is empty")
            throw CSVError.invalidData
        }
        
        print("📊 CSV Analysis: Found \(rows.count) total rows")
        
        // Process header row
        let headerRow = rows[0]
        let headerFields = CSVService.shared.parseCSVRow(headerRow)
        
        print("📊 CSV Header: \(headerFields.joined(separator: ", "))")
        
        // Verify the header contains expected fields
        let expectedFields = ["Name", "Type", "Proof", "Age", "Distillery"]
        let headerLower = headerFields.map { $0.lowercased() }
        
        // Check if at least the first few critical fields are present
        for field in expectedFields {
            if !headerLower.contains(field.lowercased()) {
                print("⚠️ CSV header missing expected field: \(field)")
            }
        }
        
        // Check for data rows
        if rows.count < 2 {
            print("⚠️ CSV file contains only a header with no data rows")
            return []
        }
        
        // Log all data rows for debugging
        print("📋 CSV contains \(rows.count - 1) data rows")
        
        // Process data rows
        var whiskeys: [WhiskeyRecord] = []
        var whiskeyNames = Set<String>()
        var duplicateNames = Set<String>()
        
        // Start from index 1 to skip header
        for i in 1..<rows.count {
            let row = rows[i]
            let fields = CSVService.shared.parseCSVRow(row)
            
            // Skip if not enough fields
            if fields.isEmpty || fields.count < 3 {
                print("⚠️ Skipping row \(i+1): insufficient fields")
                continue
            }
            
            // Check for empty name field
            if fields[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                print("⚠️ Skipping row \(i+1): empty name field")
                continue
            }
            
            // Create a new whiskey record and add to array
            let record = WhiskeyRecord(fields: fields)
            
            // Check for duplicate names
            let normalizedName = record.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if whiskeyNames.contains(normalizedName) {
                print("⚠️ Duplicate whiskey name detected: \(record.name)")
                duplicateNames.insert(normalizedName)
            }
            whiskeyNames.insert(normalizedName)
            
            // Log every whiskey being processed
            if i < 100 || i % 50 == 0 {
                print("📋 Row \(i): Whiskey: \(record.name), Type: \(record.type), Proof: \(record.proof)")
            }
            
            whiskeys.append(record)
        }
        
        if !duplicateNames.isEmpty {
            print("⚠️ Found \(duplicateNames.count) duplicate whiskey names in CSV")
            for name in duplicateNames {
                print("  - Duplicate: \(name)")
            }
        }
        
        // Print summary of whiskeys found
        print("✅ Found \(whiskeys.count) valid whiskey records in CSV")
        
        // Print a list of all whiskey names for debugging deletions
        print("📋 All whiskey names in CSV:")
        let allNames = whiskeys.map { $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }.sorted()
        for name in allNames {
            print("  - \(name)")
        }
        
        // Print a few whiskey names as a preview
        let previewCount = min(10, whiskeys.count)
        let previewNames = whiskeys.prefix(previewCount).map { $0.name }
        print("📋 First \(previewCount) whiskey names: \(previewNames.joined(separator: ", "))")
        
        return whiskeys
    }
    
    private func synchronize(csvWhiskeys: [WhiskeyRecord], localWhiskeys: [Whiskey], context: NSManagedObjectContext) throws -> SyncResult {
        var result = SyncResult()
        
        // Create dictionaries for easier lookup
        var localWhiskeyDict: [String: Whiskey] = [:]           // by name+proof+storepick
        var localWhiskeyByAttributeDict: [String: Whiskey] = [:] // by distillery+type+proof
        var processedLocalWhiskeys = Set<String>()
        var processedCsvWhiskeys = Set<String>()
        
        // Track whiskeys renamed in the app since last sync
        var renamedWhiskeys: [(localWhiskey: Whiskey, csvRecord: WhiskeyRecord)] = []
        
        // Get the last sync date
        let syncDate = self.lastSyncDate ?? Date.distantPast
        print("Last sync date: \(syncDate)")
        
        // Skip loading deleted whiskeys during sync
        // loadDeletedWhiskeysFromUserDefaults()
        let manuallyDeletedWhiskeyIDs = Array(self.deletedWhiskeyIDs)
        let manuallyDeletedWhiskeyNames = Array(self.deletedWhiskeyNames)
        print("🗑️ Manually deleted whiskey IDs count: \(manuallyDeletedWhiskeyIDs.count)")
        print("🗑️ Manually deleted whiskey names count: \(manuallyDeletedWhiskeyNames.count)")
        
        // NOTE: The csvWhiskeys passed to this method have already been filtered
        // to exclude whiskeys matching deleted names in the syncWithFile method.
        
        for whiskey in localWhiskeys {
            if let name = whiskey.name, !name.isEmpty {
                // Store by unique key (name-based)
                let key = createUniqueKey(name: name, 
                                         proof: whiskey.proof,
                                         isStorePick: whiskey.isStorePick,
                                         storePickName: whiskey.storePickName ?? "")
                localWhiskeyDict[key] = whiskey
                
                // Also store by attribute key for fuzzy matching (without name)
                let attrKey = createAttributeKey(
                    distillery: whiskey.distillery, 
                    type: whiskey.type,
                    proof: whiskey.proof
                )
                
                if !attrKey.contains("--") { // Only add if we have valid attributes
                    localWhiskeyByAttributeDict[attrKey] = whiskey
                }
                
                // Log recently modified whiskeys
                if let modDate = whiskey.modificationDate, modDate > syncDate {
                    print("Found locally modified whiskey: \(name) (modified at \(modDate))")
                }
            }
        }
        
        // Initialize the class property csvWhiskeyDict with the CSV records
        csvWhiskeyDict.removeAll() // Clear any existing data
        
        // Create a set of all CSV whiskey names for easier lookup
        var csvWhiskeyNames = Set<String>()
        
        // Process all CSV whiskeys (already filtered to remove deleted ones)
        for csvWhiskey in csvWhiskeys {
            // Create a key for the CSV whiskey dictionary
            let key = createUniqueKey(name: csvWhiskey.name, 
                                     proof: csvWhiskey.proof,
                                     isStorePick: csvWhiskey.isStorePick,
                                     storePickName: csvWhiskey.storePickName ?? "")
            csvWhiskeyDict[key] = csvWhiskey
            
            // Add to our set of names for deletion checking
            let csvName = csvWhiskey.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            csvWhiskeyNames.insert(csvName)
        }
        
        print("🔍 CSV contains \(csvWhiskeyNames.count) unique whiskey names")
        
        // FIRST PASS: Find locally modified whiskeys and prioritize them
        for (key, localWhiskey) in localWhiskeyDict {
            if let modDate = localWhiskey.modificationDate, modDate > syncDate,
               let name = localWhiskey.name, !name.isEmpty {
                
                // This whiskey was modified in the app since last sync
                print("Found modified whiskey: '\(name)' (modified at \(modDate))")
                
                // Check if there's a CSV entry with the same name (exact match)
                let exactMatchFound = csvWhiskeyDict.values.contains { 
                    $0.name == name && abs($0.proof - localWhiskey.proof) < 1.0
                }
                
                if exactMatchFound {
                    // There's already a match by name, will be handled in second pass
                    print("Exact match by name found for modified whiskey: '\(name)'")
                    continue
                }
                
                // Look for a match by attributes (for renamed whiskeys)
                let attrKey = createAttributeKey(
                    distillery: localWhiskey.distillery,
                    type: localWhiskey.type,
                    proof: localWhiskey.proof
                )
                
                // Find potential matches in CSV
                var bestMatch: WhiskeyRecord? = nil
                var bestMatchKey = ""
                var bestScore = 0.0
                
                for (csvKey, csvRecord) in csvWhiskeyDict {
                    // Skip if already processed
                    if processedCsvWhiskeys.contains(csvKey) {
                        continue
                    }
                    
                    // Check if attributes match
                    let csvAttrKey = createAttributeKey(
                        distillery: csvRecord.distillery,
                        type: csvRecord.type,
                        proof: csvRecord.proof
                    )
                    
                    if csvAttrKey == attrKey {
                        // Attributes match, calculate similarity score
                        let score = calculateSimilarityExcludingName(
                            localWhiskey: localWhiskey,
                            csvRecord: csvRecord
                        )
                        
                        if score > bestScore && score > 0.7 {
                            bestScore = score
                            bestMatch = csvRecord
                            bestMatchKey = csvKey
                        }
                    }
                }
                
                // If we found a good match, this is likely a renamed whiskey
                if let matchRecord = bestMatch, bestScore > 0.7 {
                    print("Found match for renamed whiskey: '\(matchRecord.name)' -> '\(name)'")
                    renamedWhiskeys.append((localWhiskey: localWhiskey, csvRecord: matchRecord))
                    processedLocalWhiskeys.insert(key)
                    processedCsvWhiskeys.insert(bestMatchKey)
                }
            }
        }
        
        // SECOND PASS: Process CSV whiskeys against local whiskeys
        for csvWhiskey in csvWhiskeys {
            // Create a unique key for this CSV whiskey
            let key = createUniqueKey(name: csvWhiskey.name, 
                                      proof: csvWhiskey.proof,
                                      isStorePick: csvWhiskey.isStorePick,
                                      storePickName: csvWhiskey.storePickName ?? "")
            
            // Skip if already processed in first pass
            if processedCsvWhiskeys.contains(key) {
                continue
            }
            
            // First, check for an exact match by name+proof
            if let localWhiskey = localWhiskeyDict[key] {
                // Skip if already processed
                if processedLocalWhiskeys.contains(key) {
                    continue
                }
                
                // For exact matches, only update if local hasn't been modified since last sync
                let wasModified = localWhiskey.modificationDate.map { $0 > syncDate } ?? false
                
                if wasModified {
                    print("Skipping update for locally modified whiskey: '\(localWhiskey.name ?? "unknown")'")
                    processedLocalWhiskeys.insert(key)
                    continue
                }
                
                // Update the whiskey from CSV data
                let wasUpdated = updateLocalWhiskey(localWhiskey, from: csvWhiskey, context: context)
                
                if wasUpdated {
                    print("Updated existing whiskey: \(csvWhiskey.name)")
                    result.updated += 1
                } else {
                    print("No changes needed for: \(csvWhiskey.name)")
                }
                
                processedLocalWhiskeys.insert(key)
                continue
            }
            
            // No exact match by name, try matching by attributes (for opposite rename case)
            let attrKey = createAttributeKey(
                distillery: csvWhiskey.distillery,
                type: csvWhiskey.type,
                proof: csvWhiskey.proof
            )
            
            if let matchingWhiskey = localWhiskeyByAttributeDict[attrKey] {
                let localKey = createUniqueKey(
                    name: matchingWhiskey.name ?? "",
                    proof: matchingWhiskey.proof,
                    isStorePick: matchingWhiskey.isStorePick,
                    storePickName: matchingWhiskey.storePickName ?? ""
                )
                
                // Skip if already processed
                if processedLocalWhiskeys.contains(localKey) {
                    continue
                }
                
                // Check if scores are high enough to consider them the same whiskey
                let score = calculateSimilarityExcludingName(
                    localWhiskey: matchingWhiskey,
                    csvRecord: csvWhiskey
                )
                
                if score > 0.7 {
                    print("Found match by attributes: '\(csvWhiskey.name)' -> '\(matchingWhiskey.name ?? "unknown")'")
                    
                    // Check who has priority (local or CSV)
                    let localModified = matchingWhiskey.modificationDate.map { $0 > syncDate } ?? false
                    
                    if localModified {
                        print("Local whiskey was modified since last sync, keeping local data")
                        // Update CSV record with local data (for writing back)
                        var updatedCsvRecord = csvWhiskey
                        updatedCsvRecord.name = matchingWhiskey.name ?? updatedCsvRecord.name
                        updatedCsvRecord.type = matchingWhiskey.type ?? updatedCsvRecord.type
                        updatedCsvRecord.distillery = matchingWhiskey.distillery ?? updatedCsvRecord.distillery
                        updatedCsvRecord.finish = matchingWhiskey.finish ?? updatedCsvRecord.finish
                        updatedCsvRecord.isBiB = matchingWhiskey.isBiB
                        updatedCsvRecord.isSiB = matchingWhiskey.isSiB
                        updatedCsvRecord.isStorePick = matchingWhiskey.isStorePick
                        updatedCsvRecord.storePickName = matchingWhiskey.storePickName ?? updatedCsvRecord.storePickName
                        updatedCsvRecord.externalReviews = matchingWhiskey.externalReviews ?? updatedCsvRecord.externalReviews
                        
                        // Update the record in the dictionary
                        csvWhiskeyDict[key] = updatedCsvRecord
                        
                        // Only count as update if actual data changed, not just the name
                        let dataChanged = updatedCsvRecord.type != csvWhiskey.type ||
                                        updatedCsvRecord.proof != csvWhiskey.proof ||
                                        updatedCsvRecord.age != csvWhiskey.age ||
                                        updatedCsvRecord.distillery != csvWhiskey.distillery ||
                                        updatedCsvRecord.finish != csvWhiskey.finish ||
                                        updatedCsvRecord.isBiB != csvWhiskey.isBiB ||
                                        updatedCsvRecord.isSiB != csvWhiskey.isSiB ||
                                        updatedCsvRecord.isStorePick != csvWhiskey.isStorePick ||
                                        updatedCsvRecord.storePickName != csvWhiskey.storePickName ||
                                        updatedCsvRecord.numberOfBottles != csvWhiskey.numberOfBottles ||
                                        updatedCsvRecord.isFinished != csvWhiskey.isFinished ||
                                        updatedCsvRecord.price != csvWhiskey.price
                        
                        if dataChanged {
                            print("📝 Renamed whiskey had data changes - counting as update: \(matchingWhiskey.name ?? "unknown")")
                            result.updated += 1
                        } else {
                            print("📝 Renamed whiskey had no data changes - not counting as update: \(matchingWhiskey.name ?? "unknown")")
                        }
                    } else {
                        // Update local data from CSV
                        let wasUpdated = updateLocalWhiskey(matchingWhiskey, from: csvWhiskey, context: context)
                        if wasUpdated {
                            print("Updated local whiskey: \(matchingWhiskey.name ?? "unknown") from CSV")
                            result.updated += 1
                        }
                    }
                    
                    processedLocalWhiskeys.insert(localKey)
                    processedCsvWhiskeys.insert(key)
                    continue
                }
            }
            
            // If we get here, this is a new whiskey from CSV
            print("Adding new whiskey from CSV: \(csvWhiskey.name)")
            createLocalWhiskey(from: csvWhiskey, context: context)
            result.added += 1
            processedCsvWhiskeys.insert(key)
        }
        
        // THIRD PASS: Update CSV records for locally renamed whiskeys
        for pair in renamedWhiskeys {
            let localWhiskey = pair.localWhiskey
            var csvRecord = pair.csvRecord
            
            print("Updating CSV record for renamed whiskey: '\(csvRecord.name)' -> '\(localWhiskey.name ?? "unknown")'")
            
            // Create the key for the CSV record
            let csvKey = createUniqueKey(
                name: csvRecord.name,
                proof: csvRecord.proof,
                isStorePick: csvRecord.isStorePick,
                storePickName: csvRecord.storePickName ?? ""
            )
            
            // Update CSV record with local data
            csvRecord.name = localWhiskey.name ?? csvRecord.name
            csvRecord.type = localWhiskey.type ?? csvRecord.type
            csvRecord.proof = localWhiskey.proof
            csvRecord.distillery = localWhiskey.distillery ?? csvRecord.distillery
            csvRecord.age = localWhiskey.age ?? csvRecord.age
            csvRecord.finish = localWhiskey.finish ?? csvRecord.finish
            csvRecord.isBiB = localWhiskey.isBiB
            csvRecord.isSiB = localWhiskey.isSiB
            csvRecord.isStorePick = localWhiskey.isStorePick
            csvRecord.storePickName = localWhiskey.storePickName ?? csvRecord.storePickName
            csvRecord.numberOfBottles = localWhiskey.numberOfBottles
            csvRecord.isFinished = localWhiskey.isFinished
            csvRecord.price = localWhiskey.price
            csvRecord.externalReviews = localWhiskey.externalReviews ?? csvRecord.externalReviews
            
            // Update the dictionary
            csvWhiskeyDict[csvKey] = csvRecord
            result.updated += 1
        }
        
        // FOURTH PASS: Add any new local whiskeys to CSV
        for (key, localWhiskey) in localWhiskeyDict {
            // Skip already processed whiskeys
            if processedLocalWhiskeys.contains(key) {
                continue
            }
            
            // This whiskey doesn't exist in CSV, add it
            if let name = localWhiskey.name, !name.isEmpty {
                print("Adding new local whiskey to CSV: \(name)")
                
                // Create a new CSV record from this whiskey
                let newCsvRecord = WhiskeyRecord(
                    name: name,
                    type: localWhiskey.type ?? "",
                    proof: localWhiskey.proof,
                    age: localWhiskey.age ?? "",
                    distillery: localWhiskey.distillery ?? "",
                    finish: localWhiskey.finish ?? "",
                    isBiB: localWhiskey.isBiB,
                    isSiB: localWhiskey.isSiB,
                    isStorePick: localWhiskey.isStorePick,
                    storePickName: localWhiskey.storePickName ?? "",
                    numberOfBottles: calculateTotalActiveBottles(localWhiskey),
                    isFinished: isCompletelyFinished(localWhiskey),
                    isOpen: localWhiskey.isOpen,
                    notes: localWhiskey.notes ?? "",
                    price: localWhiskey.price,
                    isCaskStrength: localWhiskey.isCaskStrength,
                    isTasted: localWhiskey.isTasted,
                    externalReviews: ""
                )
                
                // Add to dictionary for export
                csvWhiskeyDict[key] = newCsvRecord
                // Don't count adding to CSV as an update
                print("Added local whiskey to CSV dictionary: \(name)")
                
                // Mark as processed
                processedLocalWhiskeys.insert(key)
            }
        }
        
        // Fifth pass: Handle deletions from CSV
        // Check for whiskeys that exist in Core Data but not in the CSV
        var deletedCount = 0

        // Create a set of CSV whiskey names for deletion checking
        let csvWhiskeyNameSet = Set(csvWhiskeys.map { 
            $0.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) 
        })

        // Use our improved deletion method that handles initial sync properly
        deletedCount = deleteWhiskeysNotInCSV(
            csvNames: csvWhiskeyNameSet,
            csvWhiskeys: csvWhiskeys,
            localWhiskeys: localWhiskeys,
            context: context
        )

        // Save all changes to Core Data
        if result.totalChanges > 0 || deletedCount > 0 {
            try context.save()
        }
        
        // Create final result with the correct deletion count
        result.deleted = deletedCount
        print("🔄 Final sync result: added=\(result.added), updated=\(result.updated), deleted=\(result.deleted), conflicts=\(result.conflicts)")
        
        // Make one final pass to ensure any deleted whiskeys aren't in the local database anymore
        for whiskey in localWhiskeys {
            guard let whiskeyID = whiskey.id?.uuidString else { continue }
            
            if manuallyDeletedWhiskeyIDs.contains(whiskeyID) {
                // Double-check if this whiskey has been manually deleted but still exists in local DB
                print("🗑️ Found manually deleted whiskey still in database: \(whiskey.name ?? "Unknown")")
                
                // Delete it from Core Data
                context.delete(whiskey)
                
                // Update result
                result.deleted += 1
            }
        }
        
        return result
    }
    
    // New helper method to calculate similarity excluding name
    private func calculateSimilarityExcludingName(
        localWhiskey: Whiskey,
        csvRecord: WhiskeyRecord
    ) -> Double {
        var score = 0.0
        
        // Distillery and type are most important
        if csvRecord.distillery.lowercased() == (localWhiskey.distillery?.lowercased() ?? "") {
            score += 0.4 // 40% weight for distillery
        }
        
        if csvRecord.type.lowercased() == (localWhiskey.type?.lowercased() ?? "") {
            score += 0.3 // 30% weight for type
        }
        
        // Proof should be close
        let proofDiff = abs(csvRecord.proof - localWhiskey.proof)
        if proofDiff < 0.1 {
            score += 0.2 // 20% weight for proof
        } else if proofDiff < 1.0 {
            score += 0.15
        } else if proofDiff < 3.0 {
            score += 0.1
        }
        
        // Store pick status should match
        if csvRecord.isStorePick == localWhiskey.isStorePick {
            score += 0.1 // 10% weight for store pick status
            
            // If both are store picks, check store name
            if csvRecord.isStorePick && localWhiskey.isStorePick {
                let csvStore = csvRecord.storePickName.lowercased()
                let localStore = (localWhiskey.storePickName ?? "").lowercased()
                
                if !csvStore.isEmpty && !localStore.isEmpty && csvStore == localStore {
                    score += 0.1 // Extra 10% if store names match
                }
            }
        }
        
        return score
    }
    
    // Helper function to create a unique identifier for a whiskey
    private func createUniqueKey(name: String, proof: Double, isStorePick: Bool, storePickName: String) -> String {
        var key = name.lowercased()
        
        // Add proof to make it more unique
        key += "-\(String(format: "%.1f", proof))"
        
        // Add store pick info if applicable
        if isStorePick && !storePickName.isEmpty {
            key += "-sp-\(storePickName.lowercased())"
        } else if isStorePick {
            key += "-sp"
        }
        
        return key
    }
    
    // New method to create a key based on attributes other than name
    private func createAttributeKey(distillery: String?, type: String?, proof: Double) -> String {
        let distilleryKey = (distillery ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let typeKey = (type ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let proofStr = String(format: "%.1f", proof)
        
        // Create a key using distillery, type and proof
        return "attr-\(distilleryKey)-\(typeKey)-\(proofStr)"
    }
    
    private func updateLocalWhiskey(_ localWhiskey: Whiskey, from csvRecord: WhiskeyRecord, context: NSManagedObjectContext) -> Bool {
        var wasUpdated = false
        
        // Check each field for changes
        if localWhiskey.type != csvRecord.type {
            localWhiskey.type = csvRecord.type
            wasUpdated = true
        }
        
        if localWhiskey.proof != csvRecord.proof {
            localWhiskey.proof = csvRecord.proof
            wasUpdated = true
        }
        
        if localWhiskey.age != csvRecord.age {
            localWhiskey.age = csvRecord.age
            wasUpdated = true
        }
        
        if localWhiskey.distillery != csvRecord.distillery {
            localWhiskey.distillery = csvRecord.distillery
            wasUpdated = true
        }
        
        if localWhiskey.finish != csvRecord.finish {
            localWhiskey.finish = csvRecord.finish
            wasUpdated = true
        }
        
        if localWhiskey.isBiB != csvRecord.isBiB {
            localWhiskey.isBiB = csvRecord.isBiB
            wasUpdated = true
        }
        
        if localWhiskey.isSiB != csvRecord.isSiB {
            localWhiskey.isSiB = csvRecord.isSiB
            wasUpdated = true
        }
        
        if localWhiskey.isStorePick != csvRecord.isStorePick {
            localWhiskey.isStorePick = csvRecord.isStorePick
            wasUpdated = true
        }
        
        if localWhiskey.storePickName != csvRecord.storePickName {
            localWhiskey.storePickName = csvRecord.storePickName
            wasUpdated = true
        }
        
        if localWhiskey.numberOfBottles != csvRecord.numberOfBottles {
            localWhiskey.numberOfBottles = csvRecord.numberOfBottles
            wasUpdated = true
        }
        
        if localWhiskey.isFinished != csvRecord.isFinished {
            localWhiskey.isFinished = csvRecord.isFinished
            wasUpdated = true
        }
        
        if localWhiskey.price != csvRecord.price {
            localWhiskey.price = csvRecord.price
            wasUpdated = true
        }
        
        if let existingReviews = localWhiskey.externalReviews, existingReviews != csvRecord.externalReviews {
            localWhiskey.externalReviews = csvRecord.externalReviews
            wasUpdated = true
        } else if localWhiskey.externalReviews == nil && !csvRecord.externalReviews.isEmpty {
            localWhiskey.externalReviews = csvRecord.externalReviews
            wasUpdated = true
        }
        
        if localWhiskey.replacementStatus != csvRecord.replacementStatus {
            localWhiskey.replacementStatus = csvRecord.replacementStatus
            wasUpdated = true
        }
        
        if wasUpdated {
            localWhiskey.modificationDate = Date()
        }
        
        return wasUpdated
    }
    
    private func createLocalWhiskey(from csvRecord: WhiskeyRecord, context: NSManagedObjectContext) {
        // Skip deleted whiskey check during import
        /*
        // Double check this whiskey name isn't in our deleted list
        let csvName = csvRecord.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check directly against the stored deleted whiskey names
        var matchedDeletedName = ""
        let isDeleted = self.deletedWhiskeyNames.contains { deletedName in
            let exactMatch = csvName == deletedName
            let csvContainsDeleted = csvName.contains(deletedName)
            let deletedContainsCsv = deletedName.contains(csvName)
            
            if exactMatch || csvContainsDeleted || deletedContainsCsv {
                matchedDeletedName = deletedName
                return true
            }
            return false
        }
        
        if isDeleted {
            print("⛔️ PREVENTION: Blocked re-adding deleted whiskey: '\(csvRecord.name)' - matched with '\(matchedDeletedName)'")
            return
        }
        */
        
        // Not deleted, proceed with creation
        let newWhiskey = Whiskey(context: context)
        newWhiskey.id = UUID()
        newWhiskey.name = csvRecord.name
        newWhiskey.type = csvRecord.type
        newWhiskey.proof = csvRecord.proof
        newWhiskey.age = csvRecord.age
        newWhiskey.distillery = csvRecord.distillery
        newWhiskey.finish = csvRecord.finish
        newWhiskey.isBiB = csvRecord.isBiB
        newWhiskey.isSiB = csvRecord.isSiB
        newWhiskey.isStorePick = csvRecord.isStorePick
        newWhiskey.storePickName = csvRecord.storePickName
        newWhiskey.numberOfBottles = csvRecord.numberOfBottles
        newWhiskey.isFinished = csvRecord.isFinished
        newWhiskey.isOpen = csvRecord.isOpen
        newWhiskey.notes = csvRecord.notes
        newWhiskey.price = csvRecord.price
        newWhiskey.isCaskStrength = csvRecord.isCaskStrength
        newWhiskey.externalReviews = csvRecord.externalReviews
        newWhiskey.status = "owned"
        newWhiskey.replacementStatus = csvRecord.replacementStatus
        
        // Set addedDate to track when the whiskey was first added
        newWhiskey.addedDate = Date()
        
        newWhiskey.modificationDate = Date()
    }
    
    private func shouldUpdateForModifiedWhiskeys(_ context: NSManagedObjectContext) -> Bool {
        // Check if any whiskeys were modified since last sync
        let syncDate = self.lastSyncDate ?? Date.distantPast
        print("Checking for whiskeys modified since: \(syncDate)")
        
        do {
            // Get the total counts first
            let allWhiskeysFetchRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
            let countInCoreData = try context.count(for: allWhiskeysFetchRequest)
            let countInCSV = csvWhiskeyDict.count
            
            print("Count comparison - Core Data: \(countInCoreData), CSV: \(countInCSV)")
            
            // First check for any recently modified whiskeys regardless of timestamp
            // This is important for local edits that we always want to push
            let fetchRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
            
            // Check for whiskeys with any modification date (meaning they were edited at some point)
            fetchRequest.predicate = NSPredicate(format: "modificationDate != nil")
            let modifiedWhiskeys = try context.fetch(fetchRequest)
            
            // Debug log all modified whiskeys
            print("🔍 All whiskeys with modification dates:")
            for whiskey in modifiedWhiskeys {
                if let name = whiskey.name, let modDate = whiskey.modificationDate {
                    let timeAgo = Date().timeIntervalSince(modDate)
                    let minutesAgo = Int(timeAgo / 60)
                    print("  - '\(name)' modified \(minutesAgo) minutes ago (\(modDate))")
                }
            }
            
            // Count whiskeys modified after the last sync
            let recentlyModifiedCount = modifiedWhiskeys.filter { whiskey in
                guard let modDate = whiskey.modificationDate else { return false }
                return modDate > syncDate
            }.count
            
            print("Found \(recentlyModifiedCount) whiskeys modified after last sync")
            
            // For whiskeys modified recently (in the last hour), we should always update the CSV
            // This covers the case where the user makes changes after creating the sync file
            let thirtyMinutesAgo = Date(timeIntervalSinceNow: -1800) // 30 minutes
            let veryRecentModifications = modifiedWhiskeys.filter { whiskey in
                guard let modDate = whiskey.modificationDate else { return false }
                return modDate > thirtyMinutesAgo
            }
            
            let veryRecentlyModifiedCount = veryRecentModifications.count
            if veryRecentlyModifiedCount > 0 {
                print("⚠️ Found \(veryRecentlyModifiedCount) whiskeys modified within the last 30 minutes - forcing CSV update")
                
                // Log which whiskeys were recently modified
                for whiskey in veryRecentModifications {
                    print("  ✏️ Recently modified: '\(whiskey.name ?? "unknown")' - will be written to CSV")
                }
                
                return true
            }
            
            // SPECIAL CASE: After creating a new sync file, we should update the CSV file at least once
            // This ensures that any initial edits are captured
            if lastSyncDate == nil || Date().timeIntervalSince(lastSyncDate!) < 300 { // 5 minutes
                print("⚠️ New sync file detected (no previous sync or sync less than 5 minutes ago) - forcing update")
                return true
            }
            
            if recentlyModifiedCount > 0 {
                print("Need to update CSV file for modified whiskeys")
                return true
            }
            
            if countInCoreData != countInCSV {
                print("Need to update CSV file due to count mismatch")
                return true
            }
            
            // Check if any whiskey has a name that doesn't match what's in the CSV
            print("Checking for renamed whiskeys...")
            for whiskey in modifiedWhiskeys {
                if let name = whiskey.name, !name.isEmpty {
                    // Create a key for this whiskey
                    let key = createUniqueKey(
                        name: name,
                        proof: whiskey.proof,
                        isStorePick: whiskey.isStorePick,
                        storePickName: whiskey.storePickName ?? ""
                    )
                    
                    // If this key doesn't exist in the CSV, it might have been renamed
                    if !csvWhiskeyDict.keys.contains(key) {
                        print("⚠️ Possible renamed whiskey detected: '\(name)' not found in CSV - forcing update")
                        return true
                    }
                }
            }
            
            return false
        } catch {
            print("Error checking for modified whiskeys: \(error)")
            // If we encounter an error, return true to be safe and trigger an update
            return true
        }
    }
    
    // Helper method to clear tracked deleted whiskeys
    private func clearTrackedDeletedWhiskeys() {
        // Log how many whiskeys were in the tracking lists
        let idCount = deletedWhiskeyIDs.count
        let nameCount = deletedWhiskeyNames.count
        
        if idCount > 0 || nameCount > 0 {
            print("🧹 Clearing \(idCount) deleted whiskey IDs and \(nameCount) names after sync")
            
            // Actually clear the sets
            deletedWhiskeyIDs.removeAll()
            deletedWhiskeyNames.removeAll()
            
            // Save the empty sets to UserDefaults
            saveDeletedWhiskeysToUserDefaults()
        }
    }
    
    // New method to manually reset the deleted whiskeys tracking
    func resetDeletedWhiskeysTracking() {
        print("🗑️ MANUALLY RESETTING deleted whiskey tracking lists")
        
        // Store the counts for logging
        let idCount = deletedWhiskeyIDs.count
        let nameCount = deletedWhiskeyNames.count
        
        // Clear the sets
        deletedWhiskeyIDs.removeAll()
        deletedWhiskeyNames.removeAll()
        
        // Save the empty sets to UserDefaults
        saveDeletedWhiskeysToUserDefaults()
        
        print("✅ Cleared \(idCount) whiskey IDs and \(nameCount) whiskey names from deletion tracking")
    }
    
    // Add a new method to verify sync file settings on app launch
    func validateSyncSettings() {
        // Check if we have a file URL but no valid bookmark (for external files)
        if let urlString = userDefaults.string(forKey: syncFileURLKey),
           let url = URL(string: urlString) {
            
            // For files in Documents directory, verify they still exist
            if url.path.contains("/Documents/") {
                if !FileManager.default.fileExists(atPath: url.path) {
                    print("⚠️ Sync file no longer exists in Documents: \(url.lastPathComponent)")
                    clearSyncSettings()
                    return
                }
                
                print("✅ Validated Documents sync file: \(url.lastPathComponent)")
                return
            }
            
            // For external files, check if we have a bookmark
            if let bookmarkData = userDefaults.data(forKey: "csvSyncBookmarkData") {
                do {
                    var isStale = false
                    let bookmarkURL = try URL(resolvingBookmarkData: bookmarkData,
                                             options: .withoutUI,
                                             relativeTo: nil,
                                             bookmarkDataIsStale: &isStale)
                    
                    // Test if we can actually access the file
                    if bookmarkURL.startAccessingSecurityScopedResource() {
                        defer { bookmarkURL.stopAccessingSecurityScopedResource() }
                        
                        // Check if file is reachable
                        do {
                            if try bookmarkURL.checkResourceIsReachable() {
                                print("✅ Validated external sync file: \(bookmarkURL.lastPathComponent)")
                                
                                // Update the bookmark if it was stale
                                if isStale {
                                    do {
                                        let newBookmark = try bookmarkURL.bookmarkData(options: .minimalBookmark)
                                        userDefaults.set(newBookmark, forKey: syncFileBookmarkKey)
                                        print("♻️ Updated stale bookmark for: \(bookmarkURL.lastPathComponent)")
                                    } catch {
                                        print("⚠️ Failed to update stale bookmark: \(error)")
                                    }
                                }
                                
                                return
                            } else {
                                print("⚠️ External sync file no longer reachable: \(bookmarkURL.lastPathComponent)")
                            }
                        } catch {
                            print("⚠️ Error checking if file is reachable: \(error)")
                        }
                    } else {
                        print("⚠️ Could not access security-scoped resource for: \(bookmarkURL.lastPathComponent)")
                    }
                } catch {
                    print("⚠️ Failed to resolve bookmark: \(error)")
                }
            } else {
                print("⚠️ External sync file URL exists but no bookmark found: \(url.lastPathComponent)")
            }
            
            // If we get here, something went wrong with external file validation
            print("⚠️ Clearing invalid sync settings")
            clearSyncSettings()
        }
    }
    
    // Check if we have a valid and accessible sync file URL
    var hasSyncFileConfigured: Bool {
        get {
            // IMPORTANT: Critical change - always force fetch a fresh URL from UserDefaults
            // This prevents any stale cache issues with the syncFileURL property
            guard let urlString = userDefaults.string(forKey: syncFileURLKey),
                  let url = URL(string: urlString) else { 
                print("🔍 DEBUG: hasSyncFileConfigured = false (no sync URL in UserDefaults)")
                return false 
            }
            
            // For files in the Documents directory, check if they exist
            if url.path.contains("/Documents/") {
                let exists = FileManager.default.fileExists(atPath: url.path)
                print("🔍 DEBUG: hasSyncFileConfigured = \(exists) (Documents file: \(url.lastPathComponent), exists=\(exists))")
                
                if !exists {
                    // If file doesn't exist, clear sync settings to avoid future errors
                    print("⚠️ Sync file in Documents no longer exists - clearing settings")
                    // Clear IMMEDIATELY instead of async to ensure consistent state
                    clearSyncSettings()
                    return false
                }
                
                return exists
            }
            
            // For external files, check if we have a bookmark and can access it
            guard let bookmarkData = userDefaults.data(forKey: "csvSyncBookmarkData") else {
                print("🔍 DEBUG: hasSyncFileConfigured = false (external file but no bookmark data)")
                // Clear IMMEDIATELY instead of async to ensure consistent state
                clearSyncSettings()
                return false
            }
            
            do {
                var isStale = false
                let bookmarkURL = try URL(resolvingBookmarkData: bookmarkData,
                                         options: .withoutUI,
                                         relativeTo: nil,
                                         bookmarkDataIsStale: &isStale)
                
                if bookmarkURL.startAccessingSecurityScopedResource() {
                    defer { bookmarkURL.stopAccessingSecurityScopedResource() }
                    
                    do {
                        let isReachable = try bookmarkURL.checkResourceIsReachable()
                        print("🔍 DEBUG: hasSyncFileConfigured = \(isReachable) (external file: \(bookmarkURL.lastPathComponent), stale=\(isStale), reachable=\(isReachable))")
                        
                        if !isReachable {
                            // If file is not reachable, clear sync settings
                            print("⚠️ External sync file not reachable - clearing settings")
                            // Clear IMMEDIATELY instead of async
                            clearSyncSettings()
                            return false
                        } else if isStale {
                            // Update the bookmark if it was stale but file is reachable
                            do {
                                let newBookmark = try bookmarkURL.bookmarkData(options: .minimalBookmark)
                                userDefaults.set(newBookmark, forKey: syncFileBookmarkKey)
                                print("♻️ Updated stale bookmark for: \(bookmarkURL.lastPathComponent)")
                            } catch {
                                print("⚠️ Failed to update stale bookmark: \(error)")
                                // If we couldn't update the bookmark, clear settings
                                clearSyncSettings()
                                return false
                            }
                        }
                        
                        return isReachable
                    } catch {
                        print("🔍 DEBUG: hasSyncFileConfigured = false (external file not reachable: \(error.localizedDescription))")
                        // Clear settings if file is not reachable
                        clearSyncSettings() // Clear immediately
                        return false
                    }
                } else {
                    print("🔍 DEBUG: hasSyncFileConfigured = false (couldn't access security scoped resource)")
                    // Clear settings if we can't access the security scoped resource
                    clearSyncSettings() // Clear immediately
                    return false
                }
            } catch {
                print("🔍 DEBUG: hasSyncFileConfigured = false (couldn't resolve bookmark: \(error.localizedDescription))")
                // Clear settings if we can't resolve the bookmark
                clearSyncSettings() // Clear immediately
                return false
            }
        }
        set {
            // Store the sync configuration state in UserDefaults
            UserDefaults.standard.set(newValue, forKey: "hasSyncFileConfigured")
            
            // If setting to true, make sure we have a valid URL in UserDefaults
            if newValue {
                if syncFileURL != nil {
                    print("✅ hasSyncFileConfigured set to true with valid syncFileURL")
                } else if let urlString = UserDefaults.standard.string(forKey: syncFileURLKey),
                          let url = URL(string: urlString) {
                    print("✅ hasSyncFileConfigured set to true, restoring syncFileURL from UserDefaults")
                    self.syncFileURL = url
                } else {
                    print("⚠️ WARNING: Setting hasSyncFileConfigured to true without a valid syncFileURL")
                }
            } else {
                // If setting to false and we have a value in UserDefaults, consider clearing it
                print("🔍 hasSyncFileConfigured set to false")
            }
            
            UserDefaults.standard.synchronize()
        }
    }
    
    // MARK: - Cloud File Monitoring
    
    // Add wrapper method to call the existing monitoring setup
    private func setupCloudMonitoring(for url: URL) {
        // Just call the existing method
        setupCloudFileMonitoring()
    }
    
    func setupCloudFileMonitoring() {
        // Clear any existing monitoring
        stopCloudFileMonitoring()
        
        guard let syncFileURL = syncFileURL else {
            print("Cannot setup cloud monitoring without a sync file URL")
            return
        }
        
        // Check if file is in iCloud
        do {
            let resources = try syncFileURL.resourceValues(forKeys: [.isUbiquitousItemKey])
            guard let isUbiquitous = resources.isUbiquitousItem, isUbiquitous else {
                print("File is not in iCloud, skipping cloud monitoring setup")
                return
            }
            
            print("Setting up cloud file monitoring for \(syncFileURL.lastPathComponent)")
            
            // 1. Watch for iCloud identity changes
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleUbiquityIdentityChange),
                name: NSNotification.Name.NSUbiquityIdentityDidChange,
                object: nil
            )
            
            // Store current identity token
            ubiquityIdentityToken = FileManager.default.ubiquityIdentityToken
            
            // 2. Set up a metadata query to monitor file status
            let query = NSMetadataQuery()
            query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
            query.predicate = NSPredicate(format: "%K == %@", 
                                        NSMetadataItemURLKey, syncFileURL as NSURL)
            
            // Add observers for query results
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleMetadataQueryUpdates),
                name: NSNotification.Name.NSMetadataQueryDidUpdate,
                object: query
            )
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleMetadataQueryUpdates),
                name: NSNotification.Name.NSMetadataQueryDidFinishGathering,
                object: query
            )
            
            // Start the query
            metadataQuery = query
            query.start()
            
            print("✅ Cloud file monitoring setup complete")
        } catch {
            print("Error checking if file is in iCloud: \(error)")
        }
    }
    
    func stopCloudFileMonitoring() {
        // Stop the metadata query
        metadataQuery?.stop()
        metadataQuery = nil
        
        // Remove observers
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name.NSMetadataQueryDidUpdate,
            object: nil
        )
        
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name.NSMetadataQueryDidFinishGathering,
            object: nil
        )
        
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name.NSUbiquityIdentityDidChange,
            object: nil
        )
        
        print("Cloud file monitoring stopped")
    }
    
    @objc private func handleUbiquityIdentityChange(_ notification: Notification) {
        let newToken = FileManager.default.ubiquityIdentityToken
        
        // Check if iCloud account changed - fix for FileManager method call
        if ubiquityIdentityToken != nil && newToken != nil {
            // Use direct comparison instead of the non-existent method
            let tokensEqual = (ubiquityIdentityToken as? NSObject) == (newToken as? NSObject)
            
            if !tokensEqual {
                print("⚠️ iCloud account changed, need to re-establish file access")
                // Update token
                ubiquityIdentityToken = newToken
                
                // Reinitialize monitoring if we have a sync file
                if syncFileURL != nil {
                    setupCloudFileMonitoring()
                }
                
                // Post notification for UI to update
                NotificationCenter.default.post(name: .csvSyncStatusChanged, object: nil)
            }
        } else if ubiquityIdentityToken != nil && newToken == nil {
            print("⚠️ User signed out of iCloud")
            ubiquityIdentityToken = nil
            
            // Post notification for UI to update
            NotificationCenter.default.post(name: .csvSyncStatusChanged, object: nil)
        } else if ubiquityIdentityToken == nil && newToken != nil {
            print("✅ User signed in to iCloud")
            ubiquityIdentityToken = newToken
            
            // Reinitialize monitoring if we have a sync file
            if syncFileURL != nil {
                setupCloudFileMonitoring()
            }
            
            // Post notification for UI to update
            NotificationCenter.default.post(name: .csvSyncStatusChanged, object: nil)
        }
    }
    
    @objc private func handleMetadataQueryUpdates(_ notification: Notification) {
        guard let query = notification.object as? NSMetadataQuery,
              let syncFileURL = syncFileURL else { return }
        
        query.disableUpdates()
        
        // Look for our file in the results
        for item in query.results {
            guard let metadataItem = item as? NSMetadataItem,
                  let itemURL = metadataItem.value(forAttribute: NSMetadataItemURLKey) as? URL,
                  itemURL.lastPathComponent == syncFileURL.lastPathComponent else {
                continue
            }
            
            // Get file status
            if let downloadStatus = metadataItem.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String {
                print("📄 iCloud file status: \(downloadStatus)")
                
                switch downloadStatus {
                case NSMetadataUbiquitousItemDownloadingStatusCurrent:
                    print("✅ File is up to date")
                case NSMetadataUbiquitousItemDownloadingStatusDownloaded:
                    print("✅ File has been downloaded")
                case NSMetadataUbiquitousItemDownloadingStatusNotDownloaded:
                    print("⚠️ File exists in iCloud but is not downloaded")
                    // Trigger download if needed
                    do {
                        try FileManager.default.startDownloadingUbiquitousItem(at: syncFileURL)
                        print("Started downloading file...")
                    } catch {
                        print("Error starting download: \(error)")
                    }
                default:
                    print("Unknown download status: \(downloadStatus)")
                }
            }
            
            // Check if there are any conflicts
            if let hasConflicts = metadataItem.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool,
               hasConflicts {
                print("⚠️ File has unresolved conflicts")
                // Post notification for UI to show conflict resolution
                NotificationCenter.default.post(name: .csvSyncConflictDetected, object: nil)
            }
            
            // Check upload status if applicable
            if let isUploaded = metadataItem.value(forAttribute: NSMetadataUbiquitousItemIsUploadedKey) as? Bool {
                print("File upload status: \(isUploaded ? "Uploaded" : "Not uploaded")")
            }
            
            // Post notification that status has been updated
            NotificationCenter.default.post(name: .csvSyncStatusChanged, object: nil)
            break  // Found our file, no need to continue
        }
        
        query.enableUpdates()
    }
    
    // MARK: - Helper Methods
    
    func isFileAccessible(_ url: URL, useSecurityAccess: Bool = false) -> Bool {
        // For files in app sandbox, just check if they exist
        if !useSecurityAccess {
            return FileManager.default.fileExists(atPath: url.path)
        }
        
        // For security-scoped resources, we need to try accessing them
        var isAccessible = false
        let accessGranted = url.startAccessingSecurityScopedResource()
        
        if accessGranted {
            defer { url.stopAccessingSecurityScopedResource() }
            
            do {
                // Check if the file exists and is reachable
                isAccessible = try url.checkResourceIsReachable()
                
                // Additional check for file attributes
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let fileSize = attributes[.size] as? NSNumber, fileSize.intValue == 0 {
                    print("⚠️ Warning: File exists but is empty (0 bytes)")
                    // We still consider it accessible, just empty
                }
                
                // For cloud files, check download status
                if try url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem == true {
                    // Check download status
                    let downloadStatus = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                    if let status = downloadStatus.ubiquitousItemDownloadingStatus {
                        print("📄 Cloud file status: \(status)")
                        
                        // If file is not downloaded, trigger download
                        if status == URLUbiquitousItemDownloadingStatus.notDownloaded {
                            print("Starting download of cloud file...")
                            try FileManager.default.startDownloadingUbiquitousItem(at: url)
                            // Although we're downloading it, we'll consider it not accessible yet
                            isAccessible = false
                        }
                    }
                }
            } catch {
                print("File is not accessible: \(error.localizedDescription)")
                isAccessible = false
            }
        } else {
            print("Could not access security scoped resource")
        }
        
        return isAccessible
    }
    
    // MARK: - Initialization and Restoration
    
    func restoreSyncSettingsOnAppLaunch() {
        print("Restoring sync settings on app launch")
        
        // Check if we have a configured sync file
        guard let urlString = UserDefaults.standard.string(forKey: "csvSyncFileURL"),
              let url = URL(string: urlString) else {
            print("No sync file URL found, nothing to restore")
            return
        }
        
        print("Found sync file URL: \(urlString)")
        
        // Check if the file is directly accessible or needs security-scoped access
        let isAccessible: Bool
        let needsSecurityAccess = !url.path.contains("/Documents/")
        
        if needsSecurityAccess, let bookmarkData = UserDefaults.standard.data(forKey: "csvSyncBookmarkData") {
            // Try to resolve bookmark
            do {
                var isStale = false
                let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, 
                                       options: .withoutUI, 
                                       relativeTo: nil, 
                                       bookmarkDataIsStale: &isStale)
                
                isAccessible = isFileAccessible(resolvedURL, useSecurityAccess: true)
                
                if isStale {
                    print("⚠️ Bookmark is stale, updating it")
                    // Try to update the bookmark
                    if let accessGranted = try? resolvedURL.startAccessingSecurityScopedResource() {
                        defer { resolvedURL.stopAccessingSecurityScopedResource() }
                        
                        do {
                            let updatedBookmark = try resolvedURL.bookmarkData(options: .minimalBookmark)
                            UserDefaults.standard.set(updatedBookmark, forKey: "csvSyncBookmarkData")
                            UserDefaults.standard.synchronize()
                            print("✅ Updated stale bookmark")
                        } catch {
                            print("⚠️ Failed to update stale bookmark: \(error)")
                        }
                    }
                }
                
                // Update our internal state
                syncFileURL = resolvedURL
                originalFilename = resolvedURL.lastPathComponent
                
            } catch {
                print("⚠️ Failed to resolve bookmark: \(error)")
                isAccessible = isFileAccessible(url, useSecurityAccess: true)
                
                // Fall back to the string URL
                syncFileURL = url
                originalFilename = url.lastPathComponent
            }
        } else {
            // Direct file access
            isAccessible = isFileAccessible(url, useSecurityAccess: false)
            
            // Update our internal state
            syncFileURL = url
            originalFilename = url.lastPathComponent
        }
        
        if isAccessible {
            print("✅ Sync file is accessible, setting up monitoring")
            // Set up file monitoring
            setupCloudFileMonitoring()
        } else {
            print("⚠️ Sync file is not accessible, clearing sync settings")
            // Clear sync settings
            clearSyncSettings()
        }
    }
    
    // Load the deleted whiskey IDs and names from UserDefaults
    private func loadDeletedWhiskeysFromUserDefaults() {
        // Clear current sets first to avoid retaining stale data
        deletedWhiskeyIDs.removeAll()
        deletedWhiskeyNames.removeAll()
        
        // Safely load stored IDs with nil coalescing
        if let storedIDs = userDefaults.stringArray(forKey: deletedWhiskeysKey) {
            // Only log if there are actually IDs to load
            if !storedIDs.isEmpty {
                print("📂 Loading \(storedIDs.count) deleted whiskey IDs from UserDefaults")
            }
            deletedWhiskeyIDs = Set(storedIDs)
        }
        
        // Safely load stored names with nil coalescing
        if let storedNames = userDefaults.stringArray(forKey: deletedWhiskeyNamesKey) {
            // Only log if there are actually names to load
            if !storedNames.isEmpty {
                print("📂 Loading \(storedNames.count) deleted whiskey names from UserDefaults")
            }
            deletedWhiskeyNames = Set(storedNames)
        }
    }
    
    // Save the deleted whiskey IDs and names to UserDefaults
    private func saveDeletedWhiskeysToUserDefaults() {
        // Defensive code to ensure we never save nil instead of empty array
        let idsArray = Array(deletedWhiskeyIDs)
        let namesArray = Array(deletedWhiskeyNames)
        
        // Only log if we're actually saving something
        if !idsArray.isEmpty || !namesArray.isEmpty {
            print("💾 Saving \(idsArray.count) deleted IDs and \(namesArray.count) names to UserDefaults")
        }
        
        userDefaults.set(idsArray, forKey: deletedWhiskeysKey)
        userDefaults.set(namesArray, forKey: deletedWhiskeyNamesKey)
        
        // Force synchronize to ensure data is saved immediately
        userDefaults.synchronize()
    }
    
    // Add to the end of the class, before the last closing brace but after other methods
    
    // Public method to write content to a file using coordinated writing
    public func writeToFile(at url: URL, content: String) async throws {
        print("📝 Writing to file at: \(url.path)")
        
        // Check if we need security access
        let needsSecurityAccess = !url.path.contains("/Documents/")
        var securityAccessGranted = false
        
        // Handle security access if needed
        if needsSecurityAccess {
            print("📝 File requires security access")
            
            // First try the direct URL
            securityAccessGranted = url.startAccessingSecurityScopedResource()
            
            // If direct access fails, try using the bookmark
            if !securityAccessGranted {
                print("⚠️ Direct security access failed, trying bookmark data...")
                
                if let bookmarkData = UserDefaults.standard.data(forKey: "csvSyncBookmarkData") {
                    do {
                        var isStale = false
                        let resolvedURL = try URL(resolvingBookmarkData: bookmarkData,
                                                 options: .withoutUI,
                                                 relativeTo: nil,
                                                 bookmarkDataIsStale: &isStale)
                        
                        if resolvedURL.path == url.path {
                            print("✅ Successfully resolved bookmark for writing: \(resolvedURL.path)")
                            securityAccessGranted = resolvedURL.startAccessingSecurityScopedResource()
                            
                            if securityAccessGranted {
                                print("✅ Gained security access via bookmark")
                                
                                // Update bookmark if it was stale
                                if isStale {
                                    do {
                                        let updatedBookmark = try resolvedURL.bookmarkData(options: .minimalBookmark)
                                        UserDefaults.standard.set(updatedBookmark, forKey: "csvSyncBookmarkData")
                                        UserDefaults.standard.synchronize()
                                        print("♻️ Updated stale bookmark for writing")
                                    } catch {
                                        print("⚠️ Failed to update stale bookmark: \(error)")
                                    }
                                }
                            } else {
                                print("⚠️ Could not gain security access from resolved bookmark")
                            }
                        } else {
                            print("⚠️ Resolved URL doesn't match target URL")
                        }
                    } catch {
                        print("⚠️ Failed to resolve bookmark for writing: \(error)")
                    }
                } else {
                    print("⚠️ No bookmark data available")
                }
                
                // If still no access, try creating and using a new bookmark
                if !securityAccessGranted {
                    print("⚠️ Attempting to create and use new bookmark...")
                    
                    // Try to create a temporary security-scoped URL access
                    if url.startAccessingSecurityScopedResource() {
                        do {
                            let newBookmark = try url.bookmarkData(options: .minimalBookmark)
                            UserDefaults.standard.set(newBookmark, forKey: "csvSyncBookmarkData")
                            UserDefaults.standard.synchronize()
                            print("✅ Created new security bookmark")
                            
                            // Use the new bookmark right away
                            url.stopAccessingSecurityScopedResource()
                            
                            var isStale = false
                            let resolvedURL = try URL(resolvingBookmarkData: newBookmark,
                                                    options: .withoutUI,
                                                    relativeTo: nil,
                                                    bookmarkDataIsStale: &isStale)
                            
                            securityAccessGranted = resolvedURL.startAccessingSecurityScopedResource()
                            print("✅ Used new bookmark to gain access: \(securityAccessGranted)")
                        } catch {
                            print("⚠️ Failed to create new bookmark: \(error)")
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                }
            }
            
            if !securityAccessGranted {
                print("⚠️ Could not access security scoped resource for writing")
                throw NSError(domain: "com.barrelbook", code: 10, 
                             userInfo: [NSLocalizedDescriptionKey: "Could not access the file for writing."])
            }
            
            print("✅ Security access granted for writing")
        }
        
        // Ensure security access is released when done
        defer {
            if needsSecurityAccess && securityAccessGranted {
                url.stopAccessingSecurityScopedResource()
                print("📝 Stopped accessing security scoped resource")
            }
        }
        
        // Create parent directories if needed
        let directoryURL = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directoryURL.path) {
            print("📝 Creating directory: \(directoryURL.path)")
            try FileManager.default.createDirectory(at: directoryURL, 
                                                   withIntermediateDirectories: true, 
                                                   attributes: nil)
        }
        
        // Create a file coordinator for safe file access
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var fileError: Error?
        
        // Create a semaphore to make the async operation synchronous
        let semaphore = DispatchSemaphore(value: 0)
        
        // Use coordinated writing for safely writing to the file
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { newURL in
            do {
                // Write the content to the file
                try content.write(to: newURL, atomically: true, encoding: .utf8)
                print("✅ Successfully wrote to file: \(newURL.path)")
                
                // Explicitly set file permissions to ensure it's readable and writable
                try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: newURL.path)
                
                // Log file attributes for debugging
                let attributes = try FileManager.default.attributesOfItem(atPath: newURL.path)
                if let fileSize = attributes[.size] as? NSNumber {
                    print("📄 File info: size=\(fileSize) bytes")
                }
                if let permissions = attributes[.posixPermissions] as? NSNumber {
                    print("📝 File permissions: \(String(format: "%o", permissions.intValue))")
                }
            } catch {
                print("⚠️ Error writing to file: \(error)")
                fileError = error
            }
            
            semaphore.signal()
        }
        
        // Wait for the operation to complete
        _ = semaphore.wait(timeout: .distantFuture)
        
        // Handle any errors from the coordinator
        if let error = coordinatorError {
            print("⚠️ Coordinator error: \(error)")
            throw error
        }
        
        // Handle any errors from the file operation
        if let error = fileError {
            print("⚠️ Operation error: \(error)")
            throw error
        }
        
        print("📝 File write completed successfully: \(url.path)")
    }
    
    // Enhanced method that handles conflict resolution
    func writeToFileWithConflictResolution(at url: URL, content: String, lastReadVersion: String?) async throws -> ConflictResolutionStatus {
        print("📝 Writing to file with conflict resolution at: \(url.absoluteString)")
        
        // SAFETY CHECK: Don't write empty content
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("⚠️ CRITICAL ERROR: Attempted to write empty content to CSV file. Aborting to prevent data loss.")
            throw NSError(domain: "com.barrelbook", code: 999, 
                         userInfo: [NSLocalizedDescriptionKey: "Prevented writing empty content to CSV file."])
        }
        
        // Basic validation - check that content has CSV structure
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            
        if lines.isEmpty || !lines[0].contains(",") {
            print("⚠️ CRITICAL ERROR: Content to be written doesn't appear to be valid CSV format. Aborting.")
            throw NSError(domain: "com.barrelbook", code: 999, 
                         userInfo: [NSLocalizedDescriptionKey: "Content doesn't appear to be valid CSV."])
        }
        
        print("✅ Content validation passed. Writing \(lines.count) lines of CSV data.")
        
        // Check if the new content is identical to what we last read
        // If so, we don't need to write the file at all to avoid unnecessary file operations
        if let lastReadVersion = lastReadVersion, content == lastReadVersion {
            print("📝 Content is identical to last read version - skipping write operation to preserve file")
            return .noConflict
        }
        
        // Create a FileAccessCoordinator to handle the file writing
        let coordinator = FileAccessCoordinator()
        
        // Use a task and continuation to handle the async operation
        return try await withCheckedThrowingContinuation { continuation in
            coordinator.coordinateWritingWithConflictResolution(at: url, content: content, lastReadVersion: lastReadVersion) { result in
                switch result {
                case .success(let status):
                    print("✅ Write completed with status: \(status)")
                    
                    // If a conflict was detected, notify the user
                    if status == .conflictDetected || status == .mergedWithConflict {
                        // Post a notification for the UI to display
                        DispatchQueue.main.async {
                            let conflictInfo: [String: Any] = [
                                "url": url,
                                "status": status
                            ]
                            NotificationCenter.default.post(
                                name: Notification.Name.csvSyncConflictDetected,
                                object: nil,
                                userInfo: conflictInfo
                            )
                        }
                    }
                    
                    continuation.resume(returning: status)
                    
                case .failure(let error):
                    print("❌ Failed to write file with conflict resolution: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // Store the last read content for a given URL to enable conflict detection
    private var lastReadVersions: [URL: String] = [:]
    
    // Track the version of a file after reading it
    func trackFileVersion(url: URL, content: String) {
        lastReadVersions[url] = content
    }
    
    // Get the last tracked version of a file
    func getLastTrackedVersion(for url: URL) -> String? {
        return lastReadVersions[url]
    }
    
    private func deleteWhiskeysNotInCSV(csvNames: Set<String>, csvWhiskeys: [WhiskeyRecord], localWhiskeys: [Whiskey], context: NSManagedObjectContext) -> Int {
        // Skip deletion process for initial sync (no previous sync date)
        if self.lastSyncDate == nil {
            print("🔄 Skipping deletion check for initial sync")
            return 0
        }
        
        var deletedCount = 0
        var localWhiskeyNames = Set<String>()
        
        // Create a set of local whiskey names for easy lookup
        for whiskey in localWhiskeys {
            if let name = whiskey.name?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                localWhiskeyNames.insert(name)
            }
        }
        
        // CRITICAL FIX: Check if we have a dramatically different number of CSV vs local whiskeys
        // This suggests a sync issue rather than actual deletions
        if !csvNames.isEmpty && localWhiskeys.count > 0 {
            let csvCount = csvNames.count
            let localCount = localWhiskeys.count
            
            // If CSV has less than 50% of local whiskeys, this is likely an error
            if csvCount < (localCount / 2) {
                print("⚠️ CRITICAL SAFETY: CSV has much fewer whiskeys (\(csvCount)) than local database (\(localCount))")
                print("⚠️ This suggests a sync issue rather than actual deletions, skipping delete phase")
                return 0
            }
            
            // If CSV is empty but we have local whiskeys, never delete local data
            if csvCount == 0 && localCount > 0 {
                print("⚠️ CRITICAL SAFETY: CSV is empty but local database has \(localCount) whiskeys")
                print("⚠️ Skipping deletion phase to prevent data loss")
                return 0
            }
        }
        
        // Find which local whiskeys are not in the CSV and delete them
        for whiskey in localWhiskeys {
            guard let id = whiskey.id?.uuidString, let name = whiskey.name?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                continue
            }
            
            // Skip if this whiskey's name is in the CSV
            if csvNames.contains(name) {
                continue
            }
            
            // Check for fuzzy matches to handle slight differences in naming
            var foundFuzzyMatch = false
            for csvName in csvNames {
                // Check for substring relationship
                if name.contains(csvName) || csvName.contains(name) {
                    foundFuzzyMatch = true
                    break
                }
                
                // Check for similarity using Levenshtein distance or other fuzzy matching
                // (simplified here, but could be more sophisticated)
                if name.count > 3 && csvName.count > 3 {
                    let similarity = calculateNameSimilarity(name1: name, name2: csvName)
                    if similarity > 0.7 { // Threshold for "similar enough"
                        foundFuzzyMatch = true
                        break
                    }
                }
            }
            
            if foundFuzzyMatch {
                continue
            }
            
            // Log more details about the whiskey being considered for deletion
            print("🔍 Considering whiskey for deletion: '\(name)' (ID: \(id))")
            
            // ADDITIONAL SAFETY: Check if this whiskey was modified recently
            // If it was modified since the last sync, don't delete it
            if let modDate = whiskey.modificationDate, let lastSync = self.lastSyncDate, modDate > lastSync {
                print("🔒 SAFETY: Skipping deletion for recently modified whiskey: '\(name)'")
                continue
            }
            
            // This whiskey is not in the CSV and should be deleted
            print("🗑️ Deleting whiskey not in CSV: '\(name)'")
            context.delete(whiskey)
            
            // Add to the deleted whiskeys tracking list
            deletedWhiskeyIDs.insert(id)
            deletedWhiskeyNames.insert(name)
            
            deletedCount += 1
        }
        
        // Save the updated deleted whiskeys list to UserDefaults
        if deletedCount > 0 {
            saveDeletedWhiskeysToUserDefaults()
            print("🗑️ Added \(deletedCount) whiskeys to deleted tracking")
        }
        
        return deletedCount
    }
    
    // Helper function to calculate similarity between whiskey names
    private func calculateNameSimilarity(name1: String, name2: String) -> Double {
        // Simple implementation - could be improved with more sophisticated algorithms
        let name1Words = Set(name1.split(separator: " ").map { String($0) })
        let name2Words = Set(name2.split(separator: " ").map { String($0) })
        
        // Calculate Jaccard similarity
        let intersection = name1Words.intersection(name2Words).count
        let union = name1Words.union(name2Words).count
        
        return union > 0 ? Double(intersection) / Double(union) : 0.0
    }
    
    // Add these helper functions to the CSVSyncService class:
    private func calculateTotalActiveBottles(_ whiskey: Whiskey) -> Int16 {
        // Start with the original bottles
        var totalActive = whiskey.numberOfBottles
        
        // If this entry is finished but has replacements, count those instead
        if whiskey.isFinished > 0 {
            if let replacement = whiskey.replacedBy {
                // Use the replacement's count instead
                totalActive = replacement.numberOfBottles
            } else {
                // No replacement, all bottles are finished
                totalActive = 0
            }
        }
        
        return totalActive
    }
    
    private func isCompletelyFinished(_ whiskey: Whiskey) -> Int16 {
        // Only return number of bottles if:
        // 1. All bottles are marked as finished AND
        // 2. No replacement exists AND
        // 3. Not marked for future replacement
        if whiskey.isFinished > 0 && // all bottles in this entry are finished
           whiskey.replacedBy == nil && // no replacement exists
           whiskey.replacementStatus != "wantToReplace" { // not marked for future replacement
            return whiskey.numberOfBottles
        }
        return 0
    }
    
    // Add a new method to completely reset sync state
    func resetSyncState() {
        print("🧹 COMPLETELY RESETTING sync state and deleted whiskey tracking")
        
        // Clear in-memory state
        deletedWhiskeyIDs.removeAll()
        deletedWhiskeyNames.removeAll()
        csvWhiskeyDict.removeAll()
        syncFileURL = nil
        lastSyncDate = nil
        
        // Clear UserDefaults
        userDefaults.removeObject(forKey: deletedWhiskeysKey)
        userDefaults.removeObject(forKey: deletedWhiskeyNamesKey)
        userDefaults.removeObject(forKey: syncFileURLKey)
        userDefaults.removeObject(forKey: syncFileBookmarkKey)
        userDefaults.removeObject(forKey: lastSyncDateKey)
        userDefaults.removeObject(forKey: "csvSyncFileName")
        userDefaults.synchronize()
        
        print("✅ Sync state and deleted whiskey tracking completely reset")
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let csvSyncStatusChanged = Notification.Name("csvSyncStatusChanged")
    static let csvSyncConflictDetected = Notification.Name("csvSyncConflictDetected")
    static let csvSyncFileNotFound = Notification.Name("csvSyncFileNotFound")
}

// MARK: - Helper Structures

struct WhiskeyRecord: CSVExportable {
    var name: String
    var type: String
    var proof: Double
    var age: String
    var distillery: String
    var finish: String
    var isBiB: Bool
    var isSiB: Bool
    var isStorePick: Bool
    var storePickName: String
    var numberOfBottles: Int16
    var isFinished: Int16
    var isOpen: Bool
    var notes: String
    var price: Double
    var isCaskStrength: Bool
    var isTasted: Bool
    var externalReviews: String
    var replacementStatus: String
    
    // Direct constructor for creating from a list of attributes
    init(name: String, type: String, proof: Double, age: String, distillery: String, 
         finish: String, isBiB: Bool, isSiB: Bool, isStorePick: Bool, storePickName: String,
         numberOfBottles: Int16, isFinished: Int16, isOpen: Bool, notes: String, price: Double, 
         isCaskStrength: Bool, isTasted: Bool, externalReviews: String = "", replacementStatus: String = "none") {
        self.name = name
        self.type = type
        self.proof = proof
        self.age = age
        self.distillery = distillery
        self.finish = finish
        self.isBiB = isBiB
        self.isSiB = isSiB
        self.isStorePick = isStorePick
        self.storePickName = storePickName
        self.numberOfBottles = numberOfBottles
        self.isFinished = isFinished
        self.isOpen = isOpen
        self.notes = notes
        self.price = price
        self.isCaskStrength = isCaskStrength
        self.isTasted = isTasted
        self.externalReviews = externalReviews
        self.replacementStatus = replacementStatus
    }
    
    init(fields: [String]) {
        // Helper function to safely access fields
        func safeField(_ index: Int) -> String {
            guard index < fields.count else { return "" }
            return fields[index]
        }
        
        self.name = safeField(0)
        self.type = safeField(1)
        
        // Parse proof
        let proofStr = safeField(2).replacingOccurrences(of: ",", with: ".")
        self.proof = Double(proofStr) ?? 0.0
        
        self.age = safeField(3)
        self.distillery = safeField(4)
        self.finish = safeField(5)
        
        // Boolean fields - assume field 6 is cask strength
        self.isCaskStrength = Self.parseBooleanField(safeField(6), initials: "")
        self.isBiB = Self.parseBooleanField(safeField(7), initials: "BiB")
        self.isSiB = Self.parseBooleanField(safeField(8), initials: "SiB")
        self.isStorePick = Self.parseBooleanField(safeField(9), initials: "SP")
        
        // Store pick name
        self.storePickName = safeField(10)
        
        // Number of bottles
        let bottlesStr = safeField(11).trimmingCharacters(in: .whitespacesAndNewlines)
        if !bottlesStr.isEmpty {
            self.numberOfBottles = Int16(bottlesStr) ?? 1
        } else {
            self.numberOfBottles = 1 // Default to 1 bottle
        }
        
        // Other boolean fields
        self.isFinished = CSVService.shared.parseNumericField(safeField(12))
        self.isOpen = Self.parseBooleanField(safeField(13), initials: "")
        
        // Notes
        self.notes = safeField(14)
        
        // Price
        let priceStr = safeField(15)
        if !priceStr.isEmpty {
            var cleanPrice = priceStr
                .replacingOccurrences(of: "$", with: "")
                .replacingOccurrences(of: "€", with: "")
                .replacingOccurrences(of: "£", with: "")
                .replacingOccurrences(of: " ", with: "")
                .replacingOccurrences(of: ",", with: ".")
            
            self.price = Double(cleanPrice) ?? 0.0
        } else {
            self.price = 0.0
        }
        
        // Tasted
        self.isTasted = Self.parseBooleanField(safeField(16), initials: "")
        
        // External Reviews - check if the field exists in the CSV
        if fields.count > 17 {
            self.externalReviews = safeField(17)
        } else {
            self.externalReviews = ""
        }
        
        // Replacement Status - check if the field exists in the CSV
        if fields.count > 18 {
            self.replacementStatus = safeField(18)
        } else {
            self.replacementStatus = "none"
        }
    }
    
    private static func parseBooleanField(_ value: String, initials: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmedValue == "yes" || 
               trimmedValue == "y" ||
               trimmedValue == "true" || 
               trimmedValue == "1" ||
               trimmedValue == "finished" ||
               (!initials.isEmpty && (trimmedValue == initials.lowercased() || trimmedValue == "bib" || trimmedValue == "sib" || trimmedValue == "sp"))
    }
}

struct SyncResult {
    var added: Int = 0
    var updated: Int = 0
    var conflicts: Int = 0
    var deleted: Int = 0
    
    var totalChanges: Int {
        return added + updated + conflicts + deleted
    }
}

