import SwiftUI
import UIKit
import CoreData

// Create a notification name for resetting StatisticsView
extension Notification.Name {
    static let resetStatisticsView = Notification.Name("resetStatisticsView")
}

// UIKit representable to intercept tab bar taps
struct TabBarController: UIViewControllerRepresentable {
    var selectedIndex: Binding<Int>
    var onReselect: (Int) -> Void
    
    func makeUIViewController(context: Context) -> UITabBarController {
        let tabBarController = UITabBarController()
        tabBarController.delegate = context.coordinator
        return tabBarController
    }
    
    func updateUIViewController(_ uiViewController: UITabBarController, context: Context) {
        uiViewController.selectedIndex = selectedIndex.wrappedValue
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITabBarControllerDelegate {
        var parent: TabBarController
        
        init(_ parent: TabBarController) {
            self.parent = parent
        }
        
        func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            parent.selectedIndex.wrappedValue = tabBarController.selectedIndex
        }
        
        // This method is called when the user taps the currently selected tab
        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            if tabBarController.selectedViewController === viewController {
                // User tapped the already-selected tab
                parent.onReselect(tabBarController.viewControllers?.firstIndex(of: viewController) ?? 0)
            }
            return true
        }
    }
}

// Simple struct to globally track tab visibility
class TabState: ObservableObject {
    static let shared = TabState()
    @Published var statisticsWasActive = false
    @Published var resetStatistics = false
    
    func resetIfNeeded() {
        // Only reset if the statistics tab was already visible
        if statisticsWasActive {
            resetStatistics = true
            
            // Reset the flag after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.resetStatistics = false
            }
        }
        
        statisticsWasActive = true
    }
    
    func clearStatisticsActive() {
        statisticsWasActive = false
    }
}

// Activity Item Model for Recent Activities
struct ActivityItem: Identifiable {
    let id: UUID
    let icon: String
    let title: String
    let timeAgo: String
    let date: Date
    let whiskey: Whiskey?
    let isJournal: Bool
    let journalEntry: JournalEntry?
    let activityType: ActivityType
    
    init(id: UUID, icon: String, title: String, timeAgo: String, date: Date, whiskey: Whiskey?, isJournal: Bool, journalEntry: JournalEntry? = nil, activityType: ActivityType) {
        self.id = id
        self.icon = icon
        self.title = title
        self.timeAgo = timeAgo
        self.date = date
        self.whiskey = whiskey
        self.isJournal = isJournal
        self.journalEntry = journalEntry
        self.activityType = activityType
    }
    
    enum ActivityType {
        case whiskeyAdded    // New whiskey added to collection
        case bottleOpened    // Bottle opened (dateOpened on BottleInstance)
        case bottleFinished  // Bottle finished/dead (dateFinished on BottleInstance)
        case journalEntry    // Whiskey tasting or marked as tasted
        case wishlistAdded   // Whiskey added to wishlist
    }
}

// Add at the top of the file after imports
class ToolbarVisibilityManager: ObservableObject {
    @Published var shouldShowHomeToolbar = true
    @Published var shouldShowViewToolbar = false
    
    static let shared = ToolbarVisibilityManager()
}

struct ContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedTab: TabSelection = .home
    @StateObject private var tabState = TabState.shared
    @StateObject private var navigationState = NavigationStateManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showingSettings = false
    @State private var statisticsShowingFilteredView = false
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("isDemoDataActive") private var isDemoDataActive = false
    @AppStorage("colorScheme") private var storedColorScheme: AppColorScheme = .system

    /// Converts the stored preference to a SwiftUI ColorScheme so the
    /// modifier below takes effect on the very first render — before
    /// onAppear fires and sets the UIKit window style.
    private var preferredScheme: ColorScheme? {
        switch storedColorScheme {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isDemoDataActive {
                contentViewDemoBanner
            }

            TabView(selection: $selectedTab) {
                NavigationView {
                    HomeView(selectedTab: $selectedTab)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                Text("BarrelBook")
                                    .font(.headline)
                                    .fontWeight(.bold)
                            }
                            
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button {
                                    showingSettings = true
                                } label: {
                                    Image(systemName: "gear")
                                }
                            }
                        }
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(TabSelection.home)
            
            NavigationView {
                CollectionView()
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Collection", systemImage: "square.grid.2x2")
            }
            .tag(TabSelection.collection)
            
            NavigationView {
                WishlistView()
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Wishlist", systemImage: "heart.fill")
            }
            .tag(TabSelection.wishlist)
            
            NavigationView {
                JournalView()
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Tastings", systemImage: "book")
            }
            .tag(TabSelection.journal)
            
            NavigationView {
                StatisticsView(showingFilteredView: $statisticsShowingFilteredView)
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Statistics", systemImage: "chart.bar.fill")
            }
            .tag(TabSelection.statistics)
        }
        .onChange(of: selectedTab) { newTab in
            HapticManager.shared.lightImpact()
            if newTab == .statistics {
                tabState.resetIfNeeded()
            } else {
                tabState.clearStatisticsActive()
                
                // Reset the filtered view when switching away from statistics tab
                if statisticsShowingFilteredView {
                    // Force reset the filtered view to ensure clean navigation
                    DispatchQueue.main.async {
                        statisticsShowingFilteredView = false
                    }
                }
            }
        }
        .onChange(of: navigationState.activeTab) { newTab in
            if let tab = newTab {
                self.selectedTab = tab
                // Reset the navigation state to avoid repeated triggers
                DispatchQueue.main.async {
                    navigationState.activeTab = nil
                }
            }
        }
        .fullScreenCover(isPresented: $showingSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: Binding(
            get: { !hasSeenOnboarding },
            set: { _ in } // prevent dismiss — only completeOnboarding() can close this
        )) {
            OnboardingView(onLoadDemoData: { loadDemoData() })
                .interactiveDismissDisabled(true)
        }
        }
        .preferredColorScheme(preferredScheme)   // applied before first render
        .onAppear {
            applyStoredColorScheme()              // UIKit safety net for sheets/covers
        }
        .task {
            await subscriptionManager.updateSubscriptionStatus()
        }
    }

    /// Apply the persisted appearance preference to the UIWindow on every launch.
    private func applyStoredColorScheme() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        switch storedColorScheme {
        case .light:  window.overrideUserInterfaceStyle = .light
        case .dark:   window.overrideUserInterfaceStyle = .dark
        case .system: window.overrideUserInterfaceStyle = .unspecified
        }
    }

    private func loadDemoData() {
        DemoDataService.load(context: viewContext) { _ in
            isDemoDataActive = true
            HapticManager.shared.successFeedback()
        }
    }

    // MARK: - Demo Banner (persistent, all tabs)

    @State private var showingDeleteDemoConfirmation = false

    private var contentViewDemoBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "flask.fill")
                .font(.subheadline)
                .foregroundColor(Color(red: 0.84, green: 0.63, blue: 0.24))
            Text("You're viewing BarrelBook's demo data")
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
            Button("Delete") {
                showingDeleteDemoConfirmation = true
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(Color(red: 0.84, green: 0.63, blue: 0.24))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(red: 0.84, green: 0.63, blue: 0.24).opacity(0.12))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.4)
        }
        .confirmationDialog("Delete sample data?", isPresented: $showingDeleteDemoConfirmation, titleVisibility: .visible) {
            Button("Delete Sample Data", role: .destructive) { deleteDemoData() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will remove all sample bottles, tastings, and wishlist items.")
        }
    }

    private func deleteDemoData() {
        do {
            let whiskeys = try viewContext.fetch(Whiskey.fetchRequest())
            whiskeys.forEach { viewContext.delete($0) }
            let entries = try viewContext.fetch(JournalEntry.fetchRequest())
            entries.forEach { viewContext.delete($0) }
            let bottles = try viewContext.fetch(InfinityBottle.fetchRequest())
            bottles.forEach { viewContext.delete($0) }
            try viewContext.save()
            isDemoDataActive = false
            HapticManager.shared.successFeedback()
        } catch {
            HapticManager.shared.errorFeedback()
        }
    }
}

// Wrapper view to handle theme changes properly
struct SettingsViewWrapper: View {
    @AppStorage("colorScheme") private var colorScheme: AppColorScheme = .system
    @Environment(\.colorScheme) private var currentColorScheme
    @State private var viewRefreshTrigger = UUID()
    
    var body: some View {
        SettingsView()
            .onChange(of: colorScheme) { newValue in
                // Force immediate view refresh
                viewRefreshTrigger = UUID()
                
                // Force theme update through UIKit
                DispatchQueue.main.async {
                    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                          let window = windowScene.windows.first else { return }
                    
                    // Apply theme based on setting
                    switch newValue {
                    case .light:
                        window.overrideUserInterfaceStyle = .light
                    case .dark:
                        window.overrideUserInterfaceStyle = .dark
                    case .system:
                        // First toggle to force update
                        let currentStyle = currentColorScheme == .dark ? UIUserInterfaceStyle.light : UIUserInterfaceStyle.dark
                        window.overrideUserInterfaceStyle = currentStyle
                        
                        // Then set to system after a tiny delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            window.overrideUserInterfaceStyle = .unspecified
                        }
                    }
                }
            }
            .id(viewRefreshTrigger)
    }
}

// New simplified statistics view that manages its own navigation state
struct BasicStatisticsView: View {
    @StateObject private var tabState = TabState.shared
    @State private var showingDetailView = false
    @State private var navigationReset = UUID()
    
    var body: some View {
        NavigationViewRepresentable(reset: navigationReset) {
            StatisticsView(showingFilteredView: $showingDetailView)
        }
        .onChange(of: tabState.resetStatistics) { reset in
            if reset {
                // Force reset the navigation by updating the ID
                navigationReset = UUID()
                showingDetailView = false
            }
        }
    }
}

// A representable that creates a UIKit navigation controller
// This gives us more control over the navigation state
struct NavigationViewRepresentable<Content: View>: UIViewControllerRepresentable {
    let reset: UUID
    let rootView: Content
    
    init(reset: UUID, @ViewBuilder content: () -> Content) {
        self.reset = reset
        self.rootView = content()
    }
    
    func makeUIViewController(context: Context) -> UINavigationController {
        let hostingController = UIHostingController(rootView: rootView)
        let navigationController = UINavigationController(rootViewController: hostingController)
        return navigationController
    }
    
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {
        // When reset changes, pop to root
        uiViewController.popToRootViewController(animated: true)
    }
}

struct HomeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Whiskey.name, ascending: true)],
        predicate: NSPredicate(format: "status == %@ OR status == nil", "owned"),
        animation: .default)
    private var whiskeys: FetchedResults<Whiskey>
    
    // Separate FetchRequest for wishlist items
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Whiskey.name, ascending: true)],
        predicate: NSPredicate(format: "status == %@", "wishlist"),
        animation: .default)
    private var wishlistWhiskeys: FetchedResults<Whiskey>
    
    // Fetch all journal entries to track free-tier tasting limit
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \JournalEntry.date, ascending: false)],
        animation: .default)
    private var allJournalEntries: FetchedResults<JournalEntry>
    
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedTab: TabSelection
    @State private var showingAddWhiskey = false
    @State private var showingAddJournal = false
    @State private var selectedFilter: WhiskeyFilter? = nil
    @State private var showingFilteredView = false
    @State private var selectedWhiskey: Whiskey? = nil
    @State private var showingAddWishlist = false
    @State private var showingSettings = false
    @State private var selectedActivity: ActivityItem? = nil
    @State private var showingPaywall = false
    @AppStorage("hasSeenEmptyStateTip") private var hasSeenEmptyStateTip = false
    @AppStorage("isDemoDataActive") private var isDemoDataActive = false
    @State private var showingLoadDemoConfirmation = false
    @State private var showingCSVImport = false
    @State private var showingSpotlightInfo = false
    @State private var spotlightNavWhiskey: Whiskey? = nil
    @State private var spotlightJournalWhiskey: Whiskey? = nil

    private var isCollectionEmpty: Bool { whiskeys.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // First-run tip card — only when collection is empty and not yet dismissed
                if isCollectionEmpty && !hasSeenEmptyStateTip {
                    firstRunTipCard
                }

                if isCollectionEmpty {
                    // Empty state with CTAs
                    emptyStateView
                } else {
                    // Normal home content
                    actionCardsSection
                    UsageCounterView(
                        currentWhiskeyCount: whiskeys.count,
                        currentTastingCount: allJournalEntries.count
                    )
                    bottleSpotlightSection
                    recentActivitySection
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 0)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("BarrelBook")
                    .font(.headline)
                    .fontWeight(.bold)
            }
        }
        .sheet(isPresented: $showingAddWhiskey) {
            AddWhiskeyView()
        }
        .sheet(isPresented: $showingAddJournal, onDismiss: { selectedWhiskey = nil }) {
            // If a whiskey is selected, pre-select it for the journal entry
            if let whiskey = selectedWhiskey {
                AddJournalEntryView(preSelectedWhiskey: whiskey)
            } else {
                AddJournalEntryView()
            }
        }
        .sheet(isPresented: Binding(
            get: { spotlightJournalWhiskey != nil },
            set: { if !$0 { spotlightJournalWhiskey = nil } }
        )) {
            if let whiskey = spotlightJournalWhiskey {
                AddJournalEntryView(preSelectedWhiskey: whiskey)
            }
        }
        .sheet(isPresented: $showingAddWishlist) {
            AddWhiskeyToWishlistView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallView(isPresented: $showingPaywall)
        }
        .background(
            Group {
                if let activity = selectedActivity {
                    NavigationLink(
                        destination: destinationView(for: activity),
                        isActive: Binding(
                            get: { selectedActivity != nil },
                            set: { if !$0 { selectedActivity = nil } }
                        )
                    ) { EmptyView() }
                }
                if let whiskey = spotlightNavWhiskey {
                    NavigationLink(
                        destination: WhiskeyDetailView(whiskey: whiskey),
                        isActive: Binding(
                            get: { spotlightNavWhiskey != nil },
                            set: { if !$0 { spotlightNavWhiskey = nil } }
                        )
                    ) { EmptyView() }
                }
            }
        )
    }


    // MARK: - Empty State & First-run Tip

    private var firstRunTipCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .foregroundColor(ColorManager.primaryBrandColor)
                .font(.title3)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("New to BarrelBook?")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text("Already tracking in a spreadsheet? Use Import from Spreadsheet below. Or load sample data to explore, then delete it when ready.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                hasSeenEmptyStateTip = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(ColorManager.primaryBrandColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(ColorManager.primaryBrandColor.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 40)

            // Icon
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(ColorManager.primaryBrandColor.opacity(0.10))
                        .frame(width: 120, height: 120)
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 52, weight: .light))
                        .foregroundColor(ColorManager.primaryBrandColor)
                }

                VStack(spacing: 8) {
                    Text("Your shelf is empty")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Add your first bottle or explore\nthe app with sample data.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // CTAs
            VStack(spacing: 12) {
                Button {
                    if subscriptionManager.canAddWhiskey(currentCount: whiskeys.count) {
                        showingAddWhiskey = true
                    } else {
                        showingPaywall = true
                    }
                } label: {
                    Label("Add Your First Bottle", systemImage: "plus")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(ColorManager.primaryBrandColor)
                        .cornerRadius(12)
                }

                Button {
                    showingLoadDemoConfirmation = true
                } label: {
                    Label("Explore with Sample Data", systemImage: "sparkles")
                        .font(.subheadline)
                        .foregroundColor(ColorManager.primaryBrandColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(ColorManager.primaryBrandColor.opacity(0.10))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(ColorManager.primaryBrandColor.opacity(0.30), lineWidth: 1)
                        )
                }
                .sheet(isPresented: $showingLoadDemoConfirmation) {
                    LoadDemoConfirmationSheet {
                        loadDemoData()
                        hasSeenEmptyStateTip = true
                    }
                }

                Text("Sample data can be deleted anytime from the banner on this screen")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    showingCSVImport = true
                } label: {
                    Label("Import from Spreadsheet", systemImage: "tablecells")
                        .font(.subheadline)
                        .foregroundColor(.primary.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                        )
                }
                .sheet(isPresented: $showingCSVImport) {
                    CSVImportOnboardingView()
                }

                Text("If you already track your data in a spreadsheet, tap above to learn how to import your collection.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Demo Data
    private func loadDemoData() {
        DemoDataService.load(context: viewContext) { _ in
            isDemoDataActive = true
            HapticManager.shared.successFeedback()
        }
    }

    // MARK: - Bottle Spotlight

    private var todaySpotlightWhiskey: Whiskey? {
        let eligible = whiskeys.filter { !$0.isCompletelyDead }
        guard !eligible.isEmpty else { return nil }
        let dayIndex = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 1
        return eligible[dayIndex % eligible.count]
    }

    private var bottleSpotlightSection: some View {
        Group {
            if let bottle = todaySpotlightWhiskey {
                VStack(alignment: .leading, spacing: 10) {
                    // Header row
                    HStack(spacing: 6) {
                        Text("✦")
                            .font(.caption2)
                            .foregroundColor(ColorManager.primaryBrandColor)
                        Text("BOTTLE SPOTLIGHT")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(ColorManager.primaryBrandColor)
                            .tracking(0.8)
                        Button {
                            showingSpotlightInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundColor(ColorManager.primaryBrandColor.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Text("Changes daily")
                            .font(.caption2)
                            .foregroundColor(ColorManager.secondaryText)
                    }
                    .alert("Bottle Spotlight", isPresented: $showingSpotlightInfo) {
                        Button("Got it", role: .cancel) {}
                    } message: {
                        Text("A different bottle from your collection is featured here each day — a nudge to revisit something on your shelf you may not have poured recently.")
                    }

                    Divider()
                        .background(ColorManager.primaryBrandColor.opacity(0.25))

                    // Bottle name + price — tappable to go to detail
                    Button {
                        spotlightNavWhiskey = bottle
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(bottle.name ?? "")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(ColorManager.primaryText)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            if bottle.price > 0 {
                                Text(String(format: "$%.0f", bottle.price))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(ColorManager.secondaryText)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    // Distillery · Type · Proof as chips
                    HStack(spacing: 8) {
                        if let distillery = bottle.distillery, !distillery.isEmpty {
                            Text(distillery)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(ColorManager.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(ColorManager.secondaryText.opacity(0.12))
                                .cornerRadius(6)
                        }
                        if let type = bottle.type, !type.isEmpty {
                            Text(type)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(ColorManager.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(ColorManager.secondaryText.opacity(0.12))
                                .cornerRadius(6)
                        }
                        if bottle.proof > 0 {
                            Text(String(format: "%.0f Proof", bottle.proof))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(ColorManager.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(ColorManager.secondaryText.opacity(0.12))
                                .cornerRadius(6)
                        }
                    }

                    // Status + rating row
                    HStack(spacing: 8) {
                        // Bottle status chip
                        let instances = (bottle.bottleInstances as? Set<BottleInstance>) ?? []
                        let activeCount = instances.filter { !$0.isDead }.count
                        let hasOpen = instances.contains { $0.isOpen && !$0.isDead }
                        let allDead = !instances.isEmpty && activeCount == 0

                        let statusLabel = allDead ? "Finished" : (hasOpen ? "Open" : "Sealed")
                        let statusColor: Color = hasOpen ? ColorManager.primaryBrandColor : .secondary
                        let statusBg: Color = hasOpen ? ColorManager.primaryBrandColor.opacity(0.15) : Color.secondary.opacity(0.12)

                        HStack(spacing: 4) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 6, height: 6)
                            Text(statusLabel)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(statusColor)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(statusBg)
                        .cornerRadius(6)

                        // Bottle count (only if more than 1)
                        if activeCount > 1 {
                            Text("\(activeCount) bottles")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(ColorManager.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(ColorManager.secondaryText.opacity(0.12))
                                .cornerRadius(6)
                        }

                        // Rating or Untasted
                        let rating = bottle.personalRating
                        if rating > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundColor(ColorManager.primaryBrandColor)
                                Text(String(format: "%.1f", rating))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(ColorManager.primaryText)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(ColorManager.primaryBrandColor.opacity(0.12))
                            .cornerRadius(6)
                        } else {
                            Text("Untasted")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(ColorManager.secondaryText)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(ColorManager.secondaryText.opacity(0.12))
                                .cornerRadius(6)
                        }
                    }

                    // Add Tasting button
                    Button {
                        if subscriptionManager.canAddTasting(currentCount: allJournalEntries.count) {
                            spotlightJournalWhiskey = bottle
                        } else {
                            showingPaywall = true
                        }
                    } label: {
                        Text("Add Tasting")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(ColorManager.primaryBrandColor.opacity(0.75))
                            .cornerRadius(8)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark
                            ? Color(red: 0.14, green: 0.09, blue: 0.04)
                            : Color(red: 1.00, green: 0.96, blue: 0.90))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(ColorManager.primaryBrandColor.opacity(colorScheme == .dark ? 0.45 : 0.35), lineWidth: 1.5)
                )
                .shadow(color: ColorManager.primaryBrandColor.opacity(colorScheme == .dark ? 0.12 : 0.08), radius: 8, x: 0, y: 2)
            }
        }
    }

    // Main Action Cards Section
    private var actionCardsSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ActionCard(
                    icon: "🥃",
                    isEmoji: true,
                    title: "Add New Whiskey",
                    action: {
                        if subscriptionManager.canAddWhiskey(currentCount: whiskeys.count) {
                            showingAddWhiskey = true
                        } else {
                            showingPaywall = true
                        }
                    }
                )

                Rectangle()
                    .fill(ColorManager.primaryBrandColor.opacity(0.3))
                    .frame(width: 1)

                ActionCard(
                    icon: "text.badge.plus",
                    isEmoji: false,
                    title: "Add New Tasting",
                    action: {
                        selectedWhiskey = nil
                        if subscriptionManager.canAddTasting(currentCount: allJournalEntries.count) {
                            showingAddJournal = true
                        } else {
                            showingPaywall = true
                        }
                    }
                )
            }

            Rectangle()
                .fill(ColorManager.primaryBrandColor.opacity(0.3))
                .frame(height: 1)

            HStack(spacing: 0) {
                ActionCard(
                    icon: "heart.fill",
                    isEmoji: false,
                    title: "View Wishlist",
                    action: {
                        if subscriptionManager.hasAccess {
                            selectedTab = .wishlist
                        } else {
                            showingPaywall = true
                        }
                    }
                )

                Rectangle()
                    .fill(ColorManager.primaryBrandColor.opacity(0.3))
                    .frame(width: 1)

                ActionCard(
                    icon: "plus.circle",
                    isEmoji: false,
                    title: "Add to Wishlist",
                    action: {
                        if subscriptionManager.hasAccess {
                            showingAddWishlist = true
                        } else {
                            showingPaywall = true
                        }
                    }
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark
                    ? Color(red: 0.17, green: 0.12, blue: 0.08)
                    : Color(red: 0.97, green: 0.94, blue: 0.90))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(ColorManager.primaryBrandColor.opacity(colorScheme == .dark ? 0.45 : 0.35), lineWidth: 1.5)
        )
        .shadow(color: ColorManager.primaryBrandColor.opacity(colorScheme == .dark ? 0.12 : 0.08), radius: 8, x: 0, y: 2)
    }
    
    // Calculate total collection value
    private var totalCollectionValue: Double {
        let total = whiskeys.filter { $0.statusEnum == .owned }.reduce(0.0) { result, whiskey in
            guard let bottles = whiskey.bottleInstances as? Set<BottleInstance> else { return result }
            let activeBottles = bottles.filter { !$0.isDead }.count
            return result + (whiskey.price * Double(activeBottles))
        }
        return total
    }
    
    // Get last added bottle text for context
    private func getLastAddedBottleText() -> String {
        let recentWhiskeys = getRecentWhiskeys()
        if let first = recentWhiskeys.first {
            return first.name ?? "None yet"
        }
        return "None yet"
    }
    
    // Get last journal entry for context
    private func getLastJournalEntryText() -> String {
        // This would ideally check the journal entries
        // For now we'll use a placeholder - you'd implement this with actual journal data
        return getLastJournaledWhiskey()?.name ?? "None yet"
    }
    
    // Get recent activity for the activity section
    private func getRecentActivity() -> [ActivityItem] {
        var activities: [ActivityItem] = []
        
        // Add recently ADDED whiskeys (based on addedDate)
        let recentlyAddedWhiskeys = whiskeys.filter { $0.status == "owned" && $0.addedDate != nil }
            .sorted { ($0.addedDate ?? Date.distantPast) > ($1.addedDate ?? Date.distantPast) }
            .prefix(3)
        
        for whiskey in recentlyAddedWhiskeys {
            if let addedDate = whiskey.addedDate {
                activities.append(ActivityItem(
                    id: UUID(),
                    icon: "plus.circle.fill",
                    title: "Added \(whiskey.name ?? "Unknown Whiskey")",
                    timeAgo: AppFormatters.formatDateShort(addedDate),
                    date: addedDate,
                    whiskey: whiskey,
                    isJournal: false,
                    activityType: .whiskeyAdded
              ))
            }
        }
        
        // Add OPENED and FINISHED events from bottle instances (explicit dates, fully reliable)
        let ownedWhiskeys = Array(whiskeys.filter { $0.status == "owned" })
        for whiskey in ownedWhiskeys {
            guard let instances = whiskey.bottleInstances as? Set<BottleInstance> else { continue }
            let multiBottle = instances.count > 1
            let name = whiskey.name ?? "Unknown Whiskey"
            for instance in instances {
                if let dateOpened = instance.dateOpened {
                    let title = multiBottle
                        ? "Opened Bottle \(instance.bottleNumber): \(name)"
                        : "Opened: \(name)"
                    activities.append(ActivityItem(
                        id: UUID(), icon: "lock.open.fill", title: title,
                        timeAgo: AppFormatters.formatDateShort(dateOpened),
                        date: dateOpened, whiskey: whiskey, isJournal: false,
                        activityType: .bottleOpened
                    ))
                }
                if let dateFinished = instance.dateFinished {
                    let title = multiBottle
                        ? "Finished Bottle \(instance.bottleNumber): \(name)"
                        : "Finished: \(name)"
                    activities.append(ActivityItem(
                        id: UUID(), icon: "checkmark.seal.fill", title: title,
                        timeAgo: AppFormatters.formatDateShort(dateFinished),
                        date: dateFinished, whiskey: whiskey, isJournal: false,
                        activityType: .bottleFinished
                    ))
                }
            }
        }
        
        // SECOND: Add actual journal entries
        // Also include whiskeys with isTasted = true but no journal entries
        let journaledWhiskeys = whiskeys.filter { 
            ($0.journalEntries?.count ?? 0) > 0 || $0.isTasted 
        }
        .sorted { ($0.modificationDate ?? Date.distantPast) > ($1.modificationDate ?? Date.distantPast) }
        .prefix(3)
        
        for whiskey in journaledWhiskeys {
            let date = whiskey.modificationDate ?? Date()
            
            // Determine if this is a journal entry or just a tasted toggle
            let hasJournalEntries = (whiskey.journalEntries?.count ?? 0) > 0
            let isJustTastedToggle = whiskey.isTasted && !hasJournalEntries
            
            if hasJournalEntries {
                // Create an activity for the most recent journal entry
                if let entries = whiskey.journalEntries as? Set<JournalEntry>, !entries.isEmpty {
                    let sortedEntries = entries.sorted { 
                        ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) 
                    }
                    
                    if let mostRecentEntry = sortedEntries.first {
                        activities.append(ActivityItem(
                            id: UUID(),
                            icon: "text.badge.plus",
                            title: "Tasting Added: \(whiskey.name ?? "Unknown Whiskey")",
                            timeAgo: AppFormatters.formatDateShort(mostRecentEntry.date ?? date),
                            date: mostRecentEntry.date ?? date,
                            whiskey: whiskey,
                            isJournal: true,
                            journalEntry: mostRecentEntry,
                            activityType: .journalEntry
                        ))
                    }
                }
            } else if isJustTastedToggle {
                // Create an activity for the tasted toggle
                activities.append(ActivityItem(
                    id: UUID(),
                    icon: "checkmark.circle.fill",
                    title: "Marked as Tasted: \(whiskey.name ?? "Unknown Whiskey")",
                    timeAgo: AppFormatters.formatDateShort(date),
                    date: date,
                    whiskey: whiskey,
                    isJournal: false,
                    activityType: .journalEntry
                ))
            }
        }
        
        // THIRD: Add ACTUAL wishlist items (not random ones)
        let wishlistWhiskeys = whiskeys.filter { $0.status == "wishlist" }
            .sorted { ($0.modificationDate ?? Date.distantPast) > ($1.modificationDate ?? Date.distantPast) }
            .prefix(3)
        
        if !wishlistWhiskeys.isEmpty {
            for whiskey in wishlistWhiskeys {
                let date = whiskey.modificationDate ?? Date()
                activities.append(ActivityItem(
                    id: UUID(),
                    icon: "heart.fill",
                    title: "Added to Wishlist: \(whiskey.name ?? "Unknown Whiskey")",
                    timeAgo: AppFormatters.formatDateShort(date),
                    date: date,
                    whiskey: whiskey,
                    isJournal: false,
                    activityType: .wishlistAdded
                ))
            }
        }
        
        // Sort all activities by date, newest first
        return activities.sorted { $0.date > $1.date }.prefix(6).map { $0 }
    }
    
    // Refactor recentActivitySection to use Button for selection
    private var recentActivitySection: some View {
        let primaryColor = ColorManager.primaryBrandColor
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Recent Activity")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                NavigationLink(destination: RecentActivityView()) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(ColorManager.primaryBrandColor)
                }
            }
            Divider().padding(.bottom, 8)
            let activities = getRecentActivity()
            if activities.isEmpty {
                Text("No recent activity")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
                    .padding(.vertical, 12)
            } else {
                ForEach(activities.prefix(3), id: \.id) { activity in
                    Button(action: { selectedActivity = activity }) {
                        activityRow(activity, primaryColor: primaryColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding()
        .background(ColorManager.background)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    // Helper for consistent activity row styling
    private func activityRow(_ activity: ActivityItem, primaryColor: Color) -> some View {
        return HStack(alignment: .center, spacing: 12) {
            // Icon with bourbon color but no background
            Image(systemName: activity.icon)
                .font(.system(size: 20))
                .foregroundColor(primaryColor)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Text(activity.timeAgo)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    // Get recently added whiskeys
    private func getRecentWhiskeys() -> [Whiskey] {
        // Sort by creation date (if available in the model)
        // For this implementation, we'll just take a few items
        let sortedWhiskeys = Array(whiskeys).sorted { 
            // In a real Core Data implementation, you would sort by creationDate 
            // or something similar. Here we're just using the whiskey's name as a proxy
            ($0.name ?? "") > ($1.name ?? "")
        }
        return Array(sortedWhiskeys.prefix(3))
    }
    
    // Get last journaled whiskey
    private func getLastJournaledWhiskey() -> Whiskey? {
        // In a real app, this would query journal entries
        // For now, just return the first whiskey that has journal entries
        return whiskeys.first(where: { ($0.journalEntries?.count ?? 0) > 0 })
    }
    
    // Count whiskeys with journal entries (tasted)
    private func countTastedWhiskeys() -> Int {
        return whiskeys.filter { ($0.journalEntries?.count ?? 0) > 0 }.count
    }
    
    // Calculate average PPP
    private func calculateAveragePPP() -> Double {
        let validWhiskeys = whiskeys.filter { $0.price > 0 && $0.proof > 0 }
        if validWhiskeys.isEmpty { return 0 }
        
        let totalPPP = validWhiskeys.reduce(0.0) { total, whiskey in
            return total + (whiskey.price / whiskey.proof)
        }
        
        return totalPPP / Double(validWhiskeys.count)
    }
    
    // Helper function to count total active bottles
    private func getTotalActiveBottles(whiskeys: FetchedResults<Whiskey>) -> Int {
        let currentWhiskeys = whiskeys.filter { $0.status == "owned" }
        // Calculate total bottles directly from each whiskey's numberOfBottles property
        // rather than counting bottle instances, which may be inconsistent
        return currentWhiskeys.reduce(0) { total, whiskey in
            return total + Int(whiskey.numberOfBottles)
        }
    }
    
    // Helper to return the correct destination view
    @ViewBuilder
    private func destinationView(for activity: ActivityItem) -> some View {
        if let entry = activity.journalEntry {
            JournalEntryDetailView(entry: entry)
        } else if let whiskey = activity.whiskey {
            WhiskeyDetailView(whiskey: whiskey)
        } else {
            EmptyView()
        }
    }
}

// Custom action card component
struct ActionCard: View {
    let icon: String
    let isEmoji: Bool
    let title: String
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private let primaryColor = ColorManager.primaryBrandColor

    private var cardBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.17, green: 0.12, blue: 0.08)
            : Color(red: 0.97, green: 0.94, blue: 0.90)
    }
    
    var body: some View {
        Button {
            HapticManager.shared.mediumImpact()
            action()
        } label: {
            VStack(spacing: 10) {
                // Icon - either emoji or SF Symbol
                if isEmoji {
                    Text(icon)
                        .font(.system(size: 30))
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 26))
                        .foregroundColor(primaryColor)
                }

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(ColorManager.primaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding(.vertical, 16)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: .infinity)
    }
}

// Add preview for HomeView with binding parameter
struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView(selectedTab: .constant(.home))
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
}

// Full Recent Activity View
struct RecentActivityView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Whiskey.name, ascending: true)],
        animation: .default)
    private var whiskeys: FetchedResults<Whiskey>
    @State private var selectedActivity: ActivityItem? = nil
    @State private var showingAddJournal = false
    @State private var activityFilter: ActivityItem.ActivityType? = nil
    @State private var timeRange: TimeRange = .week
    
    enum TimeRange: String, CaseIterable, Identifiable {
        case day = "24 Hours"
        case week = "7 Days" 
        case month = "30 Days"
        case all = "All Time"
        
        var id: String { self.rawValue }
        
        var days: Int? {
            switch self {
            case .day: return 1
            case .week: return 7
            case .month: return 30
            case .all: return nil
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filters
            HStack {
                Picker("Time Range", selection: $timeRange) {
                    ForEach(TimeRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
            }
            .padding(.top)
            
            // Activity Type Filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    filterButton(type: nil, label: "All")
                    filterButton(type: .whiskeyAdded, label: "Added")
                    filterButton(type: .bottleOpened, label: "Opened")
                    filterButton(type: .bottleFinished, label: "Finished")
                    filterButton(type: .journalEntry, label: "Tastings")
                    filterButton(type: .wishlistAdded, label: "Wishlist")
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            
            // Activities List
            let activities = getRecentActivity()
            
            if activities.isEmpty {
                VStack {
                    Spacer()
                    Text("No activity in this time period")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                    Spacer()
                }
            } else {
                List {
                    ForEach(activities) { activity in
                        Button(action: { selectedActivity = activity }) {
                            activityRow(activity)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationTitle("Recent Activity")
        .sheet(isPresented: $showingAddJournal) {
            if let activity = selectedActivity, let whiskey = activity.whiskey {
                AddJournalEntryView(preSelectedWhiskey: whiskey)
            } else {
                AddJournalEntryView()
            }
        }
        .background(
            Group {
                if let activity = selectedActivity {
                    NavigationLink(
                        destination: destinationView(for: activity),
                        isActive: Binding(
                            get: { selectedActivity != nil },
                            set: { if !$0 { selectedActivity = nil } }
                        )
                    ) { EmptyView() }
                }
            }
        )
    }
    
    private func filterButton(type: ActivityItem.ActivityType?, label: String) -> some View {
        Button(action: {
            HapticManager.shared.lightImpact()
            activityFilter = type
        }) {
            Text(label)
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(activityFilter == type ? ColorManager.primaryBrandColor : Color.gray.opacity(0.2))
                )
                .foregroundColor(activityFilter == type ? .white : .primary)
        }
    }
    
    private func activityRow(_ activity: ActivityItem) -> some View {
        return HStack(alignment: .center, spacing: 12) {
            // Activity icon
            Image(systemName: activity.icon)
                .font(.system(size: 20))
                .foregroundColor(ColorManager.primaryBrandColor)
                .frame(width: 30, height: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Text(formatRelativeDate(activity.date))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
    
    // Format date in a relative format (today, yesterday, or date)
    private func formatRelativeDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today at \(formatTime(date))"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday at \(formatTime(date))"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.timeZone = TimeZone.current
            return formatter.string(from: date)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: date)
    }
    
    // Get all activity within the selected time range
    private func getRecentActivity() -> [ActivityItem] {
        var activities: [ActivityItem] = []
        
        // Get the earliest date to include in results
        let earliestDate: Date?
        if let days = timeRange.days {
            earliestDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        } else {
            earliestDate = nil // All time
        }
        
        // Add recently ADDED whiskeys (based on addedDate)
        let ownedWhiskeys = whiskeys.filter { $0.status == "owned" }
        
        for whiskey in ownedWhiskeys {
            // For newly added whiskeys
            if let addedDate = whiskey.addedDate {
                // Only include activities within the selected date range
                if let earliest = earliestDate, addedDate < earliest {
                    // Skip if outside date range
                } else {
                    // Apply activity type filter if one is selected
                    if let filter = activityFilter, filter != .whiskeyAdded {
                        // Skip if filtered out
                    } else {
                        // Add as a "Whiskey Added" activity
                        activities.append(ActivityItem(
                            id: UUID(),
                            icon: "plus.circle.fill",
                            title: "Added \(whiskey.name ?? "Unknown Whiskey")",
                            timeAgo: AppFormatters.formatDateShort(addedDate),
                            date: addedDate,
                            whiskey: whiskey,
                            isJournal: false,
                            activityType: .whiskeyAdded
                        ))
                    }
                }
            }
            
        }

        // OPENED and FINISHED events from bottle instances (explicit dates — fully reliable)
        for whiskey in ownedWhiskeys {
            guard let instances = whiskey.bottleInstances as? Set<BottleInstance> else { continue }
            let multiBottle = instances.count > 1
            let name = whiskey.name ?? "Unknown Whiskey"
            for instance in instances {
                if let dateOpened = instance.dateOpened {
                    if let earliest = earliestDate, dateOpened < earliest { continue }
                    if let filter = activityFilter, filter != .bottleOpened { continue }
                    let title = multiBottle
                        ? "Opened Bottle \(instance.bottleNumber): \(name)"
                        : "Opened: \(name)"
                    activities.append(ActivityItem(
                        id: UUID(), icon: "lock.open.fill", title: title,
                        timeAgo: AppFormatters.formatDateShort(dateOpened),
                        date: dateOpened, whiskey: whiskey, isJournal: false,
                        activityType: .bottleOpened
                    ))
                }
                if let dateFinished = instance.dateFinished {
                    if let earliest = earliestDate, dateFinished < earliest { continue }
                    if let filter = activityFilter, filter != .bottleFinished { continue }
                    let title = multiBottle
                        ? "Finished Bottle \(instance.bottleNumber): \(name)"
                        : "Finished: \(name)"
                    activities.append(ActivityItem(
                        id: UUID(), icon: "checkmark.seal.fill", title: title,
                        timeAgo: AppFormatters.formatDateShort(dateFinished),
                        date: dateFinished, whiskey: whiskey, isJournal: false,
                        activityType: .bottleFinished
                    ))
                }
            }
        }
        
        // SECOND: Add ACTUAL journal entries using real data
        // Also include whiskeys with isTasted = true but no journal entries
        let journaledWhiskeys = whiskeys.filter { 
            ($0.journalEntries?.count ?? 0) > 0 || $0.isTasted 
        }
        
        for whiskey in journaledWhiskeys {
            let date = whiskey.modificationDate ?? Date()
            
            // Only include activities within the selected date range
            if let earliest = earliestDate, date < earliest {
                continue
            }
            
            // Apply activity type filter if one is selected
            if let filter = activityFilter, filter != .journalEntry {
                continue
            }
            
            // Determine if this is a journal entry or just a tasted toggle
            let hasJournalEntries = (whiskey.journalEntries?.count ?? 0) > 0
            let isJustTastedToggle = whiskey.isTasted && !hasJournalEntries
            
            if hasJournalEntries {
                // Create an activity for each journal entry
                if let entries = whiskey.journalEntries as? Set<JournalEntry>, !entries.isEmpty {
                    for entry in entries {
                        activities.append(ActivityItem(
                            id: UUID(),
                            icon: "text.badge.plus",
                            title: "Tasting Added: \(whiskey.name ?? "Unknown Whiskey")",
                            timeAgo: AppFormatters.formatDateShort(entry.date ?? date),
                            date: entry.date ?? date,
                            whiskey: whiskey,
                            isJournal: true,
                            journalEntry: entry,
                            activityType: .journalEntry
                        ))
                    }
                }
            }
            
            if isJustTastedToggle {
                // Create an activity for the tasted toggle
                activities.append(ActivityItem(
                    id: UUID(),
                    icon: "checkmark.circle.fill",
                    title: "Marked as Tasted: \(whiskey.name ?? "Unknown Whiskey")",
                    timeAgo: AppFormatters.formatDateShort(date),
                    date: date,
                    whiskey: whiskey,
                    isJournal: false,
                    activityType: .journalEntry
                ))
            }
        }
        
        // THIRD: Add ACTUAL wishlist entries with real data
        let wishlistWhiskeys = whiskeys.filter { $0.status == "wishlist" }
        
        for whiskey in wishlistWhiskeys {
            let date = whiskey.modificationDate ?? Date()
            
            // Only include activities within the selected date range
            if let earliest = earliestDate, date < earliest {
                continue
            }
            
            // Apply activity type filter if one is selected
            if let filter = activityFilter, filter != .wishlistAdded {
                continue
            }
            
            activities.append(ActivityItem(
                id: UUID(),
                icon: "heart.fill",
                title: "Added to Wishlist: \(whiskey.name ?? "Unknown Whiskey")",
                timeAgo: AppFormatters.formatDateShort(date),
                date: date,
                whiskey: whiskey,
                isJournal: false,
                activityType: .wishlistAdded
            ))
        }
        
        // Sort all activities by date, newest first
        return activities.sorted(by: { $0.date > $1.date })
    }
    
    // Helper to return the correct destination view
    @ViewBuilder
    private func destinationView(for activity: ActivityItem) -> some View {
        if let entry = activity.journalEntry {
            JournalEntryDetailView(entry: entry)
        } else if let whiskey = activity.whiskey {
            WhiskeyDetailView(whiskey: whiskey)
        } else {
            EmptyView()
        }
    }
}

// Add a privacy-aware value text component
struct PrivacyAwareValueText: View {
    let value: Double
    
    @ObservedObject private var privacyManager = PrivacyManager.shared
    @State private var temporarilyShowValue: Bool = false
    
    var body: some View {
        HStack(spacing: 4) {
            if privacyManager.hidePrices && !temporarilyShowValue {
                Text("Hidden")
                    .foregroundColor(.secondary)
                
                Button(action: {
                    temporarilyShowValue = true
                    // Auto-hide after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        temporarilyShowValue = false
                    }
                    HapticManager.shared.selectionFeedback()
                }) {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text(AppFormatters.formatCurrency(value))
                    .fontWeight(.semibold)
                
                if privacyManager.hidePrices && temporarilyShowValue {
                    Image(systemName: "timer")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
}

// Usage Counter Component for Freemium Users
struct UsageCounterView: View {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    let currentWhiskeyCount: Int
    let currentTastingCount: Int
    @State private var showingPaywall = false

    var body: some View {
        if !subscriptionManager.hasAccess {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BarrelBook Essentials")
                            .font(.headline)
                            .fontWeight(.semibold)

                        Text("Free tier includes 5 bottles & 2 tasting notes")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 16) {
                            UsageCounter(
                                label: "Bottles",
                                current: currentWhiskeyCount,
                                limit: subscriptionManager.whiskeyLimit,
                                icon: "🥃"
                            )

                            UsageCounter(
                                label: "Tastings",
                                current: currentTastingCount,
                                limit: subscriptionManager.tastingLimit,
                                icon: "📝"
                            )
                        }
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
                    .cornerRadius(16)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
            .fullScreenCover(isPresented: $showingPaywall) {
                PaywallView(isPresented: $showingPaywall)
            }
        }
    }
}

struct UsageCounter: View {
    let label: String
    let current: Int
    let limit: Int
    let icon: String
    
    private var isNearLimit: Bool {
        Double(current) / Double(limit) >= 0.8
    }
    
    var body: some View {
        HStack(spacing: 6) {
            Text(icon)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Text("\(current)/\(limit)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isNearLimit ? .orange : .primary)
            }
        }
    }
}
