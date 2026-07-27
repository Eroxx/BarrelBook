import SwiftUI
import CoreData
import BackgroundTasks

@main
struct BarrelBookApp: App {
    // Add AppDelegate to handle system events
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Read the stored preference here so .preferredColorScheme is applied
    // at the very top of the view hierarchy — before any tab's NavigationView
    // is initialised — which fixes dark-mode not applying on first Statistics load.
    @AppStorage("colorScheme") private var storedColorScheme: AppColorScheme = .system

    private var preferredScheme: ColorScheme? {
        switch storedColorScheme {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }

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
                .accentColor(ColorManager.primaryBrandColor)
                .preferredColorScheme(preferredScheme)
                .onAppear {
                    applyUIKitColorScheme()
                    setupAddedDateForExistingWhiskeys()
                }
        }
    }

    /// Belt-and-suspenders: also set UIKit's window style so that
    /// UINavigationController bars (NavigationView) respect the preference.
    private func applyUIKitColorScheme() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        switch storedColorScheme {
        case .light:  window.overrideUserInterfaceStyle = .light
        case .dark:   window.overrideUserInterfaceStyle = .dark
        case .system: window.overrideUserInterfaceStyle = .unspecified
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
    /// Persisted as binary Data via NSKeyedArchiver — never as a UTF-8 String.
    private var lastHistoryToken: NSPersistentHistoryToken?
    private let historyTokenDefaultsKey = "BarrelBook.persistentHistoryToken"
    private let legacyHistoryTokenDefaultsKey = "lastProcessedToken"
    private let historyTokenQueue = DispatchQueue(label: "com.ericlinder.barrelbook.historyToken")
    
    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "BarrelBook")
        
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        
        // Configure persistent store options
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed to retrieve a persistent store description.")
        }
        
        // Enable CloudKit sync
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: "iCloud.com.ericlinder.barrelbookapp")
        // Lightweight migration for model version bumps (e.g. secondaryMarketValue)
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        
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
        loadHistoryToken()
        setupCloudKitSync()
    }
    
    /// Load history token from UserDefaults (Data). Clears invalid legacy string values.
    private func loadHistoryToken() {
        // Migration: discard old string-based tokens that could never round-trip binary archives
        if UserDefaults.standard.object(forKey: legacyHistoryTokenDefaultsKey) != nil {
            UserDefaults.standard.removeObject(forKey: legacyHistoryTokenDefaultsKey)
        }
        if UserDefaults.standard.object(forKey: historyTokenDefaultsKey) is String {
            UserDefaults.standard.removeObject(forKey: historyTokenDefaultsKey)
        }
        
        guard let data = UserDefaults.standard.data(forKey: historyTokenDefaultsKey) else { return }
        do {
            lastHistoryToken = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: NSPersistentHistoryToken.self,
                from: data
            )
        } catch {
            print("⚠️ Failed to decode history token, clearing: \(error)")
            UserDefaults.standard.removeObject(forKey: historyTokenDefaultsKey)
            lastHistoryToken = nil
        }
    }
    
    private func saveHistoryToken(_ token: NSPersistentHistoryToken) {
        historyTokenQueue.sync {
            lastHistoryToken = token
            do {
                let data = try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
                UserDefaults.standard.set(data, forKey: historyTokenDefaultsKey)
            } catch {
                print("⚠️ Failed to archive history token: \(error)")
            }
        }
    }
    
    private func currentHistoryToken() -> NSPersistentHistoryToken? {
        historyTokenQueue.sync { lastHistoryToken }
    }
    
    private func setupCloudKitSync() {
        // Remote store changes: process persistent history (token stored as Data, not UTF-8 String)
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] _ in
            self?.processPersistentHistory()
        }
        
        // Periodic fallback sync check
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkAndRetrySync()
        }
    }
    
    /// Fetch and apply persistent history since the last stored token, then refresh the UI context.
    private func processPersistentHistory() {
        let backgroundContext = container.newBackgroundContext()
        backgroundContext.perform { [weak self] in
            guard let self = self else { return }
            
            let token = self.currentHistoryToken()
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
            
            do {
                guard let result = try backgroundContext.execute(request) as? NSPersistentHistoryResult,
                      let transactions = result.result as? [NSPersistentHistoryTransaction] else {
                    DispatchQueue.main.async {
                        self.finishSyncRefresh()
                    }
                    return
                }
                
                if let newToken = transactions.last?.token {
                    self.saveHistoryToken(newToken)
                }
                
                DispatchQueue.main.async {
                    if !transactions.isEmpty {
                        print("📱 Processed \(transactions.count) CloudKit history transaction(s)")
                    }
                    self.finishSyncRefresh()
                }
            } catch {
                print("❌ Error processing persistent history: \(error)")
                DispatchQueue.main.async {
                    // Still refresh so auto-merged changes appear in the UI
                    self.finishSyncRefresh()
                }
            }
        }
    }
    
    private func finishSyncRefresh() {
        container.viewContext.refreshAllObjects()
        isSyncing = false
        lastSyncAttempt = Date()
    }
    
    private func checkAndRetrySync() {
        // Skip if we're already syncing
        guard !isSyncing else { return }
        
        // Check if we need to retry
        if let lastAttempt = lastSyncAttempt {
            let timeSinceLastAttempt = Date().timeIntervalSince(lastAttempt)
            guard timeSinceLastAttempt > maxSyncRetryInterval else { return }
        }
        
        isSyncing = true
        print("🔄 Attempting to sync with CloudKit...")
        
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        // Save any pending local changes so they can upload
        if container.viewContext.hasChanges {
            do {
                try container.viewContext.save()
                print("✅ Saved pending changes during sync attempt")
            } catch {
                print("❌ Error saving changes during sync attempt: \(error)")
            }
        }
        
        processPersistentHistory()
    }
    
    func forceSync() {
        isSyncing = true
        lastSyncAttempt = Date()
        container.viewContext.automaticallyMergesChangesFromParent = true
        
        // Push local changes first, then pull/process remote history
        if container.viewContext.hasChanges {
            do {
                try container.viewContext.save()
                print("✅ Saved pending changes before force sync")
            } catch {
                print("❌ Error saving before force sync: \(error)")
            }
        }
        
        processPersistentHistory()
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
