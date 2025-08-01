import SwiftUI
import CoreData

struct iPadDashboardView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedTab: TabSelection
    @State private var showingAddWhiskey = false
    @State private var showingAddWishlist = false
    @State private var showingAddJournal = false
    @State private var selectedJournalEntry: JournalEntry?
    
    // Fetch recently added whiskeys
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Whiskey.addedDate, ascending: false)],
        predicate: NSPredicate(format: "status == %@", "owned"),
        animation: .default)
    private var recentWhiskeys: FetchedResults<Whiskey>
    
    // Fetch favorites (using highest rated whiskeys as a proxy)
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \JournalEntry.overallRating, ascending: false)
        ],
        predicate: NSPredicate(format: "whiskey != nil"),
        animation: .default)
    private var journalEntries: FetchedResults<JournalEntry>
    
    // Fetch whiskeys in wishlist
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Whiskey.priority, ascending: true)],
        predicate: NSPredicate(format: "status == %@", "wishlist"),
        animation: .default)
    private var wishlistWhiskeys: FetchedResults<Whiskey>
    
    // Latest journal entries
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \JournalEntry.date, ascending: false)],
        animation: .default)
    private var allJournalEntries: FetchedResults<JournalEntry>
    
    // Infinity bottles
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \InfinityBottle.name, ascending: true)],
        animation: .default)
    private var infinityBottles: FetchedResults<InfinityBottle>
    
    var body: some View {
        GeometryReader { mainGeometry in
            ScrollView {
                VStack(spacing: 25) {
                    // Quick Actions Row
                    HStack(spacing: 20) {
                        // Add Whiskey
                        QuickActionButton(title: "Add Whiskey", icon: "plus.circle.fill", color: Color.blue) {
                            selectedTab = .collection
                            showingAddWhiskey = true
                        }
                        
                        // Add to Wishlist
                        QuickActionButton(title: "Add to Wishlist", icon: "heart.fill", color: Color.pink) {
                            selectedTab = .wishlist
                            showingAddWishlist = true
                        }
                        
                        // Add Journal Entry
                        QuickActionButton(title: "Add Tasting", icon: "note.text.badge.plus", color: Color.green) {
                            selectedTab = .journal
                            showingAddJournal = true
                        }
                    }
                    .padding(.top, 5)
                    .padding(.bottom, 10)
                    
                    // Main Content Area - 2x2 Grid layout with consistent spacing
                    VStack(spacing: 20) {
                        // Top Row
                        HStack(spacing: 20) {
                            // TOP LEFT - Quick Stats
                            DashboardSectionView(title: "Quick Stats", icon: "chart.bar.fill", moreAction: { selectedTab = .statistics }) {
                                VStack(spacing: 15) {
                                    // Two-column grid of stats
                                    LazyVGrid(columns: [
                                        GridItem(.flexible()),
                                        GridItem(.flexible())
                                    ], spacing: 15) {
                                        // Total Bottles
                                        QuickStatView(
                                            title: "Bottles",
                                            value: "\(getTotalBottles())",
                                            icon: "bottle.fill",
                                            color: .blue
                                        )
                                        
                                        // Collection Value Card
                                        QuickStatView(
                                            title: "Collection Value",
                                            value: formatCurrency(getTotalValue()),
                                            icon: "dollarsign.circle.fill",
                                            color: .green
                                        )
                                        
                                        // Avg PPP
                                        QuickStatView(
                                            title: "Avg PPP",
                                            value: formatPPP(getAveragePPP()),
                                            icon: "star.fill",
                                            color: .yellow
                                        )
                                        
                                        // Bottles Tasted
                                        QuickStatView(
                                            title: "Bottles Tasted",
                                            value: "\(getBottlesTasted())",
                                            icon: "square.grid.2x2",
                                            color: .purple
                                        )
                                    }
                                    .padding(.horizontal)
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 15)
                            }
                            
                            // TOP RIGHT - Recent Activity
                            DashboardSectionView(title: "Recent Activity", icon: "clock.fill", moreAction: { selectedTab = .collection }) {
                                if recentWhiskeys.isEmpty {
                                    DashboardEmptyStateView(message: "No recent additions")
                                } else {
                                    ScrollView {
                                        VStack(spacing: 12) {
                                            ForEach(Array(recentWhiskeys.prefix(15)), id: \.id) { whiskey in
                                                RecentActivityRow(whiskey: whiskey)
                                                    .onTapGesture {
                                                        selectedTab = .collection
                                                        // In a full implementation, we'd navigate to the detail view
                                                    }
                                            }
                                        }
                                        .padding(.horizontal)
                                        .padding(.vertical, 15)
                                    }
                                }
                            }
                        }
                        .frame(height: mainGeometry.size.height * 0.38)
                        
                        // Bottom Row
                        HStack(spacing: 20) {
                            // BOTTOM LEFT - Recent Tastings
                            DashboardSectionView(title: "Recent Tastings", icon: "book.fill", moreAction: { selectedTab = .journal }) {
                                if allJournalEntries.isEmpty {
                                    DashboardEmptyStateView(message: "No tastings recorded yet")
                                } else {
                                    ScrollView {
                                        VStack(spacing: 14) {
                                            ForEach(Array(allJournalEntries.prefix(10)), id: \.id) { entry in
                                                if let whiskey = entry.whiskey, let date = entry.date {
                                                                                                         Button(action: {
                                                        selectedJournalEntry = entry
                                                    }) {
                                                        DashboardJournalEntryRow(whiskey: whiskey, entry: entry, date: date)
                                                    }
                                                    .buttonStyle(PlainButtonStyle())
                                                }
                                            }
                                        }
                                        .padding(.horizontal)
                                        .padding(.vertical, 15)
                                    }
                                }
                            }
                            
                            // BOTTOM RIGHT - Wishlist
                            DashboardSectionView(title: "Wishlist", icon: "heart.fill", moreAction: { selectedTab = .wishlist }) {
                                if wishlistWhiskeys.isEmpty {
                                    DashboardEmptyStateView(message: "Your wishlist is empty")
                                } else {
                                    ScrollView {
                                        VStack(spacing: 12) {
                                            ForEach(Array(wishlistWhiskeys.prefix(15)), id: \.id) { whiskey in
                                                DashboardWishlistItemRow(whiskey: whiskey)
                                                    .onTapGesture {
                                                        // Navigate to whiskey detail
                                                        selectedTab = .wishlist
                                                        // In a full implementation, you would pass the whiskey.id to open details
                                                    }
                                                    .contextMenu {
                                                        Button(action: {
                                                            // Add code to mark as acquired
                                                        }) {
                                                            Label("Mark as Acquired", systemImage: "checkmark.circle")
                                                        }
                                                        
                                                        Button(action: {
                                                            // Add code to edit wishlist item
                                                        }) {
                                                            Label("Edit", systemImage: "pencil")
                                                        }
                                                    }
                                            }
                                        }
                                        .padding(.horizontal)
                                        .padding(.vertical, 15)
                                    }
                                }
                            }
                        }
                        .frame(height: mainGeometry.size.height * 0.38)
                    }
                    
                    // Infinity Bottles - if needed
                    if !infinityBottles.isEmpty {
                        DashboardSectionView(title: "Infinity Bottles", icon: "infinity", moreAction: { selectedTab = .collection }) {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 20) {
                                    ForEach(infinityBottles, id: \.id) { bottle in
                                        InfinityBottleCard(infinityBottle: bottle)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        }
        .sheet(item: $selectedJournalEntry) { entry in
            NavigationView {
                JournalEntryDetailView(entry: entry)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                selectedJournalEntry = nil
                            }
                        }
                    }
            }
        }
    }
    
    // Helper method to get top rated whiskeys (favorites)
    private func getTopRatedWhiskeys() -> [Whiskey] {
        var whiskeyDict: [UUID: (whiskey: Whiskey, rating: Double)] = [:]
        
        // Collect highest rating for each whiskey
        for entry in journalEntries {
            if let whiskey = entry.whiskey, let id = whiskey.id, entry.overallRating > 0 {
                if let existing = whiskeyDict[id] {
                    if entry.overallRating > existing.rating {
                        whiskeyDict[id] = (whiskey, entry.overallRating)
                    }
                } else {
                    whiskeyDict[id] = (whiskey, entry.overallRating)
                }
            }
        }
        
        // Sort by rating (highest first) and return whiskeys
        return whiskeyDict.values.sorted { $0.rating > $1.rating }.map { $0.whiskey }
    }
    
    // Helper methods for stats
    private func getTotalBottles() -> Int {
        // This is the correct calculation, using the numberOfBottles property directly
        recentWhiskeys.reduce(0) { $0 + Int($1.numberOfBottles) }
    }
    
    private func getTotalValue() -> Double {
        recentWhiskeys.reduce(0.0) { $0 + (($1.price as? Double) ?? 0.0) * Double($1.numberOfBottles) }
    }
    
    private func getAveragePPP() -> Double {
        var totalPPP: Double = 0
        var count: Int = 0
        
        for whiskey in recentWhiskeys {
            if let price = whiskey.price as? Double, 
               let proof = whiskey.proof as? Double, 
               proof > 0 {
                let ppp = price / proof
                totalPPP += ppp
                count += 1
            }
        }
        
        return count > 0 ? totalPPP / Double(count) : 0
    }
    
    // Count whiskeys that have been tasted (isOpen flag is true)
    private func getBottlesTasted() -> Int {
        return recentWhiskeys.filter { $0.isOpen }.count
    }
    
    // Get type breakdown for visualization
    private func getTypeBreakdown() -> [(type: String, count: Int, color: Color)] {
        var typeCount: [String: Int] = [:]
        
        // Count whiskeys by type
        for whiskey in recentWhiskeys {
            if let type = whiskey.type {
                typeCount[type, default: 0] += Int(whiskey.numberOfBottles)
            }
        }
        
        // Convert to array with colors
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .yellow, .red]
        
        return typeCount.enumerated().map { index, item in
            return (type: item.key, count: item.value, color: colors[index % colors.count])
        }.sorted { $0.count > $1.count }
    }
    
    // Helper method to get rating for a specific whiskey for the Top Rated section
    private func getRatingForWhiskey(_ whiskey: Whiskey) -> Double {
        var highestRating: Double = 0
        
        for entry in journalEntries {
            if entry.whiskey?.id == whiskey.id && entry.overallRating > highestRating {
                highestRating = entry.overallRating
            }
        }
        
        return highestRating
    }
    
    // Helper method to get the journal entry ID with the highest rating for a whiskey
    private func getHighestRatedJournalEntryId(for whiskey: Whiskey) -> UUID? {
        var highestRatingEntry: JournalEntry? = nil
        var highestRating: Double = 0
        
        for entry in journalEntries {
            if entry.whiskey?.id == whiskey.id && entry.overallRating > highestRating {
                highestRating = entry.overallRating
                highestRatingEntry = entry
            }
        }
        
        return highestRatingEntry?.id
    }
    
    // Format PPP value to remove leading zero if less than $1.00
    private func formatPPP(_ value: Double) -> String {
        if value < 1.0 {
            return "$.\(String(format: "%0.2f", value).dropFirst(2))"
        } else {
            return "$\(String(format: "%.2f", value))"
        }
    }
    
    // Format currency with comma separators
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        formatter.currencySymbol = "$"
        
        return formatter.string(from: NSNumber(value: value)) ?? "$\(Int(value))"
    }
}

// MARK: - Supporting Views

// Quick Action Button
struct QuickActionButton: View {
    var title: String
    var icon: String
    var color: Color
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)
                
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Mini Collection Grid - Compact display of whiskeys in a grid
struct MiniCollectionGridView: View {
    var whiskeys: [Whiskey]
    
    let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 120), spacing: 15)
    ]
    
    var body: some View {
        if whiskeys.isEmpty {
            DashboardEmptyStateView(message: "No whiskeys in collection")
        } else {
            LazyVGrid(columns: columns, spacing: 15) {
                ForEach(whiskeys, id: \.id) { whiskey in
                    MiniWhiskeyGridItem(whiskey: whiskey)
                }
            }
            .padding(.horizontal)
        }
    }
}

// Mini Whiskey Grid Item
struct MiniWhiskeyGridItem: View {
    var whiskey: Whiskey
    
    var body: some View {
        VStack(spacing: 4) {
            // Type badge at top
            if let type = whiskey.type {
                Text(type)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(Color.blue)
                    .cornerRadius(20)
            }
            
            // Bottle image placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(UIColor.tertiarySystemBackground))
                    .frame(height: 80)
                
                Text(whiskey.name?.prefix(1).uppercased() ?? "")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            VStack(spacing: 2) {
                Text(whiskey.name ?? "Unknown")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if let proof = whiskey.proof as? Double, proof > 0 {
                    Text("\(String(format: "%.1f", proof))°")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}

// Infinity Bottle Card
struct InfinityBottleCard: View {
    var infinityBottle: InfinityBottle
    
    var body: some View {
        VStack(spacing: 10) {
            // Bottle Image or Placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 110, height: 140)
                
                VStack(spacing: 5) {
                    Image(systemName: "infinity")
                        .font(.system(size: 32))
                        .foregroundColor(.purple)
                    
                    let volume = infinityBottle.remainingVolume
                    let maxVolume = infinityBottle.maxVolume
                    // Volume indicator
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.purple.opacity(0.5), lineWidth: 1)
                            .frame(width: 30, height: 60)
                        
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.purple.opacity(0.5))
                            .frame(width: 28, height: max(5, 60 * CGFloat(volume) / CGFloat(maxVolume)))
                    }
                }
            }
            
            // Infinity Bottle Info
            VStack(spacing: 4) {
                Text(infinityBottle.name ?? "Unnamed Bottle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(width: 110)
                
                Text(infinityBottle.typeCategory ?? "Mixed")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

// Type Breakdown Visualization
struct TypeBreakdownView: View {
    var typeData: [(type: String, count: Int, color: Color)]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Bar chart
            HStack(spacing: 2) {
                ForEach(typeData, id: \.type) { item in
                    let totalCount = typeData.reduce(0) { $0 + $1.count }
                    let width = CGFloat(item.count) / CGFloat(totalCount)
                    
                    VStack {
                        Rectangle()
                            .fill(item.color)
                            .cornerRadius(4)
                        
                        Text(item.type)
                            .font(.system(size: 10))
                            .lineLimit(1)
                            .frame(width: max(40, width * 200))
                    }
                    .frame(width: max(40, width * 200))
                }
                
                Spacer()
            }
            
            // Legend
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(typeData, id: \.type) { item in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(item.color)
                                .frame(width: 8, height: 8)
                            
                            Text("\(item.type): \(item.count)")
                                .font(.system(size: 12))
                        }
                    }
                }
            }
        }
    }
}

// QuickStatView - For the Quick Stats section
struct QuickStatView: View {
    var title: String
    var value: String
    var icon: String
    var color: Color
    
    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary.opacity(0.8))
            
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 16)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(12)
    }
}

// Modern Section Header - Renamed
struct DashboardSectionView<Content: View>: View {
    var title: String
    var icon: String
    var moreAction: (() -> Void)? = nil
    @ViewBuilder var content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header area with fixed height
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if let action = moreAction {
                    Button(action: action) {
                        Text("See All")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.blue)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal)
            .padding(.top, 15)
            .padding(.bottom, 15)
            
            // Content area
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// Modern Whiskey Card
struct ModernWhiskeyCard: View {
    var whiskey: Whiskey
    
    var body: some View {
        VStack(spacing: 10) {
            // Bottle Image or Placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(UIColor.tertiarySystemBackground))
                    .frame(width: 110, height: 160)
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                
                VStack(spacing: 5) {
                    Text(whiskey.name?.prefix(1).uppercased() ?? "")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                    
                    if let proof = whiskey.proof as? Double, proof > 0 {
                        Text("\(String(format: "%.1f", proof))°")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.blue)
                    }
                }
            }
            
            // Status indicators
            HStack(spacing: 8) {
                if whiskey.isOpen {
                    Image(systemName: "seal.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                }
                
                if whiskey.isBiB {
                    Text("BiB")
                        .font(.system(size: 10, weight: .bold))
                        .padding(2)
                        .background(Color.yellow.opacity(0.2))
                        .cornerRadius(3)
                }
                
                if whiskey.isSiB {
                    Text("SiB")
                        .font(.system(size: 10, weight: .bold))
                        .padding(2)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(3)
                }
            }
            
            // Whiskey Info
            VStack(spacing: 4) {
                Text(whiskey.name ?? "Unknown")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .frame(width: 110)
                
                Text(whiskey.type ?? "Unknown Type")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                if let price = whiskey.price as? Double, price > 0 {
                    Text("$\(String(format: "%.0f", price))")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(Color.blue)
                        .cornerRadius(20)
                }
            }
        }
    }
}

// Wishlist Item Row - Renamed
struct DashboardWishlistItemRow: View {
    var whiskey: Whiskey
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(whiskey.name ?? "Unknown")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                
                Text(whiskey.type ?? "Unknown Type")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 10) {
                if let targetPrice = whiskey.targetPrice as? Double, targetPrice > 0 {
                    Text("$\(String(format: "%.0f", targetPrice))")
                        .font(.system(size: 15, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.green.opacity(0.15))
                        .foregroundColor(Color.green)
                        .cornerRadius(8)
                }
                
                if let priority = whiskey.priority as? Int16, priority > 0 {
                    Text("\(priority)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.brown)
                        .cornerRadius(14)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(10)
    }
}

// Top Rated Whiskey Row
struct TopRatedWhiskeyRow: View {
    var whiskey: Whiskey
    var rating: Double
    
    var body: some View {
        HStack {
            // Bottle initial or small image
            ZStack {
                Circle()
                    .fill(Color(UIColor.tertiarySystemBackground))
                    .frame(width: 50, height: 50)
                
                Text(whiskey.name?.prefix(1).uppercased() ?? "")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            // Whiskey details
            VStack(alignment: .leading, spacing: 2) {
                Text(whiskey.name ?? "Unknown")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                
                HStack {
                    Text(whiskey.type ?? "Unknown Type")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    if let proof = whiskey.proof as? Double, proof > 0 {
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text("\(String(format: "%.1f", proof))°")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Rating display
            HStack {
                Text(String(format: "%.0f", rating))
                    .font(.system(size: 16, weight: .bold))
                
                Image(systemName: "star.fill")
                    .font(.system(size: 14))
            }
            .foregroundColor(rating >= 85 ? Color.yellow : Color.gray)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(rating >= 85 ? Color.yellow.opacity(0.15) : Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(10)
    }
}

// Journal Entry Row - Renamed
struct DashboardJournalEntryRow: View {
    var whiskey: Whiskey
    var entry: JournalEntry
    var date: Date
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(whiskey.name ?? "Unknown")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                HStack {
                    Text(String(format: "%.0f", entry.overallRating))
                        .font(.system(size: 14, weight: .bold))
                    
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                }
                .foregroundColor(entry.overallRating >= 85 ? Color.yellow : Color.gray)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(entry.overallRating >= 85 ? Color.yellow.opacity(0.15) : Color.gray.opacity(0.1))
                .cornerRadius(20)
            }
            
            HStack {
                Text(entry.review ?? "No notes")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                Spacer()
                
                Text(date, style: .date)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(12)
        .contentShape(Rectangle())
    }
}

// Empty State View - Renamed
struct DashboardEmptyStateView: View {
    var message: String
    
    var body: some View {
        VStack {
            Spacer()
            Text(message)
                .font(.system(size: 16))
                .foregroundColor(.secondary)
                .padding(.vertical, 30)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// Recent Activity Row
struct RecentActivityRow: View {
    var whiskey: Whiskey
    
    var body: some View {
        HStack {
            // Bottle initial or small image
            ZStack {
                Circle()
                    .fill(Color(UIColor.tertiarySystemBackground))
                    .frame(width: 45, height: 45)
                
                Text(whiskey.name?.prefix(1).uppercased() ?? "")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            
            // Whiskey details
            VStack(alignment: .leading, spacing: 2) {
                Text(whiskey.name ?? "Unknown")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                
                HStack {
                    Text(whiskey.type ?? "Unknown Type")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    if let proof = whiskey.proof as? Double, proof > 0 {
                        Text("•")
                            .foregroundColor(.secondary)
                        
                        Text("\(String(format: "%.1f", proof))°")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                Text("Added \(getRelativeDate(whiskey.addedDate))")
                    .font(.system(size: 12))
                    .foregroundColor(.blue)
            }
            
            Spacer()
            
            // Price
            if let price = whiskey.price as? Double, price > 0 {
                Text("$\(String(format: "%.0f", price))")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(UIColor.tertiarySystemBackground))
        .cornerRadius(10)
    }
    
    // Format relative date
    private func getRelativeDate(_ date: Date?) -> String {
        guard let date = date else { return "recently" }
        
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "today"
        } else if calendar.isDateInYesterday(date) {
            return "yesterday"
        } else {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            return formatter.localizedString(for: date, relativeTo: Date())
        }
    }
}

#Preview {
    iPadDashboardView(selectedTab: .constant(.home))
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
} 