import SwiftUI

struct OnboardingPage: Identifiable {
    let id = UUID()
    let image: String
    let title: String
    let subtitle: String
    let description: String
    let accentColor: Color
    let isWelcome: Bool
    let isPremiumPage: Bool
    let isGetStartedPage: Bool

    init(image: String, title: String, subtitle: String, description: String,
         accentColor: Color, isWelcome: Bool = false, isPremiumPage: Bool = false,
         isGetStartedPage: Bool = false) {
        self.image = image; self.title = title; self.subtitle = subtitle
        self.description = description; self.accentColor = accentColor
        self.isWelcome = isWelcome; self.isPremiumPage = isPremiumPage
        self.isGetStartedPage = isGetStartedPage
    }
}

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    /// Pass SettingsView's loadDemoData() to enable the "Explore with Sample Data" button
    var onLoadDemoData: (() -> Void)? = nil

    @State private var currentPage = 0
    @State private var isLoadingDemo = false
    @State private var showingLoadDemoConfirmation = false
    @State private var showingCSVImport = false
    @State private var isPurchasing = false

    // ── Amber palette ─────────────────────────────────────────────────────
    private let deepAmber = Color(red: 0.48, green: 0.22, blue: 0.04)
    private let richAmber = Color(red: 0.60, green: 0.30, blue: 0.06)
    private let medAmber  = Color(red: 0.70, green: 0.40, blue: 0.08)
    private let warmAmber = Color(red: 0.78, green: 0.50, blue: 0.12)
    private let gold      = Color(red: 0.84, green: 0.63, blue: 0.24)

    private var pages: [OnboardingPage] {[
        OnboardingPage(
            image: "",
            title: "Welcome to BarrelBook",
            subtitle: "Know thy shelf.",
            description: "Track your collection, log tastings, build your wishlist, and explore your whiskey journey. All in one app.",
            accentColor: gold,
            isWelcome: true
        ),
        OnboardingPage(
            image: "square.stack.3d.up.fill",
            title: "Your Collection",
            subtitle: "Start with What's on Your Shelf",
            description: "Add every bottle with proof, price, distillery, and special designations. Track open, sealed, and finished bottles separately and see your collection's total value at a glance.\n\nYou can export your entire BarrelBook collection to a CSV file at any time from Settings.",
            accentColor: warmAmber,
            isWelcome: false
        ),
        OnboardingPage(
            image: "star.bubble.fill",
            title: "Log a Tasting",
            subtitle: "A Journal for Every Pour",
            description: "Record nose, palate, and finish using the flavor wheel. Rate from 1 to 10, add tasting notes, and browse your full history in list or calendar view.",
            accentColor: medAmber,
            isWelcome: false
        ),
        OnboardingPage(
            image: "heart.fill",
            title: "Your Wishlist",
            subtitle: "Never Miss a Release",
            description: "Save bottles you want with target prices and store notes. When you find one, move it straight to your collection.",
            accentColor: richAmber
        ),
        OnboardingPage(
            image: "flag.checkered",
            title: "You're All Set",
            subtitle: "Time to build your shelf",
            description: "",
            accentColor: warmAmber,
            isGetStartedPage: true
        ),
        OnboardingPage(
            image: "crown.fill",
            title: "Unlock the Full Shelf",
            subtitle: "One purchase. Unlimited everything.",
            description: "",
            accentColor: gold,
            isPremiumPage: true
        ),
    ]}

    private var isLastPage: Bool { currentPage == pages.count - 1 }
    private var isPremiumPage: Bool { pages[currentPage].isPremiumPage }
    private var isGetStartedPage: Bool { pages[currentPage].isGetStartedPage }
    private var currentAccent: Color { pages[currentPage].accentColor }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [currentAccent.opacity(0.15), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: currentPage)

            VStack(spacing: 0) {
                HStack { Spacer() }.frame(height: 44) // reserved space, no skip button

                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        pageView(for: pages[index]).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                if isPremiumPage {
                    premiumPageButtons
                } else if isGetStartedPage {
                    lastPageButtons
                } else {
                    nextButton
                }
            }
        }
    }

    // ── Page layout ───────────────────────────────────────────────────────
    private func pageView(for page: OnboardingPage) -> some View {
        Group {
            if page.isPremiumPage {
                premiumPageContent
            } else if page.isGetStartedPage {
                getStartedPageContent
            } else {
                VStack(spacing: 28) {
                    Spacer()

                    if page.isWelcome {
                        appIconView
                    } else {
                        symbolIconView(name: page.image, color: page.accentColor)
                    }

                    VStack(spacing: 14) {
                        Text(page.title)
                            .font(.title2).bold()
                            .multilineTextAlignment(.center)

                        Text(page.subtitle)
                            .font(.title3)
                            .foregroundColor(page.accentColor)
                            .multilineTextAlignment(.center)

                        Text(page.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 32)

                    Spacer()
                }
                .padding(.top, 20)
            }
        }
    }

    // ── Get Started page content ──────────────────────────────────────────
    private var getStartedPageContent: some View {
        VStack(spacing: 28) {
            Spacer()

            symbolIconView(name: "flag.checkered", color: warmAmber)

            VStack(spacing: 14) {
                Text("You're All Set")
                    .font(.title2).bold()
                    .multilineTextAlignment(.center)

                Text("Time to build your shelf")
                    .font(.title3)
                    .foregroundColor(warmAmber)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            // Tutorial info cards
            VStack(spacing: 12) {
                tutorialInfoRow(
                    icon: "arrow.counterclockwise.circle.fill",
                    text: "Replay this walkthrough anytime",
                    detail: "Settings → Help & Tutorials"
                )
                tutorialInfoRow(
                    icon: "lightbulb.fill",
                    text: "Each screen has a built-in guide",
                    detail: "Tips appear automatically on first visit. Reset them anytime in Settings → Help & Tutorials."
                )
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding(.top, 20)
    }

    private func tutorialInfoRow(icon: String, text: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(warmAmber)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.subheadline).fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(warmAmber.opacity(0.08))
        .cornerRadius(12)
    }

    // ── Premium page content ──────────────────────────────────────────────
    private var premiumPageContent: some View {
        VStack(spacing: 10) {
            // Compact crown icon
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [gold.opacity(0.25), gold.opacity(0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 64, height: 64)
                Image(systemName: "crown.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(LinearGradient(
                        colors: [gold, deepAmber], startPoint: .top, endPoint: .bottom
                    ))
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: 3) {
                Text("Unlock the Full Shelf")
                    .font(.title3).bold()
                    .multilineTextAlignment(.center)
                Text("One purchase. Unlimited everything.")
                    .font(.subheadline)
                    .foregroundColor(gold)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)

            // Feature list
            VStack(alignment: .leading, spacing: 7) {
                premiumFeatureRow("Unlimited bottles in your collection", icon: "infinity")
                premiumFeatureRow("Unlimited tasting notes, searchable & filterable", icon: "star.bubble.fill")
                premiumFeatureRow("Deep statistics with value, spending trends, flavor profiles and more", icon: "chart.bar.fill")
                premiumFeatureRow("Sort & filter by distillery, proof, price, rating, finish, special designations (such as single barrel, BiB, etc.) and more", icon: "line.3.horizontal.decrease.circle.fill")
                premiumFeatureRow("Wishlist with target prices & store notes", icon: "heart.fill")
                premiumFeatureRow("Infinity bottle tracker with pour percentages", icon: "drop.fill")
                premiumFeatureRow("Bottle label scanner that auto-fills name, proof, type and age (beta)", icon: "camera.viewfinder")
                premiumFeatureRow("CSV import/export, light & dark mode", icon: "moon.stars.fill")
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 8)
        }
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func premiumFeatureRow(_ text: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(gold)
                .frame(width: 20)
            Text(text)
                .font(.footnote)
                .minimumScaleFactor(0.85)
                .lineLimit(2)
                .foregroundColor(.primary)
            Spacer()
        }
    }

    // ── App icon (welcome page) ───────────────────────────────────────────
    private var appIconView: some View {
        Group {
            if let uiImage = UIImage(named: "AppIcon") {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .shadow(color: gold.opacity(0.4), radius: 16, x: 0, y: 8)
            } else {
                // Fallback: styled amber circle with a whiskey glass emoji
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [gold, deepAmber],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 120, height: 120)
                    Text("🥃")
                        .font(.system(size: 60))
                }
                .shadow(color: gold.opacity(0.4), radius: 16, x: 0, y: 8)
            }
        }
        .frame(height: 160)
    }

    // ── SF Symbol icon (feature pages) ───────────────────────────────────
    private func symbolIconView(name: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [color.opacity(0.25), color.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 140, height: 140)

            Image(systemName: name)
                .font(.system(size: 58, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [color, deepAmber],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .symbolRenderingMode(.hierarchical)
        }
        .frame(height: 160)
    }

    // ── Next button ───────────────────────────────────────────────────────
    private var nextButton: some View {
        Button {
            withAnimation { currentPage += 1 }
        } label: {
            HStack {
                Text("Next").font(.headline)
                Image(systemName: "arrow.right")
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(currentAccent.gradient)
            .cornerRadius(15)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func advanceFromGetStarted() {
        if subscriptionManager.hasAccess {
            completeOnboarding()  // already premium — skip paywall
        } else {
            withAnimation { currentPage += 1 }
        }
    }

    // ── Last page: two choices ────────────────────────────────────────────
    private var lastPageButtons: some View {
        VStack(spacing: 12) {
            Button { advanceFromGetStarted() } label: {
                HStack {
                    Text("Get Started").font(.headline)
                    Image(systemName: "arrow.right")
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(currentAccent.gradient)
                .cornerRadius(15)
            }

            if onLoadDemoData != nil {
                Button {
                    showingLoadDemoConfirmation = true
                } label: {
                    HStack {
                        if isLoadingDemo {
                            ProgressView().tint(currentAccent).padding(.trailing, 4)
                        }
                        Text("Explore with Sample Data").font(.subheadline).fontWeight(.medium)
                        Image(systemName: "sparkles")
                    }
                    .foregroundColor(currentAccent)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .strokeBorder(currentAccent.opacity(0.5), lineWidth: 1.5)
                    )
                }
                .disabled(isLoadingDemo)
                .sheet(isPresented: $showingLoadDemoConfirmation) {
                    LoadDemoConfirmationSheet {
                        isLoadingDemo = true
                        onLoadDemoData?()
                        isLoadingDemo = false
                        advanceFromGetStarted()
                    }
                }

                Text("Loads a sample bourbon collection so you can explore every feature before adding your own bottles.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                showingCSVImport = true
            } label: {
                HStack {
                    Text("Import from Spreadsheet").font(.subheadline).fontWeight(.medium)
                    Image(systemName: "tablecells")
                }
                .foregroundColor(.primary.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 15)
                        .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1.5)
                )
            }
            .sheet(isPresented: $showingCSVImport) {
                CSVImportOnboardingView(onComplete: { advanceFromGetStarted() })
            }

            Text("If you already track your data in a spreadsheet, tap above to learn how to import your collection.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // ── Premium page buttons ──────────────────────────────────────────────
    private var premiumPageButtons: some View {
        VStack(spacing: 10) {
            Text("One-time purchase · \(subscriptionManager.currentSubscription?.priceFormatted ?? "…") · No subscription ever")
                .font(.footnote)
                .foregroundColor(gold.opacity(0.8))
                .multilineTextAlignment(.center)

            // Primary: Unlock Premium
            Button {
                isPurchasing = true
                Task {
                    await subscriptionManager.purchaseSubscription()
                    isPurchasing = false
                    if subscriptionManager.hasAccess {
                        completeOnboarding()
                    }
                }
            } label: {
                HStack {
                    if isPurchasing {
                        ProgressView().tint(.white).padding(.trailing, 4)
                    } else {
                        Image(systemName: "crown.fill")
                    }
                    Text(isPurchasing ? "Purchasing..." : "Unlock Premium — \(subscriptionManager.currentSubscription?.priceFormatted ?? "…")")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(gold.gradient)
                .cornerRadius(15)
            }
            .disabled(isPurchasing)

            // Secondary: Start free
            Button {
                completeOnboarding()
            } label: {
                Text("Use free version with 5 bottle limit, upgrade anytime")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.secondary.opacity(0.28), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func completeOnboarding() {
        hasSeenOnboarding = true
        dismiss()
    }
}

#Preview {
    OnboardingView()
}
