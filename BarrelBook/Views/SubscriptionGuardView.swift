import SwiftUI

struct SubscriptionGuardView<Content: View>: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showingPaywall = false
    
    let content: Content
    let feature: String
    let showTrialInfo: Bool
    
    init(feature: String = "this feature", showTrialInfo: Bool = true, @ViewBuilder content: () -> Content) {
        self.feature = feature
        self.showTrialInfo = showTrialInfo
        self.content = content()
    }
    
    var body: some View {
        Group {
            if subscriptionManager.hasAccess {
                content
            } else {
                subscriptionBlockedView
            }
        }
        .task {
            await subscriptionManager.updateSubscriptionStatus()
        }
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallView(isPresented: $showingPaywall)
        }
    }
    
    private var subscriptionBlockedView: some View {
        VStack(spacing: 24) {
            // Lock icon
            Image(systemName: "lock.fill")
                .font(.system(size: 64))
                .foregroundColor(.gray)
            
            // Title
            Text("Premium Feature")
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // Description
            Text("Access to \(feature) requires BarrelBook Premium")
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Trial info
            if showTrialInfo {
                VStack(spacing: 8) {
                    Text("Start your free 7-day trial")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(ColorManager.primaryBrandColor)
                    
                    Text("No commitment • Cancel anytime")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            
            // Upgrade button
            Button(action: {
                showingPaywall = true
            }) {
                Text("Upgrade to Premium")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(ColorManager.primaryBrandColor)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
}

// Convenience view for showing locked state in lists/grids
struct LockedFeatureOverlay: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showingPaywall = false
    
    let feature: String
    
    var body: some View {
        if !subscriptionManager.hasAccess {
            ZStack {
                // Semi-transparent overlay
                Rectangle()
                    .fill(Color.black.opacity(0.7))
                
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.title)
                        .foregroundColor(.white)
                    
                    Text("Premium")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Button("Upgrade") {
                        showingPaywall = true
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(ColorManager.primaryBrandColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
            }
            .fullScreenCover(isPresented: $showingPaywall) {
                PaywallView(isPresented: $showingPaywall)
            }
        }
    }
}

// Trial status banner
struct TrialStatusBanner: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showingPaywall = false
    
    var body: some View {
        if subscriptionManager.isInTrialPeriod {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Free Trial")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text("\(subscriptionManager.trialDaysRemaining) days remaining")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Upgrade") {
                    showingPaywall = true
                }
                .font(.caption)
                .fontWeight(.semibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(ColorManager.primaryBrandColor)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding()
            .background(Color.yellow.opacity(0.1))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color.yellow.opacity(0.3)),
                alignment: .bottom
            )
            .fullScreenCover(isPresented: $showingPaywall) {
                PaywallView(isPresented: $showingPaywall)
            }
        }
    }
}

#Preview {
    VStack {
        SubscriptionGuardView(feature: "advanced statistics") {
            Text("Protected Content")
                .font(.title)
                .padding()
        }
    }
}