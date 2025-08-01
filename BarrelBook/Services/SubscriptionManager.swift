import Foundation
import StoreKit
import SwiftUI

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    // Published properties for UI updates
    @Published private var actualSubscriptionStatus: Bool = false
    @Published var isTrialActive: Bool = false
    @Published var subscriptionStatus: Product.SubscriptionInfo.Status? = nil
    @Published var currentSubscription: Product? = nil
    @Published var products: [Product] = []
    @Published var purchaseState: PurchaseState = .idle
    
    // Published property for isSubscribed that respects testing override
    @Published var isSubscribed: Bool = false
    
    // Update isSubscribed based on testing override and actual subscription status
    private func updateIsSubscribed() {
        let newValue = forceNonSubscribedForTesting ? false : actualSubscriptionStatus
        if isSubscribed != newValue {
            isSubscribed = newValue
        }
    }
    
    // Product ID for the annual subscription
    private let productID = "com.ericlinder.barrelbook.annual"
    
    // Development mode flag - set to true during development, false for production
    // When true: simulates purchases without requiring App Store Connect setup
    // When false: requires actual subscription product configured in App Store Connect
    private let isDevelopmentMode = false
    
    // Testing override - set to true to force non-subscribed state for testing
    // This allows testing subscription flows even when you have an active subscription
    // IMPORTANT: Set to false before final App Store submission
    private let forceNonSubscribedForTesting = true
    
    // Public accessor for development mode
    var isInDevelopmentMode: Bool {
        return isDevelopmentMode
    }
    
    // Trial period in days
    private let trialPeriodDays = 7
    
    // Purchase states
    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case purchased
        case failed(String)
        case deferred
    }
    
    private var updateListenerTask: Task<Void, Error>? = nil
    
    private init() {
        // Start listening for transaction updates
        updateListenerTask = listenForTransactions()
        
        // Set initial subscription state based on testing override
        updateIsSubscribed()
        
        // Load initial subscription status
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Check if user has active subscription or trial
    var hasAccess: Bool {
        // Testing override to force non-subscribed state
        if forceNonSubscribedForTesting {
            return false
        }
        return actualSubscriptionStatus || isTrialActive
    }
    
    /// Check if user is currently in trial period
    var isInTrialPeriod: Bool {
        return isTrialActive && !isSubscribed
    }
    
    /// Get trial days remaining
    var trialDaysRemaining: Int {
        guard isTrialActive, !isSubscribed else { return 0 }
        
        let installDate = getAppInstallDate()
        let daysSinceInstall = Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
        return max(0, trialPeriodDays - daysSinceInstall)
    }
    
    /// Load available products
    func loadProducts() async {
        print("🛒 Loading products for ID: \(productID)")
        print("🛒 Development mode: \(isDevelopmentMode)")
        
        // Development mode simulation
        if isDevelopmentMode {
            print("🛒 Development mode: Simulating product loading")
            await MainActor.run {
                // Simulate that we've "loaded" but products are empty (normal for dev mode)
                self.products = []
                self.currentSubscription = nil
                print("🛒 Development mode: Product simulation completed")
            }
            return
        }
        
        do {
            print("🛒 Attempting to load products from StoreKit...")
            let products = try await Product.products(for: [productID])
            print("🛒 Loaded \(products.count) products")
            
            for product in products {
                print("🛒 Found product: \(product.id) - \(product.displayName) - \(product.displayPrice)")
            }
            
            await MainActor.run {
                self.products = products
                if let product = products.first {
                    self.currentSubscription = product
                    print("🛒 Set current subscription: \(product.displayName) - \(product.displayPrice)")
                } else {
                    print("🛒 No products found for ID: \(productID)")
                    print("🛒 Available product IDs: \(products.map { $0.id })")
                }
            }
        } catch {
            print("🛒 Failed to load products: \(error)")
            print("🛒 Error details: \(error.localizedDescription)")
            await MainActor.run {
                self.purchaseState = .failed("Failed to load subscription details: \(error.localizedDescription)")
            }
        }
    }
    
    /// Purchase subscription
    func purchaseSubscription() async {
        print("💳 Starting purchase process...")
        
        // Development mode simulation
        if isDevelopmentMode {
            print("💳 Development mode: Simulating successful purchase")
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
            print("💳 Development mode: Purchase simulation completed")
            return
        }
        
        guard let product = currentSubscription else {
            print("💳 No product available for purchase")
            await MainActor.run {
                self.purchaseState = .failed("Product not available")
            }
            return
        }
        
        print("💳 Attempting to purchase: \(product.displayName)")
        
        await MainActor.run {
            self.purchaseState = .purchasing
        }
        
        do {
            let result = try await product.purchase()
            print("💳 Purchase result received")
            
            switch result {
            case .success(let verification):
                print("💳 Purchase successful, verifying transaction...")
                let transaction = try checkVerified(verification)
                await transaction.finish()
                
                await MainActor.run {
                    self.purchaseState = .purchased
                }
                
                await updateSubscriptionStatus()
                print("💳 Purchase completed successfully")
                
            case .userCancelled:
                print("💳 Purchase cancelled by user")
                await MainActor.run {
                    self.purchaseState = .idle
                }
                
            case .pending:
                print("💳 Purchase pending")
                await MainActor.run {
                    self.purchaseState = .deferred
                }
                
            @unknown default:
                print("💳 Unknown purchase result")
                await MainActor.run {
                    self.purchaseState = .failed("Unknown purchase result")
                }
            }
        } catch {
            print("💳 Purchase failed with error: \(error)")
            await MainActor.run {
                self.purchaseState = .failed(error.localizedDescription)
            }
        }
    }
    
    /// Restore purchases
    func restorePurchases() async {
        await MainActor.run {
            self.purchaseState = .purchasing
        }
        
        try? await AppStore.sync()
        await updateSubscriptionStatus()
        
        await MainActor.run {
            self.purchaseState = .idle
        }
    }
    
    /// Update subscription status from StoreKit
    func updateSubscriptionStatus() async {
        var isActiveSubscription = false
        var currentStatus: Product.SubscriptionInfo.Status? = nil
        
        // Check for active subscriptions
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                
                if transaction.productID == productID {
                    // We have a transaction for our subscription
                    if let subscription = currentSubscription,
                       let subscriptionInfo = subscription.subscription {
                        
                        // Get subscription status
                        let statuses = try await subscriptionInfo.status
                        for status in statuses {
                            switch status.state {
                            case .subscribed, .inGracePeriod:
                                isActiveSubscription = true
                                currentStatus = status
                            case .inBillingRetryPeriod:
                                // Still consider as subscribed during retry
                                isActiveSubscription = true
                                currentStatus = status
                            default:
                                break
                            }
                        }
                    }
                }
            } catch {
                print("Failed to verify transaction: \(error)")
            }
        }
        
        // Update trial status
        let trialActive = isTrialPeriodActive()
        
        await MainActor.run {
            self.actualSubscriptionStatus = isActiveSubscription
            self.updateIsSubscribed()
            self.subscriptionStatus = currentStatus
            self.isTrialActive = trialActive
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
                    print("Transaction update failed: \(error)")
                }
            }
        }
    }
    

    
    /// Check if trial period is still active
    private func isTrialPeriodActive() -> Bool {
        let installDate = getAppInstallDate()
        let daysSinceInstall = Calendar.current.dateComponents([.day], from: installDate, to: Date()).day ?? 0
        return daysSinceInstall < trialPeriodDays
    }
    
    /// Get app install date (or first launch date)
    private func getAppInstallDate() -> Date {
        let key = "AppFirstLaunchDate"
        
        if let firstLaunchDate = UserDefaults.standard.object(forKey: key) as? Date {
            return firstLaunchDate
        } else {
            // First time launching, save current date
            let now = Date()
            UserDefaults.standard.set(now, forKey: key)
            return now
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
    
    var yearlyPriceDescription: String {
        return "\(displayPrice)/year"
    }
}