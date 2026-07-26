import Foundation
import StoreKit
import SwiftUI

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    // Published properties for UI updates
    @Published private var actualSubscriptionStatus: Bool = false
    @Published var currentSubscription: Product? = nil
    @Published var products: [Product] = []
    @Published var purchaseState: PurchaseState = .idle
    
    // Published property for isSubscribed that respects testing override
    @Published var isSubscribed: Bool = false
    
    // Published property for hasAccess that updates when bypass setting changes
    @Published var currentHasAccess: Bool = false
    
    // Update isSubscribed based on testing override and actual subscription status
    private func updateIsSubscribed() {
        let newValue = forceNonSubscribedForTesting ? false : actualSubscriptionStatus
        if isSubscribed != newValue {
            isSubscribed = newValue
        }
    }
    
    // Update hasAccess based on bypass setting and subscription status
    private func updateHasAccess() {
        let newValue: Bool
        if bypassFreemiumMode {
            newValue = true
            #if DEBUG
            #endif
        } else if forceNonSubscribedForTesting {
            newValue = false
            #if DEBUG
            #endif
        } else {
            newValue = actualSubscriptionStatus
            #if DEBUG
            #endif
        }
        
        if currentHasAccess != newValue {
            #if DEBUG
            #endif
            currentHasAccess = newValue
        } else {
            #if DEBUG
            #endif
        }
    }
    
    /// Product ID for the one-time premium purchase (non-consumable). Must match App Store Connect.
    private static let premiumOneTimeProductID = "com.ericlinder.barrelbookapp.premium.onetime"
    private var productID: String { Self.premiumOneTimeProductID }
    
    // Production mode - requires actual subscription product configured in App Store Connect
    // Set to false for TestFlight testing - we want real StoreKit behavior
    private let isDevelopmentMode = false
    
    // Testing override - set to true to force non-subscribed state for testing
    // This allows testing subscription flows even when you have an active subscription
    // IMPORTANT: Set to false before final App Store submission
    private let forceNonSubscribedForTesting = false
    
    // UserDefaults key for bypassing freemium mode
    private let bypassFreemiumKey = "bypassFreemiumMode"
    
    // Public accessor for bypass freemium mode (disabled in production)
    var bypassFreemiumMode: Bool {
        get { false } // Always false in production
        set { 
            // No-op in production
        }
    }
    
    // Free tier limits
    private let freeWhiskeyLimit = 5
    private let freeTastingLimit = 2
    
    // Purchase states
    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case purchased
        case failed(String)
        case deferred
    }
    
    /// Explicit result for Restore Purchases so UI can distinguish success / nothing / failure.
    enum RestoreResult: Equatable {
        case restored
        case nothingFound
        case failed(String)
    }
    
    private var updateListenerTask: Task<Void, Error>? = nil
    
    private init() {
        #if DEBUG
        #endif
        
        // Start listening for transaction updates
        updateListenerTask = listenForTransactions()
        
        // Set initial subscription state based on testing override
        updateIsSubscribed()
        updateHasAccess()
        
        // Load initial subscription status
        Task {
            #if DEBUG
            #endif
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Check if user has active subscription (including subscription trial)
    var hasAccess: Bool {
        return currentHasAccess
    }
    
    /// One-time purchase: no trial; kept for compatibility (always false).
    var isInTrialPeriod: Bool { false }
    
    /// Check if user can add more whiskeys (premium users have unlimited, free users have limit)
    func canAddWhiskey(currentCount: Int) -> Bool {
        if hasAccess {
            return true // Premium users have unlimited
        }
        return currentCount < freeWhiskeyLimit
    }
    
    /// Check if user can add more tasting notes (premium users have unlimited, free users have a total limit)
    func canAddTasting(currentCount: Int) -> Bool {
        if hasAccess {
            return true
        }
        return currentCount < freeTastingLimit
    }

    /// Get remaining whiskey slots for free users
    func remainingWhiskeySlots(currentCount: Int) -> Int {
        if hasAccess {
            return Int.max
        }
        return max(0, freeWhiskeyLimit - currentCount)
    }

    /// Get remaining tasting slots for free users
    func remainingTastingSlots(currentCount: Int) -> Int {
        if hasAccess {
            return Int.max
        }
        return max(0, freeTastingLimit - currentCount)
    }

    /// Get whiskey limit for free tier
    var whiskeyLimit: Int {
        return freeWhiskeyLimit
    }

    /// Get tasting limit for free tier
    var tastingLimit: Int {
        return freeTastingLimit
    }
    
    /// One-time purchase: no trial; kept for compatibility (always 0).
    var trialDaysRemaining: Int { 0 }
    
    /// Load available products
    func loadProducts() async {
        #if DEBUG
        #endif
        
        do {
            #if DEBUG
            #endif
            let products = try await Product.products(for: [productID])
            #if DEBUG
            for product in products {
            }
            #endif
            
            await MainActor.run {
                self.products = products
                if let product = products.first {
                    self.currentSubscription = product
                    self.purchaseState = .idle
                    #if DEBUG
                    #endif
                } else {
                    #if DEBUG
                    #endif
                    self.purchaseState = .failed("Premium product \"\(self.productID)\" was not found. It must exist in App Store Connect as a Non-Consumable In-App Purchase and match this ID exactly.")
                }
            }
        } catch {
            #if DEBUG
            #endif
            
            // Provide more helpful error messages for TestFlight users
            let errorMessage: String
            if isDevelopmentMode {
                errorMessage = "Premium product not available. Please ensure the Non-Consumable IAP is configured in App Store Connect and the app is properly signed."
            } else {
                if error.localizedDescription.contains("product") {
                    errorMessage = "Premium product not found. Please ensure the product ID '\(productID)' exists in App Store Connect as a Non-Consumable and matches exactly."
                } else if error.localizedDescription.contains("network") {
                    errorMessage = "Network error loading purchase details. Please check your internet connection and try again."
                } else {
                    errorMessage = "Failed to load purchase details: \(error.localizedDescription)"
                }
            }
            
            await MainActor.run {
                self.purchaseState = .failed(errorMessage)
            }
        }
    }
    
    /// Purchase subscription
    func purchaseSubscription() async {
        #if DEBUG
        print("💳 Starting purchase process...")
        #endif
        
        // Development mode simulation (only for simulator testing)
        if isDevelopmentMode && ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            #if DEBUG
            print("💳 Development mode: Simulating successful purchase for preview")
            #endif
            await MainActor.run {
                self.purchaseState = .purchasing
            }
            
            // Simulate network delay
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            
            await MainActor.run {
                self.actualSubscriptionStatus = true
                self.updateIsSubscribed()
                self.purchaseState = .purchased
            }
            #if DEBUG
            print("💳 Development mode: Purchase simulation completed")
            #endif
            return
        }
        
        guard let product = currentSubscription else {
            #if DEBUG
            print("💳 No product available for purchase")
            #endif
            await MainActor.run {
                self.purchaseState = .failed("Premium purchase is not available. Please ensure your app is properly configured in App Store Connect and try again.")
            }
            return
        }
        
        #if DEBUG
        print("💳 Attempting to purchase: \(product.displayName)")
        #endif
        
        await MainActor.run {
            self.purchaseState = .purchasing
        }
        
        do {
            let result = try await product.purchase()
            #if DEBUG
            print("💳 Purchase result received")
            #endif
            
            switch result {
            case .success(let verification):
                #if DEBUG
                print("💳 Purchase successful, verifying transaction...")
                #endif
                let transaction = try checkVerified(verification)
                await transaction.finish()
                
                await MainActor.run {
                    self.purchaseState = .purchased
                }
                
                await updateSubscriptionStatus()
                #if DEBUG
                print("💳 Purchase completed successfully")
                #endif
                
            case .userCancelled:
                #if DEBUG
                print("💳 Purchase cancelled by user")
                #endif
                await MainActor.run {
                    self.purchaseState = .idle
                }
                
            case .pending:
                #if DEBUG
                print("💳 Purchase pending")
                #endif
                await MainActor.run {
                    self.purchaseState = .deferred
                }
                
            @unknown default:
                #if DEBUG
                print("💳 Unknown purchase result")
                #endif
                await MainActor.run {
                    self.purchaseState = .failed("Unknown purchase result")
                }
            }
        } catch {
            #if DEBUG
            print("💳 Purchase failed with error: \(error)")
            #endif
            await MainActor.run {
                self.purchaseState = .failed(error.localizedDescription)
            }
        }
    }
    
    /// Restore purchases. Returns an explicit result for UI alerts (does not swallow AppStore.sync errors).
    @discardableResult
    func restorePurchases() async -> RestoreResult {
        await MainActor.run {
            self.purchaseState = .purchasing
        }
        
        do {
            try await AppStore.sync()
        } catch {
            let message = userFacingRestoreError(error)
            await MainActor.run {
                // Stay idle so purchase-error UI isn't triggered alongside restore-specific alerts
                self.purchaseState = .idle
            }
            return .failed(message)
        }
        
        await updateSubscriptionStatus()
        
        if hasAccess {
            await MainActor.run {
                self.purchaseState = .purchased
            }
            return .restored
        } else {
            await MainActor.run {
                self.purchaseState = .idle
            }
            return .nothingFound
        }
    }
    
    private func userFacingRestoreError(_ error: Error) -> String {
        let nsError = error as NSError
        // StoreKit / App Store sync cancelled by user
        if nsError.domain == "ASDErrorDomain", nsError.code == 509 {
            return "Restore was cancelled."
        }
        if nsError.localizedDescription.lowercased().contains("cancel") {
            return "Restore was cancelled."
        }
        if nsError.localizedDescription.lowercased().contains("network")
            || nsError.localizedDescription.lowercased().contains("internet") {
            return "Network error while restoring. Check your connection and try again."
        }
        return "Could not restore purchases: \(error.localizedDescription)"
    }
    
    /// Update entitlement status from StoreKit (one-time purchase: check for completed transaction).
    func updateSubscriptionStatus() async {
        #if DEBUG
        print("🔄 Checking premium purchase status...")
        #endif
        var hasPremium = false
        
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                #if DEBUG
                print("🔄 Found transaction: \(transaction.productID)")
                #endif
                if transaction.productID == productID {
                    #if DEBUG
                    print("🔄 Premium purchase found - access granted")
                    #endif
                    hasPremium = true
                    break
                }
            } catch {
                #if DEBUG
                print("Failed to verify transaction: \(error)")
                #endif
            }
        }
        
        #if DEBUG
        print("🔄 Has premium: \(hasPremium)")
        #endif
        
        await MainActor.run {
            self.actualSubscriptionStatus = hasPremium
            self.updateIsSubscribed()
            self.updateHasAccess()
        }
    }
    
    // MARK: - Private Methods
    
    /// Listen for transaction updates
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached { [weak self] in
            for await result in Transaction.updates {
                do {
                    let transaction = try checkVerified(result)
                    await transaction.finish()
                    await self?.updateSubscriptionStatus()
                } catch {
                    #if DEBUG
                    print("Transaction update failed: \(error)")
                    #endif
                }
            }
        }
    }
    

    
}

// Custom errors
enum StoreError: Error {
    case failedVerification
}

// MARK: - Global Helper Functions

/// Verify a transaction result
private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
    switch result {
    case .unverified:
        throw StoreError.failedVerification
    case .verified(let safe):
        return safe
    }
}

// MARK: - Product Extensions
extension Product {
    var priceFormatted: String {
        return displayPrice
    }
}

