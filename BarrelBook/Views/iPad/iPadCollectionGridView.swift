import SwiftUI
import CoreData

enum ColumnType: String, CaseIterable {
    case name = "Name"
    case type = "Type"
    case distillery = "Distillery"
    case age = "Age"
    case proof = "Proof"
    case abv = "ABV"
    case price = "Price"
    case rating = "Rating"
    case open = "Open"
    case tasted = "Tasted"
    case bib = "BiB"
    case sib = "SiB"
    case dateAdded = "Date Added"
    
    var width: CGFloat {
        switch self {
        case .name: return 1.5
        case .type: return 0.8
        case .distillery: return 1.2
        case .age: return 0.6
        case .proof, .abv, .rating: return 0.7
        case .price, .dateAdded: return 0.8
        case .open, .tasted, .bib, .sib: return 0.6
        }
    }
    
    var isVisible: Bool {
        switch self {
        case .name: return true // Always visible
        case .type: return true
        case .distillery: return true
        case .proof: return true
        case .abv: return false
        case .age: return false
        case .price: return true
        case .rating: return false
        case .open: return true
        case .tasted: return true
        case .bib: return true
        case .sib: return true
        case .dateAdded: return false
        }
    }
}

extension ColumnType {
    func calculateWidth(totalWidth: CGFloat, visibleColumns: [ColumnType]) -> CGFloat {
        let totalRelativeWidth = visibleColumns.reduce(0) { $0 + $1.width }
        let baseColumnWidth = totalWidth / totalRelativeWidth
        return baseColumnWidth * self.width
    }
}

struct SortCriterion: Equatable {
    let column: ColumnType
    let ascending: Bool
    
    static func == (lhs: SortCriterion, rhs: SortCriterion) -> Bool {
        return lhs.column == rhs.column && lhs.ascending == rhs.ascending
    }
}

struct iPadCollectionGridView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var selectedTypes: Set<String> = []  // New state for multiple type selection
    @State private var selectedWhiskey: Whiskey? = nil
    @State private var showingDetailView = false
    @State private var sortCriteria: [SortCriterion] = []  // Replace sortOrder with sortCriteria
    @State private var showingColumnOptions = false
    @State private var showingAddSheet = false
    
    // Column visibility states
    @State private var showTypeColumn = true
    @State private var showDistilleryColumn = true
    @State private var showProofColumn = true
    @State private var showABVColumn = false
    @State private var showAgeColumn = false
    @State private var showPriceColumn = true
    @State private var showRatingColumn = false
    @State private var showOpenColumn = true
    @State private var showTastedColumn = true
    @State private var showBiBColumn = true
    @State private var showSiBColumn = true
    @State private var showDateAddedColumn = false
    
    // Filter sliders
    @State private var proofRange: ClosedRange<Double> = 0...200
    @State private var minProof: Double = 0
    @State private var maxProof: Double = 200
    @State private var priceRange: ClosedRange<Double> = 0...500
    @State private var minPrice: Double = 0
    @State private var maxPrice: Double = 500
    @State private var ageRange: ClosedRange<Double> = 0...25
    @State private var minAge: Double = 0
    @State private var maxAge: Double = 25
    @State private var isFilterActive: Bool = false
    
    // Status filter states
    @State private var openState: ToggleState = .all
    @State private var tastedState: ToggleState = .all
    @State private var deadBottleState: ToggleState = .no // Default to hide dead bottles
    @State private var singleBarrelState: ToggleState = .all // Default to show all bottles
    @State private var bottledInBondState: ToggleState = .all
    @State private var caskStrengthState: ToggleState = .all // Add new state for cask strength
    
    // Data range bounds (actual min/max values in data)
    @State private var proofBounds: ClosedRange<Double> = 0...200
    @State private var priceBounds: ClosedRange<Double> = 0...500
    @State private var ageBounds: ClosedRange<Double> = 0...25
    
    // Main whiskey fetch request
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Whiskey.name, ascending: true)],
        predicate: NSPredicate(format: "status == %@", "owned"),
        animation: .default)
    private var whiskeys: FetchedResults<Whiskey>
    
    // Categories to filter by
    let categories = ["Bourbon", "Rye", "Scotch", "Irish", "Japanese", "Canadian", "Others"]
    
    // Add these state variables for collapsible panels
    @State private var isRangeFiltersExpanded = true
    @State private var isStatusFiltersExpanded = true
    @State private var isTypeFiltersExpanded = true
    
    // Add after the other @State properties
    @State private var columnOrder: [ColumnType] = [
        .name, .type, .distillery, .age, .proof, .abv, .price, .rating,
        .open, .tasted, .bib, .sib, .dateAdded
    ]
    @State private var isDragging: Bool = false
    @State private var draggedColumn: ColumnType? = nil
    
    // Add computed properties for sorted types and counts
    private var sortedTypes: [String] {
        let typeCounts = calculateWhiskeyTypeCounts()
        return typeCounts.sorted(by: { $0.value > $1.value }).map { $0.key }
    }
    
    private var typeCounts: [String: Int] {
        calculateWhiskeyTypeCounts()
    }
    
    // Add this computed property after the other state variables
    private var isAnyFilterActive: Bool {
        // Check status filters
        let statusFiltersActive = openState != .all ||
                                tastedState != .all ||
                                deadBottleState != .no || // Default is .no
                                singleBarrelState != .all ||
                                bottledInBondState != .all ||
                                caskStrengthState != .all
        
        // Check range filters
        let rangeFiltersActive = minProof > proofBounds.lowerBound ||
                               maxProof < proofBounds.upperBound ||
                               minPrice > priceBounds.lowerBound ||
                               maxPrice < priceBounds.upperBound ||
                               minAge > ageBounds.lowerBound ||
                               maxAge < ageBounds.upperBound
        
        return statusFiltersActive || rangeFiltersActive
    }
    
    // Add these state variables after the other @State properties
    @State private var isFiltersExpanded = true
    @State private var isTypesExpanded = true
    @State private var isTypeFilterActive = false
    
    private func updateTypeFilterActive() {
        let allTypes = Set(sortedTypes)
        isTypeFilterActive = !selectedTypes.isSuperset(of: allTypes)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search and filter bar
            HStack {
                // Reset filters button
                Button(action: {
                    // Reset filters to show full range of actual data
                    minProof = proofBounds.lowerBound
                    maxProof = proofBounds.upperBound
                    minPrice = priceBounds.lowerBound
                    maxPrice = priceBounds.upperBound
                    minAge = ageBounds.lowerBound
                    maxAge = ageBounds.upperBound
                    isFilterActive = false
                    
                    // Reset status filters
                    openState = .all
                    tastedState = .all
                    deadBottleState = .no
                    singleBarrelState = .all
                }) {
                    Label("Reset Filters", systemImage: "arrow.counterclockwise")
                        .foregroundColor(.blue)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.1))
                        )
                }
                
                // Reset sort button
                Button(action: {
                    sortCriteria = []
                }) {
                    Label("Reset Sort", systemImage: "arrow.up.arrow.down.circle")
                        .foregroundColor(.blue)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.1))
                        )
                }
                .disabled(sortCriteria.isEmpty)
                
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search whiskeys...", text: $searchText)
                        .disableAutocorrection(true)
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(10)
                .frame(maxWidth: 400)
                
                Spacer()
                
                // Column visibility button
                Button(action: {
                    showingColumnOptions.toggle()
                }) {
                    Label("Columns", systemImage: "rectangle.grid.1x2")
                        .font(.system(size: 16, weight: .medium))
                }
                .padding(.horizontal, 8)
                .popover(isPresented: $showingColumnOptions, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 12) {
                    Text("Show/Hide Columns")
                        .font(.headline)
                            .padding(.bottom, 4)
                    
                    Toggle("Type", isOn: $showTypeColumn)
                    Toggle("Distillery", isOn: $showDistilleryColumn)
                    Toggle("Age", isOn: $showAgeColumn)
                    Toggle("Proof", isOn: $showProofColumn)
                    Toggle("ABV", isOn: $showABVColumn)
                    Toggle("Price", isOn: $showPriceColumn)
                    Toggle("Rating", isOn: $showRatingColumn)
                    Toggle("Open", isOn: $showOpenColumn)
                    Toggle("Tasted", isOn: $showTastedColumn)
                    Toggle("BiB", isOn: $showBiBColumn)
                    Toggle("SiB", isOn: $showSiBColumn)
                    Toggle("Date Added", isOn: $showDateAddedColumn)
                }
                    .padding()
                    .frame(width: 200)
                }
                
                // Add new whiskey button
                Button(action: {
                    showingAddSheet = true
                }) {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 16, weight: .medium))
                }
                .padding(.horizontal)
            }
            .padding()
            
            // Filter section with collapsible panels
            VStack(spacing: 16) {
                // Combined Status and Range Filters Card
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isFiltersExpanded.toggle()
                        }
                    }) {
                        HStack {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .foregroundColor(.blue)
                            Text("Filters")
                                .font(.system(size: 17, weight: .medium))
                            Spacer()
                            if isFilterActive {
                                Text("Active")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.blue)
                                    )
                            }
                            Image(systemName: "chevron.right")
                                .rotationEffect(.degrees(isFiltersExpanded ? 90 : 0))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if isFiltersExpanded {
                        HStack(alignment: .top, spacing: 20) {
                            // Status Filters Section
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(spacing: 16) {
                                    // Open status filter
                                    StatusFilterButton(
                                        title: "Open",
                                        state: openState,
                                        action: {
                                            openState = openState.nextState
                                            isFilterActive = isAnyFilterActive
                                        }
                                    )
                                    
                                    // Tasted status filter
                                    StatusFilterButton(
                                        title: "Tasted",
                                        state: tastedState,
                                        action: {
                                            tastedState = tastedState.nextState
                                            isFilterActive = isAnyFilterActive
                                        }
                                    )
                                    
                                    // Dead Bottles status filter
                                    StatusFilterButton(
                                        title: "Dead",
                                        state: deadBottleState,
                                        action: {
                                            deadBottleState = deadBottleState.nextState
                                            isFilterActive = isAnyFilterActive
                                        }
                                    )
                                }
                                
                                HStack(spacing: 16) {
                                    // BiB status filter
                                    StatusFilterButton(
                                        title: "BiB",
                                        state: bottledInBondState,
                                        action: {
                                            bottledInBondState = bottledInBondState.nextState
                                            isFilterActive = isAnyFilterActive
                                        }
                                    )
                                    
                                    // SiB status filter
                                    StatusFilterButton(
                                        title: "Single Barrel",
                                        state: singleBarrelState,
                                        action: {
                                            singleBarrelState = singleBarrelState.nextState
                                            isFilterActive = isAnyFilterActive
                                        }
                                    )
                                    
                                    // Cask Strength status filter
                                    StatusFilterButton(
                                        title: "Cask",
                                        state: caskStrengthState,
                                        action: {
                                            caskStrengthState = caskStrengthState.nextState
                                            isFilterActive = isAnyFilterActive
                                        }
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity)
                            
                            // Range Filters Section
                            VStack(alignment: .leading, spacing: 12) {
                                // Proof slider
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Proof")
                                            .font(.system(size: 14, weight: .medium))
                                        Spacer()
                                        Text("\(Int(minProof))° - \(Int(maxProof))°")
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    SliderView(value: Binding(
                                        get: { [minProof, maxProof] },
                                        set: { values in
                                            minProof = values[0]
                                            maxProof = values[1]
                                            isFilterActive = isAnyFilterActive
                                        }
                                    ), bounds: proofBounds, step: 5)
                                }
                                
                                // Age slider
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Age")
                                            .font(.system(size: 14, weight: .medium))
                                        Spacer()
                                        Text("\(Int(minAge)) - \(Int(maxAge)) years")
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    SliderView(value: Binding(
                                        get: { [minAge, maxAge] },
                                        set: { values in
                                            minAge = values[0]
                                            maxAge = values[1]
                                            isFilterActive = isAnyFilterActive
                                        }
                                    ), bounds: ageBounds, step: 1)
                                }
                                
                                // Price slider
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Price")
                                            .font(.system(size: 14, weight: .medium))
                                        Spacer()
                                        Text("$\(Int(minPrice)) - $\(Int(maxPrice))")
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    SliderView(value: Binding(
                                        get: { [minPrice, maxPrice] },
                                        set: { values in
                                            minPrice = values[0]
                                            maxPrice = values[1]
                                            isFilterActive = isAnyFilterActive
                                        }
                                    ), bounds: priceBounds, step: 10)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                )
                
                // Whiskey Types Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "tag")
                                .foregroundColor(.blue)
                            Text("Whiskey Types")
                                .font(.headline)
                        }
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(sortedTypes, id: \.self) { type in
                                    Button(action: {
                                        if selectedTypes.contains(type) {
                                            selectedTypes.remove(type)
                                        } else {
                                            selectedTypes.insert(type)
                                        }
                                        updateTypeFilterActive()
                                    }) {
                                        HStack(spacing: 4) {
                                            Text(type)
                                                .font(.subheadline)
                                            Text("(\(typeCounts[type] ?? 0))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(
                                            selectedTypes.contains(type) ?
                                            Color.blue.opacity(0.2) :
                                            Color(.systemGray6)
                                        )
                                        .cornerRadius(8)
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        
                        if isTypeFilterActive {
                            Text("Active")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            selectAllWhiskeyTypes()
                            isTypeFilterActive = false
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 14))
                                Text("Reset Types")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.blue)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
            
            // Table Headers
            HStack(spacing: 0) {
                ForEach(columnOrder, id: \.self) { column in
                    if isColumnVisible(column) {
                        TableColumnHeader(
                            columnType: column,
                            width: calculateColumnWidth(for: column),
                            sortCriteria: sortCriteria,  // Pass sortCriteria instead of sortOrder
                            action: { handleSort(for: column) },
                            onDragStarted: { 
                                isDragging = true
                                draggedColumn = column
                            },
                            onDragEnded: {
                                isDragging = false
                                draggedColumn = nil
                            },
                            columnOrder: columnOrder,
                            isColumnVisible: isColumnVisible
                        )
                        .dropDestination(for: String.self) { items, location in
                            guard let draggedColumn = draggedColumn else { return false }
                            if let index = columnOrder.firstIndex(of: draggedColumn),
                               let targetIndex = columnOrder.firstIndex(of: column),
                               index != targetIndex {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    columnOrder.move(fromOffsets: IndexSet(integer: index),
                                                   toOffset: targetIndex > index ? targetIndex + 1 : targetIndex)
                                }
                            }
                            return true
                        }
                    }
                }
            }
            .background(Color(.systemGray6))
            .frame(maxWidth: .infinity)
            
            Divider()
            
            // Main table content
            ScrollView {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedAndFilteredWhiskeys, id: \.id) { whiskey in
                            WhiskeyTableRow(
                                whiskey: whiskey,
                                columnOrder: columnOrder,
                                rating: showRatingColumn ? getHighestRating(for: whiskey) : 0,
                                isColumnVisible: isColumnVisible
                            )
                            .onTapGesture {
                                selectedWhiskey = whiskey
                                showingDetailView = true
                            }
                            .padding(.vertical, 10)
                            
                            Divider()
                        }
                    }
                    .frame(minWidth: UIScreen.main.bounds.width)
                }
            }
        }
        .navigationTitle("Whiskey Collection")
        .sheet(isPresented: $showingDetailView) {
            if let whiskey = selectedWhiskey {
                NavigationView {
                    WhiskeyDetailView(whiskey: whiskey)
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddWhiskeyView()
        }
        .onAppear {
            // Initialize the slider ranges based on actual data
            initializeFilterRanges()
            
            // Select all whiskey types by default
            selectAllWhiskeyTypes()
        }
    }
    
    // Initialize filter ranges based on actual whiskey data
    private func initializeFilterRanges() {
        // Proof range - dynamically calculate from actual whiskey data
        let proofs = whiskeys.compactMap { $0.proof as? Double }.filter { $0 > 0 }
        if !proofs.isEmpty {
            let minFound = proofs.min() ?? 0
            let maxFound = proofs.max() ?? 200
            
            // Set bounds to exact data range (no buffer)
            proofBounds = minFound...maxFound
            
            // Initialize slider values to the full range
            minProof = minFound
            maxProof = maxFound
        }
        
        // Price range - dynamically calculate from actual whiskey data
        let prices = whiskeys.compactMap { $0.price as? Double }.filter { $0 > 0 }
        if !prices.isEmpty {
            let minFound = prices.min() ?? 0
            let maxFound = prices.max() ?? 500
            
            // Set bounds to exact data range (no buffer)
            priceBounds = minFound...maxFound
            
            // Initialize slider values to the full range
            minPrice = minFound
            maxPrice = maxFound
        }
        
        // Age range - dynamically calculate from actual whiskey data
        var ages = [Int]()
        for whiskey in whiskeys {
            if let ageStr = whiskey.age, !ageStr.isEmpty, 
               let ageNum = extractNumericValue(from: ageStr) {
                ages.append(ageNum)
            }
        }
        
        if !ages.isEmpty {
            let minFound = Double(ages.min() ?? 0)
            let maxFound = Double(ages.max() ?? 25)
            
            // Set bounds to exact data range (no buffer)
            ageBounds = minFound...maxFound
            
            // Initialize slider values to the full range
            minAge = minFound
            maxAge = maxFound
        }
    }
    
    // Select all whiskey types by default
    private func selectAllWhiskeyTypes() {
        // Calculate counts for each whiskey type
        let typeCounts = calculateWhiskeyTypeCounts()
        
        // Add all types to the selected types
        for (type, _) in typeCounts {
            selectedTypes.insert(type)
        }
    }
    
    // Filtered whiskeys based on search and category
    private var filteredWhiskeys: [Whiskey] {
        // Start with all owned whiskeys
        var filtered = Array(whiskeys)
        
        // Apply category filter if selected
        if let selectedCategory = selectedCategory {
            if selectedCategory == "Favorites" {
                filtered = getFavoriteWhiskeys()
            } else if selectedCategory == "NONE" {
                // If "NONE" is selected, return empty array
                return []
            } else if !selectedTypes.isEmpty {
                // If types are selected, ignore the category filter
                // This will be handled by the type filter below
        } else {
                filtered = filtered.filter { $0.type == selectedCategory }
            }
        }
        
        // Apply type filters if any are selected
        if !selectedTypes.isEmpty {
            filtered = filtered.filter { whiskey in
                guard let type = whiskey.type, !type.isEmpty else {
                    // If the whiskey has no type and "Others" is selected, include it
                    return selectedTypes.contains("Others")
                }
                // Normalize the type (trim whitespace, capitalize first letter)
                let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(1).uppercased() + type.dropFirst().lowercased()
                
                if selectedTypes.contains("Others") {
                    // For "Others", include whiskeys with types that have less than 10 bottles
                    let typeCount = whiskeys.filter { $0.type == type }.count
                    return typeCount < 10 || selectedTypes.contains(normalizedType)
                }
                
                return selectedTypes.contains(normalizedType)
            }
        } else if selectedCategory == nil {
            // If no types are selected and no category is selected, show all whiskeys
            // This allows for a more intuitive filtering experience
        }
        
        // Apply slider filters if active
        if isFilterActive {
            filtered = filtered.filter { whiskey in
                // Proof filter
                let proofValue = whiskey.proof as? Double ?? 0
                guard proofValue >= minProof && proofValue <= maxProof else { return false }
                
                // Price filter
                let priceValue = whiskey.price as? Double ?? 0
                guard priceValue >= minPrice && priceValue <= maxPrice else { return false }
                
                // Age filter - need to extract numeric value
                if let ageStr = whiskey.age, !ageStr.isEmpty {
                    if let ageValue = extractNumericValue(from: ageStr) {
                        guard Double(ageValue) >= minAge && Double(ageValue) <= maxAge else { return false }
                    }
                } else if minAge > 0 {
                    // If min age > 0 and no age data, exclude this whiskey
                    return false
                }
                
                // Open status filter
                let matchesOpen: Bool
                switch openState {
                case .all: matchesOpen = true  // Show all whiskeys regardless of open status
                case .yes: matchesOpen = whiskey.isOpen  // Only show open bottles
                case .no: matchesOpen = !whiskey.isOpen  // Only show sealed bottles
                }
                guard matchesOpen else { return false }
                
                // Tasted status filter
                let matchesTasted: Bool
                let hasJournalEntries = (whiskey.journalEntries?.count ?? 0) > 0
                let isMarkedAsTasted = whiskey.isTasted
                let isTasted = hasJournalEntries || isMarkedAsTasted
                switch tastedState {
                case .all: matchesTasted = true  // Show all whiskeys regardless of tasted status
                case .yes: matchesTasted = isTasted  // Only show tasted whiskeys
                case .no: matchesTasted = !isTasted  // Only show untasted whiskeys
                }
                guard matchesTasted else { return false }
                
                // Dead bottle filter
                let matchesDeadBottle: Bool
                switch deadBottleState {
                case .all: matchesDeadBottle = true  // Show all whiskeys regardless of dead status
                case .yes: matchesDeadBottle = whiskey.isCompletelyDead  // ONLY show whiskeys where ALL bottles are dead
                case .no: matchesDeadBottle = whiskey.hasActiveBottles  // Only show whiskeys with at least 1 active bottle
                }
                guard matchesDeadBottle else { return false }
                
                // Single Barrel filter
                let matchesSingleBarrel: Bool
                switch singleBarrelState {
                case .all: matchesSingleBarrel = true  // Show all whiskeys regardless of SiB status
                case .yes: matchesSingleBarrel = whiskey.isSiB  // Only show single barrel whiskeys
                case .no: matchesSingleBarrel = !whiskey.isSiB  // Only show non-single barrel whiskeys
                }
                guard matchesSingleBarrel else { return false }
                
                return true
            }
        }
        
        // Apply search text filter if needed
        if !searchText.isEmpty {
            filtered = filtered.filter { whiskey in
                let searchableText = [
                    whiskey.name,
                    whiskey.type,
                    whiskey.distillery
                ].compactMap { $0 }
                    .joined(separator: " ")
                    .lowercased()
                
                return searchableText.contains(searchText.lowercased())
            }
        }
        
        return filtered
    }
    
    // Sort the filtered whiskeys according to the current sort order
    private var sortedAndFilteredWhiskeys: [Whiskey] {
        return filteredWhiskeys.sorted { first, second in
            // If no sort criteria, maintain default order
            if sortCriteria.isEmpty {
                return (first.name ?? "") < (second.name ?? "")
            }
            
            // Apply each sort criterion in sequence
            for criterion in sortCriteria {
                let result = compareValues(first, second, for: criterion.column)
                if result != .orderedSame {
                    return criterion.ascending ? result == .orderedAscending : result == .orderedDescending
                }
            }
            
            // If all criteria are equal, maintain stable sort
            return false
        }
    }
    
    // Add a helper function to compare values for a specific column
    private func compareValues(_ first: Whiskey, _ second: Whiskey, for column: ColumnType) -> ComparisonResult {
        switch column {
        case .name:
            return (first.name ?? "").compare(second.name ?? "")
        case .type:
            return (first.type ?? "").compare(second.type ?? "")
        case .distillery:
            return (first.distillery ?? "").compare(second.distillery ?? "")
        case .price:
            let price1 = first.price as? Double ?? 0
            let price2 = second.price as? Double ?? 0
            return price1 < price2 ? .orderedAscending : price1 > price2 ? .orderedDescending : .orderedSame
        case .proof:
            let proof1 = first.proof as? Double ?? 0
            let proof2 = second.proof as? Double ?? 0
            return proof1 < proof2 ? .orderedAscending : proof1 > proof2 ? .orderedDescending : .orderedSame
        case .abv:
            let abv1 = (first.proof as? Double ?? 0) / 2
            let abv2 = (second.proof as? Double ?? 0) / 2
            return abv1 < abv2 ? .orderedAscending : abv1 > abv2 ? .orderedDescending : .orderedSame
        case .age:
            return compareAgeStrings(first.age, second.age, ascending: true) ? .orderedAscending : .orderedDescending
        case .rating:
            let rating1 = getHighestRating(for: first)
            let rating2 = getHighestRating(for: second)
            return rating1 < rating2 ? .orderedAscending : rating1 > rating2 ? .orderedDescending : .orderedSame
        case .open:
            return first.isOpen == second.isOpen ? .orderedSame : first.isOpen ? .orderedAscending : .orderedDescending
        case .tasted:
            let tasted1 = first.isTasted || (first.journalEntries?.count ?? 0) > 0
            let tasted2 = second.isTasted || (second.journalEntries?.count ?? 0) > 0
            return tasted1 == tasted2 ? .orderedSame : tasted1 ? .orderedAscending : .orderedDescending
        case .bib:
            return first.isBiB == second.isBiB ? .orderedSame : first.isBiB ? .orderedAscending : .orderedDescending
        case .sib:
            return first.isSiB == second.isSiB ? .orderedSame : first.isSiB ? .orderedAscending : .orderedDescending
        case .dateAdded:
            return (first.addedDate ?? Date.distantPast).compare(second.addedDate ?? Date.distantPast)
        }
    }
    
    // Helper function to compare age strings
    private func compareAgeStrings(_ age1: String?, _ age2: String?, ascending: Bool) -> Bool {
        // Extract numeric values if possible
        let numValue1 = extractNumericValue(from: age1)
        let numValue2 = extractNumericValue(from: age2)
        
        // If both have numeric values, compare them
        if let num1 = numValue1, let num2 = numValue2 {
            return ascending ? num1 < num2 : num1 > num2
        }
        
        // Otherwise fall back to string comparison
        let str1 = age1 ?? ""
        let str2 = age2 ?? ""
        return ascending ? str1 < str2 : str1 > str2
    }
    
    // Helper function to extract numeric value from age string
    private func extractNumericValue(from ageString: String?) -> Int? {
        guard let ageStr = ageString else { return nil }
        
        // Try to extract just the number using regex
        let pattern = "\\d+"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(ageStr.startIndex..., in: ageStr)
        
        if let match = regex?.firstMatch(in: ageStr, range: range),
           let matchRange = Range(match.range, in: ageStr),
           let value = Int(ageStr[matchRange]) {
            return value
        }
        
        return nil
    }
    
    // Get favorite whiskeys (highest rated)
    private func getFavoriteWhiskeys() -> [Whiskey] {
        let request: NSFetchRequest<JournalEntry> = JournalEntry.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.overallRating, ascending: false)]
        request.predicate = NSPredicate(format: "whiskey != nil AND overallRating > 80")
        
        do {
            let journalEntries = try viewContext.fetch(request)
            var uniqueWhiskeys: [UUID: Whiskey] = [:]
            
            for entry in journalEntries {
                if let whiskey = entry.whiskey, let id = whiskey.id,
                   whiskey.status == "owned", // Only include owned whiskeys
                   uniqueWhiskeys[id] == nil {
                    uniqueWhiskeys[id] = whiskey
                }
            }
            
            return Array(uniqueWhiskeys.values)
        } catch {
            print("Error fetching favorites: \(error)")
            return []
        }
    }
    
    // Get highest rating for a whiskey (for Rating column)
    private func getHighestRating(for whiskey: Whiskey) -> Double {
        let request: NSFetchRequest<JournalEntry> = JournalEntry.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \JournalEntry.overallRating, ascending: false)]
        request.predicate = NSPredicate(format: "whiskey == %@ AND overallRating > 0", whiskey)
        request.fetchLimit = 1
        
        do {
            let entries = try viewContext.fetch(request)
            return entries.first?.overallRating ?? 0
        } catch {
            print("Error fetching rating: \(error)")
            return 0
        }
    }
    
    // Calculate counts for each whiskey type
    private func calculateWhiskeyTypeCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        var othersCount = 0
        
        // Count whiskeys by type
        for whiskey in whiskeys {
            if let type = whiskey.type, !type.isEmpty {
                // Normalize the type (trim whitespace, capitalize first letter)
                let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(1).uppercased() + type.dropFirst().lowercased()
                
                // Increment the count for this type
                counts[normalizedType, default: 0] += 1
            } else {
                // Count whiskeys with no type as "Others"
                othersCount += 1
            }
        }
        
        // Filter out types with less than 10 bottles and add them to "Others"
        var filteredCounts = counts.filter { $0.value >= 10 }
        let otherTypesCount = counts.filter { $0.value < 10 }.values.reduce(0, +)
        
        // Add the count of types with less than 10 bottles to "Others"
        if otherTypesCount > 0 {
            filteredCounts["Others"] = (filteredCounts["Others"] ?? 0) + otherTypesCount + othersCount
        } else if othersCount > 0 {
            filteredCounts["Others"] = othersCount
        }
        
        return filteredCounts
    }
    
    // Add this function to the iPadCollectionGridView struct
    private func calculateVisibleColumns() -> Int {
        var count = 1 // Name column is always visible
        
        if showTypeColumn { count += 1 }
        if showDistilleryColumn { count += 1 }
        if showAgeColumn { count += 1 }
        if showProofColumn { count += 1 }
        if showABVColumn { count += 1 }
        if showPriceColumn { count += 1 }
        if showRatingColumn { count += 1 }
        if showOpenColumn { count += 1 }
        if showTastedColumn { count += 1 }
        if showBiBColumn { count += 1 }
        if showSiBColumn { count += 1 }
        if showDateAddedColumn { count += 1 }
        
        return count
    }
    
    // Add these helper functions to the iPadCollectionGridView struct
    private func getSortOrderAscending(for column: ColumnType) -> SortOrder? {
        switch column {
        case .name: return .nameAscending
        case .type: return .typeAscending
        case .distillery: return .distilleryAscending
        case .age: return .ageAscending
        case .proof: return .proofAscending
        case .abv: return .abvAscending
        case .price: return .priceAscending
        case .rating: return .ratingAscending
        case .open: return .openAscending
        case .tasted: return .tastedAscending
        case .bib: return .bibAscending
        case .sib: return .sibAscending
        case .dateAdded: return .dateAddedAscending
        }
    }
    
    private func getSortOrderDescending(for column: ColumnType) -> SortOrder? {
        switch column {
        case .name: return .nameDescending
        case .type: return .typeDescending
        case .distillery: return .distilleryDescending
        case .age: return .ageDescending
        case .proof: return .proofDescending
        case .abv: return .abvDescending
        case .price: return .priceDescending
        case .rating: return .ratingDescending
        case .open: return .openDescending
        case .tasted: return .tastedDescending
        case .bib: return .bibDescending
        case .sib: return .sibDescending
        case .dateAdded: return .dateAddedDescending
        }
    }
    
    private func toggleSort(for column: ColumnType) {
        if let ascending = getSortOrderAscending(for: column),
           let descending = getSortOrderDescending(for: column) {
            sortCriteria = sortCriteria.map { criterion in
                if criterion.column == column {
                    return SortCriterion(column: column, ascending: !criterion.ascending)
                }
                return criterion
            }
        }
    }
    
    private func isColumnVisible(_ column: ColumnType) -> Bool {
        switch column {
        case .name: return true
        case .type: return showTypeColumn
        case .distillery: return showDistilleryColumn
        case .age: return showAgeColumn
        case .proof: return showProofColumn
        case .abv: return showABVColumn
        case .price: return showPriceColumn
        case .rating: return showRatingColumn
        case .open: return showOpenColumn
        case .tasted: return showTastedColumn
        case .bib: return showBiBColumn
        case .sib: return showSiBColumn
        case .dateAdded: return showDateAddedColumn
        }
    }
    
    private func calculateColumnWidth(for column: ColumnType) -> CGFloat {
        let visibleColumns = columnOrder.filter(isColumnVisible)
        return column.calculateWidth(totalWidth: UIScreen.main.bounds.width, visibleColumns: visibleColumns)
    }
    
    private func handleSort(for column: ColumnType) {
        // Check if this column is already being sorted
        if let index = sortCriteria.firstIndex(where: { $0.column == column }) {
            // If it's the only sort criterion, toggle its direction
            if sortCriteria.count == 1 {
                // Create a new array with a new SortCriterion
                sortCriteria = [SortCriterion(column: column, ascending: !sortCriteria[0].ascending)]
            } else {
                // If there are multiple sort criteria, remove this one
                sortCriteria.remove(at: index)
            }
        } else {
            // Add this column as a new sort criterion (ascending by default)
            sortCriteria.append(SortCriterion(column: column, ascending: true))
        }
    }
    
    private func columnHeader(_ column: ColumnType) -> some View {
        Button(action: {
            handleSort(for: column)
        }) {
            HStack(spacing: 4) {
                Text(column.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                
                if let sortIndex = sortCriteria.firstIndex(where: { $0.column == column }) {
                    // Show sort priority number instead of icon
                    Text("\(sortIndex + 1)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                        .background(
                            Circle()
                                .fill(Color.secondary.opacity(0.2))
                        )
                } else if sortCriteria.contains(where: { $0.column == column }) {
                    // Fallback to icon if something unexpected happens
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: calculateColumnWidth(for: column))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // Break down the complex expression in the filter section
    private var isRangeFilterActive: Bool {
        let isProofFiltered = minProof > proofBounds.lowerBound || maxProof < proofBounds.upperBound
        let isPriceFiltered = minPrice > priceBounds.lowerBound || maxPrice < priceBounds.upperBound
        let isAgeFiltered = minAge > ageBounds.lowerBound || maxAge < ageBounds.upperBound
        return isProofFiltered || isPriceFiltered || isAgeFiltered
    }
}

// Sort order options
enum SortOrder {
    case nameAscending
    case nameDescending
    case typeAscending
    case typeDescending
    case distilleryAscending
    case distilleryDescending
    case priceAscending
    case priceDescending
    case proofAscending
    case proofDescending
    case abvAscending
    case abvDescending
    case ageAscending
    case ageDescending
    case ratingAscending
    case ratingDescending
    case openAscending
    case openDescending
    case tastedAscending
    case tastedDescending
    case bibAscending
    case bibDescending
    case sibAscending
    case sibDescending
    case dateAddedAscending
    case dateAddedDescending
    case dateAdded
    
    var displayName: String {
        switch self {
        case .nameAscending: return "Name (A-Z)"
        case .nameDescending: return "Name (Z-A)"
        case .typeAscending: return "Type (A-Z)"
        case .typeDescending: return "Type (Z-A)"
        case .distilleryAscending: return "Distillery (A-Z)"
        case .distilleryDescending: return "Distillery (Z-A)"
        case .priceAscending: return "Price (Low-High)"
        case .priceDescending: return "Price (High-Low)"
        case .proofAscending: return "Proof (Low-High)"
        case .proofDescending: return "Proof (High-Low)"
        case .abvAscending: return "ABV (Low-High)"
        case .abvDescending: return "ABV (High-Low)"
        case .ageAscending: return "Age (Low-High)"
        case .ageDescending: return "Age (High-Low)"
        case .ratingAscending: return "Rating (Low-High)"
        case .ratingDescending: return "Rating (High-Low)"
        case .openAscending: return "Open (Yes-No)"
        case .openDescending: return "Open (No-Yes)"
        case .tastedAscending: return "Tasted (Yes-No)"
        case .tastedDescending: return "Tasted (No-Yes)"
        case .bibAscending: return "BiB (Yes-No)"
        case .bibDescending: return "BiB (No-Yes)"
        case .sibAscending: return "SiB (Yes-No)"
        case .sibDescending: return "SiB (No-Yes)"
        case .dateAddedAscending: return "Date Added (Old-New)"
        case .dateAddedDescending: return "Date Added (New-Old)"
        case .dateAdded: return "Recently Added"
        }
    }
}

// Filter button component
struct FilterButton: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue.opacity(0.2) : Color(UIColor.secondarySystemBackground))
                .foregroundColor(isSelected ? .blue : .primary)
                .cornerRadius(20)
        }
    }
}

// Table column header with sort indicators
struct TableColumnHeader: View {
    var columnType: ColumnType
    var width: CGFloat
    var sortCriteria: [SortCriterion]
    var action: () -> Void = {}
    var onDragStarted: () -> Void = {}
    var onDragEnded: () -> Void = {}
    var columnOrder: [ColumnType]
    var isColumnVisible: (ColumnType) -> Bool
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(columnType.rawValue)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                
                // Show sort indicator if this column is being sorted
                if let index = sortCriteria.firstIndex(where: { $0.column == columnType }) {
                    let criterion = sortCriteria[index]
                    if sortCriteria.count == 1 {
                        // If there's only one sort criterion, show the direction arrow
                        Text(criterion.ascending ? "↑" : "↓")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    } else {
                        // If there are multiple sort criteria, show the priority number
                        Text("\(index + 1)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16)
                            .background(
                                Circle()
                                    .fill(Color.secondary.opacity(0.2))
                            )
                    }
                }
                
                // Add reorder icon only if the column is not being sorted
                if sortCriteria.firstIndex(where: { $0.column == columnType }) == nil {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .opacity(0.6)
                }
            }
            .frame(width: width - 16, alignment: columnType == .name || columnType == .type || columnType == .distillery || columnType == .dateAdded ? .leading : .center)
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
        .onDrag {
            onDragStarted()
            return NSItemProvider(object: columnType.rawValue as NSString)
        }
        .onDisappear {
            onDragEnded()
        }
    }
}

// Table row for whiskey display
struct WhiskeyTableRow: View {
    var whiskey: Whiskey
    var columnOrder: [ColumnType]
    var rating: Double = 0
    var isColumnVisible: (ColumnType) -> Bool
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(columnOrder, id: \.self) { column in
                if isColumnVisible(column) {
                    let visibleColumns = columnOrder.filter(isColumnVisible)
                    let width = column.calculateWidth(totalWidth: UIScreen.main.bounds.width, visibleColumns: visibleColumns)
                    switch column {
                    case .name:
                        HStack(spacing: 8) {
                            Image(systemName: whiskey.isOpen ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(whiskey.isOpen ? .orange : .secondary)
                                .font(.system(size: 16))
                            Text(whiskey.name ?? "Unknown")
                                .font(.system(size: 16, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(width: width - 16, alignment: .leading)
                        .padding(.horizontal, 8)
                    case .type:
                        Text(whiskey.type ?? "Unknown")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: width - 16, alignment: .leading)
                            .padding(.horizontal, 8)
                    case .distillery:
                        Text(whiskey.distillery ?? "Unknown")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(width: width - 16, alignment: .leading)
                            .padding(.horizontal, 8)
                    case .age:
                        if let ageStr = whiskey.age, !ageStr.isEmpty {
                            Text(ageStr)
                                .font(.system(size: 15))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: width - 16, alignment: .center)
                                .padding(.horizontal, 8)
                        } else {
                            Text("—")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                                .frame(width: width - 16, alignment: .center)
                                .padding(.horizontal, 8)
                        }
                    case .proof:
                        if let proof = whiskey.proof as? Double, proof > 0 {
                            let proofText = proof.truncatingRemainder(dividingBy: 1) == 0 ? 
                                String(format: "%.0f", proof) : 
                                String(format: "%.1f", proof)
                            Text(proofText)
                                .font(.system(size: 15))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: width - 16, alignment: .center)
                                .padding(.horizontal, 8)
                        } else {
                            Text("—")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                                .frame(width: width - 16, alignment: .center)
                                .padding(.horizontal, 8)
                        }
                    case .abv:
                        if let proof = whiskey.proof as? Double, proof > 0 {
                            let abv = proof / 2
                            let abvText = abv.truncatingRemainder(dividingBy: 1) == 0 ? 
                                String(format: "%.0f", abv) : 
                                String(format: "%.1f", abv)
                            Text("\(abvText)%")
                                .font(.system(size: 15))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: width - 16, alignment: .center)
                                .padding(.horizontal, 8)
                        } else {
                            Text("—")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                                .frame(width: width - 16, alignment: .center)
                                .padding(.horizontal, 8)
                        }
                    case .price:
                        if let price = whiskey.price as? Double, price > 0 {
                            Text("$\(String(format: "%.0f", price))")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.blue)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: width - 16, alignment: .center)
                                .padding(.horizontal, 8)
                        } else {
                            Text("—")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                                .frame(width: width - 16, alignment: .center)
                                .padding(.horizontal, 8)
                        }
                    case .rating:
                        if rating > 0 {
                            Text("\(String(format: "%.0f", rating))")
                                .font(.system(size: 15))
                                .foregroundColor(rating >= 85 ? .green : .primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: width - 16, alignment: .center)
                                .padding(.horizontal, 8)
                        } else {
                            Text("—")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                                .frame(width: width - 16, alignment: .center)
                                .padding(.horizontal, 8)
                        }
                    case .open:
                        HStack {
                            if whiskey.isOpen {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.orange)
                            } else {
                                Text("—")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: width - 16, alignment: .center)
                        .padding(.horizontal, 8)
                    case .tasted:
                        HStack {
                            if whiskey.isTasted {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.purple)
                            } else {
                                Text("—")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: width - 16, alignment: .center)
                        .padding(.horizontal, 8)
                    case .bib:
                        HStack {
                            if whiskey.isBiB {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.yellow)
                            } else {
                                Text("—")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: width - 16, alignment: .center)
                        .padding(.horizontal, 8)
                    case .sib:
                        HStack {
                            if whiskey.isSiB {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.green)
                            } else {
                                Text("—")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: width - 16, alignment: .center)
                        .padding(.horizontal, 8)
                    case .dateAdded:
                        if let addedDate = whiskey.addedDate {
                            Text(formatDate(addedDate))
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(width: width - 16, alignment: .leading)
                                .padding(.horizontal, 8)
                        } else {
                            Text("—")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .frame(width: width - 16, alignment: .leading)
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
    }
    
    // Format date for display
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

#Preview {
    iPadCollectionGridView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}

// Range slider component for the filter
struct SliderView: View {
    @Binding var value: [Double]
    let bounds: ClosedRange<Double>
    let step: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 4)
                    .padding(.horizontal, 12) // Add padding on sides to prevent thumbs from going edge to edge
                
                // Selected range
                let minX = position(for: value[0], width: geometry.size.width - 24) + 12 // Adjust for padding
                let maxX = position(for: value[1], width: geometry.size.width - 24) + 12 // Adjust for padding
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.blue)
                    .frame(width: max(0, maxX - minX), height: 4)
                    .offset(x: minX)
                
                // Min thumb
                Circle()
                    .fill(Color.white)
                    .shadow(radius: 2)
                    .frame(width: 24, height: 24)
                    .offset(x: minX - 12)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                let newValue = valueAt(position: gesture.location.x - 12, width: geometry.size.width - 24)
                                let steppedValue = roundToStep(newValue)
                                // Ensure there's at least one step difference between min and max values
                                if steppedValue <= value[1] - step && steppedValue >= bounds.lowerBound {
                                    value[0] = steppedValue
                                }
                            }
                    )
                
                // Max thumb
                Circle()
                    .fill(Color.white)
                    .shadow(radius: 2)
                    .frame(width: 24, height: 24)
                    .offset(x: maxX - 12)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                let newValue = valueAt(position: gesture.location.x - 12, width: geometry.size.width - 24)
                                let steppedValue = roundToStep(newValue)
                                // Ensure there's at least one step difference between min and max values
                                if steppedValue >= value[0] + step && steppedValue <= bounds.upperBound {
                                    value[1] = steppedValue
                                }
                            }
                    )
            }
        }
        .frame(height: 30)
    }
    
    // Convert value to position
    private func position(for value: Double, width: CGFloat) -> CGFloat {
        let range = bounds.upperBound - bounds.lowerBound
        let relativeValue = value - bounds.lowerBound
        let ratio = CGFloat(relativeValue / range)
        return ratio * width
    }
    
    // Convert position to value
    private func valueAt(position: CGFloat, width: CGFloat) -> Double {
        let ratio = max(0, min(1, position / width))
        let range = bounds.upperBound - bounds.lowerBound
        return bounds.lowerBound + Double(ratio) * range
    }
    
    // Round value to nearest step
    private func roundToStep(_ value: Double) -> Double {
        let steps = round(value / step)
        return steps * step
    }
}

// Add this struct after the iPadCollectionGridView struct
struct ColumnDropDelegate: DropDelegate {
    let item: ColumnType
    @Binding var columnOrder: [ColumnType]
    @Binding var isDragging: Bool
    
    func performDrop(info: DropInfo) -> Bool {
        isDragging = false
        return true
    }
    
    func dropEntered(info: DropInfo) {
        // Get the dragged item
        guard let draggedItem = info.itemProviders(for: [.text]).first else { return }
        
        // Load the dragged item's data
        draggedItem.loadObject(ofClass: NSString.self) { string, _ in
            guard let columnTitle = string as? String,
                  let draggedColumn = ColumnType(rawValue: columnTitle),
                  let fromIndex = columnOrder.firstIndex(of: draggedColumn),
                  let toIndex = columnOrder.firstIndex(of: item) else { return }
            
            // Only update if the indices are different
            if fromIndex != toIndex {
                DispatchQueue.main.async {
                    // Remove the item from its original position
                    let item = columnOrder.remove(at: fromIndex)
                    
                    // Insert it at the new position
                    columnOrder.insert(item, at: toIndex)
                    
                    // Print for debugging
                    print("Moved column from \(fromIndex) to \(toIndex)")
                }
            }
        }
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        return true
    }
    
    func dropExited(info: DropInfo) {
        // Reset dragging state when exiting a drop target
        isDragging = false
    }
}

// Add this new component at the bottom of the file
struct StatusFilterButton: View {
    let title: String
    let state: ToggleState
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .medium))
                
                Text(state.rawValue)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(state == .all ? .secondary : 
                                   state == .yes ? .green : .red)
            }
            .frame(minWidth: 100)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
} 
