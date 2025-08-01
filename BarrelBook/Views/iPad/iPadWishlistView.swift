import SwiftUI
import CoreData

struct iPadWishlistView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var selectedTab = 0
    @State private var showingAddSheet = false
    @State private var searchText = ""
    @State private var selectedWhiskey: Whiskey? = nil
    @State private var isFiltersExpanded = true
    @State private var isTypesExpanded = true
    
    // Filter states
    @State private var selectedPriorities: Set<Int> = [1, 2, 3, 4, 5]
    @State private var selectedTypes: Set<String> = []
    @State private var selectedRarities: Set<WhiskeyRarity> = Set(WhiskeyRarity.allCases)
    @State private var showingShareSheet = false
    @State private var shareActivityVC: UIActivityViewController?
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            HStack(spacing: 0) {
                Button(action: { selectedTab = 0 }) {
                    Text("Wishlist")
                        .font(.system(size: 17, weight: selectedTab == 0 ? .semibold : .regular))
                        .foregroundColor(selectedTab == 0 ? .blue : .secondary)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            Rectangle()
                                .fill(selectedTab == 0 ? Color.blue.opacity(0.1) : Color.clear)
                        )
                }
                
                Button(action: { selectedTab = 1 }) {
                    Text("Replacements")
                        .font(.system(size: 17, weight: selectedTab == 1 ? .semibold : .regular))
                        .foregroundColor(selectedTab == 1 ? .blue : .secondary)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            Rectangle()
                                .fill(selectedTab == 1 ? Color.blue.opacity(0.1) : Color.clear)
                        )
                }
            }
            .background(Color(UIColor.secondarySystemBackground))
            
            // Content based on selected tab
            if selectedTab == 0 {
                WishlistContentView(
                    searchText: $searchText,
                    selectedWhiskey: $selectedWhiskey,
                    isFiltersExpanded: $isFiltersExpanded,
                    isTypesExpanded: $isTypesExpanded,
                    selectedPriorities: $selectedPriorities,
                    selectedTypes: $selectedTypes,
                    selectedRarities: $selectedRarities,
                    showingAddSheet: $showingAddSheet,
                    shareAction: { shareCurrentList() },
                    getCurrentItems: { getCurrentListItems() }
                )
            } else {
                ReplacementsContentView(
                    searchText: $searchText,
                    selectedWhiskey: $selectedWhiskey,
                    isFiltersExpanded: $isFiltersExpanded,
                    isTypesExpanded: $isTypesExpanded,
                    selectedPriorities: $selectedPriorities,
                    selectedTypes: $selectedTypes,
                    selectedRarities: $selectedRarities,
                    showingAddSheet: $showingAddSheet,
                    shareAction: { shareCurrentList() },
                    getCurrentItems: { getCurrentListItems() }
                )
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            AddWhiskeyToWishlistView()
                .environment(\.managedObjectContext, viewContext)
        }
        .sheet(item: $selectedWhiskey) { whiskey in
            EditWishlistItemView(whiskey: whiskey)
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
    }
    
    // Helper methods for sharing
    private func getCurrentListItems() -> [Whiskey] {
        if selectedTab == 0 {
            // Get filtered wishlist items
            let wishlistRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
            wishlistRequest.predicate = NSPredicate(format: "status == %@", "wishlist")
            wishlistRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Whiskey.priority, ascending: true)]
            
            do {
                let items = try viewContext.fetch(wishlistRequest)
                return items.filter { whiskey in
                    // Apply same filtering logic as WishlistContentView
                    var passes = true
                    
                    // Search filter
                    if !searchText.isEmpty {
                        let searchableText = [
                            whiskey.name,
                            whiskey.type,
                            whiskey.distillery
                        ].compactMap { $0 }
                            .joined(separator: " ")
                            .lowercased()
                        
                        passes = passes && searchableText.contains(searchText.lowercased())
                    }
                    
                    // Priority filter
                    if !selectedPriorities.isEmpty {
                        passes = passes && selectedPriorities.contains(Int(whiskey.priority))
                    }
                    
                    // Type filter
                    if !selectedTypes.isEmpty {
                        passes = passes && (whiskey.type != nil && selectedTypes.contains(whiskey.type!))
                    }
                    
                    // Rarity filter
                    if !selectedRarities.isEmpty {
                        if let rarityStr = whiskey.rarity,
                           let rarity = WhiskeyRarity(rawValue: rarityStr) {
                            passes = passes && selectedRarities.contains(rarity)
                        } else {
                            passes = passes && selectedRarities.contains(.notSure)
                        }
                    }
                    
                    return passes
                }
            } catch {
                print("Error fetching wishlist items: \(error)")
                return []
            }
        } else {
            // Get replacement items
            let replacementRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
            replacementRequest.predicate = NSPredicate(format: "replacementStatus == %@", "wantToReplace")
            replacementRequest.sortDescriptors = [NSSortDescriptor(keyPath: \Whiskey.name, ascending: true)]
            
            do {
                return try viewContext.fetch(replacementRequest)
            } catch {
                print("Error fetching replacement items: \(error)")
                return []
            }
        }
    }
    
    private func shareCurrentList() {
        // Ensure we're on the main thread
        DispatchQueue.main.async {
            let items = getCurrentListItems()
            
            if selectedTab == 0 {
                // Share wishlist
                WishlistSharingService.shared.shareWishlist(items) { activityVC in
                    DispatchQueue.main.async {
                        shareActivityVC = activityVC
                        showingShareSheet = true
                    }
                }
            } else {
                // Share replacements
                WishlistSharingService.shared.shareReplacements(items) { activityVC in
                    DispatchQueue.main.async {
                        shareActivityVC = activityVC
                        showingShareSheet = true
                    }
                }
            }
        }
    }
}

// Separate content views for better organization
struct WishlistContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var searchText: String
    @Binding var selectedWhiskey: Whiskey?
    @Binding var isFiltersExpanded: Bool
    @Binding var isTypesExpanded: Bool
    @Binding var selectedPriorities: Set<Int>
    @Binding var selectedTypes: Set<String>
    @Binding var selectedRarities: Set<WhiskeyRarity>
    @Binding var showingAddSheet: Bool
    let shareAction: () -> Void
    let getCurrentItems: () -> [Whiskey]
    
    // Fetch whiskeys in wishlist
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Whiskey.priority, ascending: true)],
        predicate: NSPredicate(format: "status == %@", "wishlist"),
        animation: .default)
    private var wishlistItems: FetchedResults<Whiskey>
    
    // Computed property for filtered whiskeys
    private var filteredWhiskeys: [Whiskey] {
        var filtered = Array(wishlistItems)
        
        // Apply search filter
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
        
        // Apply priority filter
        if !selectedPriorities.isEmpty {
            filtered = filtered.filter { whiskey in
                selectedPriorities.contains(Int(whiskey.priority))
            }
        }
        
        // Apply type filter
        if !selectedTypes.isEmpty {
            filtered = filtered.filter { whiskey in
                guard let type = whiskey.type else { return false }
                return selectedTypes.contains(type)
            }
        }
        
        // Apply rarity filter
        if !selectedRarities.isEmpty {
            filtered = filtered.filter { whiskey in
                guard let rarityStr = whiskey.rarity,
                      let rarity = WhiskeyRarity(rawValue: rarityStr) else {
                    return selectedRarities.contains(.notSure)
                }
                return selectedRarities.contains(rarity)
            }   
        }
        
        return filtered
    }
    
    // Check if any filters are active
    private var isFilterActive: Bool {
        return selectedPriorities.count != 5 || // Not all priorities selected
               !selectedTypes.isEmpty || // Any type filter active
               selectedRarities.count != WhiskeyRarity.allCases.count // Not all rarities selected
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Search and filter bar
            HStack {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search wishlist...", text: $searchText)
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
                
                // Share button
                Button(action: {
                    shareAction()
                }) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                }
                .disabled(getCurrentItems().isEmpty)
                .padding(.horizontal, 8)
                
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
            
            // Filter section
            VStack(spacing: 16) {
                // Priority Filter Card
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
                        // Priority and Rarity Filters
                        HStack(alignment: .top, spacing: 24) {
                            // Priority Filter
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Priority")
                                    .font(.system(size: 15, weight: .medium))
                                
                                HStack(spacing: 12) {
                                    ForEach(1...5, id: \.self) { priority in
                                        Button(action: {
                                            if selectedPriorities.contains(priority) {
                                                selectedPriorities.remove(priority)
                                                if selectedPriorities.isEmpty {
                                                    selectedPriorities.insert(priority) // Keep at least one selected
                                                }
                                            } else {
                                                selectedPriorities.insert(priority)
                                            }
                                        }) {
                                            Text("\(priority)")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(selectedPriorities.contains(priority) ? .white : .blue)
                                                .frame(width: 32, height: 32)
                                                .background(
                                                    Circle()
                                                        .fill(selectedPriorities.contains(priority) ? Color.blue : Color.blue.opacity(0.1))
                                                )
                                        }
                                    }
                                }
                            }
                            
                            // Rarity Filter
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Rarity")
                                    .font(.system(size: 15, weight: .medium))
                                
                                HStack(spacing: 12) {
                                    ForEach(WhiskeyRarity.allCases, id: \.self) { rarity in
                                        Button(action: {
                                            if selectedRarities.contains(rarity) {
                                                selectedRarities.remove(rarity)
                                                if selectedRarities.isEmpty {
                                                    selectedRarities.insert(rarity) // Keep at least one selected
                                                }
                                            } else {
                                                selectedRarities.insert(rarity)
                                            }
                                        }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: selectedRarities.contains(rarity) ? "checkmark.square.fill" : "square")
                                                    .foregroundColor(selectedRarities.contains(rarity) ? .blue : .secondary)
                                                    .font(.system(size: 14))
                                                
                                                Text(rarity.displayName)
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.primary)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(selectedRarities.contains(rarity) ? 
                                                        Color.blue.opacity(0.1) : 
                                                        Color(UIColor.secondarySystemBackground))
                                            )
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            if isFilterActive {
                                Button(action: {
                                    selectedPriorities = Set(1...5)
                                    selectedTypes = []
                                    selectedRarities = Set(WhiskeyRarity.allCases)
                                }) {
                                    Text("Reset")
                                        .font(.system(size: 14))
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .padding(.bottom, 12)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                )
                
                // Whiskey Types Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: "tag")
                                .foregroundColor(.blue)
                            Text("Whiskey Types")
                                .font(.system(size: 17, weight: .medium))
                        }
                        
                        Spacer()
                        
                        if !selectedTypes.isEmpty {
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
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(uniqueTypes, id: \.self) { type in
                                Button(action: {
                                    if selectedTypes.contains(type) {
                                        selectedTypes.remove(type)
                                    } else {
                                        selectedTypes.insert(type)
                                    }
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: selectedTypes.contains(type) ? "checkmark.square.fill" : "square")
                                            .foregroundColor(selectedTypes.contains(type) ? .blue : .secondary)
                                            .font(.system(size: 14))
                                        
                                        Text(type)
                                            .font(.system(size: 14))
                                            .foregroundColor(.primary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(selectedTypes.contains(type) ? 
                                                Color.blue.opacity(0.1) : 
                                                Color(UIColor.secondarySystemBackground))
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                )
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
            
            // Grid of wishlist items
            ScrollView {
                if filteredWhiskeys.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        
                        Text("No whiskeys in wishlist")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        if isFilterActive {
                            Text("Try adjusting your filters")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Button(action: {
                                showingAddSheet = true
                            }) {
                                Text("Add a whiskey")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Color.blue)
                                    .cornerRadius(10)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ForEach(filteredWhiskeys, id: \.id) { whiskey in
                            WishlistCard(whiskey: whiskey)
                                .onTapGesture {
                                    selectedWhiskey = whiskey
                                }
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    // Get unique whiskey types
    private var uniqueTypes: [String] {
        var types = Set<String>()
        for whiskey in wishlistItems {
            if let type = whiskey.type, !type.isEmpty {
                types.insert(type)
            }
        }
        return Array(types).sorted()
    }
}

struct ReplacementsContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var searchText: String
    @Binding var selectedWhiskey: Whiskey?
    @Binding var isFiltersExpanded: Bool
    @Binding var isTypesExpanded: Bool
    @Binding var selectedPriorities: Set<Int>
    @Binding var selectedTypes: Set<String>
    @Binding var selectedRarities: Set<WhiskeyRarity>
    @Binding var showingAddSheet: Bool
    let shareAction: () -> Void
    let getCurrentItems: () -> [Whiskey]
    
    // Fetch whiskeys that need replacement
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Whiskey.name, ascending: true)],
        predicate: NSPredicate(format: "replacementStatus == %@", "wantToReplace"),
        animation: .default)
    private var replacementItems: FetchedResults<Whiskey>
    
    var body: some View {
        VStack(spacing: 0) {
            // Search and filter bar
            HStack {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search replacements...", text: $searchText)
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
                
                // Share button
                Button(action: {
                    shareAction()
                }) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .medium))
                }
                .disabled(getCurrentItems().isEmpty)
                .padding(.horizontal, 8)
            }
            .padding()
            
            // Grid of replacement items
            ScrollView {
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
                    .padding(.top, 40)
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ForEach(replacementItems, id: \.id) { whiskey in
                            WishlistCard(whiskey: whiskey)
                                .onTapGesture {
                                    selectedWhiskey = whiskey
                                }
                        }
                    }
                    .padding()
                }
            }
        }
    }
}

// Wishlist Card View
struct WishlistCard: View {
    let whiskey: Whiskey
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Name and Priority
            HStack {
                Text(whiskey.name ?? "Unknown")
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(2)
                
                Spacer()
                
                if let priority = whiskey.priority as? Int16, priority > 0 {
                    Text("\(priority)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.brown)
                        .cornerRadius(8)
                }
            }
            
            // Type and Distillery
            if let type = whiskey.type, !type.isEmpty {
                Text(type)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            
            if let distillery = whiskey.distillery, !distillery.isEmpty {
                Text(distillery)
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            
            // Target Price
            if let targetPrice = whiskey.targetPrice as? Double, targetPrice > 0 {
                Text("$\(String(format: "%.0f", targetPrice))")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
            }
            
            // Location and Rarity row
            HStack(spacing: 8) {
                if let whereToFind = whiskey.whereToFind, !whereToFind.isEmpty {
                    Text("Location: \(whereToFind)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else if whiskey.isStorePick, let storePickName = whiskey.storePickName, !storePickName.isEmpty {
                    Text("Store Pick: \(storePickName)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                if let rarityStr = whiskey.rarity, let rarity = WhiskeyRarity(rawValue: rarityStr) {
                    Text("Rarity: \(rarity.displayName)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// Filter Toggle Button
struct FilterToggleButton: View {
    let title: String
    @Binding var isSelected: Bool
    let color: Color
    
    var body: some View {
        Button(action: {
            isSelected.toggle()
        }) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? .white : color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? color : color.opacity(0.1))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Custom Slider Style
struct CustomSliderStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .accentColor(.blue)
    }
}

extension View {
    func customSliderStyle() -> some View {
        modifier(CustomSliderStyle())
    }
}

#Preview {
    iPadWishlistView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
} 
