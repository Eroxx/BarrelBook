import SwiftUI

struct OnboardingPage: Identifiable {
    let id = UUID()
    let image: String           // SF Symbol name — ignored on welcome page
    let title: String
    let subtitle: String
    let description: String
    let accentColor: Color
    let isWelcome: Bool         // shows the real app icon instead of an SF Symbol
}

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding: Bool = false
    @Environment(\.dismiss) private var dismiss

    /// Pass SettingsView's loadDemoData() to enable the "Explore with Sample Data" button
    var onLoadDemoData: (() -> Void)? = nil

    @State private var currentPage = 0
    @State private var isLoadingDemo = false
    @State private var showingCSVImport = false

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
            accentColor: richAmber,
            isWelcome: false
        ),
    ]}

    private var isLastPage: Bool { currentPage == pages.count - 1 }
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
                HStack {
                    Spacer()
                    Button("Skip") { completeOnboarding() }
                        .foregroundColor(.secondary)
                        .padding()
                }

                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        pageView(for: pages[index]).tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                if isLastPage {
                    lastPageButtons
                } else {
                    nextButton
                }

                Text("You can replay this anytime in Settings → Help")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .opacity(isLastPage ? 1 : 0)
                    .padding(.bottom, 28)
            }
        }
    }

    // ── Page layout ───────────────────────────────────────────────────────
    private func pageView(for page: OnboardingPage) -> some View {
        VStack(spacing: 28) {
            Spacer()

            // Icon area
            if page.isWelcome {
                appIconView
            } else {
                symbolIconView(name: page.image, color: page.accentColor)
            }

            // Text
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

    // ── Last page: two choices ────────────────────────────────────────────
    private var lastPageButtons: some View {
        VStack(spacing: 12) {
            Button { completeOnboarding() } label: {
                HStack {
                    Text("Get Started").font(.headline)
                    Image(systemName: "checkmark")
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(currentAccent.gradient)
                .cornerRadius(15)
            }

            if onLoadDemoData != nil {
                Button {
                    isLoadingDemo = true
                    onLoadDemoData?()
                    completeOnboarding()
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

                Text("Loads a sample bourbon collection so you can explore every feature. Clear it anytime in Settings.")
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
                CSVImportOnboardingView(onComplete: completeOnboarding)
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

    private func completeOnboarding() {
        hasSeenOnboarding = true
        dismiss()
    }
}

#Preview {
    OnboardingView()
}
