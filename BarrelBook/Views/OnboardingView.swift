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

    /// Real iPad idiom — NOT horizontalSizeClass. Sheets / split detail often report
    /// `.compact` on iPad, which previously kept the phone column layout forever.
    private var useIPadLayout: Bool { DeviceTypeHelper.isIPad }

    private var outerHorizontalInset: CGFloat { useIPadLayout ? 48 : 0 }
    private var buttonMaxWidth: CGFloat { useIPadLayout ? 560 : .infinity }
    private var horizontalPadding: CGFloat { useIPadLayout ? 48 : 32 }
    private var copyMaxWidth: CGFloat { useIPadLayout ? 560 : .infinity }
    private var contentMaxWidth: CGFloat { useIPadLayout ? 1100 : .infinity }

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

    private var isPremiumPage: Bool { pages[currentPage].isPremiumPage }
    private var isGetStartedPage: Bool { pages[currentPage].isGetStartedPage }
    private var currentAccent: Color { pages[currentPage].accentColor }

    var body: some View {
        GeometryReader { geo in
            let wide = useIPadLayout && geo.size.width >= 700

            ZStack {
                LinearGradient(
                    colors: [currentAccent.opacity(0.15), Color(.systemBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: currentPage)

                VStack(spacing: 0) {
                    HStack { Spacer() }.frame(height: wide ? 20 : 44)

                    TabView(selection: $currentPage) {
                        ForEach(pages.indices, id: \.self) { index in
                            pageView(for: pages[index], wide: wide)
                                .tag(index)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Group {
                        if isPremiumPage {
                            premiumPageButtons
                        } else if isGetStartedPage {
                            lastPageButtons
                        } else {
                            nextButton
                        }
                    }
                    .frame(maxWidth: buttonMaxWidth)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, wide ? outerHorizontalInset : 0)
            }
        }
    }

    // ── Page layout ───────────────────────────────────────────────────────
    private func pageView(for page: OnboardingPage, wide: Bool) -> some View {
        Group {
            if page.isPremiumPage {
                premiumPageContent(wide: wide)
            } else if page.isGetStartedPage {
                getStartedPageContent(wide: wide)
            } else if wide {
                regularWidthFeaturePage(for: page)
            } else {
                compactFeaturePage(for: page)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Phone: stacked icon + copy
    private func compactFeaturePage(for page: OnboardingPage) -> some View {
        VStack(spacing: 28) {
            Spacer()

            if page.isWelcome {
                appIconView(wide: false)
            } else {
                symbolIconView(name: page.image, color: page.accentColor, wide: false)
            }

            pageCopy(for: page, centered: true, wide: false)

            Spacer()
        }
        .padding(.top, 20)
    }

    /// iPad: side-by-side hero across the full canvas (not a ~400pt phone column)
    private func regularWidthFeaturePage(for page: OnboardingPage) -> some View {
        HStack(alignment: .center, spacing: 56) {
            Group {
                if page.isWelcome {
                    appIconView(wide: true)
                } else {
                    symbolIconView(name: page.image, color: page.accentColor, wide: true)
                }
            }
            .frame(maxWidth: .infinity)

            pageCopy(for: page, centered: false, wide: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pageCopy(for page: OnboardingPage, centered: Bool, wide: Bool) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: wide ? 22 : 14) {
            Text(page.title)
                .font(wide ? .system(size: 40, weight: .bold) : .title2.bold())
                .multilineTextAlignment(centered ? .center : .leading)

            Text(page.subtitle)
                .font(wide ? .title : .title3)
                .foregroundColor(page.accentColor)
                .multilineTextAlignment(centered ? .center : .leading)

            Text(page.description)
                .font(wide ? .title3 : .body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(centered ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: wide ? copyMaxWidth : .infinity,
                       alignment: centered ? .center : .leading)
        }
        .padding(.horizontal, centered ? horizontalPadding : 0)
    }

    // ── Get Started page content ──────────────────────────────────────────
    private func getStartedPageContent(wide: Bool) -> some View {
        Group {
            if wide {
                HStack(alignment: .center, spacing: 56) {
                    VStack(spacing: 24) {
                        symbolIconView(name: "flag.checkered", color: warmAmber, wide: true)
                        VStack(alignment: .leading, spacing: 14) {
                            Text("You're All Set")
                                .font(.system(size: 40, weight: .bold))
                            Text("Time to build your shelf")
                                .font(.title)
                                .foregroundColor(warmAmber)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 20) {
                        tutorialInfoRow(
                            icon: "arrow.counterclockwise.circle.fill",
                            text: "Replay this walkthrough anytime",
                            detail: "Settings → Help & Tutorials",
                            wide: true
                        )
                        tutorialInfoRow(
                            icon: "lightbulb.fill",
                            text: "Each screen has a built-in guide",
                            detail: "Tips appear automatically on first visit. Reset them anytime in Settings → Help & Tutorials.",
                            wide: true
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 28) {
                    Spacer()

                    symbolIconView(name: "flag.checkered", color: warmAmber, wide: false)

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

                    VStack(spacing: 12) {
                        tutorialInfoRow(
                            icon: "arrow.counterclockwise.circle.fill",
                            text: "Replay this walkthrough anytime",
                            detail: "Settings → Help & Tutorials",
                            wide: false
                        )
                        tutorialInfoRow(
                            icon: "lightbulb.fill",
                            text: "Each screen has a built-in guide",
                            detail: "Tips appear automatically on first visit. Reset them anytime in Settings → Help & Tutorials.",
                            wide: false
                        )
                    }
                    .padding(.horizontal, 32)

                    Spacer()
                }
                .padding(.top, 20)
            }
        }
    }

    private func tutorialInfoRow(icon: String, text: String, detail: String, wide: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: wide ? 36 : 28))
                .foregroundColor(warmAmber)
                .frame(width: wide ? 44 : 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(wide ? .title3.weight(.semibold) : .subheadline.weight(.medium))
                Text(detail)
                    .font(wide ? .body : .caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(wide ? 22 : 14)
        .background(warmAmber.opacity(0.08))
        .cornerRadius(14)
    }

    // ── Premium page content ──────────────────────────────────────────────
    private func premiumPageContent(wide: Bool) -> some View {
        VStack(spacing: wide ? 20 : 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [gold.opacity(0.25), gold.opacity(0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: wide ? 100 : 64, height: wide ? 100 : 64)
                Image(systemName: "crown.fill")
                    .font(.system(size: wide ? 42 : 26, weight: .medium))
                    .foregroundStyle(LinearGradient(
                        colors: [gold, deepAmber], startPoint: .top, endPoint: .bottom
                    ))
                    .symbolRenderingMode(.hierarchical)
            }

            VStack(spacing: wide ? 8 : 3) {
                Text("Unlock the Full Shelf")
                    .font(wide ? .system(size: 34, weight: .bold) : .title3.bold())
                    .multilineTextAlignment(.center)
                Text("One purchase. Unlimited everything.")
                    .font(wide ? .title2 : .subheadline)
                    .foregroundColor(gold)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, horizontalPadding)

            Group {
                if wide {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 20),
                        GridItem(.flexible(), spacing: 20)
                    ], alignment: .leading, spacing: 16) {
                        premiumFeatureRow("Unlimited bottles in your collection", icon: "infinity", wide: true)
                        premiumFeatureRow("Unlimited tasting notes, searchable & filterable", icon: "star.bubble.fill", wide: true)
                        premiumFeatureRow("Deep statistics with value, spending trends, flavor profiles and more", icon: "chart.bar.fill", wide: true)
                        premiumFeatureRow("Sort & filter by distillery, proof, price, rating, finish, special designations (such as single barrel, BiB, etc.) and more", icon: "line.3.horizontal.decrease.circle.fill", wide: true)
                        premiumFeatureRow("Wishlist with target prices & store notes", icon: "heart.fill", wide: true)
                        premiumFeatureRow("Infinity bottle tracker with pour percentages", icon: "drop.fill", wide: true)
                        premiumFeatureRow("Bottle label scanner that auto-fills name, proof, type and age (beta)", icon: "camera.viewfinder", wide: true)
                        premiumFeatureRow("CSV import/export, light & dark mode", icon: "moon.stars.fill", wide: true)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        premiumFeatureRow("Unlimited bottles in your collection", icon: "infinity", wide: false)
                        premiumFeatureRow("Unlimited tasting notes, searchable & filterable", icon: "star.bubble.fill", wide: false)
                        premiumFeatureRow("Deep statistics with value, spending trends, flavor profiles and more", icon: "chart.bar.fill", wide: false)
                        premiumFeatureRow("Sort & filter by distillery, proof, price, rating, finish, special designations (such as single barrel, BiB, etc.) and more", icon: "line.3.horizontal.decrease.circle.fill", wide: false)
                        premiumFeatureRow("Wishlist with target prices & store notes", icon: "heart.fill", wide: false)
                        premiumFeatureRow("Infinity bottle tracker with pour percentages", icon: "drop.fill", wide: false)
                        premiumFeatureRow("Bottle label scanner that auto-fills name, proof, type and age (beta)", icon: "camera.viewfinder", wide: false)
                        premiumFeatureRow("CSV import/export, light & dark mode", icon: "moon.stars.fill", wide: false)
                    }
                }
            }
            .padding(.horizontal, wide ? horizontalPadding : 28)
            .frame(maxWidth: wide ? contentMaxWidth : .infinity)

            Spacer(minLength: 8)
        }
        .padding(.top, wide ? 28 : 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func premiumFeatureRow(_ text: String, icon: String, wide: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: wide ? 18 : 14, weight: .medium))
                .foregroundColor(gold)
                .frame(width: wide ? 28 : 20)
            Text(text)
                .font(wide ? .body : .footnote)
                .minimumScaleFactor(0.85)
                .lineLimit(wide ? 3 : 2)
                .foregroundColor(.primary)
            Spacer(minLength: 0)
        }
        .padding(wide ? 14 : 0)
        .background(
            Group {
                if wide {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(gold.opacity(0.06))
                }
            }
        )
    }

    // ── App icon (welcome page) ───────────────────────────────────────────
    private func appIconView(wide: Bool) -> some View {
        let size: CGFloat = wide ? 220 : 120
        let radius: CGFloat = wide ? 46 : 26
        return Group {
            if let uiImage = UIImage(named: "AppIcon") {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .shadow(color: gold.opacity(0.4), radius: 16, x: 0, y: 8)
            } else {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [gold, deepAmber],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: size, height: size)
                    Text("🥃")
                        .font(.system(size: size * 0.5))
                }
                .shadow(color: gold.opacity(0.4), radius: 16, x: 0, y: 8)
            }
        }
        .frame(height: wide ? 240 : 160)
    }

    // ── SF Symbol icon (feature pages) ───────────────────────────────────
    private func symbolIconView(name: String, color: Color, wide: Bool) -> some View {
        let circle: CGFloat = wide ? 220 : 140
        let symbol: CGFloat = wide ? 88 : 58
        return ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [color.opacity(0.25), color.opacity(0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: circle, height: circle)

            Image(systemName: name)
                .font(.system(size: symbol, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [color, deepAmber],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .symbolRenderingMode(.hierarchical)
        }
        .frame(height: wide ? 240 : 160)
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
