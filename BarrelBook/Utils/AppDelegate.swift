import UIKit
import CoreData
import UserNotifications
import CloudKit

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // Request notification permissions
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                print("Notification permission granted")
                
                // Register for remote notifications once permission is granted
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
        
        // Setup for file access permissions
        setupFileAccessPermissions()
        
        // Setup CloudKit container
        setupCloudKitContainer()
        
        return true
    }
    
    // Setup CloudKit container and check account status
    private func setupCloudKitContainer() {
        let container = CKContainer(identifier: "iCloud.com.ericlinder.barrelbook")
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error checking iCloud account status: \(error)")
                    return
                }
                
                switch status {
                case .available:
                    print("iCloud account is available")
                    self?.requestApplicationPermission()
                    // Force a sync when iCloud becomes available
                    PersistenceController.shared.forceSync()
                case .noAccount:
                    print("No iCloud account found")
                case .restricted:
                    print("iCloud account is restricted")
                case .couldNotDetermine:
                    print("Could not determine iCloud account status")
                case .temporarilyUnavailable:
                    print("iCloud account is temporarily unavailable")
                    // Schedule a retry when iCloud becomes available
                    DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                        self?.setupCloudKitContainer()
                    }
                @unknown default:
                    print("Unknown iCloud account status")
                }
            }
        }
    }
    
    private func requestApplicationPermission() {
        let container = CKContainer(identifier: "iCloud.com.ericlinder.barrelbook")
        container.requestApplicationPermission(.userDiscoverability) { status, error in
            if let error = error {
                print("Error requesting application permission: \(error)")
                return
            }
            
            if status == .granted {
                print("Application permission granted")
            } else {
                print("Application permission not granted: \(status)")
            }
        }
    }
    
    // Setup file access permissions and cleanup temporary items
    private func setupFileAccessPermissions() {
        // Ensure our temp directory exists and is accessible
        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
        
        do {
            // Create or clear temporary directory for file operations
            if !fileManager.fileExists(atPath: tempDirectory.path) {
                try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            } else {
                // Cleanup any old temporary files that may cause issues
                let tempContents = try fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
                for fileURL in tempContents {
                    if fileURL.lastPathComponent.contains("barrelbook-temp") {
                        try? fileManager.removeItem(at: fileURL)
                    }
                }
            }
            
            // Set app container directory permissions
            let containerURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: containerURL.path)
            
            print("File access permissions setup completed")
        } catch {
            print("Error setting up file access permissions: \(error)")
        }
    }
    
    // MARK: - Remote Notifications
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("Registered for remote notifications with token: \(deviceToken)")
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // Handle CloudKit remote notifications
        if let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            print("Received CloudKit notification: \(notification)")
            
            // Refresh Core Data context
            PersistenceController.shared.container.viewContext.refreshAllObjects()
            
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }
    
    // MARK: - Notification handling
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show notification while app is in foreground
        completionHandler([.banner, .sound])
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        // Handle notification response
        completionHandler()
    }
} 