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
    @State private var showingRestoreAlert = false
    @State private var restoreAlertTitle = ""
    @State private var restoreAlertMessage = ""

    // Amber palette (matches OnboardingView)
    private let deepAmber = Color(red: 0.48, green: 0.22, blue: 0.04)
    private let gold      = Color(red: 0.84, green: 0.63, blue: 0.24)
    
    private var displayPrice: String {
        subscriptionManager.currentSubscription?.priceFormatted ?? "…"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    headerSection
                    featuresSection
                    purchaseSection
                    legalSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .alert(restoreAlertTitle, isPresented: $showingRestoreAlert) {
            Button("OK") { }
        } message: {
            Text(restoreAlertMessage)
        }
        .onChange(of: subscriptionManager.purchaseState) { state in
            switch state {
            case .purchased:
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

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [gold.opacity(0.25), gold.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 80, height: 80)

                Image(systemName: "crown.fill")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [gold, deepAmber],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 4) {
                Text("Unlock the Full Shelf")
                    .font(.title2).bold()
                    .multilineTextAlignment(.center)

                Text("One purchase. Unlimited everything.")
                    .font(.subheadline)
                    .foregroundColor(gold)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 4)
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            paywallFeatureRow("Unlimited bottles in your collection",                                                           icon: "infinity")
            paywallFeatureRow("Unlimited tasting notes, searchable & filterable",                                              icon: "star.bubble.fill")
            paywallFeatureRow("Deep statistics with value, spending trends, flavor profiles and more",                         icon: "chart.bar.fill")
            paywallFeatureRow("Sort & filter by distillery, proof, price, rating, finish, special designations (such as single barrel, BiB, etc.) and more", icon: "line.3.horizontal.decrease.circle.fill")
            paywallFeatureRow("Wishlist with target prices & store notes",                                                     icon: "heart.fill")
            paywallFeatureRow("Infinity bottle tracker with pour percentages",                                                 icon: "drop.fill")
            paywallFeatureRow("Bottle label scanner that auto-fills name, proof, type and age (beta)",                        icon: "camera.viewfinder")
            paywallFeatureRow("CSV import/export, light & dark mode",                                                         icon: "moon.stars.fill")
        }
    }

    private func paywallFeatureRow(_ text: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(gold)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
        }
    }

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            Text("One-time purchase · \(displayPrice) · No subscription ever")
                .font(.footnote)
                .foregroundColor(gold.opacity(0.8))
                .multilineTextAlignment(.center)

            Button(action: startTrial) {
                HStack(spacing: 8) {
                    if subscriptionManager.purchaseState == .purchasing {
                        ProgressView().tint(.white).padding(.trailing, 4)
                    } else {
                        Image(systemName: "crown.fill")
                    }
                    Text(subscriptionManager.purchaseState == .purchasing
                         ? "Purchasing..."
                         : "Unlock Premium — \(displayPrice)")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(gold.gradient)
                .cornerRadius(15)
            }
            .disabled(subscriptionManager.purchaseState == .purchasing)
            .buttonStyle(.plain)

            Button(action: restorePurchases) {
                Text("Restore Purchases")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .disabled(subscriptionManager.purchaseState == .purchasing)
        }
    }

    private var legalSection: some View {
        VStack(spacing: 12) {
            Text("Payment is charged once to your Apple ID. No subscription — you own premium forever. Restore on a new device via Restore Purchases.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 24) {
                Button("Terms of Service") { showingTerms = true }
                    .font(.caption2).fontWeight(.medium).foregroundColor(.blue)
                Button("Privacy Policy") { showingPrivacy = true }
                    .font(.caption2).fontWeight(.medium).foregroundColor(.blue)
            }
        }
        .padding(.top, 4)
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
            let result = await subscriptionManager.restorePurchases()
            await MainActor.run {
                switch result {
                case .restored:
                    isPresented = false
                case .nothingFound:
                    restoreAlertTitle = "No Purchases Found"
                    restoreAlertMessage = "We couldn’t find a previous BarrelBook Premium purchase for this Apple ID."
                    showingRestoreAlert = true
                case .failed(let message):
                    restoreAlertTitle = "Restore Failed"
                    restoreAlertMessage = message
                    showingRestoreAlert = true
                }
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
                        Text("BarrelBook Premium is a one-time in-app purchase that provides unlimited access to all features of the BarrelBook application, including unlimited whiskey collection management, tasting notes, wishlist management, and advanced analytics. The purchase price is shown in the App Store for your region at the time of purchase. This is not a subscription; you own premium access with no recurring charges.")
                        
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