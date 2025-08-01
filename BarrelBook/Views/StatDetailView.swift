import SwiftUI
import CoreData

// Detail view shown when a statistics section is tapped
struct StatDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.presentationMode) var presentationMode
    
    @Binding var isActive: Bool
    let title: String
    let whiskeys: [Whiskey]
    let initialFilter: WhiskeyFilter?
    
    @State private var filter: WhiskeyFilter?
    @State private var filteredWhiskeys: [Whiskey] = []
    @State private var searchText = ""
    @State private var viewStateUpdater = UUID()
    @State private var selectedWhiskeyID: NSManagedObjectID? = nil
    @State private var showingHostedDetail = false
    @State private var tastingFilter: TastingFilter = .all
    @State private var sortOption: SortOption = .nameAsc
    @State private var showingSortMenu = false
    
    enum TastingFilter {
        case all
        case tasted
        case untasted
    }
    
    enum SortOption: String, CaseIterable {
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Show tasting filter for views that are part of the "Coverage by Type" section
            if initialFilter != nil && 
               initialFilter?.section != .collectionOverview && 
               initialFilter?.section != .specialAttributes && 
               initialFilter?.section != .topDistilleries && 
               initialFilter?.section != .collectionComposition && 
               initialFilter?.section != .proofAnalysis && 
               initialFilter?.section != .priceAnalysis {
                HStack {
                    Text("Show:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("Filter", selection: $tastingFilter) {
                        Text("All").tag(TastingFilter.all)
                        Text("Tasted").tag(TastingFilter.tasted)
                        Text("Untasted").tag(TastingFilter.untasted)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 250)
                    .onChange(of: tastingFilter) { _ in
                        updateFilteredWhiskeys()
                    }
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemGroupedBackground))
            }
            
            // Add collection summary info (count and value)
            HStack {
                let currentBottles = filteredWhiskeys.count
                let currentValue = filteredWhiskeys.reduce(0.0) { $0 + ($1.price * Double($1.numberOfBottles)) }
                
                Text("\(currentBottles) bottle\(currentBottles == 1 ? "" : "s")")
                    .foregroundColor(.secondary)
                Text("•")
                    .foregroundColor(.secondary)
                PrivacyAwareValueText(value: currentValue)
            }
            .font(.footnote)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
            
            // Main content
            Group {
                if filteredWhiskeys.isEmpty {
                    VStack(spacing: 20) {
                        Text("No matching whiskeys found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(UIColor.systemGroupedBackground))
                } else {
                    List {
                        ForEach(filteredWhiskeys) { whiskey in
                            Button(action: {
                                // Store only the object ID, not the object itself
                                selectedWhiskeyID = whiskey.objectID
                                showingHostedDetail = true
                            }) {
                                WhiskeyRowView(whiskey: whiskey)
                            }
                        }
                    }
                    .background(Color(UIColor.systemGroupedBackground))
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search whiskeys")
        .onAppear {
            print("📱 StatDetailView appeared with title: \(title)")
            filter = initialFilter
            
            // Set default sort based on filter type
            if let filter = initialFilter {
                switch filter.type {
                case .proof(_, _):
                    sortOption = .proofLow
                case .price(_, _):
                    sortOption = .priceLow
                default:
                    sortOption = .nameAsc
                }
            }
            
            updateFilteredWhiskeys()
        }
        .onChange(of: searchText) { _ in
            updateFilteredWhiskeys()
        }
        .onChange(of: filter) { _ in
            updateFilteredWhiskeys()
        }
        .onChange(of: sortOption) { _ in
            sortFilteredWhiskeys()
        }
        .id(viewStateUpdater)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ForEach(SortOption.allCases, id: \.self) { option in
                        Button(action: {
                            sortOption = option
                        }) {
                            HStack {
                                Text(option.rawValue)
                                if sortOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .background(
            // Special hosting controller that prevents navigation stack corruption
            NavigationLink(
                destination: WhiskeyDetailHostingView(objectID: selectedWhiskeyID),
                isActive: $showingHostedDetail
            ) {
                EmptyView()
            }
        )
    }
    
    private func updateFilteredWhiskeys() {
        print("🔄 Updating filtered whiskeys with filter: \(String(describing: filter))")
        print("📊 Total whiskeys: \(whiskeys.count)")
        
        // Start with all whiskeys
        var filtered = whiskeys
        
        // Apply filter if present
        if let currentFilter = filter {
            print("🔍 Applying filter: \(currentFilter)")
            // Create a new array with only the matching whiskeys
            let matchingWhiskeys = filtered.filter { whiskey in
                // Check if the whiskey matches the current filter
                let matches = matchesFilter(whiskey: whiskey, filter: currentFilter)
                return matches
            }
            
            // Update the filtered array
            filtered = matchingWhiskeys
            print("📊 After filter: \(filtered.count) whiskeys")
        }
        
        // Apply tasted filter if needed
        switch tastingFilter {
        case .tasted:
            filtered = filtered.filter { whiskey in
                let hasJournalEntries = (whiskey.journalEntries?.count ?? 0) > 0
                let isMarkedAsTasted = whiskey.isTasted
                return hasJournalEntries || isMarkedAsTasted
            }
            print("📊 After tasted filter: \(filtered.count) whiskeys")
        case .untasted:
            filtered = filtered.filter { whiskey in
                let hasJournalEntries = (whiskey.journalEntries?.count ?? 0) > 0
                let isMarkedAsTasted = whiskey.isTasted
                return !hasJournalEntries && !isMarkedAsTasted
            }
            print("📊 After untasted filter: \(filtered.count) whiskeys")
        case .all:
            // No additional filtering needed
            break
        }
        
        // Apply search text if present
        if !searchText.isEmpty {
            // Create a new array with only the matching whiskeys
            let matchingWhiskeys = filtered.filter { whiskey in
                // Check if the whiskey matches the search text
                let nameMatch = (whiskey.name ?? "").localizedCaseInsensitiveContains(searchText)
                let distilleryMatch = (whiskey.distillery ?? "").localizedCaseInsensitiveContains(searchText)
                let typeMatch = (whiskey.type ?? "").localizedCaseInsensitiveContains(searchText)
                
                return nameMatch || distilleryMatch || typeMatch
            }
            
            // Update the filtered array
            filtered = matchingWhiskeys
            print("📊 After search: \(filtered.count) whiskeys")
        }
        
        // Update the filtered whiskeys
        filteredWhiskeys = filtered
        print("📊 Final filtered count: \(filteredWhiskeys.count)")
        
        // Apply sorting
        sortFilteredWhiskeys()
    }
    
    private func sortFilteredWhiskeys() {
        print("🔄 Sorting filtered whiskeys with option: \(sortOption)")
        print("📊 Total whiskeys: \(filteredWhiskeys.count)")
        
        // Sort the filtered whiskeys based on the selected sort option
        filteredWhiskeys = filteredWhiskeys.sorted(by: { (whiskey1: Whiskey, whiskey2: Whiskey) -> Bool in
            switch sortOption {
            case .nameAsc:
                return (whiskey1.name ?? "") < (whiskey2.name ?? "")
            case .nameDesc:
                return (whiskey1.name ?? "") > (whiskey2.name ?? "")
            case .proofHigh:
                return whiskey1.proof > whiskey2.proof
            case .proofLow:
                return whiskey1.proof < whiskey2.proof
            case .priceHigh:
                return whiskey1.price > whiskey2.price
            case .priceLow:
                return whiskey1.price < whiskey2.price
            case .typeAsc:
                return (whiskey1.type ?? "") < (whiskey2.type ?? "")
            case .ageDesc:
                return (whiskey1.age ?? "") > (whiskey2.age ?? "")
            case .ageAsc:
                return (whiskey1.age ?? "") < (whiskey2.age ?? "")
            case .openFirst:
                return whiskey1.isOpen
            case .sealedFirst:
                return !whiskey1.isOpen
            case .dateAdded:
                // Use modificationDate if available, otherwise fallback to name
                if let date1 = whiskey1.modificationDate, let date2 = whiskey2.modificationDate {
                    return date1 > date2  // Newest first
                } else {
                    return (whiskey1.name ?? "") < (whiskey2.name ?? "")
                }
            }
        })
        
        print("📊 After sorting: \(filteredWhiskeys.count) whiskeys")
    }
    
    private func matchesFilter(whiskey: Whiskey, filter: WhiskeyFilter) -> Bool {
        switch filter.type {
        case .type(let type):
            return whiskey.type == type
        case .proof(let min, let max):
            return whiskey.proof >= min && whiskey.proof <= max
        case .attribute(let attribute, let value):
            switch attribute {
            case "Bottled in Bond":
                return whiskey.isBiB == value
            case "Single Barrel":
                return whiskey.isSiB == value
            case "Store Picks", "Store Pick":
                return whiskey.isStorePick == value
            case "High Proof":
                return whiskey.proof > 100
            case "Tasted":
                let hasJournalEntries = (whiskey.journalEntries?.count ?? 0) > 0
                let isMarkedAsTasted = whiskey.isTasted
                return value == (hasJournalEntries || isMarkedAsTasted)
            case "Other Types":
                // For "Other" category logic
                let topTypes = whiskeys
                    .reduce(into: [String: Int]()) { counts, whiskey in
                        if let type = whiskey.type {
                            counts[type, default: 0] += 1
                        }
                    }
                    .sorted { $0.value > $1.value }
                    .prefix(3)
                    .map { $0.key }
                
                return whiskey.type == nil || !topTypes.contains(whiskey.type!)
            case "Finished Whiskeys in Other Types":
                // First check if it's in the "Other" category
                let topTypes = whiskeys
                    .reduce(into: [String: Int]()) { counts, whiskey in
                        if let type = whiskey.type {
                            counts[type, default: 0] += 1
                        }
                    }
                    .sorted { $0.value > $1.value }
                    .prefix(3)
                    .map { $0.key }
                
                let isOtherType = whiskey.type == nil || !topTypes.contains(whiskey.type!)
                let hasFinish = whiskey.finish != nil && !whiskey.finish!.isEmpty
                let hasFinishInName = whiskey.name?.lowercased().contains("port") ?? false ||
                                    whiskey.name?.lowercased().contains("sherry") ?? false ||
                                    whiskey.name?.lowercased().contains("madeira") ?? false ||
                                    whiskey.name?.lowercased().contains("rum") ?? false ||
                                    whiskey.name?.lowercased().contains("cognac") ?? false
                
                return isOtherType && (hasFinish || hasFinishInName)
            case "Single Barrel in Other Types":
                // First check if it's in the "Other" category
                let topTypes = whiskeys
                    .reduce(into: [String: Int]()) { counts, whiskey in
                        if let type = whiskey.type {
                            counts[type, default: 0] += 1
                        }
                    }
                    .sorted { $0.value > $1.value }
                    .prefix(3)
                    .map { $0.key }
                
                let isOtherType = whiskey.type == nil || !topTypes.contains(whiskey.type!)
                return isOtherType && whiskey.isSiB
            case "Bottled in Bond in Other Types":
                // First check if it's in the "Other" category
                let topTypes = whiskeys
                    .reduce(into: [String: Int]()) { counts, whiskey in
                        if let type = whiskey.type {
                            counts[type, default: 0] += 1
                        }
                    }
                    .sorted { $0.value > $1.value }
                    .prefix(3)
                    .map { $0.key }
                
                let isOtherType = whiskey.type == nil || !topTypes.contains(whiskey.type!)
                return isOtherType && whiskey.isBiB
            case "Store Picks in Other Types":
                // First check if it's in the "Other" category
                let topTypes = whiskeys
                    .reduce(into: [String: Int]()) { counts, whiskey in
                        if let type = whiskey.type {
                            counts[type, default: 0] += 1
                        }
                    }
                    .sorted { $0.value > $1.value }
                    .prefix(3)
                    .map { $0.key }
                
                let isOtherType = whiskey.type == nil || !topTypes.contains(whiskey.type!)
                return isOtherType && whiskey.isStorePick
            case "No Special Attributes in Other Types":
                // First check if it's in the "Other" category
                let topTypes = whiskeys
                    .reduce(into: [String: Int]()) { counts, whiskey in
                        if let type = whiskey.type {
                            counts[type, default: 0] += 1
                        }
                    }
                    .sorted { $0.value > $1.value }
                    .prefix(3)
                    .map { $0.key }
                
                let isOtherType = whiskey.type == nil || !topTypes.contains(whiskey.type!)
                let hasFinish = whiskey.finish != nil && !whiskey.finish!.isEmpty
                let hasFinishInName = whiskey.name?.lowercased().contains("port") ?? false ||
                                    whiskey.name?.lowercased().contains("sherry") ?? false ||
                                    whiskey.name?.lowercased().contains("madeira") ?? false ||
                                    whiskey.name?.lowercased().contains("rum") ?? false ||
                                    whiskey.name?.lowercased().contains("cognac") ?? false
                
                return isOtherType && !whiskey.isSiB && !whiskey.isBiB && !whiskey.isStorePick && 
                       !hasFinish && !hasFinishInName
            default:
                return false
            }
        case .distillery(let distillery):
            return whiskey.distillery == distillery
        case .finishType(let finish):
            return whiskey.finish == finish
        case .subtype(let parent, let child):
            print("🔍 Checking subtype: Parent=\(parent), Subtype=\(child)")
            print("🔍 Whiskey: Type=\(whiskey.type ?? "nil"), isSiB=\(whiskey.isSiB), isBiB=\(whiskey.isBiB), isStorePick=\(whiskey.isStorePick)")
            
            // First check if this is an "Other" category
            if parent == "Other" {
                // Get the top types to exclude
                let topTypes = whiskeys
                    .reduce(into: [String: Int]()) { counts, whiskey in
                        if let type = whiskey.type {
                            counts[type, default: 0] += 1
                        }
                    }
                    .sorted { $0.value > $1.value }
                    .prefix(3)
                    .map { $0.key }
                
                // Check if this whiskey is in the "Other" category (not in top types)
                let isOtherType = whiskey.type == nil || !topTypes.contains(whiskey.type!)
                
                if !isOtherType {
                    return false
                }
                
                // Now check the subtype
                switch child {
                case "Finished":
                    let hasFinish = whiskey.finish != nil && !whiskey.finish!.isEmpty
                    let hasFinishInName = whiskey.name?.lowercased().contains("port") ?? false ||
                                        whiskey.name?.lowercased().contains("sherry") ?? false ||
                                        whiskey.name?.lowercased().contains("madeira") ?? false ||
                                        whiskey.name?.lowercased().contains("rum") ?? false ||
                                        whiskey.name?.lowercased().contains("cognac") ?? false
                    return hasFinish || hasFinishInName
                case "Single Barrel":
                    return whiskey.isSiB
                case "Bottled in Bond":
                    return whiskey.isBiB
                case "Store Pick":
                    return whiskey.isStorePick
                case "Standard":
                    let hasFinish = whiskey.finish != nil && !whiskey.finish!.isEmpty
                    let hasFinishInName = whiskey.name?.lowercased().contains("port") ?? false ||
                                        whiskey.name?.lowercased().contains("sherry") ?? false ||
                                        whiskey.name?.lowercased().contains("madeira") ?? false ||
                                        whiskey.name?.lowercased().contains("rum") ?? false ||
                                        whiskey.name?.lowercased().contains("cognac") ?? false
                    return !whiskey.isSiB && !whiskey.isBiB && !whiskey.isStorePick && 
                           !hasFinish && !hasFinishInName
                default:
                    return false
                }
            }
            
            // Handle regular type/subtype combinations
            // First check if the whiskey matches the parent type
            guard whiskey.type == parent else {
                return false
            }
            
            // Then check the subtype
            switch child {
            case "Finished":
                let hasFinish = whiskey.finish != nil && !whiskey.finish!.isEmpty
                let hasFinishInName = whiskey.name?.lowercased().contains("port") ?? false ||
                                    whiskey.name?.lowercased().contains("sherry") ?? false ||
                                    whiskey.name?.lowercased().contains("madeira") ?? false ||
                                    whiskey.name?.lowercased().contains("rum") ?? false ||
                                    whiskey.name?.lowercased().contains("cognac") ?? false
                return hasFinish || hasFinishInName
            case "Single Barrel":
                return whiskey.isSiB
            case "Bottled in Bond":
                return whiskey.isBiB
            case "Store Pick":
                return whiskey.isStorePick
            case "Standard":
                let hasFinish = whiskey.finish != nil && !whiskey.finish!.isEmpty
                let hasFinishInName = whiskey.name?.lowercased().contains("port") ?? false ||
                                    whiskey.name?.lowercased().contains("sherry") ?? false ||
                                    whiskey.name?.lowercased().contains("madeira") ?? false ||
                                    whiskey.name?.lowercased().contains("rum") ?? false ||
                                    whiskey.name?.lowercased().contains("cognac") ?? false
                return !whiskey.isSiB && !whiskey.isBiB && !whiskey.isStorePick && 
                       !hasFinish && !hasFinishInName
            default:
                return false
            }
        case .tastedStatus(let tasted):
            let hasJournalEntries = (whiskey.journalEntries?.count ?? 0) > 0
            let isMarkedAsTasted = whiskey.isTasted
            return tasted == (hasJournalEntries || isMarkedAsTasted)
        case .price(let min, let max):
            return whiskey.price >= min && whiskey.price <= max
        }
    }
}

// Special hosting view that loads the whiskey by ID, not by reference
struct WhiskeyDetailHostingView: View {
    let objectID: NSManagedObjectID?
    @Environment(\.managedObjectContext) var viewContext
    @State private var whiskey: Whiskey?
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            if isLoading {
                ProgressView("Loading...")
            } else if let whiskey = whiskey {
                // Create whiskey detail with explicit ID to avoid navigation issues
                WhiskeyDetailView(whiskey: whiskey)
                    .id(whiskey.objectID) // Ensures stable identity
            } else {
                Text("Could not load whiskey")
            }
        }
        .onAppear {
            loadWhiskey()
        }
    }
    
    private func loadWhiskey() {
        guard let objectID = objectID else {
            isLoading = false
            return
        }
        
        // Load the whiskey from its ID, which is stable
        do {
            if let whiskey = try viewContext.existingObject(with: objectID) as? Whiskey {
                self.whiskey = whiskey
            }
        } catch {
            print("Error loading whiskey: \(error)")
        }
        
        isLoading = false
    }
} 