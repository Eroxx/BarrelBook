import SwiftUI
import CoreData
import BackgroundTasks

@main
struct BarrelBookApp: App {
    // Add AppDelegate to handle system events
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    let persistenceController = PersistenceController.shared
    
    init() {
        // Reset sync state first
        CSVSyncService.shared.resetSyncState()
        
        // Restore CSV sync settings when app launches
        DispatchQueue.main.async {
            CSVSyncService.shared.restoreSyncSettingsOnAppLaunch()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            DeviceAdaptiveContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    // Set up addedDate for existing whiskeys first
                    setupAddedDateForExistingWhiskeys()
                }
        }
    }
    
    private func setupAddedDateForExistingWhiskeys() {
        let context = persistenceController.container.viewContext
        let fetchRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
        
        do {
            let whiskeys = try context.fetch(fetchRequest)
            let today = Calendar.current.startOfDay(for: Date())
            
            for whiskey in whiskeys {
                if whiskey.addedDate == nil {
                    whiskey.addedDate = today
                }
            }
            
            try context.save()
        } catch {
            print("Error setting up addedDate for existing whiskeys: \(error)")
        }
    }
}

// MARK: - Persistence Controller
class PersistenceController {
    static let shared = PersistenceController()
    
    // Add sync status tracking
    private var isSyncing = false
    private var lastSyncAttempt: Date?
    private let maxSyncRetryInterval: TimeInterval = 30 // 30 seconds between retries
    
    // Add preview instance for SwiftUI previews
    static var preview: PersistenceController = {
        let result = PersistenceController(inMemory: true)
        let viewContext = result.container.viewContext
        
        // Add some sample data for previews
        let sampleWhiskey = Whiskey(context: viewContext)
        sampleWhiskey.name = "Sample Bourbon"
        sampleWhiskey.type = "Bourbon"
        sampleWhiskey.proof = 100.0
        sampleWhiskey.price = 50.0
        sampleWhiskey.status = "owned"
        sampleWhiskey.id = UUID()
        sampleWhiskey.modificationDate = Date()
        sampleWhiskey.addedDate = Date()
        
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
        
        return result
    }()
    
    let container: NSPersistentCloudKitContainer
    private var lastProcessedToken: String?
    
    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "BarrelBook")
        
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        
        // Configure persistent store options
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve a persistent store description.")
        }
        
        // Enable CloudKit sync
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.ericlinder.barrelbook")
        
        // Load the persistent stores
        container.loadPersistentStores { description, error in
            if let error = error {
                print("Core Data failed to load: \(error.localizedDescription)")
            }
        }
        
        // Configure automatic merging of changes
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        // Set up CloudKit sync callbacks
        container.viewContext.transactionAuthor = "app"
        setupCloudKitSync()
    }
    
    private func setupCloudKitSync() {
        // Enable remote notifications for CloudKit changes
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let historyToken = userInfo["historyToken"] as? NSPersistentHistoryToken,
                  let tokenData = try? NSKeyedArchiver.archivedData(withRootObject: historyToken, requiringSecureCoding: true),
                  let tokenString = String(data: tokenData, encoding: .utf8)
            else {
                return
            }
            
            // Skip if we've already processed this token
            if tokenString == self.lastProcessedToken {
                return
            }
            
            self.lastProcessedToken = tokenString
            print("📱 Processing CloudKit changes")
            
            // Refresh the view context
            self.container.viewContext.refreshAllObjects()
            
            // Mark sync as successful
            self.isSyncing = false
            self.lastSyncAttempt = Date()
        }
        
        // Add periodic sync check
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkAndRetrySync()
        }
    }
    
    private func checkAndRetrySync() {
        // Skip if we're already syncing
        guard !isSyncing else { return }
        
        // Check if we need to retry
        if let lastAttempt = lastSyncAttempt {
            let timeSinceLastAttempt = Date().timeIntervalSince(lastAttempt)
            guard timeSinceLastAttempt > maxSyncRetryInterval else { return }
        }
        
        // Attempt to sync
        isSyncing = true
        print("🔄 Attempting to sync with CloudKit...")
        
        // Force a refresh of all objects
        container.viewContext.refreshAllObjects()
        
        // Ensure sync is enabled
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        // Save any pending changes
        if container.viewContext.hasChanges {
            do {
                try container.viewContext.save()
                print("✅ Saved pending changes during sync attempt")
            } catch {
                print("❌ Error saving changes during sync attempt: \(error)")
            }
        }
    }
    
    func forceSync() {
        isSyncing = true
        lastSyncAttempt = Date()
        checkAndRetrySync()
    }
    
    func save() {
        let context = container.viewContext
        
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("Error saving context: \(error)")
            }
        }
    }
    
    func forceSave() {
        save()
    }
    
    // Add a method to reset Core Data objects
    func resetAllObjects() {
        let context = container.viewContext
        
        // Cancel any existing changes
        context.rollback()
        
        // Reset the context to ensure clean state
        container.viewContext.reset()
        
        // Log the reset operation
        print("Reset all Core Data objects and context")
        
        // Notify observers that data has been reset
        NotificationCenter.default.post(name: NSNotification.Name("DataReset"), object: nil)
    }
}
