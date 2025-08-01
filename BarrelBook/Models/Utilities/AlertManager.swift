import Foundation
import SwiftUI

// Singleton manager for handling app-wide alerts
class AlertManager: ObservableObject {
    static let shared = AlertManager()
    
    // Published properties that views can observe
    @Published var showingBuyNewBottleAlert = false
    @Published var currentWhiskeyID: UUID? = nil
    
    // Flag to track if a sheet is being presented
    @Published var isSheetPresented = false
    
    private init() {} // Private initializer for singleton
    
    // Show the buy new bottle alert for a specific whiskey
    func showBuyNewBottleAlert(for whiskeyID: UUID?) {
        guard let id = whiskeyID else { return }
        
        // Don't show the alert if one is already showing or a sheet is presented
        if showingBuyNewBottleAlert || isSheetPresented {
            print("DEBUG: AlertManager skipping alert - already showing alert or sheet is presented")
            // Still store in UserDefaults for future display
            UserDefaults.standard.set(true, forKey: "showBuyAlert_\(id)")
            return
        }
        
        print("DEBUG: AlertManager showing buy alert for whiskey ID: \(id)")
        
        // Set this on the main thread to ensure UI updates properly
        DispatchQueue.main.async {
            self.currentWhiskeyID = id
            self.showingBuyNewBottleAlert = true
            
            // Store in UserDefaults for persistence
            UserDefaults.standard.set(true, forKey: "showBuyAlert_\(id)")
        }
    }
    
    // Dismiss the buy new bottle alert
    func dismissBuyNewBottleAlert() {
        guard let id = currentWhiskeyID else { return }
        
        print("DEBUG: AlertManager dismissing buy alert for whiskey ID: \(id)")
        
        DispatchQueue.main.async {
            self.showingBuyNewBottleAlert = false
            
            // Remove from UserDefaults
            UserDefaults.standard.removeObject(forKey: "showBuyAlert_\(id)")
            self.currentWhiskeyID = nil
        }
    }
    
    // Check if the alert should be shown for a whiskey
    func shouldShowBuyNewBottleAlert(for whiskeyID: UUID?) -> Bool {
        guard let id = whiskeyID else { return false }
        
        // Don't show if a sheet is presented
        if isSheetPresented {
            return false
        }
        
        // Check if this whiskey matches the current one and the alert is active
        if showingBuyNewBottleAlert && currentWhiskeyID == id {
            return true
        }
        
        // Check if there's a persisted alert
        return UserDefaults.standard.bool(forKey: "showBuyAlert_\(id)")
    }
} 