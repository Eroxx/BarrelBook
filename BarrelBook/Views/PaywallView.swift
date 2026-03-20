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
                VStack(spacing: 28) {
                    headerSection
                    featuresSection
                    subscriptionSection
                    purchaseSection
                    legalSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle("Premium")
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
        VStack(spacing: 20) {
            Image(systemName: "crown.fill")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.yellow, Color.orange.opacity(0.9)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
            
            VStack(spacing: 8) {
                Text("Unlock Your Complete")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("Whiskey Experience")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(ColorManager.primaryBrandColor)
            }
            .multilineTextAlignment(.center)
            
            Text("One-time purchase · \(subscriptionManager.currentSubscription?.priceFormatted ?? "$7.99") · Unlock forever")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
    
    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Everything you need to track and enjoy your collection")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            
            VStack(spacing: 0) {
                FeatureRow(
                    icon: "square.grid.2x2.fill",
                    title: "Unlimited Collection",
                    description: "Add as many bottles as you own"
                )
                .padding(.vertical, 6)
                
                Divider()
                    .padding(.leading, 44)
                
                FeatureRow(
                    icon: "book.fill",
                    title: "Unlimited Tastings",
                    description: "Journal every pour with notes and ratings"
                )
                .padding(.vertical, 6)
                
                Divider()
                    .padding(.leading, 44)
                
                FeatureRow(
                    icon: "heart.fill",
                    title: "Unlimited Wishlist",
                    description: "Build and manage your dream list"
                )
                .padding(.vertical, 6)
                
                Divider()
                    .padding(.leading, 44)
                
                FeatureRow(
                    icon: "chart.bar.fill",
                    title: "Advanced Analytics",
                    description: "Proof, price, and composition insights"
                )
                .padding(.vertical, 6)
                
                Divider()
                    .padding(.leading, 44)
                
                FeatureRow(
                    icon: "square.and.arrow.up.fill",
                    title: "Export & Backup",
                    description: "Full collection export, CSV import, and backup"
                )
                .padding(.vertical, 6)
            }
            .padding(20)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(16)
        }
    }
    
    private var subscriptionSection: some View {
        VStack(spacing: 8) {
            if let product = subscriptionManager.currentSubscription {
                Text(product.priceFormatted)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(ColorManager.primaryBrandColor)
            } else {
                Text("$7.99")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundColor(ColorManager.primaryBrandColor)
            }
            Text("one-time · unlock forever")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private var purchaseSection: some View {
        VStack(spacing: 16) {
            Button(action: startTrial) {
                HStack(spacing: 8) {
                    if subscriptionManager.purchaseState == .purchasing {
                        ProgressView()
                            .scaleEffect(0.9)
                            .tint(.white)
                    }
                    Text(subscriptionManager.purchaseState == .purchasing ? "Purchasing…" : "Unlock for \(subscriptionManager.currentSubscription?.priceFormatted ?? "$7.99")")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(ColorManager.primaryBrandColor)
                .foregroundColor(.white)
                .cornerRadius(14)
            }
            .disabled(subscriptionManager.purchaseState == .purchasing)
            .buttonStyle(.plain)
            
            Button(action: restorePurchases) {
                Text("Restore Purchases")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(ColorManager.primaryBrandColor)
            }
            .disabled(subscriptionManager.purchaseState == .purchasing)
        }
    }
    
    private var legalSection: some View {
        VStack(spacing: 16) {
            Text("Payment is charged once to your Apple ID. No subscription — you own premium forever. Restore on a new device via Restore Purchases.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 24) {
                Button("Terms of Service") { showingTerms = true }
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
                Button("Privacy Policy") { showingPrivacy = true }
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Actions
    
    private func startTrial() {
        Task {
            if subscriptionManager.currentSubscription == nil {
                await subscriptionManager.loadProducts()
            }
            if subscriptionManager.currentSubscription == nil {
                await MainActor.run {
                    if case .failed(let message) = subscriptionManager.purchaseState {
                        errorMessage = message
                    } else {
                        errorMessage = "Premium purchase is not available. Please ensure the Non-Consumable in-app purchase is set up in App Store Connect and try again."
                    }
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
            if subscriptionManager.hasAccess {
                isPresented = false
            }
        }
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
                        Text("By purchasing BarrelBook Premium, you agree to be bound by these Terms of Service. These terms apply to your use of the BarrelBook application and all related services.")
                        
                        Text("2. Premium Purchase")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("BarrelBook Premium is a one-time in-app purchase that provides unlimited access to all features of the BarrelBook application, including unlimited whiskey collection management, tasting notes, wishlist management, and advanced analytics. The purchase price is $7.99. This is not a subscription; you own premium access with no recurring charges.")
                        
                        Text("3. Payment")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Text("Payment is charged once to your Apple ID account at confirmation of purchase. There are no recurring fees. You may restore your purchase on a new device using the Restore Purchases option.")
                        
                        Text("4. Changes to Terms")
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
                        Text("BarrelBook uses Apple's App Store for purchase and payment processing. These services are governed by Apple's privacy policy and terms of service.")
                        
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
        return "March 20, 2026"  // Update this when the Privacy Policy changes
    }
}

#Preview {
    PaywallView(isPresented: .constant(true))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}