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
        case whiskeyEdited   // Whiskey information edited
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
    @State private var selectedTab: TabSelection = .home
    @StateObject private var tabState = TabState.shared
    @StateObject private var navigationState = NavigationStateManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showingSettings = false
    @State private var statisticsShowingFilteredView = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Trial status banner - removed
            // TrialStatusBanner()
            
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
                SubscriptionGuardView(feature: "your whiskey collection") {
                    CollectionView()
                }
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Collection", systemImage: "square.grid.2x2")
            }
            .tag(TabSelection.collection)
            
            NavigationView {
                SubscriptionGuardView(feature: "your wishlist") {
                    WishlistView()
                }
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Wishlist", systemImage: "heart.fill")
            }
            .tag(TabSelection.wishlist)
            
            NavigationView {
                SubscriptionGuardView(feature: "tasting notes and journal entries") {
                    JournalView()
                }
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .tabItem {
                Label("Tastings", systemImage: "book")
            }
            .tag(TabSelection.journal)
            
            NavigationView {
                SubscriptionGuardView(feature: "advanced statistics and analytics") {
                    StatisticsView(showingFilteredView: $statisticsShowingFilteredView)
                }
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
        }
        .task {
            await subscriptionManager.updateSubscriptionStatus()
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
    
    @StateObject private var subscriptionManager = SubscriptionManager.shared
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
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Main Action Cards
                actionCardsSection
                
                // Recent Activity Section
                recentActivitySection
                
                // Quick Stats Section
                quickStatsSection
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
        .sheet(isPresented: $showingAddJournal) {
            // If a whiskey is selected, pre-select it for the journal entry
            if let whiskey = selectedWhiskey {
                AddJournalEntryView(preSelectedWhiskey: whiskey)
            } else {
                AddJournalEntryView()
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
            }
        )
    }
    
    // Main Action Cards Section
    private var actionCardsSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                // Add Whiskey Card
                ActionCard(
                    icon: "🥃", // Whiskey glass emoji
                    isEmoji: true,
                    title: "ADD NEW WHISKEY",
                    action: {
                        if subscriptionManager.hasAccess {
                            showingAddWhiskey = true
                        } else {
                            showingPaywall = true
                        }
                    }
                )
                
                // Add Tasting Card (renamed from Journal)
                ActionCard(
                    icon: "text.badge.plus",
                    isEmoji: false,
                    title: "ADD NEW TASTING",
                    action: {
                        if subscriptionManager.hasAccess {
                            showingAddJournal = true
                        } else {
                            showingPaywall = true
                        }
                    }
                )
            }
            
            // Wishlist Actions
            HStack(spacing: 16) {
                // View Wishlist
                ActionCard(
                    icon: "heart.fill",
                    isEmoji: false,
                    title: "VIEW WISHLIST",
                    action: {
                        if subscriptionManager.hasAccess {
                            selectedTab = .wishlist
                        } else {
                            showingPaywall = true
                        }
                    }
                )
                
                // Add to Wishlist
                ActionCard(
                    icon: "plus.circle",
                    isEmoji: false,
                    title: "ADD TO WISHLIST",
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
    
    // Format currency values
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
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
                    timeAgo: formatDate(addedDate),
                    date: addedDate,
                    whiskey: whiskey,
                    isJournal: false,
                    activityType: .whiskeyAdded
              ))
            }
        }
        
        // Add recently EDITED whiskeys (based on modificationDate)
        let recentlyEditedWhiskeys = whiskeys.filter { 
            $0.status == "owned" && 
            // Only include if modificationDate is different from addedDate (it's a true edit, not an add)
            ($0.modificationDate != $0.addedDate) 
        }
        .sorted { ($0.modificationDate ?? Date.distantPast) > ($1.modificationDate ?? Date.distantPast) }
        .prefix(3)
        
        for whiskey in recentlyEditedWhiskeys {
            let date = whiskey.modificationDate ?? Date()
            
            // Determine what changed based on the modification date
            var title = "Edited \(whiskey.name ?? "Unknown Whiskey")"
            var icon = "pencil.circle.fill"
            var isTastedToggle = false
            
            // Check for specific toggle changes
            if let lastModification = whiskey.modificationDate {
                // If the modification was very recent (within the last hour), try to determine what changed
                let oneHourAgo = Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()
                if lastModification > oneHourAgo {
                    // First, check if name was changed - we need to infer this from the history
                    if didNameChangeRecently(whiskey) {
                        title = "Renamed to: \(whiskey.name ?? "Unknown Whiskey")"
                        icon = "character.cursor.ibeam"
                    }
                    // Then check toggle properties only if name didn't change
                    else if whiskey.isOpen {
                        title = "Opened \(whiskey.name ?? "Unknown Whiskey")"
                        icon = "lock.open.fill"
                    } else if whiskey.isTasted {
                        title = "Marked as Tasted: \(whiskey.name ?? "Unknown Whiskey")"
                        icon = "checkmark.circle.fill"
                        isTastedToggle = true
                    }
                }
            }
            
            // Don't add tasted toggle as a separate whiskey edit activity
            // It will be added in the journal entries section
            if !isTastedToggle {
                activities.append(ActivityItem(
                    id: UUID(),
                    icon: icon,
                    title: title,
                    timeAgo: formatDate(date),
                    date: date,
                    whiskey: whiskey,
                    isJournal: false,
                    activityType: .whiskeyEdited
                ))
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
                            timeAgo: formatDate(mostRecentEntry.date ?? date),
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
                    timeAgo: formatDate(date),
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
                    timeAgo: formatDate(date),
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
    
    // Format date to dd/mm/yyyy
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter.string(from: date)
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
                        .foregroundColor(.blue)
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
    
    // Format PPP value
    private func formatPPP(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
    
    // Quick Stats Section
    private var quickStatsSection: some View {
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quick Stats")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button(action: {
                    TabState.shared.clearStatisticsActive()
                    withAnimation {
                        DispatchQueue.main.async {
                            selectedTab = .statistics
                        }
                    }
                }) {
                    Text("See All")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
            
            Divider()
                .padding(.bottom, 8)
            
            // Key Stats
            VStack(spacing: 12) {
                HStack {
                    Text("Collection:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    let currentWhiskeys = whiskeys.filter { $0.status == "owned" }
                    // Calculate total bottles using the numberOfBottles property which is more reliable
                    let totalBottles = currentWhiskeys.reduce(0) { total, whiskey in
                        return total + Int(whiskey.numberOfBottles)
                    }
                    Text("\(currentWhiskeys.count) whiskeys (\(totalBottles) bottles)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("Total Value:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    PrivacyAwareValueText(value: totalCollectionValue)
                }
                
                HStack {
                    Text("Avg PPP:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(formatPPP(calculateAveragePPP()))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("Tasted:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(countTastedWhiskeys()) bottles")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("Wishlist:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(getWishlistCountText())
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding()
        .background(ColorManager.background)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
    
    // Helper method to get wishlist count text
    private func getWishlistCountText() -> String {
        // Use the dedicated wishlist fetch request instead of filtering
        let count = wishlistWhiskeys.count
        print("ContentView: Using wishlist count = \(count)")
        return "\(count) whiskeys"
    }
    
    // Helper function to check if a whiskey's name was recently changed
    private func didNameChangeRecently(_ whiskey: Whiskey) -> Bool {
        // We don't have previous whiskey state to compare against, so we'll use some heuristics
        
        // 1. Check if any property toggles are enabled - less likely to be a rename operation
        if whiskey.isOpen || whiskey.isTasted || whiskey.isCaskStrength || 
           whiskey.isBiB || whiskey.isSiB || whiskey.isStorePick {
            // If the whiskey was just created (addedDate very close to modificationDate),
            // and these properties are set, it's more likely an addition with properties
            // than a rename
            if let addedDate = whiskey.addedDate, let modDate = whiskey.modificationDate {
                let hoursSinceAdded = Calendar.current.dateComponents([.hour], from: addedDate, to: modDate).hour ?? 0
                
                if hoursSinceAdded <= 1 {
                    // If modified within an hour of being added, more likely
                    // this is setting initial properties, not a rename
                    return false
                }
            }
        }
        
        // 2. Check journal entries - if the whiskey has journal entries with a different name
        // it suggests a rename
        if let entries = whiskey.journalEntries as? Set<JournalEntry>, !entries.isEmpty {
            for entry in entries {
                // Get the date when the entry was created
                let entryDate = entry.date ?? Date.distantPast
                let whiskeyCurrName = whiskey.name ?? ""
                
                // If the entry is old enough (created more than a day before the latest modification)
                if let modDate = whiskey.modificationDate,
                   let daysBetween = Calendar.current.dateComponents([.day], from: entryDate, to: modDate).day,
                   daysBetween > 0,
                   !whiskeyCurrName.isEmpty {
                    return true
                }
            }
        }
        
        // 3. If neither case above was triggered, we'll make a more reasonable guess
        // Instead of just checking if toggles are true, we'll consider several factors:
        
        // a. Has it been modified significantly after being added?
        if let addedDate = whiskey.addedDate, let modDate = whiskey.modificationDate {
            let daysSinceAdded = Calendar.current.dateComponents([.day], from: addedDate, to: modDate).day ?? 0
            
            // For bottles that have been in the collection for a while, name changes are more common
            if daysSinceAdded > 30 {
                // For older items, it's more likely to be a name correction/update
                return true
            }
        }
        
        // b. Does it look like a correction? (e.g., simple name changes often happen shortly after adding)
        if let name = whiskey.name, name.count > 3 {
            // Name is long enough to be a proper name - less likely to just be a typo correction
            // We'll err on the side of NOT showing rename notifications for minor edits
            return false
        }
        
        // c. Default to not showing rename notification when we can't be sure
        return false
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
    
    // Whiskey-themed color for icons only
    private let primaryColor = ColorManager.primaryBrandColor
    
    var body: some View {
        Button {
            HapticManager.shared.mediumImpact()
            action()
        } label: {
            VStack(spacing: 8) {
                // Icon - either emoji or SF Symbol
                if isEmoji {
                    Text(icon)
                        .font(.system(size: 32))
                        .padding(.top, 4)
                        .frame(height: 40)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 28))
                        .foregroundColor(primaryColor)
                        .padding(.top, 8)
                        .frame(height: 40)
                }
                
                // Action Button with standard iOS styling
                VStack {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity, minHeight: 110)
            .background(ColorManager.background)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
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
                    filterButton(type: .whiskeyEdited, label: "Edited")
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
                            timeAgo: formatDateString(addedDate),
                            date: addedDate,
                            whiskey: whiskey,
                            isJournal: false,
                            activityType: .whiskeyAdded
                        ))
                    }
                }
            }
            
            // For edited whiskeys (excluding the initial addition)
            let date = whiskey.modificationDate ?? Date()
            
            // Only include activities within the selected date range
            if let earliest = earliestDate, date < earliest {
                continue
            }
            
            // Apply activity type filter if one is selected
            if let filter = activityFilter, filter != .whiskeyAdded && filter != .whiskeyEdited {
                continue
            }
            
            // Skip if this is just the initial creation (addedDate is the same as modificationDate)
            if let addedDate = whiskey.addedDate, 
               Calendar.current.isDate(addedDate, inSameDayAs: date) {
                continue
            }
            
            // Determine what changed based on the modification date
            var title = "Edited \(whiskey.name ?? "Unknown Whiskey")"
            var icon = "pencil.circle.fill"
            var isTastedToggle = false
            
            // Check for specific toggle changes
            if let lastModification = whiskey.modificationDate {
                // If the modification was very recent (within the last hour), try to determine what changed
                let oneHourAgo = Calendar.current.date(byAdding: .hour, value: -1, to: Date()) ?? Date()
                if lastModification > oneHourAgo {
                    // First, check if name was changed - we need to infer this from the history
                    if didNameChangeRecently(whiskey) {
                        title = "Renamed to: \(whiskey.name ?? "Unknown Whiskey")"
                        icon = "character.cursor.ibeam"
                    }
                    // Then check toggle properties only if name didn't change
                    else if whiskey.isOpen {
                        title = "Opened \(whiskey.name ?? "Unknown Whiskey")"
                        icon = "lock.open.fill"
                    } else if whiskey.isTasted {
                        title = "Marked as Tasted: \(whiskey.name ?? "Unknown Whiskey")"
                        icon = "checkmark.circle.fill"
                        isTastedToggle = true
                    }
                }
            }
            
            // Don't add tasted toggle as a separate whiskey edit activity
            // It will be added in the journal entries section
            if !isTastedToggle {
                activities.append(ActivityItem(
                    id: UUID(),
                    icon: icon,
                    title: title,
                    timeAgo: formatDateString(date),
                    date: date,
                    whiskey: whiskey,
                    isJournal: false,
                    activityType: .whiskeyEdited
                ))
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
                            timeAgo: formatDateString(entry.date ?? date),
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
                    timeAgo: formatDateString(date),
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
                timeAgo: formatDateString(date),
                date: date,
                whiskey: whiskey,
                isJournal: false,
                activityType: .wishlistAdded
            ))
        }
        
        // Sort all activities by date, newest first
        return activities.sorted(by: { $0.date > $1.date })
    }
    
    // Format date to string
    private func formatDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter.string(from: date)
    }
    
    // Helper function to check if a whiskey's name was recently changed
    private func didNameChangeRecently(_ whiskey: Whiskey) -> Bool {
        // We don't have previous whiskey state to compare against, so we'll use some heuristics
        
        // 1. Check if any property toggles are enabled - less likely to be a rename operation
        if whiskey.isOpen || whiskey.isTasted || whiskey.isCaskStrength || 
           whiskey.isBiB || whiskey.isSiB || whiskey.isStorePick {
            // If the whiskey was just created (addedDate very close to modificationDate),
            // and these properties are set, it's more likely an addition with properties
            // than a rename
            if let addedDate = whiskey.addedDate, let modDate = whiskey.modificationDate {
                let hoursSinceAdded = Calendar.current.dateComponents([.hour], from: addedDate, to: modDate).hour ?? 0
                
                if hoursSinceAdded <= 1 {
                    // If modified within an hour of being added, more likely
                    // this is setting initial properties, not a rename
                    return false
                }
            }
        }
        
        // 2. Check journal entries - if the whiskey has journal entries with a different name
        // it suggests a rename
        if let entries = whiskey.journalEntries as? Set<JournalEntry>, !entries.isEmpty {
            for entry in entries {
                // Get the date when the entry was created
                let entryDate = entry.date ?? Date.distantPast
                let whiskeyCurrName = whiskey.name ?? ""
                
                // If the entry is old enough (created more than a day before the latest modification)
                if let modDate = whiskey.modificationDate,
                   let daysBetween = Calendar.current.dateComponents([.day], from: entryDate, to: modDate).day,
                   daysBetween > 0,
                   !whiskeyCurrName.isEmpty {
                    return true
                }
            }
        }
        
        // 3. If neither case above was triggered, we'll make a more reasonable guess
        // Instead of just checking if toggles are true, we'll consider several factors:
        
        // a. Has it been modified significantly after being added?
        if let addedDate = whiskey.addedDate, let modDate = whiskey.modificationDate {
            let daysSinceAdded = Calendar.current.dateComponents([.day], from: addedDate, to: modDate).day ?? 0
            
            // For bottles that have been in the collection for a while, name changes are more common
            if daysSinceAdded > 30 {
                // For older items, it's more likely to be a name correction/update
                return true
            }
        }
        
        // b. Does it look like a correction? (e.g., simple name changes often happen shortly after adding)
        if let name = whiskey.name, name.count > 3 {
            // Name is long enough to be a proper name - less likely to just be a typo correction
            // We'll err on the side of NOT showing rename notifications for minor edits
            return false
        }
        
        // c. Default to not showing rename notification when we can't be sure
        return false
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
                Text(formatCurrency(value))
                    .fontWeight(.semibold)
                
                if privacyManager.hidePrices && temporarilyShowValue {
                    Image(systemName: "timer")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // Format currency values
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
} 
