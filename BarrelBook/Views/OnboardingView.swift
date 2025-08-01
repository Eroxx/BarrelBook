import SwiftUI

struct OnboardingPage: Identifiable {
    let id = UUID()
    let image: String  // SF Symbol name
    let title: String
    let subtitle: String
    let description: String
    let accentColor: Color
    let secondarySymbols: [String]  // Additional SF Symbols for feature highlights
}

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            image: "square.grid.3x3.square",
            title: "Welcome to BarrelBook",
            subtitle: "Your Personal Whiskey Collection",
            description: "Track, discover, and organize your whiskey journey with powerful features designed for enthusiasts.",
            accentColor: .blue,
            secondarySymbols: ["magnifyingglass", "tag.fill", "chart.bar.fill"]
        ),
        OnboardingPage(
            image: "magnifyingglass",
            title: "Quick Search",
            subtitle: "Find Your Bottles Fast",
            description: "Search by name, type, or attributes:\n\n• 'Eagle Rare' → All Eagle Rare\n• 'Eagle Rare sib' → Eagle Rare Single Barrel\n• 'Eagle Rare proof: 100' → 100 proof Eagle Rare\n• 'type: bourbon price: 50-100' → Bourbons $50-$100",
            accentColor: .blue,
            secondarySymbols: []
        ),
        OnboardingPage(
            image: "line.3.horizontal.decrease.circle.fill",
            title: "Advanced Filtering",
            subtitle: "Perfect Organization",
            description: "Filter your collection by:\n\n• Whiskey Type\n• Price Range\n• Proof\n• Special Designations",
            accentColor: .purple,
            secondarySymbols: []
        ),
        OnboardingPage(
            image: "chart.bar.fill",
            title: "Collection Insights",
            subtitle: "Know Your Collection",
            description: "Track everything about your whiskeys:\n\n• Total Collection Value\n• Bottle Count\n• Tasting Notes\n• Store Picks",
            accentColor: .orange,
            secondarySymbols: []
        ),
        OnboardingPage(
            image: "book.fill",
            title: "Track Every Tasting!",
            subtitle: "Your Digital Tasting Journal",
            description: """
            Capture nose, palate & finish notes
            Rate your experience (1-10)
            Serve: 🥃 Neat  🧊 Rocks  💧 Water  ✏️ Custom

            View in list or calendar mode
            
            ──────────
            
            Your tasting notes are powerful. Search for specific flavors like "nose: vanilla", filter by how you enjoyed it ("neat"), or find your highest-rated pours.
            """,
            accentColor: Color(red: 0.8, green: 0.6, blue: 0.3),
            secondarySymbols: ["pencil.and.list.clipboard", "star.fill", "magnifyingglass", "calendar"]
        )
    ]
    
    @State private var currentPage = 0
    @State private var shouldAnimate = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    pages[currentPage].accentColor.opacity(0.2),
                    Color(.systemBackground)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Content
            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    Button("Skip") {
                        completeOnboarding()
                    }
                    .foregroundColor(.secondary)
                    .padding()
                }
                
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        pageView(for: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .onChange(of: currentPage) { _ in
                    shouldAnimate = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        shouldAnimate = true
                    }
                }
                
                // Next/Get Started button
                Button(action: {
                    if currentPage < pages.count - 1 {
                        withAnimation {
                            currentPage += 1
                        }
                    } else {
                        completeOnboarding()
                    }
                }) {
                    HStack {
                        Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                            .font(.headline)
                        Image(systemName: currentPage < pages.count - 1 ? "arrow.right" : "checkmark")
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(pages[currentPage].accentColor.gradient)
                    .cornerRadius(15)
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
        }
    }
    
    private func pageView(for page: OnboardingPage) -> some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon Section - Consistent height for all pages
            VStack(spacing: 24) {
                Image(systemName: page.image)
                    .font(.system(size: 60))
                    .foregroundColor(page.accentColor)
                    .symbolEffect(.bounce, options: .repeat(2), value: shouldAnimate)
                
                if !page.secondarySymbols.isEmpty {
                    HStack(spacing: 30) {
                        ForEach(page.secondarySymbols, id: \.self) { symbol in
                            Image(systemName: symbol)
                                .font(.system(size: 24))
                                .foregroundColor(page.accentColor)
                                .frame(width: 50, height: 50)
                                .background(
                                    Circle()
                                        .fill(page.accentColor.opacity(0.1))
                                )
                        }
                    }
                }
            }
            .frame(height: 160) // Fixed height for icon section
            
            // Text Section
            VStack(spacing: 16) {
                Text(page.title)
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)
                
                Text(page.subtitle)
                    .font(.title3)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                ScrollView {
                    Text(page.description)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
        }
        .padding(.top, 20)
    }
    
    private func completeOnboarding() {
        hasSeenOnboarding = true
        dismiss()
    }
}

#Preview {
    OnboardingView()
} 