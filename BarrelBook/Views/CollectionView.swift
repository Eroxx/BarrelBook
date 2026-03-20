import SwiftUI
import CoreData
import Foundation

enum SortOption: String, CaseIterable, Codable {
    case nameAsc = "Name (A-Z)"
    case nameDesc = "Name (Z-A)"
    case proofHigh = "Proof (High-Low)"
    case proofLow = "Proof (Low-High)"
    case priceHigh = "Price (High-Low)"
    case priceLow = "Price (Low-High)"
    case typeAsc = "Type (A-Z)"
    case ageDesc = "Age (High-Low)"
    case ageAsc = "Age (Low-High)"
    case openFirst = "Open First"
    case sealedFirst = "Sealed First"
    case dateAdded = "Recently Added"
}

// Define price range options
enum PriceRangeOption: String, CaseIterable, Identifiable, Equatable {
    case all = "All Prices"
    case budget = "Budget ($0-$30)"
    case midRange = "Mid-Range ($30-$70)"
    case premium = "Premium ($70-$150)"
    case ultraPremium = "Ultra Premium ($150+)"
    
    var id: String { rawValue }
    
    var range: (min: Double, max: Double) {
        switch self {
        case .all:
            return (0, Double.infinity)
        case .budget:
            return (0, 30)
        case .midRange:
            return (30, 70)
        case .premium:
            return (70, 150)
        case .ultraPremium:
            return (150, Double.infinity)
        }
    }
}

// Define a three-state toggle option
enum ToggleState: String, CaseIterable, Equatable {
    case all = "All"       // Show all items, regardless of the attribute
    case yes = "Yes"       // Only show items with this attribute
    case no = "No"         // Only show items without this attribute
    
    var nextState: ToggleState {
        switch self {
        case .all: return .yes
        case .yes: return .no
        case .no: return .all
        }
    }
}

struct FilterOptions: Equatable {
    var selectedTypes: Set<String> = []
    // Convert boolean filters to three-state toggles
    var bibState: ToggleState = .all
    var sibState: ToggleState = .all
    var storePickState: ToggleState = .all
    var openState: ToggleState = .all
    var finishState: ToggleState = .all
    var deadBottleState: ToggleState = .no // Default to hide dead bottles
    var reviewState: ToggleState = .all // New filter for reviews
    var tastedState: ToggleState = .all // New filter for tasted status
    
    // Legacy boolean properties for backwards compatibility
    var isBiB: Bool {
        get { bibState != .no }
        set { bibState = newValue ? .all : .no }
    }
    
    var isSiB: Bool {
        get { sibState != .no }
        set { sibState = newValue ? .all : .no }
    }
    
    var isStorePick: Bool {
        get { storePickState != .no }
        set { storePickState = newValue ? .all : .no }
    }
    
    var isOpen: Bool {
        get { openState != .no }
        set { openState = newValue ? .all : .no }
    }
    
    var hasFinish: Bool {
        get { finishState != .no }
        set { finishState = newValue ? .all : .no }
    }
    
    var includeDeadBottles: Bool {
        get { deadBottleState != .no }
        set { deadBottleState = newValue ? .all : .no }
    }
    
    var hasReviews: Bool {
        get { reviewState != .no }
        set { reviewState = newValue ? .all : .no }
    }
    
    var isTasted: Bool {
        get { tastedState != .no }
        set { tastedState = newValue ? .all : .no }
    }
    
    var proofRange: ClosedRange<Double>? = nil
    var ageRange: ClosedRange<Int>? = nil
    var priceRangeOption: PriceRangeOption = .all
    var customPriceRange: ClosedRange<Double>? = nil
}

struct SectionIndexModifier: ViewModifier {
    let proxy: ScrollViewProxy
    let alphabet: [Character]
    let filteredWhiskeys: [(key: String, whiskeys: [Whiskey])]
    let primarySortOption: SortOption?
    
    init(proxy: ScrollViewProxy, alphabet: [Character], filteredWhiskeys: [(key: String, whiskeys: [Whiskey])], primarySortOption: SortOption?) {
        self.proxy = proxy
        self.alphabet = alphabet
        self.filteredWhiskeys = filteredWhiskeys
        self.primarySortOption = primarySortOption
    }
    
    func body(content: Content) -> some View {
        if primarySortOption == .nameAsc || primarySortOption == .nameDesc {
            // Only show alphabet bar for name-based sorts
            return AnyView(
                ZStack {
                    content
                    
                    if !filteredWhiskeys.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(alphabet, id: \.self) { letter in
                                let letterStr = String(letter)
                                let exists = filteredWhiskeys.contains { $0.key == letterStr }
                                
                                Button {
                                    if exists {
                                        withAnimation {
                                            proxy.scrollTo(letterStr, anchor: .top)
                                            HapticManager.shared.selectionFeedback()
                                        }
                                    }
                                } label: {
                                    Text(letterStr)
                                        .font(.system(size: 11, weight: .medium))
                                        .frame(width: 16, height: 14)
                                        .foregroundColor(exists ? .accentColor : .gray)
                                        .opacity(exists ? 1 : 0.6)
                                }
                                .disabled(!exists)
                            }
                        }
                        .padding(.vertical, 5)
                        .frame(maxHeight: .infinity, alignment: .center)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 5)
                    }
                }
            )
        } else {
            // For other sorts, return only the content with no alphabet sidebar
            return AnyView(content)
        }
    }
}

struct CollectionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showingPaywall = false
    @State private var showingAddSheet = false
    @State private var showingFilterSheet = false
    @State private var showingSettings = false
    @State private var searchText = ""
    @State private var sortConfig = HierarchicalSortConfig(activeSorts: [SortCriterionIdentifiable(option: .nameAsc)])
    @State private var showingSortSheet = false
    @State private var debouncedSearchText = ""
    @State private var isUpdatingFiltersFromSearch = false
    @State private var searchDebounceTimer: Timer?
    @State private var filterOptions = FilterOptions()
    @State private var showingDeleteConfirmation = false
    @State private var refreshTrigger = UUID()
    @State private var filterUpdateTrigger = UUID()
    @State private var selectedWhiskey: Whiskey? = nil
    @State private var selectedTab = 0 // 0 for wishlist, 1 for replacements
    @State private var filteredWhiskeys: [Whiskey] = []
    
    // FetchRequest for collection items
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Whiskey.name, ascending: true)],
        predicate: NSPredicate(format: "status == %@", WhiskeyStatus.owned.rawValue),
        animation: .default
    ) private var collectionItems: FetchedResults<Whiskey>
    
    // Fetch request for infinity bottles
    @FetchRequest(
        entity: InfinityBottle.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \InfinityBottle.name, ascending: true)
        ]
    ) private var infinityBottles: FetchedResults<InfinityBottle>
    
    // New state variables for search results view
    @State private var showingSearchResults = false
    @State private var searchPerformed = false
    
    // New state variable for collection view mode
    @State private var viewMode: CollectionViewMode = .whiskeys
    
    // State for showing add infinity bottle view
    @State private var showingAddInfinityBottle = false
    @AppStorage("hasSeenCollectionTutorial") private var hasSeenCollectionTutorial = false
    @State private var showingCollectionTutorialOverlay = false
    @AppStorage("hasSeenEmptyCollectionTutorial") private var hasSeenEmptyCollectionTutorial = false
    @State private var showingEmptyCollectionTutorialOverlay = false
    
    // Add a new state object to track updates
    @StateObject private var viewStateUpdater = ViewStateUpdater()
    
    // All possible letters that could appear
    private let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    
    private var availableTypes: [String] {
        Array(Set(collectionItems.compactMap { $0.type })).sorted()
    }
    
    private var lowestProof: Double {
        collectionItems.min(by: { $0.proof < $1.proof })?.proof ?? 80
    }
    
    private var highestProof: Double {
        collectionItems.max(by: { $0.proof < $1.proof })?.proof ?? 160
    }
    
    // Function to update filtered whiskeys - called only when needed
    private func updateFilteredWhiskeys() {
        let filtered = filterWhiskeys()
        filteredWhiskeys = filtered
        
        // Force UI update by triggering a refresh
        DispatchQueue.main.async {
            refreshTrigger = UUID()
        }
    }
    
    // Separated filtering logic
    private func filterWhiskeys() -> [Whiskey] {
        // TEMPORARY: Debug mode - show all collection items without filtering
        let debugMode = false  // Turned off - search debouncing implemented
        if debugMode {
            print("🚨 DEBUG MODE: Bypassing all filters, showing all \(collectionItems.count) collection items")
            return Array(collectionItems)
        }
        
        let filtered = collectionItems.filter { whiskey in
            let matchesSearch = debouncedSearchText.isEmpty || 
                (whiskey.name?.localizedCaseInsensitiveContains(debouncedSearchText) ?? false) ||
                (whiskey.type?.localizedCaseInsensitiveContains(debouncedSearchText) ?? false) ||
                (whiskey.distillery?.localizedCaseInsensitiveContains(debouncedSearchText) ?? false) ||
                (whiskey.finish?.localizedCaseInsensitiveContains(debouncedSearchText) ?? false) ||
                (whiskey.storePickName?.localizedCaseInsensitiveContains(debouncedSearchText) ?? false) ||
                (String(format: "%.1f", whiskey.proof).contains(debouncedSearchText)) ||
                (whiskey.age?.localizedCaseInsensitiveContains(debouncedSearchText) ?? false)
            
            // Type filtering: if no types are selected, show all whiskeys
            // If types are selected, only show those types
            let matchesType = filterOptions.selectedTypes.isEmpty || 
                (whiskey.type != nil && filterOptions.selectedTypes.contains(whiskey.type!))
            
            // Special attribute filtering - updated for three-state toggles
            let matchesBiB: Bool
            switch filterOptions.bibState {
            case .all: matchesBiB = true  // Show all whiskeys regardless of BIB status
            case .yes: matchesBiB = whiskey.isBiB  // Only show BIB whiskeys
            case .no: matchesBiB = !whiskey.isBiB  // Only show non-BIB whiskeys
            }
            
            let matchesSiB: Bool
            switch filterOptions.sibState {
            case .all: matchesSiB = true  // Show all whiskeys regardless of SIB status
            case .yes: matchesSiB = whiskey.isSiB  // Only show SIB whiskeys
            case .no: matchesSiB = !whiskey.isSiB  // Only show non-SIB whiskeys
            }
            
            let matchesStorePick: Bool
            switch filterOptions.storePickState {
            case .all: matchesStorePick = true  // Show all whiskeys regardless of store pick status
            case .yes: matchesStorePick = whiskey.isStorePick  // Only show store picks
            case .no: matchesStorePick = !whiskey.isStorePick  // Only show non-store picks
            }
            
            let matchesOpen: Bool
            switch filterOptions.openState {
            case .all: matchesOpen = true  // Show all whiskeys regardless of open status
            case .yes: matchesOpen = whiskey.isOpen  // Only show open bottles
            case .no: matchesOpen = !whiskey.isOpen  // Only show sealed bottles
            }
            
            // Finish filtering - only include finished bottles based on the state
            let matchesFinish: Bool
            let hasFinish = whiskey.finish != nil && !whiskey.finish!.isEmpty
            switch filterOptions.finishState {
            case .all: matchesFinish = true  // Show all whiskeys regardless of finish
            case .yes: matchesFinish = hasFinish  // Only show bottles with finish
            case .no: matchesFinish = !hasFinish  // Only show bottles without finish
            }
            
            // Dead bottle filtering - using three-way toggle state
            let matchesDeadBottle: Bool
            switch filterOptions.deadBottleState {
            case .all: matchesDeadBottle = true  // Show all whiskeys regardless of dead status
            case .yes: matchesDeadBottle = whiskey.isCompletelyDead  // ONLY show whiskeys where ALL bottles are dead
            case .no: matchesDeadBottle = whiskey.hasActiveBottles  // Only show whiskeys with at least 1 active bottle
            }
            
            // Review filtering - check if the whiskey has any web content reviews
            let matchesReviews: Bool
            let hasReviews = whiskey.webContent?.count ?? 0 > 0
            switch filterOptions.reviewState {
            case .all: matchesReviews = true  // Show all whiskeys regardless of reviews
            case .yes: matchesReviews = hasReviews  // Only show whiskeys with reviews
            case .no: matchesReviews = !hasReviews  // Only show whiskeys without reviews
            }
            
            // Tasted filtering - check both journal entries and isTasted flag
            let matchesTasted: Bool
            let hasJournalEntries = (whiskey.journalEntries?.count ?? 0) > 0
            let isMarkedAsTasted = whiskey.isTasted
            let isTasted = hasJournalEntries || isMarkedAsTasted
            switch filterOptions.tastedState {
            case .all: matchesTasted = true  // Show all whiskeys regardless of tasted status
            case .yes: matchesTasted = isTasted  // Only show tasted whiskeys
            case .no: matchesTasted = !isTasted  // Only show untasted whiskeys
            }
            
            // Add price range filtering
            let priceRange = filterOptions.priceRangeOption.range
            let matchesPriceRange: Bool
            
            if let customRange = filterOptions.customPriceRange {
                // Use custom range if set - handle zero-priced whiskeys
                if whiskey.price == 0 {
                    // Skip whiskeys with no price when filtering by price
                    matchesPriceRange = false
                } else {
                    matchesPriceRange = whiskey.price >= customRange.lowerBound && 
                        (customRange.upperBound == Double.infinity || whiskey.price <= customRange.upperBound)
                }
            } else {
                // Use predefined range
                if filterOptions.priceRangeOption == .all {
                    matchesPriceRange = true  // Show all whiskeys including those with no price
                } else if whiskey.price == 0 {
                    // Skip whiskeys with no price when filtering by specific price ranges
                    matchesPriceRange = false 
                } else {
                    matchesPriceRange = whiskey.price >= priceRange.min && 
                        (priceRange.max == Double.infinity || whiskey.price <= priceRange.max)
                }
            }
            
            // Proof range filtering
            let matchesProofRange: Bool
            if let proofRange = filterOptions.proofRange {
                matchesProofRange = whiskey.proof >= proofRange.lowerBound && whiskey.proof <= proofRange.upperBound
            } else {
                matchesProofRange = true
            }
            
            return matchesSearch && matchesType && matchesBiB && matchesSiB && matchesStorePick && matchesOpen && 
                   matchesPriceRange && matchesProofRange && matchesDeadBottle && matchesFinish && matchesReviews && matchesTasted
        }
        
        return filtered
    }
    
    // Computed property for sorted and grouped whiskeys
    private var filteredAndSortedWhiskeysByLetter: [(key: String, whiskeys: [Whiskey])] {
        // Use hierarchical sorting
        let sorted = SortingUtils.sortWhiskeysHierarchically(filteredWhiskeys, by: sortConfig)
        
        // Group by first letter if the primary sort is name-based
        if let firstSort = sortConfig.activeSorts.first?.option,
           firstSort == .nameAsc || firstSort == .nameDesc {
            let grouped = Dictionary(grouping: sorted) { whiskey in
                String(whiskey.name?.prefix(1).uppercased() ?? "#")
            }
            return grouped.map { (key: $0.key, whiskeys: $0.value) }
                .sorted { $0.key < $1.key }
        } else {
            // For other sorts, return as single section
            return [("All Whiskeys", sorted)]
        }
    }
    
    // Initialize filter options with all available types when the view appears
    private func initializeFilterOptions() {
        // Load saved filter settings or initialize with defaults
        let savedFilterOptions = FilterSettingsManager.loadFilterOptions()
        
        // Always start with saved settings
        filterOptions = savedFilterOptions
        
        // Ensure that if no types are saved, we select all available types
        if filterOptions.selectedTypes.isEmpty {
            filterOptions.selectedTypes = Set(availableTypes)
            // Save this default selection so it persists
            FilterSettingsManager.saveFilterOptions(filterOptions)
        }
        
        // Also load the saved sort config (for now, using legacy single-sort as default)
        let savedSort = FilterSettingsManager.loadCurrentSort()
        sortConfig = HierarchicalSortConfig(activeSorts: [SortCriterionIdentifiable(option: savedSort)])
    }
    
    @State private var shouldMaintainNavigation = false
    @State private var notificationObserver: Any? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ZStack {
                    VStack(spacing: 0) {
                        // Add search bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            
                            TextField("Search collection...", text: $searchText)
                                .disableAutocorrection(true)
                            
                            // Show debouncing indicator when search is being processed
                            if isUpdatingFiltersFromSearch && !searchText.isEmpty {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 20, height: 20)
                            } else if !searchText.isEmpty {
                                Button(action: {
                                    searchText = ""
                                    debouncedSearchText = ""
                                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        
                        // View mode segmented control
                        Picker("View Mode", selection: $viewMode) {
                            Text("Whiskeys").tag(CollectionViewMode.whiskeys)
                            Text("Infinity Bottles").tag(CollectionViewMode.infinityBottles)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        
                        if viewMode == .whiskeys {
                            // Totals summary for whiskeys
                            HStack {
                                let currentWhiskeys = filteredAndSortedWhiskeysByLetter.flatMap { $0.whiskeys }
                                // Calculate total bottles directly from each whiskey's numberOfBottles property
                                // rather than counting bottle instances, which may be inconsistent
                                let totalBottles = currentWhiskeys.reduce(0) { total, whiskey in
                                    return total + Int(whiskey.numberOfBottles)
                                }
                                let currentValue = currentWhiskeys.reduce(0.0) { $0 + ($1.price * Double($1.numberOfBottles)) }
                                
                                // Show both unique whiskeys and total bottles
                                Text("\(currentWhiskeys.count) whiskeys (\(totalBottles) bottles)")
                                    .foregroundColor(.secondary)
                                Text("•")
                                    .foregroundColor(.secondary)
                                PrivacyAwareValueText(value: currentValue)
                            }
                            .font(.footnote)
                            .padding(.horizontal)
                            .padding(.bottom, 4)
                            
                            // Show whiskey collection
                            let isEmpty = filteredAndSortedWhiskeysByLetter.isEmpty || filteredAndSortedWhiskeysByLetter.allSatisfy { $0.whiskeys.isEmpty }
                            
                            if isEmpty {
                                // Empty state
                                VStack(spacing: 20) {
                                    Image(systemName: "cabinet")
                                        .font(.system(size: 52, weight: .thin))
                                        .foregroundColor(ColorManager.primaryBrandColor.opacity(0.55))

                                    if collectionItems.isEmpty {
                                        // Truly empty shelf
                                        VStack(spacing: 8) {
                                            Text("Your shelf is empty")
                                                .font(.title3)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary)
                                            Text("Add your first bottle to get started")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                                .multilineTextAlignment(.center)
                                        }
                                    } else {
                                        // Filters returned nothing
                                        VStack(spacing: 8) {
                                            Text("No whiskeys match")
                                                .font(.title3)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary)
                                            Text("Try adjusting your search or filters")
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                        Button {
                                            resetFiltersToDefault()
                                            HapticManager.shared.mediumImpact()
                                        } label: {
                                            Text("Reset Filters")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 24)
                                                .padding(.vertical, 10)
                                                .background(ColorManager.primaryBrandColor)
                                                .cornerRadius(10)
                                        }
                                    }
                                }
                                .padding(40)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(UIColor.systemGroupedBackground))
                            } else if let firstSort = sortConfig.activeSorts.first?.option,
                                      firstSort == .nameAsc || firstSort == .nameDesc {
                                // For name-based sorts, use sections with index
                                List {
                                    // Use sections with alphabetical headers for name-based sorts
                                    ForEach(filteredAndSortedWhiskeysByLetter, id: \.key) { section in
                                        Section {
                                            ForEach(section.whiskeys) { whiskey in
                                                NavigationLink {
                                                    WhiskeyDetailView(whiskey: whiskey)
                                                } label: {
                                                    WhiskeyRowView(whiskey: whiskey)
                                                }
                                            }
                                            .onDelete { indices in
                                                deleteWhiskeys(from: section.whiskeys, at: indices)
                                            }
                                        } header: {
                                            Text(section.key)
                                                .id(section.key)
                                        }
                                    }
                                }
                                .listStyle(.plain)
                                .modifier(SectionIndexModifier(proxy: scrollProxy, alphabet: alphabet, filteredWhiskeys: filteredAndSortedWhiskeysByLetter, primarySortOption: sortConfig.activeSorts.first?.option))
                            } else {
                                // For other sorts, use a flat list with no alphabet index
                                List {
                                    // For non-name sorts, use a flat list with no sections or headers
                                    ForEach(filteredAndSortedWhiskeysByLetter, id: \.key) { section in
                                        ForEach(section.whiskeys) { whiskey in
                                            NavigationLink {
                                                WhiskeyDetailView(whiskey: whiskey)
                                            } label: {
                                                WhiskeyRowView(whiskey: whiskey)
                                            }
                                        }
                                        .onDelete { indices in
                                            deleteWhiskeys(from: section.whiskeys, at: indices)
                                        }
                                    }
                                }
                                .listStyle(.plain)
                                // No modifier for non-name sorts
                            }
                        } else {
                            // Show infinity bottles
                            InfinityBottlesView(infinityBottles: infinityBottles)
                        }
                    }
                    
                    // Navigation link to search results view (only for whiskey mode)
                    if viewMode == .whiskeys {
                        NavigationLink(
                            destination: SearchResultsView(
                                searchQuery: searchText,
                                whiskeys: Array(collectionItems)
                            ),
                            isActive: $showingSearchResults
                        ) {
                            EmptyView()
                        }
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Collection")
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
                Button(action: {
                    showingSettings = true
                    HapticManager.shared.lightImpact()
                }) {
                    Image(systemName: "gear")
                }
                // Only show this settings icon on iPhone, not on iPad
                .opacity(UIDevice.current.userInterfaceIdiom == .pad ? 0 : 1)
            }
        }
        .sheet(isPresented: $showingSortSheet) {
            HierarchicalSortPickerView(sortConfig: $sortConfig)
        }
        .sheet(isPresented: $showingFilterSheet) {
            WhiskeyFilterView(
                filterOptions: $filterOptions, 
                availableTypes: availableTypes,
                showingWhiskeyCount: filteredAndSortedWhiskeysByLetter.reduce(0) { $0 + $1.whiskeys.count },
                totalWhiskeyCount: collectionItems.count,
                lowestProof: lowestProof,
                highestProof: highestProof,
                onFilterChanged: {
                    // Trigger immediate update when filters change
                    DispatchQueue.main.async {
                        filterUpdateTrigger = UUID()
                    }
                }
            )
        }
        .onChange(of: showingFilterSheet) { isPresented in
            // Force update filtered whiskeys when filter sheet is dismissed
            if !isPresented {
                DispatchQueue.main.async {
                    updateFilteredWhiskeys()
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingAddInfinityBottle) {
            AddInfinityBottleView()
        }
        .alert("Delete All Whiskeys", isPresented: $showingDeleteConfirmation) {
            Button("Delete All", role: .destructive) {
                deleteAllWhiskeys()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete all whiskeys? This action cannot be undone.")
        }
        .onAppear {
            // Initialize filter options when view appears
            initializeFilterOptions()
            
            // Initialize debounced search text
            debouncedSearchText = searchText
            
            // Initial filtering
            updateFilteredWhiskeys()
            
            if collectionItems.isEmpty && !hasSeenEmptyCollectionTutorial {
                showingEmptyCollectionTutorialOverlay = true
            } else if !collectionItems.isEmpty && !hasSeenCollectionTutorial {
                showingCollectionTutorialOverlay = true
            }
            
            // Set up notification observers
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("WhiskeyUpdated"),
                object: nil,
                queue: .main
            ) { notification in
                // If the notification includes a specific whiskey, refresh it
                if let updatedWhiskey = notification.object as? Whiskey {
                    if let context = updatedWhiskey.managedObjectContext {
                        context.refresh(updatedWhiskey, mergeChanges: true)
                        
                        // Make sure changes like deadBottleCount are properly recalculated
                        updatedWhiskey.updateFinishedStatus()
                        
                        // Force refresh of all objects to pick up status changes
                        context.refreshAllObjects()
                    }
                }
                
                // Force immediate refresh of the UI
                DispatchQueue.main.async {
                    refreshTrigger = UUID()
                }
            }
        }
        .onChange(of: searchText) { newValue in
            // Cancel any existing timer
            searchDebounceTimer?.invalidate()
            
            // Show loading indicator
            isUpdatingFiltersFromSearch = true
            
            // Create a new timer for debouncing
            searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                DispatchQueue.main.async {
                    debouncedSearchText = newValue
                    isUpdatingFiltersFromSearch = false
                    updateFilteredWhiskeys()
                }
            }
            
            // Fallback: ensure search results update even if debouncing fails
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if debouncedSearchText != newValue {
                    debouncedSearchText = newValue
                    isUpdatingFiltersFromSearch = false
                    updateFilteredWhiskeys()
                }
            }
        }
        .onChange(of: debouncedSearchText) { _ in
            updateFilteredWhiskeys()
        }
        .onChange(of: filterOptions.selectedTypes) { _ in
            updateFilteredWhiskeys()
        }
        .onChange(of: filterOptions.bibState) { _ in
            updateFilteredWhiskeys()
        }
        .onChange(of: filterOptions.sibState) { _ in
            updateFilteredWhiskeys()
        }
        .onChange(of: filterOptions.storePickState) { _ in
            updateFilteredWhiskeys()
        }
        .onChange(of: filterOptions.openState) { _ in
            updateFilteredWhiskeys()
        }
        .onChange(of: filterOptions.finishState) { _ in
            updateFilteredWhiskeys()
        }
        .onChange(of: filterOptions.deadBottleState) { _ in
            updateFilteredWhiskeys()
        }
        .onChange(of: filterOptions.reviewState) { _ in
            updateFilteredWhiskeys()
        }
        .onChange(of: filterOptions.tastedState) { _ in
            updateFilteredWhiskeys()
        }
        .onChange(of: filterOptions.priceRangeOption) { _ in
            updateFilteredWhiskeys()
        }
        .onChange(of: filterOptions.customPriceRange) { _ in
            updateFilteredWhiskeys()
        }
        .onChange(of: filterOptions.proofRange) { _ in
            updateFilteredWhiskeys()
        }
        .onChange(of: sortConfig.activeSorts) { _ in
            updateFilteredWhiskeys()
            // Save the first sort option for backwards compatibility
            if let firstSort = sortConfig.activeSorts.first?.option {
                FilterSettingsManager.saveCurrentSort(firstSort)
            }
        }
        .onChange(of: collectionItems.count) { newCount in
            updateFilteredWhiskeys()
        }
        // Add a general onChange handler for filterOptions to catch any changes
        .onChange(of: filterOptions) { _ in
            updateFilteredWhiskeys()
        }
        // Add onChange handler for filter update trigger
        .onChange(of: filterUpdateTrigger) { _ in
            updateFilteredWhiskeys()
        }
        
        // Floating add button
        .overlay(alignment: .bottomTrailing) {
            FloatingAddButton {
                if viewMode == .whiskeys {
                    if subscriptionManager.canAddWhiskey(currentCount: collectionItems.count) {
                        showingAddSheet = true
                        HapticManager.shared.lightImpact()
                    } else {
                        showingPaywall = true
                        HapticManager.shared.lightImpact()
                    }
                } else {
                    showingAddInfinityBottle = true
                    HapticManager.shared.lightImpact()
                }
            }
        }
        .overlay {
            if showingEmptyCollectionTutorialOverlay {
                EmptyCollectionTutorialOverlay(onDismiss: {
                    hasSeenEmptyCollectionTutorial = true
                    showingEmptyCollectionTutorialOverlay = false
                    HapticManager.shared.lightImpact()
                })
            } else if showingCollectionTutorialOverlay {
                CollectionTutorialOverlay(onDismiss: {
                    hasSeenCollectionTutorial = true
                    showingCollectionTutorialOverlay = false
                    HapticManager.shared.lightImpact()
                })
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddWhiskeyView()
                .environment(\.managedObjectContext, viewContext)
        }
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallView(isPresented: $showingPaywall)
        }
    }
    
    private func deleteWhiskeys(from whiskeys: [Whiskey], at offsets: IndexSet) {
        withAnimation {
            // First track the whiskeys as deleted in the CSV sync service
            let whiskeyToDelete = offsets.map { whiskeys[$0] }
            for whiskey in whiskeyToDelete {
                trackDeletedWhiskey(whiskey)
                viewContext.delete(whiskey)
            }
            do {
                try viewContext.save()
            } catch {
                HapticManager.shared.errorFeedback()
                viewContext.rollback()
            }
        }
    }
    
    private func deleteAllWhiskeys() {
        do {
            let fetchRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
            let whiskeys = try viewContext.fetch(fetchRequest)
            
            for whiskey in whiskeys {
                viewContext.delete(whiskey)
            }
            
            try viewContext.save()
            
            // Force view refresh
            refreshTrigger = UUID()
        } catch {
            // Handle error silently
        }
    }
    
    // Add a helper method to force context refresh
    private func forceContextRefresh() {
        // Refresh all Core Data objects to ensure latest data
        for whiskey in collectionItems {
            viewContext.refresh(whiskey, mergeChanges: false)
        }
        
        // Force refresh the view
        self.refreshTrigger = UUID()
    }
    
    // Helper method to track deleted whiskeys (wrapper around CSVSyncService)
    private func trackDeletedWhiskey(_ whiskey: Whiskey) {
        // Track the deletion in CSVSyncService
        CSVSyncService.shared.trackDeletedWhiskey(whiskey)
    }
    
    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }
    }
    
    private func resetFiltersToDefault() {
        // Reset filter options to default state
        var newFilterOptions = FilterOptions()
        // Make sure all available types are selected 
        newFilterOptions.selectedTypes = Set(availableTypes)
        
        // Explicitly reset all filter options to their default values
        newFilterOptions.isBiB = true
        newFilterOptions.isSiB = true
        newFilterOptions.isStorePick = true
        newFilterOptions.isOpen = true
        newFilterOptions.includeDeadBottles = false // Preserve default of excluding dead bottles
        newFilterOptions.hasFinish = true // Reset finish filter to default
        newFilterOptions.hasReviews = true // Reset review filter to default
        newFilterOptions.proofRange = nil
        newFilterOptions.customPriceRange = nil
        newFilterOptions.priceRangeOption = .all
        
        // Apply the new filter options
        filterOptions = newFilterOptions
        
        // Save the reset filter options
        FilterSettingsManager.saveFilterOptions(newFilterOptions)
        
        // Reset flag when done
        isUpdatingFiltersFromSearch = false
    }
    
    
    // Function to show add infinity bottle view
    private func showAddInfinityBottle() {
        showingAddInfinityBottle = true
    }
}

// Define view mode enum
enum CollectionViewMode {
    case whiskeys
    case infinityBottles
}

// Define InfinityBottlesView
struct InfinityBottlesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("hasSeenInfinityBottleTutorial") private var hasSeenInfinityBottleTutorial = false
    @State private var showingTutorialOverlay = false
    let infinityBottles: FetchedResults<InfinityBottle>
    
    var body: some View {
        ZStack {
        if infinityBottles.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "wineglass")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
                
                Text("No Infinity Bottles")
                    .font(.headline)
                
                Text("Tap the + button to create your first infinity bottle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(infinityBottles) { bottle in
                    NavigationLink(
                        destination: InfinityBottleDetailView(bottle: bottle)
                            .environment(\.managedObjectContext, viewContext)
                    ) {
                        InfinityBottleRowView(bottle: bottle)
                    }
                }
                .onDelete(perform: deleteInfinityBottles)
            }
            .listStyle(.plain)
        }
            if showingTutorialOverlay {
                InfinityBottleTutorialOverlay(onDismiss: {
                    hasSeenInfinityBottleTutorial = true
                    showingTutorialOverlay = false
                    HapticManager.shared.lightImpact()
                })
            }
        }
        .onAppear {
            if !hasSeenInfinityBottleTutorial {
                showingTutorialOverlay = true
            }
        }
    }
    
    private func deleteInfinityBottles(at offsets: IndexSet) {
        withAnimation {
            offsets.map { infinityBottles[$0] }.forEach(viewContext.delete)
            
            do {
                try viewContext.save()
            } catch {
                print("Error deleting infinity bottles: \(error)")
            }
        }
    }
}

// MARK: - Infinity Bottle tutorial (first-time overlay)

struct InfinityBottleTutorialOverlay: View {
    var onDismiss: () -> Void
    
    var body: some View {
        ColorManager.tutorialScrim
            .ignoresSafeArea()
            .onTapGesture { }
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "wineglass.fill")
                                    .font(.title2)
                                    .foregroundColor(ColorManager.primaryBrandColor)
                                Text("Infinity Bottles")
                                    .font(.headline)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Some whiskey lovers create what are known as infinity bottles. An infinity bottle is made from a few ounces of different bottles that are combined into a single bottle that evolves over time as you drink it and add new whiskeys to it. This section helps you keep track of what whiskeys are in your infinity bottles.")
                                    .font(.subheadline)
                                Text("Tap the + button below to create your first bottle, and I'll walk you through the process!")
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
                        Button(action: onDismiss) {
                            Text("Got it")
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

// MARK: - Empty collection tutorial (first bottle — show when collection is empty)
private struct EmptyCollectionTutorialOverlay: View {
    var onDismiss: () -> Void
    
    var body: some View {
        ColorManager.tutorialScrim
            .ignoresSafeArea()
            .onTapGesture { }
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(ColorManager.primaryBrandColor)
                                Text("Add your first bottle")
                                    .font(.headline)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                Text(LocalizedStringKey("Your collection is empty. Tap the **+** button below to add your first whiskey. You can enter name, type, proof, price, and more."))
                                    .font(.subheadline)
                                Text(LocalizedStringKey("Have a whiskey database already? You can import from a CSV in **Settings → Data Management → Import CSV**."))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
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
                        Button(action: onDismiss) {
                            Text("Got it")
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

// MARK: - Collection tutorial (first-time overlay — show when collection has at least one bottle)
private struct CollectionTutorialOverlay: View {
    var onDismiss: () -> Void
    
    var body: some View {
        ColorManager.tutorialScrim
            .ignoresSafeArea()
            .onTapGesture { }
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "square.grid.2x2.fill")
                                    .font(.title2)
                                    .foregroundColor(ColorManager.primaryBrandColor)
                                Text("Your Collection")
                                    .font(.headline)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                collectionTutorialRow(icon: "1.circle.fill", text: "**Tap any bottle** to open its detail view: inventory, individual bottles, notes, tastings, and saved reviews all live there.")
                                collectionTutorialRow(icon: "2.circle.fill", text: "Use the **search bar** to find bottles by name, type, distillery, proof, or age.")
                                collectionTutorialRow(icon: "3.circle.fill", text: "**Filter** (funnel icon) narrows by type, price, proof, open/sealed, tasted, and more.")
                                collectionTutorialRow(icon: "4.circle.fill", text: "**Sort** (arrows icon) changes order: by name, proof, price, date added, or open first.")
                                collectionTutorialRow(icon: "5.circle.fill", text: "**Open bottles** show a half-circle indicator on the row so you can tell at a glance which whiskeys you’ve cracked into.")
                                collectionTutorialRow(icon: "plus.circle.fill", text: "The **+** button adds a new whiskey. Switch to **Infinity Bottles** in the segment to manage or create infinity bottles.")
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
                        Button(action: onDismiss) {
                            Text("Got it")
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
    
    private func collectionTutorialRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(ColorManager.primaryBrandColor)
                .font(.subheadline)
            Text(LocalizedStringKey(text))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct WhiskeyFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filterOptions: FilterOptions
    let availableTypes: [String]
    let onFilterChanged: (() -> Void)?
    
    // New state variables for range sliders
    @State private var priceRange: ClosedRange<Double> = 0...500
    @State private var proofRange: ClosedRange<Double> = 80...160 // Default range
    @State private var minPrice: Double = 0
    @State private var maxPrice: Double = 500
    @State private var minProof: Double = 80
    @State private var maxProof: Double = 160
    let showingWhiskeyCount: Int
    let totalWhiskeyCount: Int
    
    init(filterOptions: Binding<FilterOptions>, availableTypes: [String], showingWhiskeyCount: Int, totalWhiskeyCount: Int, lowestProof: Double, highestProof: Double, onFilterChanged: (() -> Void)? = nil) {
        self._filterOptions = filterOptions
        self.availableTypes = availableTypes
        self.showingWhiskeyCount = showingWhiskeyCount
        self.totalWhiskeyCount = totalWhiskeyCount
        self.lowestProof = lowestProof
        self.highestProof = highestProof
        self.onFilterChanged = onFilterChanged
    }
    
    // Real-time slider feedback state
    @State private var isDraggingSlider = false
    @State private var previewProofCount: Int? = nil
    
    // Dynamic proof range values
    let lowestProof: Double
    let highestProof: Double
    
    // Function to calculate expected results for a proof range
    private func countMatchingProof(_ range: ClosedRange<Double>) -> Int {
        var matchCount = 0
        // Create a temporary filter options with this proof range
        var tempOptions = filterOptions
        tempOptions.proofRange = range
        
        // PLACEHOLDER: This would need to be replaced with actual counting logic based on your model
        // For now, we'll show a simulated count 
        return max(0, showingWhiskeyCount - Int(range.upperBound - range.lowerBound)/4)
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Global filter controls
                Section("FILTER CONTROLS") {
                    Button {
                        // Reset the filter options to show all
                        var newFilterOptions = FilterOptions()
                        // Make sure all available types are selected 
                        newFilterOptions.selectedTypes = Set(availableTypes)
                        
                        // Explicitly reset all filter options
                        newFilterOptions.isBiB = true
                        newFilterOptions.isSiB = true
                        newFilterOptions.isStorePick = true
                        newFilterOptions.isOpen = true
                        newFilterOptions.includeDeadBottles = false // Preserve default of excluding dead bottles
                        newFilterOptions.hasFinish = true // Reset finish filter to default
                        newFilterOptions.hasReviews = true // Reset review filter to default
                        newFilterOptions.proofRange = nil
                        newFilterOptions.customPriceRange = nil
                        newFilterOptions.priceRangeOption = .all
                        
                        // Apply the new filter options
                        filterOptions = newFilterOptions
                        
                        // Reset the sliders to full range
                        priceRange = 0...500
                        proofRange = lowestProof...highestProof
                        
                        // Reset preview counts
                        previewProofCount = nil
                        
                        // Save the reset filter settings
                        FilterSettingsManager.saveFilterOptions(newFilterOptions)
                        onFilterChanged?()
                        
                        // Provide haptic feedback for reset action
                        HapticManager.shared.mediumImpact()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset All Filters")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.blue.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Type section
                Section("Type") {
                    ForEach(availableTypes, id: \.self) { type in
                        Toggle(type, isOn: Binding(
                            get: { filterOptions.selectedTypes.contains(type) },
                            set: { isSelected in
                                if isSelected {
                                    filterOptions.selectedTypes.insert(type)
                                } else {
                                    filterOptions.selectedTypes.remove(type)
                                }
                                // Save filter settings
                                FilterSettingsManager.saveFilterOptions(filterOptions)
                                onFilterChanged?()
                            }
                        ))
                    }
                }
                
                // Proof range section with slider
                Section("Proof Range") {
                    HStack {
                        Text("\(Int(proofRange.lowerBound))°")
                        Spacer()
                        if let preview = previewProofCount {
                            Text("\(preview) whiskeys")
                                .foregroundColor(.blue)
                                .fontWeight(.medium)
                                .transition(.opacity)
                        }
                        Spacer()
                        Text("\(Int(proofRange.upperBound))°")
                    }
                    
                    // Custom proof range slider
                    PriceRangeSlider(range: $proofRange, bounds: lowestProof...highestProof, isDragging: $isDraggingSlider)
                        .frame(height: 30)
                        .padding(.vertical, 8)
                        .onChange(of: proofRange) { newRange in
                            // Update the proof range filter
                            if newRange.lowerBound == lowestProof && newRange.upperBound == highestProof {
                                // Full range selected
                                filterOptions.proofRange = nil
                                previewProofCount = nil
                            } else {
                                // Custom range selected
                                filterOptions.proofRange = newRange
                                
                                // Only update the preview count when dragging
                                if isDraggingSlider {
                                    previewProofCount = countMatchingProof(newRange)
                                } else {
                                    previewProofCount = nil
                                    
                                    // Save filter settings when dragging ends
                                    FilterSettingsManager.saveFilterOptions(filterOptions)
                                    onFilterChanged?()
                                }
                            }
                        }
                }
                
                // Price range section with slider
                Section("Price Range") {
                    HStack {
                        Text("$\(Int(priceRange.lowerBound))")
                        Spacer()
                        Spacer()
                        Text(priceRange.upperBound >= 500 ? "$500+" : "$\(Int(priceRange.upperBound))")
                    }
                    
                    // Custom price range slider
                    PriceRangeSlider(range: $priceRange, bounds: 0...500, isDragging: $isDraggingSlider)
                        .frame(height: 30)
                        .padding(.vertical, 8)
                        .onChange(of: priceRange) { newRange in
                            // Update the price range filter based on slider values
                            if newRange.lowerBound == 0 && newRange.upperBound >= 500 {
                                // If full range is selected, use "All" option
                                filterOptions.priceRangeOption = .all
                                filterOptions.customPriceRange = nil
                            } else {
                                // Create custom price range
                                let customMin = newRange.lowerBound
                                let customMax = newRange.upperBound >= 500 ? Double.infinity : newRange.upperBound
                                
                                // Find closest predefined range or use custom range
                                if customMin <= 30 && customMax >= 30 && customMax <= 70 {
                                    filterOptions.priceRangeOption = .budget
                                    filterOptions.customPriceRange = nil
                                } else if customMin >= 30 && customMin <= 70 && customMax >= 70 && customMax <= 150 {
                                    filterOptions.priceRangeOption = .midRange
                                    filterOptions.customPriceRange = nil
                                } else if customMin >= 70 && customMin <= 150 && (customMax == Double.infinity || customMax >= 150) {
                                    filterOptions.priceRangeOption = .premium
                                    filterOptions.customPriceRange = nil
                                } else if customMin >= 150 && (customMax == Double.infinity || customMax >= 500) {
                                    filterOptions.priceRangeOption = .ultraPremium
                                    filterOptions.customPriceRange = nil
                                } else {
                                    // Use a custom range for non-standard selections
                                    // Do NOT set priceRangeOption to .all for custom ranges
                                    // Instead use a non-matching option to ensure filtering works
                                    filterOptions.priceRangeOption = PriceRangeOption(rawValue: "custom") ?? .ultraPremium
                                    filterOptions.customPriceRange = customMin...customMax
                                }
                                
                                // Save filter settings when dragging ends
                                if !isDraggingSlider {
                                    FilterSettingsManager.saveFilterOptions(filterOptions)
                                    onFilterChanged?()
                                }
                            }
                        }
                }
                
                // Special designations section
                Section(header: VStack(alignment: .leading, spacing: 4) {
                    Text("Special Designations")
                    Text("Tap to cycle between: All (show everything) → Yes (only show bottles with this attribute) → No (only show bottles without this attribute)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }) {
                    ThreeWayToggle(
                        label: "Bottled in Bond",
                        state: $filterOptions.bibState,
                        explanation: "Bottled in Bond whiskeys are at least 4 years old, bottled at 100 proof, and produced at a single distillery in one distilling season.",
                        onChanged: { _ in
                            FilterSettingsManager.saveFilterOptions(filterOptions)
                            onFilterChanged?()
                        }
                    )
                    
                    ThreeWayToggle(
                        label: "Single Barrel",
                        state: $filterOptions.sibState,
                        explanation: "Single Barrel whiskeys come from an individual aging barrel, not blended with other barrels.",
                        onChanged: { _ in
                            FilterSettingsManager.saveFilterOptions(filterOptions)
                            onFilterChanged?()
                        }
                    )
                    
                    ThreeWayToggle(
                        label: "Store Pick",
                        state: $filterOptions.storePickState,
                        explanation: "Store Pick bottles are selected by a specific retailer, often offering a unique flavor profile compared to standard releases.",
                        onChanged: { _ in
                            FilterSettingsManager.saveFilterOptions(filterOptions)
                            onFilterChanged?()
                        }
                    )
                    
                    ThreeWayToggle(
                        label: "Open Bottles",
                        state: $filterOptions.openState,
                        explanation: "Bottles that have been opened for tasting, rather than being sealed in your collection.",
                        onChanged: { _ in
                            FilterSettingsManager.saveFilterOptions(filterOptions)
                            onFilterChanged?()
                        }
                    )
                    
                    ThreeWayToggle(
                        label: "Whiskeys with Cask Finish",
                        state: $filterOptions.finishState,
                        explanation: "Whiskeys aged in a secondary barrel (such as port, sherry, or wine casks) to impart additional flavors.",
                        onChanged: { _ in
                            FilterSettingsManager.saveFilterOptions(filterOptions)
                            onFilterChanged?()
                        }
                    )
                    
                    ThreeWayToggle(
                        label: "Dead Bottles",
                        state: $filterOptions.deadBottleState,
                        explanation: "Filter by bottle status: NO shows only whiskeys with at least one active bottle, YES shows only completely dead whiskeys (all bottles finished), ALL shows all whiskeys.",
                        onChanged: { _ in
                            FilterSettingsManager.saveFilterOptions(filterOptions)
                            onFilterChanged?()
                        }
                    )
                    
                    ThreeWayToggle(
                        label: "Has Web Reviews",
                        state: $filterOptions.reviewState,
                        explanation: "Whiskeys that have saved web reviews or tasting notes from external sources.",
                        onChanged: { _ in
                            FilterSettingsManager.saveFilterOptions(filterOptions)
                            onFilterChanged?()
                        }
                    )
                    
                    ThreeWayToggle(
                        label: "Tasted",
                        state: $filterOptions.tastedState,
                        explanation: "Whiskeys that have been tasted, either through journal entries or manually marked as tasted.",
                        onChanged: { _ in
                            FilterSettingsManager.saveFilterOptions(filterOptions)
                            onFilterChanged?()
                        }
                    )
                }
                
                // Results counter
                if showingWhiskeyCount > 0 {
                    Section {
                        HStack {
                            Spacer()
                            Text("Showing \(showingWhiskeyCount) of \(totalWhiskeyCount) whiskeys")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        // Reset the filter options to show all
                        var newFilterOptions = FilterOptions()
                        // Make sure all available types are selected 
                        newFilterOptions.selectedTypes = Set(availableTypes)
                        
                        // Explicitly reset all filter options
                        newFilterOptions.isBiB = true
                        newFilterOptions.isSiB = true
                        newFilterOptions.isStorePick = true
                        newFilterOptions.isOpen = true
                        newFilterOptions.includeDeadBottles = false // Preserve default of excluding dead bottles
                        newFilterOptions.hasFinish = true // Reset finish filter to default
                        newFilterOptions.hasReviews = true // Reset review filter to default
                        newFilterOptions.proofRange = nil
                        newFilterOptions.customPriceRange = nil
                        newFilterOptions.priceRangeOption = .all
                        
                        // Apply the new filter options
                        filterOptions = newFilterOptions
                        
                        // Reset the sliders to full range
                        priceRange = 0...500
                        proofRange = lowestProof...highestProof
                        
                        // Reset preview counts
                        previewProofCount = nil
                        
                        // Save reset filter settings
                        FilterSettingsManager.saveFilterOptions(newFilterOptions)
                        onFilterChanged?()
                        
                        // Provide haptic feedback for reset action
                        HapticManager.shared.mediumImpact()
                    }
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        // Make sure we save filter settings before dismissing
                        FilterSettingsManager.saveFilterOptions(filterOptions)
                        onFilterChanged?()
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Initialize price range based on current filter options
                if filterOptions.priceRangeOption != .all {
                    let range = filterOptions.priceRangeOption.range
                    priceRange = range.min...(range.max == Double.infinity ? 500 : range.max)
                } else if let custom = filterOptions.customPriceRange {
                    priceRange = custom.lowerBound...(custom.upperBound == Double.infinity ? 500 : custom.upperBound)
                }
                
                // Initialize proof range based on current filter options
                if let range = filterOptions.proofRange {
                    proofRange = range
                } else {
                    proofRange = lowestProof...highestProof
                }
            }
        }
    }
}

// Custom price range slider
struct PriceRangeSlider: View {
    @Binding var range: ClosedRange<Double>
    let bounds: ClosedRange<Double>
    @Binding var isDragging: Bool
    
    @State private var draggedThumbPosition: CGFloat = 0
    @State private var isDraggingLower = false
    @State private var isDraggingUpper = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 4)
                
                // Selected range
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue)
                    .frame(width: width(for: range, in: geometry), height: 4)
                    .offset(x: position(for: range.lowerBound, in: geometry))
                
                // Lower thumb
                Circle()
                    .fill(Color.white)
                    .shadow(radius: 2)
                    .frame(width: 24, height: 24)
                    .offset(x: position(for: range.lowerBound, in: geometry) - 12)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                isDraggingLower = true
                                isDragging = true
                                let newValue = valueFor(position: gesture.location.x, in: geometry)
                                if newValue < range.upperBound {
                                    range = newValue...range.upperBound
                                }
                            }
                            .onEnded { _ in
                                isDraggingLower = false
                                isDragging = false
                                HapticManager.shared.selectionFeedback()
                            }
                    )
                
                // Upper thumb
                Circle()
                    .fill(Color.white)
                    .shadow(radius: 2)
                    .frame(width: 24, height: 24)
                    .offset(x: position(for: range.upperBound, in: geometry) - 12)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                isDraggingUpper = true
                                isDragging = true
                                let newValue = valueFor(position: gesture.location.x, in: geometry)
                                if newValue > range.lowerBound {
                                    range = range.lowerBound...newValue
                                }
                            }
                            .onEnded { _ in
                                isDraggingUpper = false
                                isDragging = false
                                HapticManager.shared.selectionFeedback()
                            }
                    )
            }
        }
    }
    
    private func position(for value: Double, in geometry: GeometryProxy) -> CGFloat {
        let scale = geometry.size.width / (bounds.upperBound - bounds.lowerBound)
        return CGFloat(value - bounds.lowerBound) * scale
    }
    
    private func width(for range: ClosedRange<Double>, in geometry: GeometryProxy) -> CGFloat {
        let scale = geometry.size.width / (bounds.upperBound - bounds.lowerBound)
        return CGFloat(range.upperBound - range.lowerBound) * scale
    }
    
    private func valueFor(position: CGFloat, in geometry: GeometryProxy) -> Double {
        let width = geometry.size.width
        let scale = (bounds.upperBound - bounds.lowerBound) / Double(width)
        let value = Double(position) * scale + bounds.lowerBound
        let roundedValue = round(value / 5) * 5 // Round to nearest $5
        
        return min(max(roundedValue, bounds.lowerBound), bounds.upperBound)
    }
}

struct SearchResultsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.presentationMode) var presentationMode
    
    let searchQuery: String
    let whiskeys: [Whiskey]
    
    @State private var showingFilterSheet = false
    @State private var sortConfig = HierarchicalSortConfig(activeSorts: [SortCriterionIdentifiable(option: .nameAsc)])
    @State private var showingSortSheet = false
    @State private var filterOptions = FilterOptions()
    @State private var localSearchText: String
    
    @State private var availableTypes: [String] = []
    
    // Initialize with the search query
    init(searchQuery: String, whiskeys: [Whiskey]) {
        self.searchQuery = searchQuery
        self.whiskeys = whiskeys
        self._localSearchText = State(initialValue: searchQuery)
    }
    
    // Calculate proof range
    private var lowestProof: Double {
        whiskeys.min(by: { $0.proof < $1.proof })?.proof ?? 80
    }
    
    private var highestProof: Double {
        whiskeys.max(by: { $0.proof < $1.proof })?.proof ?? 160
    }
    
    // Initialize filter options with all available types when the view appears
    private func initializeFilterOptions() {
        // Ensure that if no types are selected, we select all available types by default
        if filterOptions.selectedTypes.isEmpty {
            filterOptions.selectedTypes = Set(availableTypes)
        }
    }
    
    // Filter whiskeys based on local search
    private var filteredWhiskeys: [Whiskey] {
        // Always search the full collection
        let filtered = whiskeys.filter { whiskey in
            // Text search filtering - now using localSearchText for fresh search
            let matchesText = localSearchText.isEmpty ||
                (whiskey.name?.localizedCaseInsensitiveContains(localSearchText) ?? false) ||
                (whiskey.type?.localizedCaseInsensitiveContains(localSearchText) ?? false) ||
                (whiskey.distillery?.localizedCaseInsensitiveContains(localSearchText) ?? false) ||
                (whiskey.finish?.localizedCaseInsensitiveContains(localSearchText) ?? false) ||
                (whiskey.storePickName?.localizedCaseInsensitiveContains(localSearchText) ?? false) ||
                (String(format: "%.1f", whiskey.proof).contains(localSearchText)) ||
                (whiskey.age?.localizedCaseInsensitiveContains(localSearchText) ?? false)
            
            // Type filtering: if no types are selected, show all whiskeys
            // If types are selected, only show those types
            let matchesType = filterOptions.selectedTypes.isEmpty || 
                 (whiskey.type != nil && filterOptions.selectedTypes.contains(whiskey.type!))
             
            // Special attribute filtering - updated for three-state toggles
            let matchesBiB: Bool
            switch filterOptions.bibState {
            case .all: matchesBiB = true  // Show all whiskeys regardless of BIB status
            case .yes: matchesBiB = whiskey.isBiB  // Only show BIB whiskeys
            case .no: matchesBiB = !whiskey.isBiB  // Only show non-BIB whiskeys
            }
            
            let matchesSiB: Bool
            switch filterOptions.sibState {
            case .all: matchesSiB = true  // Show all whiskeys regardless of SIB status
            case .yes: matchesSiB = whiskey.isSiB  // Only show SIB whiskeys
            case .no: matchesSiB = !whiskey.isSiB  // Only show non-SIB whiskeys
            }
            
            let matchesStorePick: Bool
            switch filterOptions.storePickState {
            case .all: matchesStorePick = true  // Show all whiskeys regardless of store pick status
            case .yes: matchesStorePick = whiskey.isStorePick  // Only show store picks
            case .no: matchesStorePick = !whiskey.isStorePick  // Only show non-store picks
            }
            
            let matchesOpen: Bool
            switch filterOptions.openState {
            case .all: matchesOpen = true  // Show all whiskeys regardless of open status
            case .yes: matchesOpen = whiskey.isOpen  // Only show open bottles
            case .no: matchesOpen = !whiskey.isOpen  // Only show sealed bottles
            }
            
            // Finish filtering - only include finished bottles based on the state
            let matchesFinish: Bool
            let hasFinish = whiskey.finish != nil && !whiskey.finish!.isEmpty
            switch filterOptions.finishState {
            case .all: matchesFinish = true  // Show all whiskeys regardless of finish
            case .yes: matchesFinish = hasFinish  // Only show bottles with finish
            case .no: matchesFinish = !hasFinish  // Only show bottles without finish
            }
            
            // Dead bottle filtering - using three-way toggle state
            let matchesDeadBottle: Bool
            switch filterOptions.deadBottleState {
            case .all: matchesDeadBottle = true  // Show all whiskeys regardless of dead status
            case .yes: matchesDeadBottle = whiskey.isCompletelyDead  // ONLY show whiskeys where ALL bottles are dead
            case .no: matchesDeadBottle = whiskey.hasActiveBottles  // Only show whiskeys with at least 1 active bottle
            }
            
            // Review filtering - check if the whiskey has any web content reviews
            let matchesReviews: Bool
            let hasReviews = whiskey.webContent?.count ?? 0 > 0
            switch filterOptions.reviewState {
            case .all: matchesReviews = true  // Show all whiskeys regardless of reviews
            case .yes: matchesReviews = hasReviews  // Only show whiskeys with reviews
            case .no: matchesReviews = !hasReviews  // Only show whiskeys without reviews
            }
            
            // Tasted filtering - check both journal entries and isTasted flag
            let matchesTasted: Bool
            let hasJournalEntries = (whiskey.journalEntries?.count ?? 0) > 0
            let isMarkedAsTasted = whiskey.isTasted
            let isTasted = hasJournalEntries || isMarkedAsTasted
            switch filterOptions.tastedState {
            case .all: matchesTasted = true  // Show all whiskeys regardless of tasted status
            case .yes: matchesTasted = isTasted  // Only show tasted whiskeys
            case .no: matchesTasted = !isTasted  // Only show untasted whiskeys
            }
            
            // Add price range filtering
            let priceRange = filterOptions.priceRangeOption.range
            let matchesPriceRange: Bool
             
            if let customRange = filterOptions.customPriceRange {
                // Use custom range if set - handle zero-priced whiskeys
                if whiskey.price == 0 {
                    // Skip whiskeys with no price when filtering by price
                    matchesPriceRange = false
                } else {
                    matchesPriceRange = whiskey.price >= customRange.lowerBound && 
                        (customRange.upperBound == Double.infinity || whiskey.price <= customRange.upperBound)
                }
            } else {
                // Use predefined range
                if filterOptions.priceRangeOption == .all {
                    matchesPriceRange = true  // Show all whiskeys including those with no price
                } else if whiskey.price == 0 {
                    // Skip whiskeys with no price when filtering by specific price ranges
                    matchesPriceRange = false 
                } else {
                    matchesPriceRange = whiskey.price >= priceRange.min && 
                        (priceRange.max == Double.infinity || whiskey.price <= priceRange.max)
                }
            }
             
            // Proof range filtering
            let matchesProofRange: Bool
            if let proofRange = filterOptions.proofRange {
                matchesProofRange = whiskey.proof >= proofRange.lowerBound && whiskey.proof <= proofRange.upperBound
            } else {
                matchesProofRange = true
            }
             
            return matchesText && matchesType && matchesBiB && matchesSiB && matchesStorePick && matchesOpen && 
                   matchesPriceRange && matchesProofRange && matchesFinish && matchesReviews && matchesTasted
        }
        
        return filtered
    }
    
    // Hierarchical sorting functionality
    private var sortedWhiskeys: [Whiskey] {
        return SortingUtils.sortWhiskeysHierarchically(filteredWhiskeys, by: sortConfig)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Persistent search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search collection...", text: $localSearchText)
                    .disableAutocorrection(true)
                
                if !localSearchText.isEmpty {
                    Button(action: {
                        localSearchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.top, 8)
            
            // Results summary
            HStack {
                Text("\(filteredWhiskeys.count) results")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                if !filteredWhiskeys.isEmpty {
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    let totalBottles = filteredWhiskeys.reduce(0) { $0 + Int($1.numberOfBottles) }
                    Text("\(totalBottles) bottles")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    let totalValue = filteredWhiskeys.reduce(0.0) { $0 + ($1.price * Double($1.numberOfBottles)) }
                    Text(AppFormatters.formatCurrency(totalValue))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
            
            // Results list
            List {
                if filteredWhiskeys.isEmpty {
                    Text("No results found")
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(sortedWhiskeys, id: \.self) { whiskey in
                        NavigationLink(destination: WhiskeyDetailView(whiskey: whiskey)) {
                            WhiskeyRowView(whiskey: whiskey)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Search: \(localSearchText.isEmpty ? searchQuery : localSearchText)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                EmptyView()
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
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
            }
        }
        .sheet(isPresented: $showingSortSheet) {
            HierarchicalSortPickerView(sortConfig: $sortConfig)
        }
        .sheet(isPresented: $showingFilterSheet) {
            WhiskeyFilterView(
                filterOptions: $filterOptions,
                availableTypes: availableTypes,
                showingWhiskeyCount: filteredWhiskeys.count,
                totalWhiskeyCount: whiskeys.count,
                lowestProof: lowestProof,
                highestProof: highestProof
            )
        }
        .onAppear {
            // Get available whiskey types for filtering
            availableTypes = Array(Set(whiskeys.compactMap { $0.type })).sorted()
            
            // Initialize filter options to ensure all types are selected by default
            initializeFilterOptions()
        }
    }
    
}

struct CollectionView_Previews: PreviewProvider {
    static var previews: some View {
        CollectionView()
    }
} 
