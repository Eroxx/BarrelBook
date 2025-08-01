import SwiftUI
import CoreData
import MapKit
import CoreLocation

// Date formatter for consistent date display
private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}()

// At the top of the file, add this extension
extension UserDefaults {
    func contentID(for whiskeyID: String) -> String? {
        return string(forKey: "lastContentID_\(whiskeyID)")
    }
    
    func setContentID(_ contentID: String, for whiskeyID: String) {
        set(contentID, forKey: "lastContentID_\(whiskeyID)")
    }
}

// Add typealias for BottleInstance with a different name
typealias BottleInstanceType = NSManagedObject

struct WhiskeyDetailView: View {
    @ObservedObject var whiskey: Whiskey
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditSheet = false
    @State private var showingAddJournalSheet = false
    @State private var showingWebSearch = false
    @State private var selectedWebContent: WebContent? = nil
    @State private var selectedContentID: UUID? = nil
    @State private var showingWebContentDetail = false
    @State private var editingWebContent: WebContent? = nil
    @State private var showingEditWebContent = false
    @State private var webContentRefreshTrigger = UUID()
    @State private var lastSelectedContentID: UUID? = nil
    @State private var isEditingNotes = false
    @State private var editedNotes = ""
    @State private var showMiniEditSheet = false
    @State private var tempIsOpen: Bool
    @State private var hasUnsavedChanges = false
    @State private var originalIsOpen: Bool
    @State private var tempIsTasted: Bool
    @State private var hasUnsavedTastedChanges = false
    @State private var originalIsTasted: Bool
    @State private var isFinished = Int16(0)
    @State private var originalNumberOfBottles: Int16
    @State private var hasUnsavedFinishedChanges = false
    @State private var showingWishlistToCollectionSheet = false
    @State private var showingAddReplacementSheet = false
    @State private var showingReplacementAlert = false
    @State private var isFinishedString: String = ""
    @State private var showingAddPurchaseSheet = false
    @State private var bottleListRefreshTrigger = UUID()
    
    // Use the AlertManager for alert state
    @StateObject private var alertManager = AlertManager.shared
    @StateObject private var locationManager = LocationManager.shared
    
    @FetchRequest private var journalEntries: FetchedResults<JournalEntry>
    @FetchRequest private var bottleInstances: FetchedResults<BottleInstance>
    
    // Static set to track which whiskeys have already had views initialized for them
    static var initializedViews = Set<String>()
    
    // Add viewID property
    private var viewID: String {
        if let id = whiskey.id?.uuidString {
            return "WhiskeyDetailView-\(id)"
        }
        return "WhiskeyDetailView-\(UUID().uuidString)"
    }

    init(whiskey: Whiskey) {
        self.whiskey = whiskey
        
        // Check if we should show alert - break down the expression
        let hasID = whiskey.id != nil
        let alertKey = hasID ? "showBuyAlert_\(whiskey.id!.uuidString)" : ""
        let shouldShowAlert = hasID && UserDefaults.standard.bool(forKey: alertKey)
        
        // Initialize state variables with whiskey properties
        _tempIsOpen = State(initialValue: whiskey.isOpen)
        _originalIsOpen = State(initialValue: whiskey.isOpen)
        _tempIsTasted = State(initialValue: whiskey.isTasted)
        _originalIsTasted = State(initialValue: whiskey.isTasted)
        _isFinished = State(initialValue: Int16(whiskey.isFinished))
        _originalNumberOfBottles = State(initialValue: whiskey.numberOfBottles)
        
        // Initialize the journal entries fetch request
        _journalEntries = FetchRequest<JournalEntry>(
            sortDescriptors: [NSSortDescriptor(keyPath: \JournalEntry.date, ascending: false)],
            predicate: NSPredicate(format: "whiskey == %@", whiskey),
            animation: .default
        )
        
        // Initialize the bottle instances fetch request with explicit type
        let bottleInstancesRequest = FetchRequest<BottleInstance>(
            sortDescriptors: [NSSortDescriptor(keyPath: \BottleInstance.bottleNumber, ascending: true)],
            predicate: NSPredicate(format: "whiskey == %@", whiskey),
            animation: .default
        )
        _bottleInstances = bottleInstancesRequest
        
        // Ensure we have the correct number of bottle instances
        if let context = whiskey.managedObjectContext {
            let fetchRequest: NSFetchRequest<BottleInstance> = BottleInstance.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "whiskey == %@", whiskey)
            
            do {
                let existingBottles = try context.fetch(fetchRequest)
                let activeBottles = existingBottles.filter { !$0.isDead }
                
                // Check if we have a recently dead bottle (in the last 2 seconds)
                let recentlyDeadBottles = existingBottles.filter { 
                    $0.isDead && 
                    $0.dateFinished != nil && 
                    $0.dateFinished! > Date().addingTimeInterval(-2) 
                }
                
                // Only automatically create bottles if we don't have a recent dead bottle
                // This prevents creating a new bottle when one was just marked as dead
                if recentlyDeadBottles.isEmpty {
                    // If we need more bottles, create them
                    if whiskey.numberOfBottles > Int16(activeBottles.count) {
                        for i in activeBottles.count..<Int(whiskey.numberOfBottles) {
                            let newBottle = BottleInstance(context: context)
                            newBottle.id = UUID()
                            newBottle.dateAdded = Date()
                            newBottle.price = whiskey.price
                            
                            // Ensure whiskey is valid before setting the relationship
                            if let whiskeyID = whiskey.id, 
                               let validWhiskey = try? context.existingObject(with: whiskey.objectID) as? Whiskey {
                                newBottle.whiskey = validWhiskey
                            } else {
                                print("Error: Invalid whiskey reference when creating bottle instance")
                                continue
                            }
                            
                            newBottle.isOpen = false
                            newBottle.isDead = false
                            newBottle.bottleNumber = Int16(i + 1)
                            
                            #if DEBUG
                            print("DEBUG: Created new bottle with number \(newBottle.bottleNumber)")
                            #endif
                        }
                        try context.save()
                    }
                    // If we need fewer bottles, mark the excess as dead
                    else if whiskey.numberOfBottles < Int16(activeBottles.count) {
                        let bottlesToMarkDead = activeBottles
                            .sorted { $0.bottleNumber > $1.bottleNumber }
                            .prefix(activeBottles.count - Int(whiskey.numberOfBottles))
                        
                        for bottle in bottlesToMarkDead {
                            bottle.isDead = true
                        }
                        try context.save()
                    }
                }
            } catch {
                print("Error initializing bottle instances: \(error)")
            }
        }
        
        // Add debug logging only in debug builds
        #if DEBUG
        let viewIdentifier = "\(whiskey.id?.uuidString ?? "unknown")"
        if !Self.initializedViews.contains(viewIdentifier) {
            print("DEBUG: Initializing WhiskeyDetailView for \(whiskey.name ?? "Unknown")")
            print("DEBUG: Initial isTasted value: \(whiskey.isTasted)")
            print("DEBUG: Initial isFinished value: \(whiskey.isFinished)")
            print("DEBUG: Number of bottles: \(whiskey.numberOfBottles)")
            print("DEBUG: Journal entries count: \(whiskey.journalEntries?.count ?? 0)")
            Self.initializedViews.insert(viewIdentifier)
        }
        #endif
    }
    
    // Computed properties for derived status
    private var isOpen: Bool {
        bottleInstances.filter { !$0.isDead }.first { $0.isOpen } != nil
    }
    
    // The isTasted property is now just a simple boolean from the whiskey model
    // No need to check individual bottles
    
    // Add helper property for active bottles count
    private var activeBottlesCount: Int {
        bottleInstances.filter { !$0.isDead }.count
    }
    
    // Add helper property for open bottles count
    private var openBottlesCount: Int {
        bottleInstances.filter { !$0.isDead && $0.isOpen }.count
    }
    
    // Add helper property for tasted bottles count
    private var tastedBottlesCount: Int {
        bottleInstances.filter { !$0.isDead }.filter { bottle in
            guard let entries = bottle.whiskey?.journalEntries as? Set<JournalEntry> else { return false }
            return !entries.isEmpty
        }.count
    }
    
    private var deadBottleCount: Int {
        bottleInstances.filter { $0.isDead }.count
    }
    
    private var totalInvestment: Double {
        bottleInstances.reduce(0) { $0 + $1.price }
    }
    
    private var averagePrice: Double {
        guard !bottleInstances.isEmpty else { return 0 }
        return totalInvestment / Double(bottleInstances.count)
    }
    
    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title with edit icon
                    HStack {
                        Text(whiskey.name ?? "Unknown Whiskey")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Spacer()
                        
                        Button(action: {
                            showingEditSheet = true
                            HapticManager.shared.lightImpact()
                        }) {
                            Image(systemName: "pencil")
                                .font(.title3)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.bottom, 4)
                    
                    // Core Details Section
                    VStack(spacing: 12) {
                        if let type = whiskey.type, !type.isEmpty {
                            DetailRow(label: "Type", value: type)
                        }
                        
                        if let distillery = whiskey.distillery, !distillery.isEmpty {
                            DetailRow(label: "Distillery", value: distillery)
                        }
                        
                        if whiskey.proof > 0 {
                            DetailRow(label: "Proof", value: String(format: "%.1f", whiskey.proof))
                        }
                        
                        if let age = whiskey.age, !age.isEmpty {
                            DetailRow(label: "Age", value: age)
                        }
                        
                        if !whiskey.isWishlist {
                            // Special Designations moved inside details section - no labels
                            if whiskey.isBiB || whiskey.isSiB || whiskey.isStorePick || whiskey.isCaskStrength {
                                HStack {
                                    if whiskey.isBiB {
                                        DetailBadge(text: "BiB", color: Color(red: 0.8, green: 0.6, blue: 0.3))
                                    }
                                    
                                    if whiskey.isSiB {
                                        DetailBadge(text: "SiB", color: .blue)
                                    }
                                    
                                    if whiskey.isStorePick {
                                        if let name = whiskey.storePickName, !name.isEmpty {
                                            DetailBadge(text: "SP: \(name)", color: .purple)
                                        } else {
                                            DetailBadge(text: "SP", color: .purple)
                                        }
                                    }
                                    
                                    if whiskey.isCaskStrength {
                                        DetailBadge(text: "Cask Strength", color: .red)
                                    }
                                    
                                    Spacer()
                                }
                            }
                            
                            if let finish = whiskey.finish, !finish.isEmpty {
                                DetailRow(label: "Finish", value: finish)
                            }
                            
                            Spacer().frame(height: 8) // Add extra space here
                            
                            HStack {
                                Text("Tasted")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Toggle("", isOn: $tempIsTasted)
                                    .labelsHidden()
                                    .onChange(of: tempIsTasted) { newValue in
                                        // Auto-save tasted status when toggled
                                        whiskey.isTasted = newValue
                                        originalIsTasted = newValue
                                        hasUnsavedTastedChanges = false
                                        do {
                                            try viewContext.save()
                                            HapticManager.shared.successFeedback()
                                        } catch {
                                            HapticManager.shared.errorFeedback()
                                            print("Error saving tasted status: \(error)")
                                        }
                                    }
                                    
                                if hasUnsavedTastedChanges {
                                    Button(action: saveTastedStatus) {
                                        Text("Save")
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color.blue)
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                    }
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                            
                            // Show "Want to Replace" status if bottle is finished
                            if whiskey.isFinished > 0 && whiskey.replacedBy == nil {
                                HStack {
                                    Text("Want to Replace")
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Toggle("", isOn: Binding(
                                        get: { whiskey.wantsToBeReplaced },
                                        set: { newValue in
                                            whiskey.replacementStatus = newValue ? "wantToReplace" : "none"
                                            try? viewContext.save()
                                        }
                                    ))
                                    .labelsHidden()
                                }
                            }
                            
                            // Show replacement info if this bottle is finished
                            if whiskey.isFinished > 0 {
                                if let replacement = whiskey.replacedBy {
                                    NavigationLink(destination: WhiskeyDetailView(whiskey: replacement)) {
                                        Text("Replaced by \(replacement.name ?? "Unknown")")
                                    }
                                } else {
                                    Text("No replacement yet")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        if whiskey.isWishlist && whiskey.targetPrice > 0 {
                            DetailRow(label: "Target Price", value: String(format: "$%.2f", whiskey.targetPrice))
                        }
                        
                        // Add price information only if price is greater than 0
                        if whiskey.price > 0 {
                            DetailRow(label: "Price", value: String(format: "$%.2f", whiskey.price))
                        }
                        
                        // Add rarity and store location for wishlist items
                        if whiskey.isWishlist {
                            if let rarityStr = whiskey.rarity, let rarity = WhiskeyRarity(rawValue: rarityStr) {
                                DetailRow(label: "Rarity", value: rarity.displayName)
                            }
                            
                            // Show store information from both sources
                            if let stores = whiskey.stores as? Set<Store>, !stores.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Stores")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    // Convert Set to Array and sort by distance
                                    let sortedStores = Array(stores).sorted { store1, store2 in
                                        if let location = locationManager.location {
                                            let store1Location = CLLocation(latitude: store1.latitude, longitude: store1.longitude)
                                            let store2Location = CLLocation(latitude: store2.latitude, longitude: store2.longitude)
                                            let distance1 = location.distance(from: store1Location)
                                            let distance2 = location.distance(from: store2Location)
                                            return distance1 < distance2
                                        }
                                        return true // If no location, maintain original order
                                    }
                                    
                                    ForEach(sortedStores, id: \.id) { store in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(store.name ?? "Unknown Store")
                                                .font(.subheadline)
                                                .fontWeight(.medium)
                                            
                                            if let address = store.address {
                                                Text(address)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            
                                            // Show distance if we have user location
                                            if let location = locationManager.location {
                                                let storeLocation = CLLocation(latitude: store.latitude, longitude: store.longitude)
                                                let distance = location.distance(from: storeLocation)
                                                // Convert meters to miles (1 meter = 0.000621371 miles)
                                                let miles = distance * 0.000621371
                                                Text(String(format: "%.1f miles away", miles))
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            } else if let whereToFind = whiskey.whereToFind, !whereToFind.isEmpty {
                                DetailRow(label: "Location", value: whereToFind)
                            } else if whiskey.isStorePick, let storePickName = whiskey.storePickName, !storePickName.isEmpty {
                                DetailRow(label: "Store", value: storePickName)
                            }
                        }
                        
                        // Display wishlist status badge if it's a wishlist item
                        if whiskey.isWishlist {
                            Text("WISHLIST")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(4)
                                .padding(.top, 4)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: Color(.systemGray4), radius: 3)
                    .animation(.spring(response: 0.3), value: hasUnsavedChanges)
                    .animation(.spring(response: 0.3), value: hasUnsavedFinishedChanges)
                    .animation(.spring(response: 0.3), value: hasUnsavedTastedChanges)
                    
                    // Rename and modify the section to handle all bottle additions
                    if !whiskey.isWishlist {
                        BottleHistorySection(whiskey: whiskey)
                        
                        // Add back the bottle cards view
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Individual Bottles")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            // Combined section with scrolling for both active and dead bottles
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(alignment: .top, spacing: 0) {
                                    // Active Bottles Section with header
                                    VStack(alignment: .leading, spacing: 8) {
                                        if bottleInstances.contains(where: { $0.isDead }) {
                                            // Active header (inside the scroll view)
                                            Text("Active")
                                                .font(.headline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.green)
                                                .padding(.leading, 16)
                                        }
                                        HStack(spacing: 16) {
                                            // Active bottle cards (with fixed size)
                                            ForEach(bottleInstances.filter { !$0.isDead }.sorted { $0.bottleNumber < $1.bottleNumber }, id: \ .id) { bottle in
                                                BottleContainer {
                                                    BottleCardView(bottle: bottle, onRenumbered: { bottleListRefreshTrigger = UUID() })
                                                        .padding(0)
                                                }
                                            }
                                        }
                                        .padding(.horizontal)
                                        .id(bottleListRefreshTrigger)
                                    }
                                    // Only show divider and dead bottles if there are any dead bottles
                                    if bottleInstances.contains(where: { $0.isDead }) {
                                        // Vertical divider between active and dead bottles
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.3))
                                            .frame(width: 1, height: 260) // Increased height to account for header
                                            .padding(.vertical, 5)
                                        // Dead Bottles Section with header
                                        VStack(alignment: .leading, spacing: 8) {
                                            // Dead header (inside the scroll view)
                                            Text("Dead")
                                                .font(.headline)
                                                .fontWeight(.semibold)
                                                .foregroundColor(.red)
                                                .padding(.leading, 16)
                                            HStack(spacing: 16) {
                                                // Dead bottle cards (with fixed size)
                                                ForEach(bottleInstances.filter { $0.isDead }.sorted { $0.bottleNumber < $1.bottleNumber }, id: \ .id) { bottle in
                                                    BottleContainer {
                                                        BottleCardView(bottle: bottle, onRenumbered: { bottleListRefreshTrigger = UUID() })
                                                            .padding(0)
                                                    }
                                                }
                                            }
                                            .padding(.horizontal)
                                            .id(bottleListRefreshTrigger)
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color(.systemGroupedBackground))
                        .cornerRadius(10)
                        
                        // Add Additional Bottles button
                        Button(action: { showingAddPurchaseSheet = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add Additional Bottles")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    
                    // Add Replacement Bottle Section if the whiskey is finished
                    if whiskey.isFinished > 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Replacement Bottle")
                                .font(.headline)
                            
                            if let replacement = whiskey.replacedBy {
                                // Show current replacement bottle
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(replacement.name ?? "Unknown")
                                        .font(.subheadline)
                                        .bold()
                                    
                                    HStack {
                                        if replacement.isOpen {
                                            Text("Open")
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color.orange.opacity(0.2))
                                                .cornerRadius(4)
                                        }
                                        
                                        if let date = replacement.addedDate {
                                            Text("Added \(date, formatter: itemFormatter)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                            } else {
                                // Show add replacement button
                                Button(action: { showingAddReplacementSheet = true }) {
                                    HStack {
                                        Image(systemName: "plus.circle.fill")
                                        Text("Add Replacement Bottle")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundColor(.blue)
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // If it's a wishlist item, show the Add to Collection button
                    if whiskey.isWishlist {
                        Button(action: {
                            showingWishlistToCollectionSheet = true
                        }) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Add to Collection")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .padding(.top)
                    }
                    
                    // Bottle Notes Section
                    if !whiskey.isWishlist {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("BOTTLE NOTES")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            
                            if isEditingNotes {
                                TextEditor(text: $editedNotes)
                                    .frame(minHeight: 100)
                                    .padding(4)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                                
                                HStack {
                                    Button("Cancel") {
                                        isEditingNotes = false
                                        editedNotes = whiskey.notes ?? ""
                                    }
                                    .foregroundColor(.red)
                                    
                                    Spacer()
                                    
                                    Button("Save") {
                                        saveNotes()
                                    }
                                    .foregroundColor(.blue)
                                    .fontWeight(.bold)
                                }
                                .padding(.top, 8)
                            } else {
                                if let notes = whiskey.notes, !notes.isEmpty {
                                    Text(notes)
                                        .font(.body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Text("No bottle notes yet")
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding()
                                }
                                
                                Button(action: {
                                    editedNotes = whiskey.notes ?? ""
                                    isEditingNotes = true
                                }) {
                                    Text("Add Bottle Notes")
                                        .foregroundColor(.blue)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                }
                                .padding(.top, 8)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: Color(.systemGray4), radius: 3)
                        
                        // Tastings Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("TASTINGS")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            
                            if journalEntries.isEmpty {
                                Text("No tastings yet")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding()
                            } else {
                                ForEach(journalEntries) { entry in
                                    JournalEntryRow(entry: entry)
                                }
                            }
                            
                            Button(action: { showingAddJournalSheet = true }) {
                                Text("Add Tasting")
                                    .foregroundColor(.blue)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .padding(.top, 8)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: Color(.systemGray4), radius: 3)
                        
                        // External Content Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("EXTERNAL CONTENT")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            
                            let webContent = fetchAllWebContent()
                            if webContent.isEmpty {
                                VStack {
                                    Text("No web reviews yet")
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding()
                                    
                                    Button(action: { showingWebSearch = true }) {
                                        Text("Search Web for Reviews")
                                            .foregroundColor(.blue)
                                            .frame(maxWidth: .infinity, alignment: .center)
                                    }
                                    .padding(.top, 8)
                                }
                            } else {
                                List(webContent, id: \.id) { content in
                                    WebContentRow(content: content, whiskey: whiskey)
                                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                                        .listRowSeparator(.hidden)
                                }
                                .listStyle(.plain)
                                .frame(minHeight: CGFloat(webContent.count) * 60)
                                .scrollDisabled(true)
                            }
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: Color(.systemGray4), radius: 3)
                    }
                }
                .padding()
            }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingEditSheet) {
            if whiskey.isWishlist {
                EditWishlistItemView(whiskey: whiskey)
            } else {
                EditWhiskeyView(whiskey: whiskey)
            }
        }
        .sheet(isPresented: $showingWebSearch) {
            WebSearchView(whiskey: whiskey)
        }
        .sheet(isPresented: $showingAddJournalSheet) {
            AddJournalEntryView(preSelectedWhiskey: whiskey)
        }
        .sheet(isPresented: $showingAddReplacementSheet) {
            AddReplacementBottleView(originalWhiskey: whiskey)
        }
        // Update sheet presentation to use AlertManager binding
        .sheet(isPresented: $showingAddPurchaseSheet) {
            AddPurchaseView(whiskey: whiskey)
        }
        .sheet(isPresented: $showingWishlistToCollectionSheet) {
            WishlistToCollectionView(wishlistWhiskey: whiskey)
        }
        // Add an ID modifier to prevent duplicate initializations
        .id(viewID)
        .onAppear {
            print("DEBUG: WhiskeyDetailView onAppear for \(whiskey.name ?? "unknown")")
            
            // Force refresh of whiskey from Core Data to ensure latest values
            if let context = whiskey.managedObjectContext {
                context.refresh(whiskey, mergeChanges: true)
            }
            // --- FIX: Always sync tempIsTasted and originalIsTasted with persisted value ---
            tempIsTasted = whiskey.isTasted
            originalIsTasted = whiskey.isTasted
            // ------------------------------------------------------
            // Check if we should show the alert using AlertManager
            if let id = whiskey.id, AlertManager.shared.shouldShowBuyNewBottleAlert(for: id) {
                print("DEBUG: Should show buy alert for \(whiskey.name ?? "unknown")")
                // Delay slightly to ensure view is ready
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    AlertManager.shared.showBuyNewBottleAlert(for: id)
                }
            }
            cleanupInvalidBottleInstances()
            locationManager.requestLocation()
            verifyBottleCounts()
        }
        .onDisappear {
            print("DEBUG: WhiskeyDetailView onDisappear for \(whiskey.name ?? "unknown")")
            
            // Clean up the initialized views set when the view disappears
            if let id = whiskey.id?.uuidString {
                Self.initializedViews.remove(id)
            }
        }
        // Use the AlertManager's published property for the alert
        .alert("Buy New Bottle?", isPresented: Binding(
            get: { alertManager.showingBuyNewBottleAlert && alertManager.currentWhiskeyID == whiskey.id },
            set: { if !$0 { alertManager.dismissBuyNewBottleAlert() } }
        )) {
            Button("Buy Now") {
                print("DEBUG: User selected 'Buy Now'")
                showingAddPurchaseSheet = true
                alertManager.dismissBuyNewBottleAlert()
            }
            Button("Add to Shopping List") {
                print("DEBUG: User selected 'Add to Shopping List'")
                addToShoppingList()
                alertManager.dismissBuyNewBottleAlert()
            }
            Button("Not Now", role: .cancel) { 
                print("DEBUG: User selected 'Not Now'")
                alertManager.dismissBuyNewBottleAlert()
            }
        } message: {
            Text("Would you like to buy another bottle of \(whiskey.name ?? "this whiskey") or add it to your shopping list?")
        }
        .onChange(of: whiskey) { _ in
            cleanupInvalidBottleInstances()
        }
    }
    
    // Convert wishlist item to owned
    private func convertToOwned() {
        if whiskey.isWishlist {
            withAnimation {
                whiskey.statusEnum = .owned
                
                // Update modification date when converting to owned
                whiskey.modificationDate = Date()
                
                do {
                    try viewContext.save()
                    HapticManager.shared.successFeedback()
                } catch {
                    // Handle the error
                    HapticManager.shared.errorFeedback()
                }
            }
        }
    }
    
    // Helper function to sort web content alphabetically by source
    private func sortedWebContent(_ content: Set<WebContent>) -> [WebContent] {
        // Force a refresh of the content to ensure it's up to date
        for item in content {
            viewContext.refresh(item, mergeChanges: true)
        }
        
        return content.sorted { 
            let source1 = ($0.sourceURL?.lowercased() ?? "").components(separatedBy: "//").last?.components(separatedBy: "/").first ?? ""
            let source2 = ($1.sourceURL?.lowercased() ?? "").components(separatedBy: "//").last?.components(separatedBy: "/").first ?? ""
            return source1 < source2
        }
    }
    
    // Get all web content for this whiskey using a direct fetch
    private func fetchAllWebContent() -> [WebContent] {
        let fetchRequest: NSFetchRequest<WebContent> = WebContent.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "whiskey == %@", whiskey)
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            
            if !results.isEmpty {
                for content in results {
                    // Ensure each content item has an ID
                    if content.id == nil {
                        content.id = UUID()
                    }
                    
                    // Ensure content is properly loaded
                    if content.content == nil || content.content?.isEmpty == true {
                        viewContext.refresh(content, mergeChanges: true)
                    }
                    
                    // Ensure the relationship is properly set
                    if content.whiskey?.id != whiskey.id {
                        content.whiskey = whiskey
                    }
                }
                
                // Try to save any changes
                do {
                    try viewContext.save()
                } catch {
                    // Handle error silently
                }
                
                // If we have a last selected content ID, try to restore the selection
                if let lastID = lastSelectedContentID {
                    if let matchingContent = results.first(where: { $0.id == lastID }) {
                        selectedWebContent = matchingContent
                        selectedContentID = lastID
                    }
                }
            }
            
            return results
        } catch {
            return []
        }
    }
    
    // Delete web content
    private func deleteWebContent(_ content: WebContent) {
        withAnimation {
            viewContext.delete(content)
            
            do {
                try viewContext.save()
                HapticManager.shared.successFeedback()
            } catch {
                print("Error deleting web content: \(error)")
                HapticManager.shared.errorFeedback()
            }
        }
    }
    
    // Fetch a fresh reference to WebContent from Core Data by ID
    private func fetchWebContent(withID id: UUID) -> WebContent? {
        let fetchRequest: NSFetchRequest<WebContent> = WebContent.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            
            if let content = results.first {
                print("✅ Successfully fetched WebContent with ID: \(id.uuidString)")
                return content
            } else {
                print("⚠️ No WebContent found with ID: \(id.uuidString)")
                return nil
            }
        } catch {
            print("❌ Error fetching WebContent: \(error)")
            return nil
        }
    }
    
    // Force fetch web content with more aggressive refreshing and error handling
    private func forceFetchWebContent(withID id: UUID) -> WebContent? {
        print("🔄 Attempting aggressive fetch for WebContent ID: \(id.uuidString)")
        
        // First try to fetch directly with the ID
        let fetchRequest: NSFetchRequest<WebContent> = WebContent.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        
        do {
            // First clear any cache to ensure fresh data
            viewContext.refreshAllObjects()
            
            let results = try viewContext.fetch(fetchRequest)
            
            if let content = results.first {
                // Force refresh this object
                viewContext.refresh(content, mergeChanges: true)
                
                if content.content == nil || content.content?.isEmpty == true {
                    print("⚠️ Content is empty after refresh, trying alternative methods")
                    
                    // Try to find it through whiskey relationship
                    if let whiskeyID = whiskey.id {
                        let altFetchRequest: NSFetchRequest<WebContent> = WebContent.fetchRequest()
                        altFetchRequest.predicate = NSPredicate(format: "whiskey.id == %@ AND id == %@", whiskeyID as CVarArg, id as CVarArg)
                        
                        let altResults = try viewContext.fetch(altFetchRequest)
                        if let altContent = altResults.first {
                            // Force refresh again
                            viewContext.refresh(altContent, mergeChanges: true)
                            print("✅ Successfully retrieved content through alternative query")
                            return altContent
                        }
                    }
                    
                    // If still empty, try one more approach - get all content for this whiskey
                    // and find a match
                    if let whiskeyContent = whiskey.webContent as? Set<WebContent>, !whiskeyContent.isEmpty {
                        for potentialContent in whiskeyContent {
                            if potentialContent.id == id {
                                // Force refresh
                                viewContext.refresh(potentialContent, mergeChanges: true)
                                print("✅ Found content through direct object relationship")
                                return potentialContent
                            }
                        }
                    }
                    
                    print("❌ All content loading methods failed")
                    return nil
                }
                
                print("✅ Successfully forced fetch of WebContent with ID: \(id.uuidString)")
                return content
            } else {
                print("⚠️ No WebContent found with ID: \(id.uuidString) during forced fetch")
                
                // Try alternate approach - search by whiskey relationship
                if let whiskeyID = whiskey.id {
                    let allContentRequest: NSFetchRequest<WebContent> = WebContent.fetchRequest()
                    allContentRequest.predicate = NSPredicate(format: "whiskey.id == %@", whiskeyID as CVarArg)
                    
                    let allWhiskeyContent = try viewContext.fetch(allContentRequest)
                    
                    // Find a match by ID
                    if let matchingContent = allWhiskeyContent.first(where: { $0.id == id }) {
                        print("✅ Found matching content through whiskey relationship")
                        return matchingContent
                    }
                }
                
                return nil
            }
        } catch {
            print("❌ Error during forced fetch of WebContent: \(error)")
            return nil
        }
    }
    
    // Force refresh of web content
    private func refreshWebContent() {
        print("Forcing refresh of web content")
        print("Whiskey ID: \(whiskey.id?.uuidString ?? "NO ID")")
        
        // Try to fetch web content directly
        let fetchRequest: NSFetchRequest<WebContent> = WebContent.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "whiskey == %@", whiskey)
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            print("Direct fetch found \(results.count) web content items")
            
            if !results.isEmpty {
                print("✅ Found web content through direct fetch")
                for content in results {
                    print("Content: \(content.title ?? "untitled"), ID: \(content.id?.uuidString ?? "NO ID")")
                }
            }
            
            // Force view refresh only once
            DispatchQueue.main.async {
                webContentRefreshTrigger = UUID()
                print("Set new webContentRefreshTrigger: \(webContentRefreshTrigger.uuidString)")
            }
        } catch {
            print("❌ Error fetching web content directly: \(error)")
        }
    }
    
    // Add this new function to save notes
    private func saveNotes() {
        withAnimation {
            whiskey.notes = editedNotes.isEmpty ? nil : editedNotes
            whiskey.modificationDate = Date()
            
            do {
                try viewContext.save()
                HapticManager.shared.successFeedback()
                isEditingNotes = false
            } catch {
                HapticManager.shared.errorFeedback()
                print("Error saving notes: \(error)")
            }
        }
    }
    
    private func saveOpenStatus() {
        // Update the whiskey
        whiskey.isOpen = tempIsOpen
        whiskey.modificationDate = Date()
        
        // Save to Core Data
        do {
            try viewContext.save()
            print("✅ Successfully saved toggle state to Core Data")
            
            // Update the original value to match the new state
            originalIsOpen = tempIsOpen
            
            // Reset the unsaved changes flag
            hasUnsavedChanges = false
            
            // Provide haptic feedback
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } catch {
            print("❌ Error saving toggle state: \(error)")
            
            // Error feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
    
    private func saveTastedStatus() {
        withAnimation {
            if tempIsTasted != originalIsTasted {
                whiskey.isTasted = tempIsTasted
                originalIsTasted = tempIsTasted
                hasUnsavedTastedChanges = false
                
                do {
                    try viewContext.save()
                    HapticManager.shared.successFeedback()
                } catch {
                    HapticManager.shared.errorFeedback()
                    print("Error saving tasted status: \(error)")
                }
            }
        }
    }
    
    // Mark the current bottle as finished
    private func markAsFinished() {
        withAnimation {
            whiskey.isFinished = whiskey.numberOfBottles
            whiskey.modificationDate = Date()
            
            do {
                try viewContext.save()
                HapticManager.shared.successFeedback()
            } catch {
                HapticManager.shared.errorFeedback()
                let nsError = error as NSError
                print("Error marking as finished: \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    private func markAsReplacement() {
        withAnimation {
            // Set the replacement status
            whiskey.replacementStatus = "isReplacement"
            
            // Mark all bottles as finished
            whiskey.isFinished = whiskey.numberOfBottles
            whiskey.modificationDate = Date()
            
            do {
                try viewContext.save()
                HapticManager.shared.successFeedback()
            } catch {
                HapticManager.shared.errorFeedback()
                let nsError = error as NSError
                print("Error marking as replacement: \(nsError), \(nsError.userInfo)")
            }
        }
    }
    
    private func saveFinishedStatus() {
        print("Saving finished status. Current isFinished: \(isFinished)")
        
        // Store the current value we want to save
        let newFinishedValue = isFinished
        print("newFinishedValue to save: \(newFinishedValue)")
        
        // Update the whiskey
        whiskey.isFinished = Int16(newFinishedValue)
        whiskey.modificationDate = Date()
        
        do {
            try viewContext.save()
            print("Successfully saved. Whiskey.isFinished now: \(whiskey.isFinished)")
            
            // After successful save, update our state
            DispatchQueue.main.async {
                hasUnsavedFinishedChanges = false
                
                // Show buy new bottle options only after successfully saving and if marking as finished
                if newFinishedValue > Int16(whiskey.isFinished) - 1 {
                    showBuyNewBottleOptions()
                }
            }
            
            HapticManager.shared.successFeedback()
        } catch {
            // If save fails, revert the isFinished value
            print("Save failed!")
            DispatchQueue.main.async {
                isFinished = Int16(whiskey.isFinished)
            }
            HapticManager.shared.errorFeedback()
            let nsError = error as NSError
            print("Error saving finished status: \(nsError), \(nsError.userInfo)")
        }
    }
    
    private func showBuyNewBottleOptions() {
        // Use the AlertManager instead of local state
        AlertManager.shared.showBuyNewBottleAlert(for: whiskey.id)
    }
    
    private func addToShoppingList() {
        withAnimation {
            whiskey.replacementStatus = "wantToReplace"  // Using existing status
            whiskey.modificationDate = Date()
            
            do {
                try viewContext.save()
                HapticManager.shared.successFeedback()
            } catch {
                HapticManager.shared.errorFeedback()
                print("Error adding to shopping list: \(error)")
            }
        }
    }
    
    private func addNewBottle() {
        // Show the purchase view instead of directly creating a bottle
        showingAddPurchaseSheet = true
    }
    
    // Timer to handle alert cleanup
    @State private var alertTimer: Timer? = nil
    
    private func cleanupInvalidBottleInstances() {
        let context = viewContext
        let fetchRequest: NSFetchRequest<BottleInstance> = BottleInstance.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "whiskey == nil")
        
        do {
            let invalidBottles = try context.fetch(fetchRequest)
            for bottle in invalidBottles {
                context.delete(bottle)
            }
            
            if !invalidBottles.isEmpty {
                try context.save()
                print("Cleaned up \(invalidBottles.count) invalid bottle instances")
            }
        } catch {
            print("Error cleaning up invalid bottle instances: \(error)")
        }
    }
    
    private func verifyBottleCounts() {
        let activeBottles = bottleInstances.filter { !$0.isDead }
        let deadBottles = bottleInstances.filter { $0.isDead }
        
        print("DEBUG: Bottle counts verification")
        print("DEBUG: Whiskey: \(whiskey.name ?? "unknown")")
        print("DEBUG: Active bottles count: \(activeBottles.count)")
        print("DEBUG: Dead bottles count: \(deadBottles.count)")
        print("DEBUG: Total bottles count: \(bottleInstances.count)")
        print("DEBUG: Whiskey.numberOfBottles: \(whiskey.numberOfBottles)")
        print("DEBUG: Whiskey.isFinished: \(whiskey.isFinished)")
        print("DEBUG: Whiskey.deadBottleCount: \(whiskey.deadBottleCount)")
        print("DEBUG: Whiskey.activeBottleCount: \(whiskey.activeBottleCount)")
        
        // Ensure isFinished matches dead bottles count
        if whiskey.isFinished != Int16(deadBottles.count) {
            print("DEBUG: ⚠️ Mismatch: isFinished (\(whiskey.isFinished)) doesn't match dead bottles count (\(deadBottles.count))")
            whiskey.isFinished = Int16(deadBottles.count)
            try? whiskey.managedObjectContext?.save()
            print("DEBUG: ✅ Fixed: isFinished updated to \(whiskey.isFinished)")
        }
        
        // Ensure numberOfBottles matches active bottles count
        if whiskey.numberOfBottles != Int16(activeBottles.count) {
            print("DEBUG: ⚠️ Mismatch: numberOfBottles (\(whiskey.numberOfBottles)) doesn't match active bottles count (\(activeBottles.count))")
            whiskey.numberOfBottles = Int16(activeBottles.count)
            try? whiskey.managedObjectContext?.save()
            print("DEBUG: ✅ Fixed: numberOfBottles updated to \(whiskey.numberOfBottles)")
        }
    }
}

// Edit whiskey view
struct EditWhiskeyView: View {
    let whiskey: Whiskey
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var type: String
    @State private var age: String
    @State private var proof: String
    @State private var finish: String
    @State private var distillery: String
    @State private var numberOfBottles: String
    @State private var price: String
    @State private var isFinished: Int16
    @State private var isBiB: Bool
    @State private var isSiB: Bool
    @State private var isStorePick: Bool
    @State private var storePickName: String
    @State private var notes: String
    @State private var isCaskStrength: Bool
    @State private var isTasted: Bool
    
    @StateObject private var viewStateUpdater = ViewStateUpdater()
    
    // Computed properties for derived status
    private var isOpen: Bool {
        bottleInstances.filter { !$0.isDead }.first { $0.isOpen } != nil
    }
    
    // The isTasted property is now just a simple boolean from the whiskey model
    // No need to check individual bottles
    
    // Add helper property for active bottles count
    private var activeBottlesCount: Int {
        bottleInstances.filter { !$0.isDead }.count
    }
    
    // Add helper property for open bottles count
    private var openBottlesCount: Int {
        bottleInstances.filter { !$0.isDead && $0.isOpen }.count
    }
    
    // Add helper property for tasted bottles count
    private var tastedBottlesCount: Int {
        bottleInstances.filter { !$0.isDead }.filter { bottle in
            guard let entries = bottle.whiskey?.journalEntries as? Set<JournalEntry> else { return false }
            return !entries.isEmpty
        }.count
    }
    
    @FetchRequest private var bottleInstances: FetchedResults<BottleInstance>
    
    init(whiskey: Whiskey) {
        self.whiskey = whiskey
        
        // Initialize state variables with whiskey properties
        _name = State(initialValue: whiskey.name ?? "")
        _type = State(initialValue: whiskey.type ?? "")
        _age = State(initialValue: whiskey.age ?? "")
        _proof = State(initialValue: whiskey.proof > 0 ? String(format: "%.1f", whiskey.proof) : "")
        _finish = State(initialValue: whiskey.finish ?? "")
        _distillery = State(initialValue: whiskey.distillery ?? "")
        // Initialize with active bottles (total - finished)
        _numberOfBottles = State(initialValue: String(max(0, Int(whiskey.numberOfBottles) - Int(whiskey.isFinished))))
        _price = State(initialValue: whiskey.price > 0 ? String(format: "%.2f", whiskey.price) : "")
        _isFinished = State(initialValue: whiskey.isFinished)
        _isBiB = State(initialValue: whiskey.isBiB)
        _isSiB = State(initialValue: whiskey.isSiB)
        _isStorePick = State(initialValue: whiskey.isStorePick)
        _storePickName = State(initialValue: whiskey.storePickName ?? "")
        _notes = State(initialValue: whiskey.notes ?? "")
        _isCaskStrength = State(initialValue: whiskey.isCaskStrength)
        _isTasted = State(initialValue: whiskey.isTasted)
        
        // Initialize the bottle instances fetch request
        _bottleInstances = FetchRequest<BottleInstance>(
            sortDescriptors: [NSSortDescriptor(keyPath: \BottleInstance.bottleNumber, ascending: true)],
            predicate: NSPredicate(format: "whiskey == %@", whiskey),
            animation: .default
        )
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Info")) {
                    TextField("Name", text: $name)
                    TextField("Type", text: $type)
                    TextField("Distillery", text: $distillery)
                    TextField("Age Statement", text: $age)
                    TextField("Proof", text: $proof)
                        .keyboardType(.decimalPad)
                    TextField("Finish", text: $finish)
                    TextField("Price", text: $price)
                        .keyboardType(.decimalPad)
                }
                
                Section(header: Text("Inventory Info")) {
                    HStack {
                        Text("Number of Bottles:")
                            .foregroundColor(.secondary)
                        Spacer()
                        TextField("1", text: $numberOfBottles)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                    }
                    
                    HStack {
                        Text("Number of Dead Bottles:")
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack {
                            Button(action: {
                                if isFinished > Int16(0) {
                                    isFinished -= 1
                                }
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(Color(red: 0.8, green: 0.6, blue: 0.3))
                            }
                            
                            Text("\(isFinished)")
                                .frame(minWidth: 30)
                                .multilineTextAlignment(.center)
                            
                            Button(action: {
                                if isFinished < whiskey.numberOfBottles {
                                    isFinished += 1
                                }
                            }) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(Color(red: 0.8, green: 0.6, blue: 0.3))
                            }
                        }
                    }
                    
                    // Show derived status instead of toggles
                    HStack {
                        Text("Open Status:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(openBottlesCount) of \(activeBottlesCount) bottles open")
                            .foregroundColor(openBottlesCount > 0 ? .green : .secondary)
                    }
                    
                    HStack {
                        Text("Tasted:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Toggle("", isOn: $isTasted)
                            .labelsHidden()
                    }
                }
                
                Section(header: Text("Bottle Notes")) {
                    TextField("Notes about this bottle", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section(header: Text("Special Attributes")) {
                    Toggle("Bottled in Bond", isOn: $isBiB)
                    Toggle("Single Barrel", isOn: $isSiB)
                    Toggle("Store Pick", isOn: $isStorePick)
                    if isStorePick {
                        TextField("Store Name", text: $storePickName)
                    }
                    Toggle("Cask Strength", isOn: $isCaskStrength)
                }
            }
            .navigationTitle("Edit Whiskey")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveWhiskey()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    // Helper function to normalize whiskey type and prevent duplicates
    private func normalizeType(_ inputType: String, existingTypes: [String]) -> String {
        let trimmedType = inputType.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If empty, return as-is
        if trimmedType.isEmpty {
            return trimmedType
        }
        
        // Look for case-insensitive match with existing types
        for existingType in existingTypes {
            if existingType.lowercased() == trimmedType.lowercased() {
                return existingType // Use the existing capitalization
            }
        }
        
        // No match found, return the trimmed input (properly capitalized)
        return trimmedType
    }
    
    private func saveWhiskey() {
        withAnimation {
            // Get all existing types from the context to prevent duplicates
            let fetchRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
            let allWhiskeys = (try? viewContext.fetch(fetchRequest)) ?? []
            let existingTypes = Array(Set(allWhiskeys.compactMap { $0.type }.filter { !$0.isEmpty }))
            
            // Update whiskey properties
            whiskey.name = name
            whiskey.type = normalizeType(type, existingTypes: existingTypes)
            whiskey.age = age
            whiskey.proof = Double(proof) ?? 0.0
            whiskey.finish = finish
            whiskey.distillery = distillery
            whiskey.price = Double(price) ?? 0.0
            whiskey.isOpen = isOpen
            whiskey.isBiB = isBiB
            whiskey.isSiB = isSiB
            whiskey.isStorePick = isStorePick
            whiskey.storePickName = isStorePick ? storePickName : nil
            whiskey.notes = notes.isEmpty ? nil : notes
            whiskey.isCaskStrength = isCaskStrength
            whiskey.isTasted = isTasted
            
            // Get the target number of bottles from user input
            let targetBottles = Int16(numberOfBottles) ?? 1
            
            // Get current bottle instances
            let bottleFetchRequest: NSFetchRequest<BottleInstance> = BottleInstance.fetchRequest()
            bottleFetchRequest.predicate = NSPredicate(format: "whiskey == %@", whiskey)
            
            do {
                let existingBottles = try viewContext.fetch(bottleFetchRequest)
                let currentActiveCount = existingBottles.filter { !$0.isDead }.count
                
                #if DEBUG
                print("DEBUG: Current active bottles: \(currentActiveCount)")
                print("DEBUG: Target bottles: \(targetBottles)")
                #endif
                
                // If we need more bottles, create them
                if targetBottles > currentActiveCount {
                    for i in currentActiveCount..<Int(targetBottles) {
                        let newBottle = BottleInstance(context: viewContext)
                        newBottle.id = UUID()
                        newBottle.dateAdded = Date()
                        newBottle.price = whiskey.price
                        
                        // Ensure whiskey is valid before setting the relationship
                        if let whiskeyID = whiskey.id, 
                           let validWhiskey = try? viewContext.existingObject(with: whiskey.objectID) as? Whiskey {
                            newBottle.whiskey = validWhiskey
                        } else {
                            print("Error: Invalid whiskey reference when creating bottle instance")
                            continue
                        }
                        
                        newBottle.isOpen = false
                        newBottle.isDead = false
                        newBottle.bottleNumber = Int16(i + 1)
                        
                        #if DEBUG
                        print("DEBUG: Created new bottle with number \(newBottle.bottleNumber)")
                        #endif
                    }
                }
                // If we need fewer bottles, mark the excess as dead
                else if targetBottles < currentActiveCount {
                    let bottlesToMarkDead = existingBottles
                        .filter { !$0.isDead }
                        .sorted { $0.bottleNumber > $1.bottleNumber }
                        .prefix(currentActiveCount - Int(targetBottles))
                    
                    for bottle in bottlesToMarkDead {
                        bottle.isDead = true
                        #if DEBUG
                        print("DEBUG: Marked bottle \(bottle.bottleNumber) as dead")
                        #endif
                    }
                }
                
                // Update the total number of bottles
                whiskey.numberOfBottles = targetBottles + whiskey.isFinished
                
                #if DEBUG
                print("DEBUG: Total bottles after update: \(whiskey.numberOfBottles)")
                print("DEBUG: Active bottles after update: \(targetBottles)")
                #endif
                
                // Save all changes
                try viewContext.save()
                HapticManager.shared.successFeedback()
                
                // Force updates to propagate
                viewStateUpdater.objectWillChange.send()
                
                // Explicitly refresh this object
                viewContext.refresh(whiskey, mergeChanges: true)
                
                // Post notification for any observers
                NotificationCenter.default.post(name: NSNotification.Name("WhiskeyUpdated"), object: whiskey)
                
                dismiss()
            } catch {
                HapticManager.shared.errorFeedback()
                let nsError = error as NSError
                print("Error saving whiskey: \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

// Helper class to enable view refresh
class ViewStateUpdater: ObservableObject, Hashable {
    // Add an ID to make the class hashable
    private let id = UUID()
    
    func refresh() {
        objectWillChange.send()
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // Equatable conformance required by Hashable
    static func == (lhs: ViewStateUpdater, rhs: ViewStateUpdater) -> Bool {
        lhs.id == rhs.id
    }
}

// Consistent badge style with list view
struct DetailBadge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

// Section header component
struct SectionHeader: View {
    let title: String
    
    var body: some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .padding(.bottom, 4)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

// Price detail view with privacy features
struct PriceDetailView: View {
    let price: Double
    
    @ObservedObject private var privacyManager = PrivacyManager.shared
    @State private var temporarilyShowPrice: Bool = false
    
    var body: some View {
        HStack(spacing: 5) {
            if privacyManager.hidePrices && !temporarilyShowPrice {
                Text("Hidden")
                    .multilineTextAlignment(.trailing)
                
                Button(action: {
                    temporarilyShowPrice = true
                    // Auto-hide after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        temporarilyShowPrice = false
                    }
                    HapticManager.shared.selectionFeedback()
                }) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.secondary)
                }
            } else {
                Text("$\(String(format: "%.2f", price))")
                    .multilineTextAlignment(.trailing)
                
                if privacyManager.hidePrices && temporarilyShowPrice {
                    Image(systemName: "timer")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct WhiskeyDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            WhiskeyDetailView(whiskey: {
                let whiskey = Whiskey()
                whiskey.name = "Buffalo Trace"
                whiskey.type = "Kentucky Straight Bourbon"
                whiskey.age = "10 Year"
                whiskey.proof = 90
                whiskey.finish = "Oak and Vanilla"
                whiskey.distillery = "Buffalo Trace Distillery"
                whiskey.numberOfBottles = 2
                whiskey.isFinished = 1
                whiskey.isBiB = true
                whiskey.isSiB = true
                whiskey.isStorePick = true
                whiskey.storePickName = "Blanton's Store"
                return whiskey
            }())
        }
    }
}

// View for editing a saved web review (renamed to avoid conflict)
struct DetailEditWebContentView: View {
    @ObservedObject var content: WebContent
    
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String
    @State private var contentText: String
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    init(content: WebContent) {
        self.content = content
        print("Initializing DetailEditWebContentView with content ID: \(content.id?.uuidString ?? "No ID")")
        print("Content length at init: \(content.content?.count ?? 0)")
        
        _title = State(initialValue: content.title ?? "")
        _contentText = State(initialValue: content.content ?? "")
    }
    
    var body: some View {
        Form {
            Section(header: Text("Review Details")) {
                TextField("Title", text: $title)
                
                if let sourceURL = content.sourceURL, let url = URL(string: sourceURL) {
                    HStack {
                        Text("Source")
                        Spacer()
                        Text(url.host ?? sourceURL)
                            .foregroundColor(.blue)
                    }
                }
                
                if let date = content.date {
                    HStack {
                        Text("Saved on")
                        Spacer()
                        Text(date, style: .date)
                    }
                }
            }
            
            Section(header: Text("Content")) {
                TextEditor(text: $contentText)
                    .frame(minHeight: 200)
            }
            
            // Debugging info
            Section(header: Text("Debug Info")) {
                Text("Content ID: \(content.id?.uuidString ?? "No ID")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Edit Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveChanges()
                }
                .disabled(title.isEmpty || contentText.isEmpty)
            }
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func saveChanges() {
        withAnimation {
            print("Saving changes to WebContent with ID: \(content.id?.uuidString ?? "No ID")")
            print("New content length: \(contentText.count)")
            
            // Create a backup of the original content in case we need to restore
            let originalTitle = content.title
            let originalContent = content.content
            
            // Assign values directly
            content.title = title
            content.content = contentText
            
            // Ensure date is set if missing
            if content.date == nil {
                content.date = Date()
            }
            
            // Ensure ID is set if missing
            if content.id == nil {
                content.id = UUID()
            }
            
            do {
                // Force context to process changes
                viewContext.refresh(content, mergeChanges: true)
                
                // Save changes
                try viewContext.save()
                print("Successfully saved changes to WebContent")
                
                // Extra verification after save
                if content.content == nil || content.content?.isEmpty == true {
                    print("WARNING: Content is still empty after save!")
                    
                    // Try to recover by restoring original content
                    content.title = originalTitle
                    content.content = originalContent
                    
                    do {
                        try viewContext.save()
                        print("Successfully restored original content")
                    } catch {
                        print("Failed to restore original content: \(error)")
                    }
                    
                    errorMessage = "Failed to save content. Original content has been restored."
                    showingErrorAlert = true
                } else {
                    print("Content verified after save: \(content.content?.count ?? 0) characters")
                    HapticManager.shared.successFeedback()
                    dismiss()
                }
            } catch {
                HapticManager.shared.errorFeedback()
                print("Error saving edited content: \(error)")
                
                // Try to recover by rolling back and retrying once
                viewContext.rollback()
                
                do {
                    // Ensure ID is set again after rollback
                    if content.id == nil {
                        content.id = UUID()
                    }
                    
                    // Try saving again
                    try viewContext.save()
                    print("Successfully saved changes to WebContent after retry")
                    HapticManager.shared.successFeedback()
                    dismiss()
                } catch {
                    print("Failed to save changes after retry: \(error)")
                    errorMessage = "Failed to save changes. Please try again."
                    showingErrorAlert = true
                }
            }
        }
    }
}

// New direct web content view that uses only strings for reliability
struct DirectWebContentView: View {
    let contentIDString: String  // Uses string to avoid UUID parsing issues
    let whiskeyIDString: String  // Uses string to avoid UUID parsing issues
    let startInEditMode: Bool    // Whether to start directly in edit mode
    
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    // State for UI
    @State private var isLoading = true
    @State private var title = ""
    @State private var content = ""
    @State private var sourceURL = ""
    @State private var date = Date()
    @State private var showingEditSheet = false
    @State private var errorMessage: String? = nil
    @State private var refreshTrigger = UUID()
    
    init(contentIDString: String, whiskeyIDString: String, startInEditMode: Bool = false) {
        self.contentIDString = contentIDString
        self.whiskeyIDString = whiskeyIDString
        self.startInEditMode = startInEditMode
    }
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    VStack {
                        ProgressView("Loading content...")
                        Text("Content ID: \(contentIDString)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.top)
                    }
                } else if let error = errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        
                        Text("Error Loading Content")
                            .font(.headline)
                        
                        Text(error)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Close") {
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        .padding(.top)
                    }
                    .padding()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text(title)
                                .font(.title)
                                .fontWeight(.bold)
                            
                            if !sourceURL.isEmpty, let url = URL(string: sourceURL) {
                                Link("Source: \(url.host ?? sourceURL)", destination: url)
                                    .font(.caption)
                            }
                            
                            Text("Saved on \(date, formatter: itemFormatter)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Divider()
                            
                            Text(content)
                                .font(.body)
                        }
                        .padding()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !content.isEmpty {
                        Button("Edit") {
                            showingEditSheet = true
                        }
                    }
                }
            }
        }
        .id(refreshTrigger)
        .onAppear {
            loadContent()
            if startInEditMode {
                // Small delay to ensure content is loaded first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            NavigationView {
                DirectContentEditView(
                    title: title,
                    content: content,
                    sourceURL: sourceURL,
                    date: date,
                    contentIDString: contentIDString,
                    whiskeyIDString: whiskeyIDString,
                    onSave: { newTitle, newContent in
                        // Update our local state immediately
                        self.title = newTitle
                        self.content = newContent
                        self.refreshTrigger = UUID()
                    }
                )
                .environment(\.managedObjectContext, viewContext)
            }
        }
    }
    
    private func loadContent() {
        print("🔍 DirectWebContentView: Loading content with ID string: \(contentIDString)")
        isLoading = true
        errorMessage = nil
        
        // Create a fetch request to directly get the content by ID string
        let fetchRequest: NSFetchRequest<WebContent> = WebContent.fetchRequest()
        
        // Try to convert the ID string to UUID, but have a fallback
        if let contentID = UUID(uuidString: contentIDString) {
            fetchRequest.predicate = NSPredicate(format: "id == %@", contentID as CVarArg)
        } else {
            // If can't parse ID, try to match the string representation
            fetchRequest.predicate = NSPredicate(format: "id.description == %@", contentIDString)
        }
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            
            if let foundContent = results.first {
                print("✅ DirectWebContentView: Found content with ID: \(contentIDString)")
                
                // Force a refresh to ensure we have the latest data
                viewContext.refresh(foundContent, mergeChanges: true)
                
                // Ensure web content has a valid whiskey relationship
                if foundContent.whiskey == nil && !whiskeyIDString.isEmpty {
                    if let whiskeyID = UUID(uuidString: whiskeyIDString) {
                        let whiskeyFetch = NSFetchRequest<Whiskey>(entityName: "Whiskey")
                        whiskeyFetch.predicate = NSPredicate(format: "id == %@", whiskeyID as CVarArg)
                        
                        if let whiskey = try viewContext.fetch(whiskeyFetch).first {
                            print("⚠️ DirectWebContentView: Content missing whiskey relationship, fixing")
                            foundContent.whiskey = whiskey
                            
                            // Ensure changes are saved
                            try viewContext.save()
                            print("✅ DirectWebContentView: Fixed whiskey relationship")
                        }
                    }
                }
                
                // Directly extract all data into local state
                self.title = foundContent.title ?? "Untitled"
                self.content = foundContent.content ?? ""
                self.sourceURL = foundContent.sourceURL ?? ""
                self.date = foundContent.date ?? Date()
                
                if self.content.isEmpty {
                    print("⚠️ DirectWebContentView: Content is empty, trying alternative approach")
                    tryAlternativeFetch()
                } else {
                    print("✅ DirectWebContentView: Successfully loaded content: \(self.title)")
                    
                    // Verify content is properly persisted by forcing a re-fetch
                    verifyContentPersistence(contentID: UUID(uuidString: contentIDString))
                    
                    isLoading = false
                }
            } else {
                print("⚠️ DirectWebContentView: No content found with ID: \(contentIDString)")
                tryAlternativeFetch()
            }
        } catch {
            print("❌ DirectWebContentView: Error fetching content: \(error)")
            tryAlternativeFetch()
        }
    }
    
    private func tryAlternativeFetch() {
        print("🔄 DirectWebContentView: Trying alternative fetch methods for content ID: \(contentIDString)")
        
        // First try to find content by whiskey relationship
        if let whiskeyID = UUID(uuidString: whiskeyIDString) {
            let fetchRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", whiskeyID as CVarArg)
            
            do {
                let whiskeys = try viewContext.fetch(fetchRequest)
                
                if let whiskey = whiskeys.first {
                    print("✅ DirectWebContentView: Found whiskey with ID: \(whiskeyIDString)")
                    
                    // Get ALL associated WebContent objects for this whiskey
                    let contentFetch: NSFetchRequest<WebContent> = WebContent.fetchRequest()
                    contentFetch.predicate = NSPredicate(format: "whiskey == %@", whiskey)
                    
                    let allContent = try viewContext.fetch(contentFetch)
                    print("DirectWebContentView: Found \(allContent.count) content items for this whiskey")
                    
                    if allContent.isEmpty {
                        errorMessage = "No saved reviews for this whiskey"
                        isLoading = false
                        return
                    }
                    
                    // Try to find by matching the ID string
                    if let matchingContent = allContent.first(where: { 
                        $0.id?.uuidString == contentIDString || 
                        $0.id?.description == contentIDString 
                    }) {
                        print("✅ DirectWebContentView: Found matching content through whiskey relationship")
                        
                        // Directly extract all data
                        self.title = matchingContent.title ?? "Untitled"
                        self.content = matchingContent.content ?? ""
                        self.sourceURL = matchingContent.sourceURL ?? ""
                        self.date = matchingContent.date ?? Date()
                        
                        if self.content.isEmpty {
                            errorMessage = "Content data is empty"
                        } else {
                            print("✅ DirectWebContentView: Successfully loaded content: \(self.title)")
                        }
                    } else {
                        // If we couldn't find the specific content, just show the first one
                        print("⚠️ DirectWebContentView: Specific content not found, showing most recent review")
                        
                        // Sort by date, most recent first
                        let sortedContent = allContent.sorted { 
                            ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast)
                        }
                        
                        if let firstContent = sortedContent.first {
                            // Load the first/most recent content item
                            self.title = firstContent.title ?? "Untitled"
                            self.content = firstContent.content ?? ""
                            self.sourceURL = firstContent.sourceURL ?? ""
                            self.date = firstContent.date ?? Date()
                            
                            // Update the stored content ID to match this one
                            if let contentID = firstContent.id?.uuidString {
                                print("⚠️ DirectWebContentView: Updating saved content ID to \(contentID)")
                                UserDefaults.standard.setContentID(contentID, for: whiskeyIDString)
                            }
                            
                            print("✅ DirectWebContentView: Loaded alternative content: \(self.title)")
                        } else {
                            errorMessage = "Could not find content with ID: \(contentIDString)"
                        }
                    }
                } else {
                    errorMessage = "Could not find associated whiskey"
                }
            } catch {
                print("❌ DirectWebContentView: Error in alternative fetch: \(error)")
                errorMessage = "Error loading content: \(error.localizedDescription)"
            }
        } else {
            errorMessage = "Invalid whiskey ID format: \(whiskeyIDString)"
        }
        
        isLoading = false
    }
    
    private func verifyContentPersistence(contentID: UUID?) {
        guard let contentID = contentID else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            do {
                // Try to fetch the content again to verify it's persisted
                let verifyFetch = NSFetchRequest<WebContent>(entityName: "WebContent")
                verifyFetch.predicate = NSPredicate(format: "id == %@", contentID as CVarArg)
                
                let results = try viewContext.fetch(verifyFetch)
                
                if let verifiedContent = results.first, verifiedContent.content != nil {
                    print("✅ DirectWebContentView: Verified content is persisted in Core Data")
                } else {
                    print("⚠️ DirectWebContentView: Content verification failed - could not re-fetch content")
                }
            } catch {
                print("❌ DirectWebContentView: Error during content verification: \(error)")
            }
        }
    }
}

// Direct content edit view that uses only strings
struct DirectContentEditView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String
    @State private var content: String
    let sourceURL: String
    let date: Date
    let contentIDString: String
    let whiskeyIDString: String
    let onSave: (String, String) -> Void
    
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    @State private var isLoading = false
    @State private var contentVerified = false
    
    init(title: String, content: String, sourceURL: String, date: Date, 
         contentIDString: String, whiskeyIDString: String,
         onSave: @escaping (String, String) -> Void) {
        self._title = State(initialValue: title)
        self._content = State(initialValue: content)
        self.sourceURL = sourceURL
        self.date = date
        self.contentIDString = contentIDString
        self.whiskeyIDString = whiskeyIDString
        self.onSave = onSave
        
        print("📝 DirectContentEditView: Initialized with content length: \(content.count) characters")
    }
    
    var body: some View {
        ZStack {
            Form {
                Section(header: Text("Review Details")) {
                    TextField("Title", text: $title)
                    
                    if !sourceURL.isEmpty, let url = URL(string: sourceURL) {
                        HStack {
                            Text("Source")
                            Spacer()
                            Text(url.host ?? sourceURL)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    HStack {
                        Text("Saved on")
                        Spacer()
                        Text(date, style: .date)
                    }
                }
                
                Section(header: Text("Content")) {
                    TextEditor(text: $content)
                        .frame(minHeight: 200)
                }
                
                #if DEBUG
                // Debug info section
                Section(header: Text("Debug Info")) {
                    Text("Content ID: \(contentIDString)")
                        .font(.caption2)
                    Text("Content Length: \(content.count) characters")
                        .font(.caption2)
                    Text("Verified: \(contentVerified ? "Yes" : "No")")
                        .font(.caption2)
                }
                #endif
            }
            .navigationTitle("Edit Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(title.isEmpty || content.isEmpty || isLoading)
                }
            }
            .onAppear {
                verifyContent()
            }
            .alert("Error", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            
            if isLoading {
                Color.black.opacity(0.2)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    ProgressView()
                    Text("Loading...")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                }
            }
        }
    }
    
    private func verifyContent() {
        print("🔍 DirectContentEditView: Verifying content is loaded properly")
        
        // Simple check for content length
        if content.isEmpty && !contentIDString.isEmpty {
            isLoading = true
            
            // Attempt to reload the content
            if let contentID = UUID(uuidString: contentIDString) {
                let fetchRequest: NSFetchRequest<WebContent> = WebContent.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "id == %@", contentID as CVarArg)
                
                do {
                    let results = try viewContext.fetch(fetchRequest)
                    
                    if let foundContent = results.first {
                        print("✅ DirectContentEditView: Successfully reloaded content")
                        
                        // Update local state
                        DispatchQueue.main.async {
                            self.title = foundContent.title ?? "Untitled"
                            self.content = foundContent.content ?? ""
                            self.contentVerified = true
                            self.isLoading = false
                        }
                    } else {
                        print("⚠️ DirectContentEditView: Content not found during verification")
                        self.contentVerified = false
                        self.isLoading = false
                    }
                } catch {
                    print("❌ DirectContentEditView: Error verifying content: \(error)")
                    self.isLoading = false
                }
            } else {
                print("⚠️ DirectContentEditView: Invalid content ID format during verification")
                self.isLoading = false
            }
        } else {
            print("✅ DirectContentEditView: Content already loaded (\(content.count) characters)")
            self.contentVerified = true
        }
    }
    
    private func saveChanges() {
        print("💾 DirectContentEditView: Saving changes for content ID: \(contentIDString)")
        isLoading = true
        
        // Try to find the content by ID
        if let contentID = UUID(uuidString: contentIDString) {
            let fetchRequest: NSFetchRequest<WebContent> = WebContent.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", contentID as CVarArg)
            
            do {
                let results = try viewContext.fetch(fetchRequest)
                
                if let foundContent = results.first {
                    print("✅ DirectContentEditView: Found content to update")
                    
                    // Update the content
                    foundContent.title = title
                    foundContent.content = content
                    
                    try viewContext.save()
                    print("✅ DirectContentEditView: Successfully saved content changes")
                    
                    // Call the onSave callback
                    onSave(title, content)
                    
                    // Dismiss
                    isLoading = false
                    dismiss()
                } else {
                    print("⚠️ DirectContentEditView: Content not found, attempting to create new")
                    
                    // Try to find the whiskey
                    if let whiskeyID = UUID(uuidString: whiskeyIDString) {
                        let whiskeyFetch: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
                        whiskeyFetch.predicate = NSPredicate(format: "id == %@", whiskeyID as CVarArg)
                        
                        let whiskeys = try viewContext.fetch(whiskeyFetch)
                        
                        if let whiskey = whiskeys.first {
                            // Create a new content
                            let newContent = WebContent(context: viewContext)
                            newContent.id = contentID
                            newContent.title = title
                            newContent.content = content
                            newContent.sourceURL = sourceURL
                            newContent.date = date
                            newContent.whiskey = whiskey
                            
                            try viewContext.save()
                            print("✅ DirectContentEditView: Created new content with ID: \(contentIDString)")
                            
                            // Call the onSave callback
                            onSave(title, content)
                            
                            // Dismiss
                            isLoading = false
                            dismiss()
                        } else {
                            isLoading = false
                            errorMessage = "Could not find associated whiskey"
                            showingErrorAlert = true
                        }
                    } else {
                        isLoading = false
                        errorMessage = "Invalid whiskey ID format"
                        showingErrorAlert = true
                    }
                }
            } catch {
                print("❌ DirectContentEditView: Error saving content: \(error)")
                isLoading = false
                errorMessage = "Failed to save changes: \(error.localizedDescription)"
                showingErrorAlert = true
            }
        } else {
            isLoading = false
            errorMessage = "Invalid content ID format"
            showingErrorAlert = true
        }
    }
}

// Mini modal to toggle open status
struct MiniEditView: View {
    let whiskey: Whiskey
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var isOpen: Bool
    
    init(whiskey: Whiskey) {
        self.whiskey = whiskey
        _isOpen = State(initialValue: whiskey.isOpen)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Toggle("Open", isOn: $isOpen)
                    .onChange(of: isOpen) { newValue in
                        whiskey.isOpen = newValue
                        try? viewContext.save()
                    }
            }
            .navigationTitle("Edit Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// Journal Entry Row Component
struct JournalEntryRow: View {
    let entry: JournalEntry
    @State private var showingDetail = false
    
    var body: some View {
        Button(action: {
            showingDetail = true
        }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.date ?? Date(), style: .date)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if entry.overallRating > 0 {
                        Text("\(entry.overallRating, specifier: "%.1f")")
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                }
                
                if let review = entry.review, !review.isEmpty {
                    Text(review)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDetail) {
            NavigationView {
                JournalEntryDetailView(entry: entry)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showingDetail = false
                            }
                        }
                    }
            }
        }
    }
}

// Web Content Row Component
struct WebContentRow: View {
    let content: WebContent
    let whiskey: Whiskey
    @State private var showingDetail = false
    @State private var showingEditSheet = false
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.title ?? "Untitled Review")
                .font(.subheadline)
                .foregroundColor(.primary)
            
            if let sourceURL = content.sourceURL, let url = URL(string: sourceURL) {
                Text(url.host ?? sourceURL)
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            
            if let date = content.date {
                Text("Saved on \(date, formatter: itemFormatter)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            showingDetail = true
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteWebContent()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(.red)
            
            Button {
                showingEditSheet = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .sheet(isPresented: $showingDetail) {
            DirectWebContentView(contentIDString: content.id?.uuidString ?? "", 
                                 whiskeyIDString: content.whiskey?.id?.uuidString ?? "")
        }
        .sheet(isPresented: $showingEditSheet) {
            DirectWebContentView(contentIDString: content.id?.uuidString ?? "", 
                                 whiskeyIDString: whiskey.id?.uuidString ?? "",
                                 startInEditMode: true)
        }
    }
    
    private func deleteWebContent() {
        withAnimation {
            viewContext.delete(content)
            
            do {
                try viewContext.save()
                HapticManager.shared.successFeedback()
            } catch {
                print("Error deleting web content: \(error)")
                HapticManager.shared.errorFeedback()
            }
        }
    }
}

// Add this new view after the existing views
struct AddReplacementBottleView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let originalWhiskey: Whiskey
    
    @State private var name: String
    @State private var type: String
    @State private var age: String
    @State private var proof: String
    @State private var finish: String
    @State private var distillery: String
    @State private var numberOfBottles: String
    @State private var price: String
    @State private var isBiB: Bool
    @State private var isSiB: Bool
    @State private var isStorePick: Bool
    @State private var storePickName: String
    @State private var isOpen: Bool
    @State private var notes: String
    @State private var isCaskStrength: Bool
    @State private var batchNumber: String = ""
    @State private var purchaseDate: Date = Date()
    
    init(originalWhiskey: Whiskey) {
        self.originalWhiskey = originalWhiskey
        
        // Initialize state variables with original whiskey properties
        _name = State(initialValue: originalWhiskey.name ?? "")
        _type = State(initialValue: originalWhiskey.type ?? "")
        _age = State(initialValue: originalWhiskey.age ?? "")
        _proof = State(initialValue: String(originalWhiskey.proof))
        _finish = State(initialValue: originalWhiskey.finish ?? "")
        _distillery = State(initialValue: originalWhiskey.distillery ?? "")
        _numberOfBottles = State(initialValue: "1") // Default to 1 for replacement
        _price = State(initialValue: String(originalWhiskey.price))
        _isBiB = State(initialValue: originalWhiskey.isBiB)
        _isSiB = State(initialValue: originalWhiskey.isSiB)
        _isStorePick = State(initialValue: originalWhiskey.isStorePick)
        _storePickName = State(initialValue: originalWhiskey.storePickName ?? "")
        _isOpen = State(initialValue: false) // Default to unopened
        _notes = State(initialValue: "")
        _isCaskStrength = State(initialValue: originalWhiskey.isCaskStrength)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Info")) {
                    // Grayed out fields for basic info
                    Text(name)
                        .foregroundColor(.gray)
                    
                    if !type.isEmpty {
                        Text(type)
                            .foregroundColor(.gray)
                    }
                    
                    if !distillery.isEmpty {
                        Text(distillery)
                            .foregroundColor(.gray)
                    }
                    
                    if !age.isEmpty {
                        Text(age)
                            .foregroundColor(.gray)
                    }
                    
                    if Double(proof) ?? 0.0 > 0 {
                        Text(String(format: "%.1f", Double(proof) ?? 0.0) + " proof")
                            .foregroundColor(.gray)
                    }
                    
                    if !finish.isEmpty {
                        Text(finish)
                            .foregroundColor(.gray)
                    }
                }
                
                Section(header: Text("Purchase Info")) {
                    // Allow user to specify number of bottles
                    Stepper(value: Binding(
                        get: { Double(numberOfBottles) ?? 1.0 },
                        set: { numberOfBottles = String(Int($0)) }
                    ), in: 1...10) {
                        HStack {
                            Text("Number of Bottles:")
                            Spacer()
                            Text(numberOfBottles)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    HStack {
                        Text("Price per Bottle:")
                        Spacer()
                        HStack {
                            Text("$")
                            TextField("", text: $price)
                                .keyboardType(.decimalPad)
                    }
                    }
                    
                    DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
                }
            }
            .navigationTitle("Add Bottle")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveReplacementBottle()
                    }
                }
            }
        }
    }
    
    private func saveReplacementBottle() {
        withAnimation {
            // Instead of creating a new whiskey, we'll just add a new bottle instance to the original
            let priceValue = Double(price) ?? originalWhiskey.price
            
            // Get the next bottle number
            let fetchRequest: NSFetchRequest<BottleInstance> = BottleInstance.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "whiskey == %@", originalWhiskey)
            
            do {
                let existingBottles = try viewContext.fetch(fetchRequest)
                let bottleCount = Int16(numberOfBottles) ?? 1
                
                // Increment the original whiskey's numberOfBottles
                originalWhiskey.numberOfBottles += bottleCount
                originalWhiskey.modificationDate = Date()
                
                // Create bottle instances for the original whiskey
                for i in 0..<Int(bottleCount) {
                    let newBottle = BottleInstance(context: viewContext)
                    newBottle.id = UUID()
                    newBottle.dateAdded = purchaseDate
                    newBottle.price = priceValue
                    newBottle.whiskey = originalWhiskey
                    newBottle.isOpen = isOpen
                    newBottle.isDead = false
                    
                    // Next bottle number
                    let nextBottleNumber = existingBottles.isEmpty ? 
                        1 : existingBottles.map { $0.bottleNumber }.max()! + Int16(i) + 1
                    newBottle.bottleNumber = nextBottleNumber
                }
                
                // Create a bottle addition record for tracking
                let addition = BottleAddition(context: viewContext)
                addition.id = UUID()
                addition.whiskey = originalWhiskey
                addition.amount = Double(bottleCount)
                addition.date = purchaseDate
                
                // Store notes in the addition
                var additionNotes = [String]()
                additionNotes.append("Price: $\(String(format: "%.2f", priceValue))")
                addition.notes = additionNotes.joined(separator: "\n")
            
                // Clear any replacement status
                if originalWhiskey.replacementStatus == "wantToReplace" {
                    originalWhiskey.replacementStatus = "none"
                }
                
                try viewContext.save()
                HapticManager.shared.successFeedback()
                dismiss()
            } catch {
                HapticManager.shared.errorFeedback()
                print("Error saving replacement bottle: \(error)")
            }
        }
    }
}

// Rename and modify the section to handle all bottle additions
struct BottleHistorySection: View {
    let whiskey: Whiskey
    @State private var isExpanded = false
    @State private var refreshTrigger = UUID() // Add refresh trigger
    
    private var currencyFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter
    }
    
    // Get all bottle instances sorted by date
    private var bottleInstances: [BottleInstance] {
        let fetchRequest: NSFetchRequest<BottleInstance> = BottleInstance.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "whiskey == %@", whiskey)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \BottleInstance.dateAdded, ascending: false)]
        
        do {
            return try whiskey.managedObjectContext?.fetch(fetchRequest) ?? []
        } catch {
            print("Error fetching bottle instances: \(error)")
            return []
        }
    }
    
    // Get all inventory changes (purchases and status changes)
    private var inventoryChanges: [(date: Date, type: String, details: String, price: Double?)] {
        var changes = [(date: Date, type: String, details: String, price: Double?)]()
        
        // Add bottle status changes only for bottles that weren't part of a purchase
        // (i.e., bottles that were added individually)
        for bottle in bottleInstances {
            // Skip if this bottle was part of a purchase
            if let dateAdded = bottle.dateAdded,
               !changes.contains(where: { $0.date == dateAdded && $0.type == "purchase" }) {
                changes.append((date: dateAdded, type: "added", details: "Bottle \(bottle.bottleNumber) added", price: bottle.price))
            }
            
            if let dateOpened = bottle.dateOpened {
                changes.append((date: dateOpened, type: "opened", details: "Bottle \(bottle.bottleNumber) opened", price: nil))
            }
            if let dateFinished = bottle.dateFinished {
                changes.append((date: dateFinished, type: "finished", details: "Bottle \(bottle.bottleNumber) finished", price: nil))
            }
        }
        
        // Sort by date, most recent first
        return changes.sorted { $0.date > $1.date }
    }
    
    private var totalBottles: Int {
        return Int(whiskey.numberOfBottles)
    }
    
    private var totalSpent: Double {
        var total = 0.0
        // Sum up all bottle prices
        for bottle in bottleInstances {
            total += bottle.price
        }
        return total
    }
    
    private var averagePricePerBottle: Double {
        guard totalBottles > 0 else { return 0 }
        return totalSpent / Double(totalBottles)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with expand/collapse button
            Button(action: {
                withAnimation(.spring(response: 0.3)) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Text("INVENTORY HISTORY")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                let changes = inventoryChanges
                
                // Current status
                VStack(alignment: .leading, spacing: 8) {
                    Text("Current Status")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Active Bottles: \(bottleInstances.filter { !$0.isDead }.count)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text("Dead Bottles: \(bottleInstances.filter { $0.isDead }.count)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Total Investment: \(currencyFormatter.string(from: NSNumber(value: totalSpent)) ?? "$0")")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Spacer()
                            
                            Text("Avg. Price: \(currencyFormatter.string(from: NSNumber(value: averagePricePerBottle)) ?? "$0")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .padding(.bottom, 8)
                
                // History section
                if !changes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("History")
                            .font(.headline)
                            .padding(.bottom, 4)
                        
                        ForEach(Array(changes.enumerated()), id: \.element.date) { index, change in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(change.details)
                                        .font(.subheadline)
                                    
                                    Spacer()
                                    
                                    Text(change.date, formatter: itemFormatter)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                if let price = change.price {
                                    Text("Price: \(currencyFormatter.string(from: NSNumber(value: price)) ?? "$0")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .id(refreshTrigger) // Add refresh trigger
        .onAppear {
            // Force refresh of Core Data context
            if let context = whiskey.managedObjectContext {
                context.refresh(whiskey, mergeChanges: true)
                for bottle in bottleInstances {
                    context.refresh(bottle, mergeChanges: true)
                }
            }
        }
    }
}

// Add Purchase View
struct AddPurchaseView: View {
    let whiskey: Whiskey
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var numberOfBottles: String = "1"
    @State private var price: String
    @State private var purchaseDate: Date = Date()
    
    init(whiskey: Whiskey) {
        self.whiskey = whiskey
        // Initialize price with the whiskey's current price
        _price = State(initialValue: String(format: "%.2f", whiskey.price))
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Purchase Details")) {
                    HStack {
                        Text("Whiskey:")
                        Spacer()
                        Text(whiskey.name ?? "Unknown")
                            .foregroundColor(.secondary)
                    }
                
                    Stepper(value: Binding(
                        get: { Double(numberOfBottles) ?? 1.0 },
                        set: { numberOfBottles = String(Int($0)) }
                    ), in: 1...10) {
                        HStack {
                            Text("Number of Bottles:")
                            Spacer()
                            Text(numberOfBottles)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    HStack {
                        Text("$")
                        TextField("Price per Bottle", text: $price)
                            .keyboardType(.decimalPad)
                    }
                    .foregroundColor(.blue) // Highlight this field to draw attention
                    
                    DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
                }
            }
            .navigationTitle("Add Bottle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        savePurchase()
                    }
                    .disabled(numberOfBottles.isEmpty || Int(numberOfBottles) == 0)
                }
            }
        }
    }
    
    private func savePurchase() {
        withAnimation {
            // Create new bottle addition record
            let addition = BottleAddition(context: viewContext)
            addition.id = UUID()
            addition.whiskey = whiskey
            addition.amount = Double(numberOfBottles) ?? 1.0
            addition.date = purchaseDate
            
            // Get price value if available
            let priceValue = !price.isEmpty ? (Double(price) ?? whiskey.price) : whiskey.price
            
            // Store price, store, and batch info in notes
            var notes = [String]()
            if !price.isEmpty, let priceValue = Double(price) {
                notes.append("Price: $\(String(format: "%.2f", priceValue))")
            }
            addition.notes = notes.joined(separator: "\n")
            
            // Update the whiskey's active bottle count
            whiskey.numberOfBottles += Int16(addition.amount)
            whiskey.modificationDate = Date()
            
            // Create new bottle instances
            let numBottlesToAdd = Int(addition.amount)
            
            // Fetch existing bottle instances to calculate the next bottle number
            let fetchRequest: NSFetchRequest<BottleInstance> = BottleInstance.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "whiskey == %@", whiskey)
            
            do {
                let existingBottles = try viewContext.fetch(fetchRequest)
                let activeBottles = existingBottles.filter { !$0.isDead }.sorted { $0.bottleNumber < $1.bottleNumber }
                
                // Get the next bottle number
                let nextBottleNumber = activeBottles.isEmpty ? 1 : Int16(activeBottles.count + 1)
                
                // Create the new bottle instances
                for i in 0..<numBottlesToAdd {
                    let newBottle = BottleInstance(context: viewContext)
                    newBottle.id = UUID()
                    newBottle.dateAdded = purchaseDate
                    newBottle.price = priceValue
                    newBottle.whiskey = whiskey
                    newBottle.isOpen = false
                    newBottle.isDead = false
                    newBottle.bottleNumber = nextBottleNumber + Int16(i)
                    
                    print("DEBUG: Created new bottle with number \(newBottle.bottleNumber) and price \(newBottle.price)")
                }
                
                // Clear any shopping list status
                if whiskey.replacementStatus == "wantToReplace" {
                    whiskey.replacementStatus = "none"
                }
                
                try viewContext.save()
                
                // Renumber bottles to ensure consecutive numbering within each group
                whiskey.renumberBottles()
                
                HapticManager.shared.successFeedback()
                dismiss()
            } catch {
                HapticManager.shared.errorFeedback()
                print("Error saving purchase: \(error)")
            }
        }
    }
}

// Add AddBottleCardView struct for consistent sizing with BottleCardView
struct AddBottleCardView: View {
    var action: () -> Void
    @State private var dummyToggle1 = false
    @State private var dummyToggle2 = false
    
    var body: some View {
        Button(action: action) {
            // Exact copy of BottleCardView structure
            VStack(alignment: .leading, spacing: 8) {
                // Bottle name and price - exact copy
                HStack {
                    Text("Add New Bottle")
                        .font(.headline)
                    Spacer()
                    Text("$0.00")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Toggles - use actual toggles for identical sizing
                VStack(spacing: 12) {
                    Toggle(isOn: .constant(false)) {
                        Text("Click to add")
                            .font(.subheadline)
                    }
                    .disabled(true)
                    .opacity(0.7)
                    
                    Toggle(isOn: .constant(false)) {
                        HStack {
                            Text("Add Bottle")
                                .font(.subheadline)
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                                .font(.title3)
                        }
                    }
                    .disabled(true)
                    .opacity(0.7)
                }
                
                Divider()
                
                // Dates - use same VStack structure
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add a new bottle of this whiskey")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .shadow(color: Color(.systemGray4), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 280)
    }
}

// Add a mock BottleInstance for use in the AddBottleButton
class MockBottle: NSObject, ObservableObject {
    var bottleNumber: Int16 = 0
    var price: Double = 0.0
    var isOpen: Bool = false
    var isDead: Bool = false
    var dateAdded: Date? = nil
    var dateOpened: Date? = nil
    var dateFinished: Date? = nil
    var whiskey: Whiskey? = nil
}

// Add AddBottleButton that uses the same BottleCardView for perfect sizing
struct AddBottleButton: View {
    var action: () -> Void
    @StateObject private var mockBottle = MockBottle()
    @Environment(\.managedObjectContext) private var viewContext
    
    // Create a representation that looks like a bottle card but is a button
    var body: some View {
        Button(action: action) {
            ZStack {
                // This creates the exact same layout as a regular bottle card
                VStack(alignment: .leading, spacing: 8) {
                    // Header
                    HStack {
                        Text("Add New Bottle")
                            .font(.headline)
                        Spacer()
                        Text("$0.00")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    // Middle section with same height as toggles
                    VStack(spacing: 12) {
                        HStack {
                            Text("Click to add")
                                .font(.subheadline)
                            Spacer()
                            Image(systemName: "toggleicon")
                                .font(.body)
                                .opacity(0)
                        }
                        
                        HStack {
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.blue)
                            Spacer()
                        }
                    }
                    
                    Divider()
                    
                    // Bottom section with date layout
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add a new bottle")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .shadow(color: Color(.systemGray4), radius: 2, x: 0, y: 1)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 280)
    }
}

// Add a fixed size container view for consistency
struct BottleContainer<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .frame(width: 280, height: 240) // Fixed exact size for all bottle cards
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .shadow(color: Color(.systemGray4), radius: 2, x: 0, y: 1)
    }
}

// Simple add bottle button with fixed size
struct AddBottleButtonFixed: View {
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Add New Bottle")
                        .font(.headline)
                    Spacer()
                }
                
                Divider()
                
                Spacer()
                
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.blue)
                        
                        Text("Add Bottle")
                            .font(.subheadline)
                    }
                    Spacer()
                }
                
                Spacer()
                
                Divider()
                
                HStack {
                    Text("Click to add a new bottle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .padding()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Add BottleCardView definition
struct BottleCardView: View {
    let bottle: BottleInstance
    var onRenumbered: (() -> Void)? = nil
    @StateObject private var alertManager = AlertManager.shared
    @StateObject private var viewStateUpdater = ViewStateUpdater()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Bottle name and price
            HStack {
                Text("\(bottle.whiskey?.name ?? "Unknown") \(bottle.bottleNumber)")
                    .font(.headline)
                Spacer()
                Text("$\(String(format: "%.2f", bottle.price))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Status toggles
            VStack(spacing: 12) {
                if !bottle.isDead {
                    Toggle(isOn: Binding(
                        get: { bottle.isOpen },
                        set: { newValue in
                            bottle.isOpen = newValue
                            if newValue {
                                bottle.dateOpened = Date()
                            }
                            try? bottle.managedObjectContext?.save()
                            if let whiskey = bottle.whiskey {
                                NotificationCenter.default.post(name: NSNotification.Name("WhiskeyUpdated"), object: whiskey)
                            }
                        }
                    )) {
                        Text("Open?")
                            .font(.subheadline)
                    }
                }
                Toggle(isOn: Binding(
                    get: { bottle.isDead },
                    set: { newValue in
                        if let context = bottle.managedObjectContext,
                           let whiskey = bottle.whiskey {
                            bottle.isDead = newValue
                            if newValue {
                                bottle.dateFinished = Date()
                                if let whiskeyID = whiskey.id {
                                    alertManager.showBuyNewBottleAlert(for: whiskeyID)
                                }
                            } else {
                                bottle.dateFinished = nil
                            }
                            if let bottleInstances = whiskey.bottleInstances as? Set<BottleInstance> {
                                let deadBottles = bottleInstances.filter { $0.isDead }
                                whiskey.isFinished = Int16(deadBottles.count)
                                print("DEBUG: Updated bottle status - isDead: \(newValue), deadBottleCount: \(whiskey.deadBottleCount), isFinished: \(whiskey.isFinished)")
                            }
                            try? context.save()
                            viewStateUpdater.objectWillChange.send()
                            NotificationCenter.default.post(name: NSNotification.Name("WhiskeyUpdated"), object: whiskey)
                            whiskey.renumberBottles()
                            onRenumbered?() // Trigger parent refresh
                        }
                    }
                )) {
                    Text("Dead Bottle?")
                        .font(.subheadline)
                }
            }
            
            Divider()
            
            // Dates
            VStack(alignment: .leading, spacing: 4) {
                if let dateAdded = bottle.dateAdded {
                    Text("Added: \(dateAdded, formatter: itemFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let dateOpened = bottle.dateOpened {
                    Text("Opened: \(dateOpened, formatter: itemFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let dateFinished = bottle.dateFinished {
                    Text("Finished: \(dateFinished, formatter: itemFormatter)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: Color(.systemGray4), radius: 2, x: 0, y: 1)
    }
}
