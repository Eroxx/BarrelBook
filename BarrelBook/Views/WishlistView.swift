import SwiftUI
import CoreData

// Wishlist-specific sort options
enum WishlistSortOption: String, CaseIterable, Codable {
    case nameAsc = "Name (A-Z)"
    case nameDesc = "Name (Z-A)"
    case priorityHigh = "Priority (High-Low)"
    case targetPriceLow = "Target Price (Low-High)"
    case targetPriceHigh = "Target Price (High-Low)"
    case rarityLow = "Rarity (Low-High)"
    case rarityHigh = "Rarity (High-Low)"
}

// Wishlist-specific filter options
struct WishlistFilterOptions {
    var selectedTypes: Set<String> = []
    var selectedPriorities: Set<Int> = [] // 1-5 star priorities
    var selectedRarities: Set<WhiskeyRarity> = []
    var targetPriceRange: ClosedRange<Double>? = nil
    
    var hasActiveFilters: Bool {
        return !selectedTypes.isEmpty || 
               !selectedPriorities.isEmpty || 
               !selectedRarities.isEmpty || 
               targetPriceRange != nil
    }
}

// Wishlist-specific filter view
struct WishlistFilterView: View {
    @Binding var filterOptions: WishlistFilterOptions
    let availableTypes: [String]
    let showingWhiskeyCount: Int
    let totalWhiskeyCount: Int
    @Environment(\.dismiss) private var dismiss
    
    @State private var targetPriceRange: ClosedRange<Double> = 0...1000
    @State private var isDraggingSlider = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Results")) {
                    HStack {
                        Text("Showing")
                        Spacer()
                        Text("\(showingWhiskeyCount) of \(totalWhiskeyCount)")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Priority (1-5 Stars)")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                        ForEach(1...5, id: \.self) { priority in
                            Button(action: {
                                if filterOptions.selectedPriorities.contains(priority) {
                                    filterOptions.selectedPriorities.remove(priority)
                                } else {
                                    filterOptions.selectedPriorities.insert(priority)
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Text("\(priority)")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                    Image(systemName: "star.fill")
                                        .font(.caption)
                                }
                                .foregroundColor(filterOptions.selectedPriorities.contains(priority) ? .white : .blue)
                                .frame(width: 50, height: 50)
                                .background(filterOptions.selectedPriorities.contains(priority) ? .blue : .clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(.blue, lineWidth: 1)
                                )
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section(header: Text("Rarity")) {
                    ForEach(WhiskeyRarity.allCases, id: \.self) { rarity in
                        HStack {
                            Image(systemName: filterOptions.selectedRarities.contains(rarity) ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(filterOptions.selectedRarities.contains(rarity) ? .blue : .secondary)
                            Text(rarity.displayName)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if filterOptions.selectedRarities.contains(rarity) {
                                filterOptions.selectedRarities.remove(rarity)
                            } else {
                                filterOptions.selectedRarities.insert(rarity)
                            }
                        }
                    }
                }
                
                Section("Target Price Range") {
                    HStack {
                        Text("$\(Int(targetPriceRange.lowerBound))")
                        Spacer()
                        Text(targetPriceRange.upperBound >= 1000 ? "$1000+" : "$\(Int(targetPriceRange.upperBound))")
                    }
                    
                    // Custom price range slider
                    PriceRangeSlider(range: $targetPriceRange, bounds: 0...1000, isDragging: $isDraggingSlider)
                        .frame(height: 30)
                        .padding(.vertical, 8)
                        .onChange(of: targetPriceRange) { newRange in
                            updatePriceFilter()
                        }
                }
                
                Section(header: Text("Type")) {
                    if availableTypes.isEmpty {
                        Text("No types available")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(availableTypes, id: \.self) { type in
                            HStack {
                                Image(systemName: filterOptions.selectedTypes.contains(type) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(filterOptions.selectedTypes.contains(type) ? .blue : .secondary)
                                Text(type)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if filterOptions.selectedTypes.contains(type) {
                                    filterOptions.selectedTypes.remove(type)
                                } else {
                                    filterOptions.selectedTypes.insert(type)
                                }
                            }
                        }
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        // Reset all filters
                        filterOptions.selectedTypes.removeAll()
                        filterOptions.selectedPriorities.removeAll()
                        filterOptions.selectedRarities.removeAll()
                        targetPriceRange = 0...1000
                        updatePriceFilter()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Reset All Filters")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Filter Wishlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Initialize price filter - always enabled, default to show all
                updatePriceFilter()
            }
        }
    }
    
    private func updatePriceFilter() {
        // Only apply price filter if the range is not the full default range
        if targetPriceRange.lowerBound == 0 && targetPriceRange.upperBound >= 1000 {
            // Default range - show all items
            filterOptions.targetPriceRange = nil
        } else {
            // Custom range - apply filter
            filterOptions.targetPriceRange = targetPriceRange
        }
    }
}

// Empty state view
struct WishlistEmptyStateView: View {
    let searchText: String
    let addAction: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            if !searchText.isEmpty {
                Text("No matching whiskeys found")
                    .foregroundColor(.secondary)
            } else {
                Text("Your wishlist is empty")
                    .foregroundColor(.secondary)
                Text("Add whiskeys you'd like to purchase")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
                
                Button(action: addAction) {
                    Label("Add to Wishlist", systemImage: "plus.circle.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// Search results count overlay
struct SearchResultsCountOverlay: View {
    let count: Int
    let shouldShow: Bool
    
    var body: some View {
        VStack {
            if shouldShow {
                Text("\(count) whiskeys found")
                    .font(.caption)
                    .padding(6)
                    .background(Color(.systemBackground).opacity(0.8))
                    .cornerRadius(8)
                    .shadow(radius: 2)
                    .padding(.top, 8)
            }
            Spacer()
        }
    }
}

// Main WishlistView
struct WishlistView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showingPaywall = false
    @State private var showingAddSheet = false
    @State private var showingFilterSheet = false
    @State private var showingSettings = false
    @State private var searchText = ""
    @State private var sortConfig = WishlistHierarchicalSortConfig(activeSorts: [WishlistSortCriterionIdentifiable(option: .nameAsc)])
    @State private var showingSortSheet = false
    @State private var debouncedSearchText = ""
    @State private var isUpdatingFiltersFromSearch = false
    @State private var wishlistFilterOptions = WishlistFilterOptions()
    @State private var showingDeleteConfirmation = false
    @State private var refreshTrigger = UUID()
    @State private var selectedWhiskey: Whiskey? = nil
    @State private var selectedTab = 0 // 0 for wishlist, 1 for replacements
    @State private var selectedStore: Store? = nil
    @State private var showingStorePicker = false
    @State private var showingNoStoresExplanation = false
    @AppStorage("hasSeenWishlistTutorial") private var hasSeenWishlistTutorial = false
    @State private var showingWishlistTutorialOverlay = false
    @State private var wishlistTutorialStep = 1
    @State private var showingShareSheet = false
    @State private var shareActivityVC: UIActivityViewController?
    
    // Status-specific FetchRequest for wishlist items
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Whiskey.name, ascending: true)],
        predicate: NSPredicate(format: "status == %@", WhiskeyStatus.wishlist.rawValue),
        animation: .default
    ) private var wishlistItems: FetchedResults<Whiskey>
    
    // FetchRequest for replacement items
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Whiskey.name, ascending: true)],
        predicate: NSPredicate(format: "replacementStatus == %@", "wantToReplace"),
        animation: .default
    ) private var replacementItems: FetchedResults<Whiskey>
    
    // Get filtered whiskeys
    private var filteredWhiskeys: [Whiskey] {
        var filtered = Array(wishlistItems)
        
        if let selectedStore = selectedStore {
            filtered = filtered.filter { whiskey in
                whiskey.stores?.contains(selectedStore) ?? false
            }
        }
        
        if !searchIsEmpty {
            filtered = filtered.filter { whiskey in
                searchMatches(whiskey)
            }
        }
        
        // Apply wishlist-specific filters
        if !wishlistFilterOptions.selectedTypes.isEmpty {
            filtered = filtered.filter { whiskey in
                wishlistFilterOptions.selectedTypes.contains(whiskey.type ?? "")
            }
        }
        
        if !wishlistFilterOptions.selectedPriorities.isEmpty {
            filtered = filtered.filter { whiskey in
                wishlistFilterOptions.selectedPriorities.contains(Int(whiskey.priority))
            }
        }
        
        if !wishlistFilterOptions.selectedRarities.isEmpty {
            filtered = filtered.filter { whiskey in
                let whiskey_rarity = WhiskeyRarity(rawValue: whiskey.rarity ?? "") ?? .notSure
                return wishlistFilterOptions.selectedRarities.contains(whiskey_rarity)
            }
        }
        
        if let priceRange = wishlistFilterOptions.targetPriceRange {
            filtered = filtered.filter { whiskey in
                priceRange.contains(whiskey.targetPrice)
            }
        }
        
        return filtered
    }
    
    // Helper properties to simplify filtering logic
    private var searchIsEmpty: Bool {
        return searchText.isEmpty
    }
    
    private func searchMatches(_ whiskey: Whiskey) -> Bool {
        let matches = (whiskey.name?.localizedCaseInsensitiveContains(searchText) ?? false) ||
               (whiskey.type?.localizedCaseInsensitiveContains(searchText) ?? false) ||
               (whiskey.distillery?.localizedCaseInsensitiveContains(searchText) ?? false) ||
               (whiskey.finish?.localizedCaseInsensitiveContains(searchText) ?? false) ||
               (whiskey.storePickName?.localizedCaseInsensitiveContains(searchText) ?? false) ||
               (whiskey.whereToFind?.localizedCaseInsensitiveContains(searchText) ?? false) ||
               (String(format: "%.1f", whiskey.proof).contains(searchText)) ||
               (String(whiskey.targetPrice).contains(searchText))
        return matches
    }
    
    // Removed old filtering helper functions - now using direct filtering logic in filteredWhiskeys
    
    // Sorted whiskeys using hierarchical sorting
    private var sortedWhiskeys: [Whiskey] {
        return SortingUtils.sortWishlistHierarchically(filteredWhiskeys, by: sortConfig)
    }
    
    // Get unique types for filter options
    private var uniqueTypes: [String] {
        var types = Set<String>()
        for whiskey in wishlistItems {
            if let type = whiskey.type, !type.isEmpty {
                types.insert(type)
            }
        }
        return Array(types).sorted()
    }
    
    // Check if results count should be shown
    private var shouldShowResultsCount: Bool {
        return !filteredWhiskeys.isEmpty && 
               (!searchText.isEmpty || wishlistFilterOptions.hasActiveFilters)
    }
    
    var body: some View {
        ZStack {
        VStack(spacing: 0) {
            // Tab selector
            Picker("", selection: $selectedTab) {
                Text("Wishlist").tag(0)
                Text("Replacements").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            // Store picker button
            if selectedTab == 0 {
                Button(action: {
                    showingStorePicker = true
                    HapticManager.shared.lightImpact()
                }) {
                    HStack {
                        Image(systemName: "storefront")
                        Text(selectedStore?.name ?? "All Stores")
                        if selectedStore != nil {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
            
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField(selectedTab == 0 ? "Search wishlist..." : "Search replacements...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            // Main content area
            if selectedTab == 0 {
                // Wishlist tab
                if wishlistItems.isEmpty && searchText.isEmpty {
                    WishlistEmptyStateView(searchText: searchText) {
                        if subscriptionManager.hasAccess {
                            showingAddSheet = true
                        } else {
                            showingPaywall = true
                        }
                    }
                } else {
                    List {
                        ForEach(sortedWhiskeys) { whiskey in
                            NavigationLink(destination: WhiskeyDetailView(whiskey: whiskey)) {
                                WishlistRowView(whiskey: whiskey)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    HapticManager.shared.mediumImpact()
                                    deleteWishlistItem(whiskey)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                
                                Button {
                                    HapticManager.shared.lightImpact()
                                    selectedWhiskey = whiskey
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                    .id(refreshTrigger) // Force List refresh when stores change
                }
            } else {
                // Replacements tab
                if replacementItems.isEmpty {
                    VStack(spacing: 16) {
                        Text("No bottles to replace")
                            .foregroundColor(.secondary)
                        Text("Mark bottles as 'Want to Replace' when finishing them")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    List {
                        ForEach(replacementItems) { whiskey in
                            NavigationLink(destination: WhiskeyDetailView(whiskey: whiskey)) {
                                ReplacementRowView(whiskey: whiskey)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    HapticManager.shared.mediumImpact()
                                    removeFromReplacements(whiskey)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
        }
            if showingWishlistTutorialOverlay {
                WishlistTutorialOverlay(step: wishlistTutorialStep, onNext: {
                    wishlistTutorialStep = 2
                    HapticManager.shared.lightImpact()
                }, onDismiss: {
                    hasSeenWishlistTutorial = true
                    showingWishlistTutorialOverlay = false
                    HapticManager.shared.lightImpact()
                })
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Wishlist")
                    .font(.headline)
                    .fontWeight(.bold)
                    // Hide title on iPad
                    .opacity(UIDevice.current.userInterfaceIdiom == .pad ? 0 : 1)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 12) {
                    // Filter button
                    Button {
                        showingFilterSheet = true
                        HapticManager.shared.mediumImpact()
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    
                    // Sort button
                    Button {
                        showingSortSheet = true
                        HapticManager.shared.mediumImpact()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                            if sortConfig.activeSorts.count > 1 {
                                Text("\(sortConfig.activeSorts.count)")
                                    .font(.caption2)
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
                // Hide sort/filter buttons on iPad
                .opacity(UIDevice.current.userInterfaceIdiom == .pad ? 0 : 1)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    // Share button
                    Button(action: {
                        shareCurrentList()
                        HapticManager.shared.lightImpact()
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(selectedTab == 0 ? wishlistItems.isEmpty : replacementItems.isEmpty)
                    
                    // Settings button
                    Button(action: {
                        showingSettings = true
                        HapticManager.shared.lightImpact()
                    }) {
                        Image(systemName: "gear")
                    }
                }
                // Only show these buttons on iPhone, not on iPad
                .opacity(UIDevice.current.userInterfaceIdiom == .pad ? 0 : 1)
            }
        }
        .overlay(
            Group {
                if selectedTab == 0 && (!sortedWhiskeys.isEmpty || !searchText.isEmpty) {
                    FloatingAddButton {
                        if subscriptionManager.hasAccess {
                            showingAddSheet = true
                        } else {
                            showingPaywall = true
                        }
                    }
                }
            }
        )
        .sheet(item: $selectedWhiskey) { whiskey in
            EditWishlistItemView(whiskey: whiskey)
        }
        .sheet(isPresented: $showingAddSheet, onDismiss: {
            viewContext.refreshAllObjects()
        }) {
            AddWhiskeyToWishlistView()
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(isPresented: $showingSortSheet) {
            WishlistHierarchicalSortPickerView(sortConfig: $sortConfig)
        }
        .sheet(isPresented: $showingFilterSheet) {
            WishlistFilterView(
                filterOptions: $wishlistFilterOptions,
                availableTypes: uniqueTypes,
                showingWhiskeyCount: filteredWhiskeys.count,
                totalWhiskeyCount: selectedTab == 0 ? wishlistItems.count : replacementItems.count
            )
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallView(isPresented: $showingPaywall)
        }
        .sheet(isPresented: Binding(
            get: { showingShareSheet && shareActivityVC != nil },
            set: { newValue in 
                showingShareSheet = newValue
                if !newValue {
                    shareActivityVC = nil
                }
            }
        )) {
            if let shareActivityVC = shareActivityVC {
                ShareSheet(activityViewController: shareActivityVC)
            } else {
                // Fallback view to prevent blank screen
                VStack {
                    Text("Preparing to share...")
                        .font(.headline)
                        .padding()
                    
                    Button("Close") {
                        showingShareSheet = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
        }
        .sheet(isPresented: $showingStorePicker) {
            let pickerStores = Array(Set(wishlistItems.flatMap { $0.stores?.allObjects as? [Store] ?? [] }))
            NavigationView {
                List {
                    Button("All Stores") {
                        selectedStore = nil
                        showingStorePicker = false
                    }
                    .foregroundColor(.primary)
                    
                    ForEach(pickerStores, id: \.self) { store in
                        Button(store.name ?? "Unnamed Store") {
                            selectedStore = store
                            showingStorePicker = false
                        }
                        .foregroundColor(.primary)
                    }
                }
                .navigationTitle("Select Store")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingStorePicker = false
                        }
                    }
                }
            }
            .onAppear {
                if pickerStores.isEmpty {
                    showingNoStoresExplanation = true
                }
            }
            .onDisappear {
                showingNoStoresExplanation = false
            }
            .alert("No stores yet", isPresented: $showingNoStoresExplanation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Stores appear here when you add them to wishlist items. When adding or editing a bottle, use \"Where to Find\" to add one or more stores.")
            }
        }
        .onAppear {
            if !hasSeenWishlistTutorial {
                showingWishlistTutorialOverlay = true
                wishlistTutorialStep = 1
            }
            
            // Reset filters to default state
            wishlistFilterOptions = WishlistFilterOptions()
            
            // Fetch all whiskeys to check their status
            let fetchRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
            do {
                let allWhiskeys = try viewContext.fetch(fetchRequest)
                
                for whiskey in allWhiskeys {
                }
                
                // Fetch only wishlist items
                let wishlistFetch: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
                wishlistFetch.predicate = NSPredicate(format: "status == %@", "wishlist")
                let wishlistResults = try viewContext.fetch(wishlistFetch)

                

                
            } catch {
                // Silent error handling - could log to crash reporting service
            }
            
            // Refresh all objects
            viewContext.refreshAllObjects()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("WishlistUpdated"))) { _ in
            // Force immediate UI update
            DispatchQueue.main.async {
                // Refresh all objects and their relationships
                viewContext.refreshAllObjects()
                
                // Force refresh of all whiskey objects and their store relationships
                for whiskey in wishlistItems {
                    viewContext.refresh(whiskey, mergeChanges: true)
                }
                
                // Reset filters and trigger view refresh
                wishlistFilterOptions = WishlistFilterOptions()
                refreshTrigger = UUID()
            }
        }
    }
    
    private func deleteWishlistItem(_ whiskey: Whiskey) {
        withAnimation {
            // Track the deletion in CSVSyncService
            CSVSyncService.shared.trackDeletedWhiskey(whiskey)
            
            viewContext.delete(whiskey)
            
            do {
                try viewContext.save()
                HapticManager.shared.successFeedback()
            } catch {
                HapticManager.shared.errorFeedback()
                print("Error deleting whiskey: \(error)")
            }
        }
    }
    
    private func convertToOwned(_ whiskey: Whiskey) {
        withAnimation {
            whiskey.statusEnum = .owned
            whiskey.modificationDate = Date()
            
            do {
                try viewContext.save()
                HapticManager.shared.successFeedback()
            } catch {
                HapticManager.shared.errorFeedback()
                print("Error converting whiskey to owned: \(error)")
            }
        }
    }
    
    private func removeFromReplacements(_ whiskey: Whiskey) {
        withAnimation {
            whiskey.replacementStatus = "none"
            try? viewContext.save()
        }
    }
    
    private func shareCurrentList() {
        // Ensure we're on the main thread
        DispatchQueue.main.async {
            if selectedTab == 0 {
                // Share wishlist
                let whiskeyArray = Array(filteredWhiskeys)
                WishlistSharingService.shared.shareWishlist(whiskeyArray) { activityVC in
                    DispatchQueue.main.async {
                        shareActivityVC = activityVC
                        showingShareSheet = true
                    }
                }
            } else {
                // Share replacements
                let replacementArray = Array(replacementItems)
                WishlistSharingService.shared.shareReplacements(replacementArray) { activityVC in
                    DispatchQueue.main.async {
                        shareActivityVC = activityVC
                        showingShareSheet = true
                    }
                }
            }
        }
    }
}

// MARK: - Wishlist tutorial (screen 1: general, screen 2: Stores)

private struct WishlistTutorialOverlay: View {
    let step: Int
    let onNext: () -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        ColorManager.tutorialScrim
            .ignoresSafeArea()
            .onTapGesture { }
        if step == 1 {
            wishlistGeneralScreen(onNext: onNext)
        } else {
            StoresTutorialOverlay(onDismiss: onDismiss, useParentScrim: true)
        }
    }
    
    private func wishlistGeneralScreen(onNext: @escaping () -> Void) -> some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "list.star")
                        .font(.title2)
                        .foregroundColor(ColorManager.primaryBrandColor)
                    Text("Your Wishlist")
                        .font(.headline)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text(LocalizedStringKey("Track bottles you’re hunting for. Add name, target price, and priority; tap **Save** when you’re done."))
                    Text("You can filter by store, sort, and edit or remove items anytime.")
                        .font(.subheadline)
                }
                .font(.subheadline)
            }
            .padding(24)
            .background(Color(UIColor.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(ColorManager.tutorialCardBorder, lineWidth: 1)
            )
            .cornerRadius(16)
            .shadow(radius: 12)
            .padding(.horizontal, 24)
            Button(action: onNext) {
                Text("Next")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(ColorManager.primaryBrandColor)
            .padding(.horizontal, 24)
                    }
                    .padding()
                    Spacer(minLength: 0)
                }
                .frame(minHeight: geometry.size.height)
            }
            .padding()
        }
    }
}

// New view for replacement items
struct ReplacementRowView: View {
    let whiskey: Whiskey
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Top row: Name
            HStack {
                Text(whiskey.name ?? "Unnamed Whiskey")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
            }
            
            // Middle row: Proof, Type, Distillery
            HStack(spacing: 8) {
                if whiskey.proof > 0 {
                    Text("\(Int(whiskey.proof)) Proof")
                }
                
                if whiskey.proof > 0 && (whiskey.type?.isEmpty == false) {
                    Text("•")
                }
                
                if let type = whiskey.type, !type.isEmpty {
                    Text(type)
                }
                
                if let type = whiskey.type, !type.isEmpty,
                   let distillery = whiskey.distillery, !distillery.isEmpty {
                    Text("•")
                    Text(distillery)
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            
            // Special tags row - check each attribute individually
            if whiskey.isBiB || whiskey.isSiB || whiskey.isStorePick || whiskey.isCaskStrength {
                HStack(spacing: 8) {
                    if whiskey.isBiB {
                        Text("BiB")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(red: 0.8, green: 0.6, blue: 0.3).opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    if whiskey.isSiB {
                        Text("SiB")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    if whiskey.isStorePick {
                        if let name = whiskey.storePickName, !name.isEmpty {
                            Text("SP: \(name)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.2))
                                .cornerRadius(4)
                        } else {
                            Text("SP")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.purple.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    
                    if whiskey.isCaskStrength {
                        Text("CS")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                .padding(.top, 2)
            }
            
            // Last price paid
            if whiskey.price > 0 {
                Text("Last Price: \(String(format: "$%.2f", whiskey.price))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// Preview
struct WishlistView_Previews: PreviewProvider {
    static var previews: some View {
        WishlistView()
    }
} 