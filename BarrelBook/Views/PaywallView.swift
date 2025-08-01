import SwiftUI
import StoreKit

struct PaywallView: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool
    
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingTerms = false
    @State private var showingPrivacy = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Features
                    featuresSection
                    
                    // Subscription offer
                    subscriptionSection
                    
                    // Purchase buttons
                    purchaseSection
                    
                    // Legal text
                    legalSection
                }
                .padding()
            }
            .navigationTitle("BarrelBook Subscription")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onChange(of: subscriptionManager.purchaseState) { state in
            switch state {
            case .purchased:
                // Dismiss paywall on successful purchase
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    isPresented = false
                }
            case .failed(let error):
                errorMessage = error
                showingError = true
            default:
                break
            }
        }
        .task {
            await subscriptionManager.loadProducts()
        }
        .sheet(isPresented: $showingTerms) {
            TermsOfServiceView()
        }
        .sheet(isPresented: $showingPrivacy) {
            PrivacyPolicyView()
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "crown.fill")
                .font(.system(size: 64))
                .foregroundColor(.yellow)
            
            Text("Unlock Your Complete")
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            Text("Whiskey Collection Experience")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(ColorManager.primaryBrandColor)
                .multilineTextAlignment(.center)
            
            Text("Start your 7-day free trial today")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Premium Features")
                .font(.title2)
                .fontWeight(.bold)
            
            FeatureRow(
                icon: "square.grid.2x2.fill",
                title: "Unlimited Collection",
                description: "Add unlimited whiskeys to your collection"
            )
            
            FeatureRow(
                icon: "book.fill",
                title: "Unlimited Tastings",
                description: "Record unlimited tasting notes and journal entries"
            )
            
            FeatureRow(
                icon: "heart.fill",
                title: "Unlimited Wishlist",
                description: "Save unlimited whiskeys to your wishlist"
            )
            
            FeatureRow(
                icon: "chart.bar.fill",
                title: "Advanced Analytics",
                description: "Access detailed statistics and insights"
            )
            
            FeatureRow(
                icon: "square.and.arrow.up.fill",
                title: "Export & Backup",
                description: "Export your collection data and create backups"
            )
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var subscriptionSection: some View {
        VStack(spacing: 12) {
            Text("Annual Subscription")
                .font(.title2)
                .fontWeight(.bold)
            
            if let product = subscriptionManager.currentSubscription {
                VStack(spacing: 8) {
                    Text(product.priceFormatted)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(ColorManager.primaryBrandColor)
                    
                    Text("per year")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
            } else if case .failed(_) = subscriptionManager.purchaseState {
                VStack(spacing: 8) {
                    Text("$7.99")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(ColorManager.primaryBrandColor)
                    
                    Text("per year")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
            } else {
                // Show fallback pricing immediately in development mode, or while loading
                VStack(spacing: 8) {
                    Text("$7.99")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(ColorManager.primaryBrandColor)
                    
                    Text("per year")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ColorManager.primaryBrandColor, lineWidth: 2)
        )
    }
    
    private var purchaseSection: some View {
        VStack(spacing: 12) {
            // Start Trial Button
            Button(action: startTrial) {
                HStack {
                    if subscriptionManager.purchaseState == .purchasing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .foregroundColor(.white)
                    }
                    
                    Text(subscriptionManager.isInDevelopmentMode ? "Start 7-Day Free Trial (Demo)" : "Start 7-Day Free Trial")
                        .font(.headline)
                        .fontWeight(.bold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(ColorManager.primaryBrandColor)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(subscriptionManager.purchaseState == .purchasing)
            
            // Restore Purchases Button
            Button(action: restorePurchases) {
                Text("Restore Purchases")
                    .font(.subheadline)
                    .foregroundColor(ColorManager.primaryBrandColor)
            }
            .disabled(subscriptionManager.purchaseState == .purchasing)
        }
    }
    
    private var legalSection: some View {
        VStack(spacing: 8) {
            Text("• Free trial for 7 days, then \(subscriptionManager.currentSubscription?.priceFormatted ?? "$7.99") per year")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text("• Payment will be charged to your Apple ID account at confirmation of purchase")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text("• Subscription automatically renews unless cancelled at least 24 hours before the end of the current period")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Text("• You can cancel anytime in your Apple ID settings")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 20) {
                Button("Terms of Service") {
                    showingTerms = true
                }
                .font(.caption)
                .foregroundColor(.blue)
                
                Button("Privacy Policy") {
                    showingPrivacy = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            .padding(.top)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Actions
    
    private func startTrial() {
        Task {
            // In development mode, proceed directly to purchase
            if subscriptionManager.isInDevelopmentMode {
                await subscriptionManager.purchaseSubscription()
                return
            }
            
            // If no product is loaded, try to load it first
            if subscriptionManager.currentSubscription == nil {
                await subscriptionManager.loadProducts()
            }
            
            // If still no product, show an error
            if subscriptionManager.currentSubscription == nil {
                await MainActor.run {
                    errorMessage = "Unable to load subscription details. Please check your internet connection and try again."
                    showingError = true
                }
                return
            }
            
            await subscriptionManager.purchaseSubscription()
        }
    }
    
    private func restorePurchases() {
        Task {
            await subscriptionManager.restorePurchases()
        }
    }
    
    // MARK: - Helper Methods
    
    private func monthlyPrice(from yearlyPrice: String) -> String {
        // Extract numeric value from price string and calculate monthly equivalent
        let numericString = yearlyPrice.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        if let yearly = Double(numericString) {
            let monthly = yearly / 12.0
            return String(format: "$%.2f", monthly)
        }
        return "$0.67" // Fallback for $7.99/year
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(ColorManager.primaryBrandColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Terms and Privacy Views

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Terms of Service")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.bottom)
                    
                    Group {
                        Text("1. Acceptance of Terms")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("By subscribing to BarrelBook Premium, you agree to be bound by these Terms of Service. These terms apply to your use of the BarrelBook application and all related services.")
                        
                        Text("2. Subscription Service")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("BarrelBook Premium is a subscription service that provides unlimited access to all features of the BarrelBook application, including unlimited whiskey collection management, tasting notes, wishlist management, and advanced analytics.")
                        
                        Text("3. Free Trial")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("New subscribers are eligible for a 7-day free trial. During the trial period, you have full access to all Premium features. The trial will automatically convert to a paid subscription unless cancelled before the trial period ends.")
                        
                        Text("4. Payment and Billing")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("Subscription fees are charged annually to your Apple ID account. Payment will be charged at confirmation of purchase. Subscriptions automatically renew unless auto-renew is turned off at least 24 hours before the end of the current period.")
                        
                        Text("5. Cancellation")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("You may cancel your subscription at any time through your Apple ID account settings. Cancellation will take effect at the end of the current billing period.")
                        
                        Text("6. Changes to Terms")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("We reserve the right to modify these terms at any time. Continued use of the service constitutes acceptance of any changes.")
                    }
                    .font(.body)
                }
                .padding()
            }
            .navigationTitle("Terms of Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Privacy Policy")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.bottom)
                    
                    Group {
                        Text("1. Information We Collect")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("BarrelBook stores your whiskey collection data, tasting notes, and app preferences locally on your device.")
                        
                        Text("2. How We Use Your Information")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("Your data is used solely to provide the BarrelBook service functionality and analytics about your whiskey collection.")
                        
                        Text("3. Data Security")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("Your data is encrypted and stored securely on your device. We do not have access to your personal whiskey collection data.")
                        
                        Text("4. Third Party Services")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("BarrelBook uses Apple's App Store for subscription management. These services are governed by Apple's privacy policy.")
                        
                        Text("5. Data Deletion")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("You can delete your data at any time by deleting the app from your device.")
                        
                        Text("6. Contact Us")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("If you have questions about this privacy policy, please contact us through the app's support section.")
                        
                        Text("Last updated: \(formattedDate)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top)
                    }
                    .font(.body)
                }
                .padding()
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: Date())
    }
}

#Preview {
    PaywallView(isPresented: .constant(true))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}