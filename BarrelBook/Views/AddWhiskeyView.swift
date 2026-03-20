import SwiftUI
import CoreData

struct AddWhiskeyView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @State private var showingPaywall = false
    @AppStorage("hasSeenAddWhiskeyTutorial") private var hasSeenAddWhiskeyTutorial = false
    @State private var showingAddWhiskeyTutorialOverlay = false

    // MARK: Bottle Scanner — remove this block + BottleScannerView.swift + LabelParser.swift to disable feature
    @State private var showingBottleScanner = false
    @State private var scannerFoundNothing = false
    
    @State private var name = ""
    @State private var type = ""
    @State private var age = ""
    @State private var proof = ""
    @State private var finish = ""
    @State private var distillery = ""
    @State private var activeBottles = 1
    @State private var openBottles = 0
    @State private var price = ""
    @State private var deadBottles = 0
    @State private var isBiB = false
    @State private var isSiB = false
    @State private var isStorePick = false
    @State private var storePickName = ""
    @State private var isOpen = false
    @State private var notes = ""
    
    // Fetch current whiskeys to check limits
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Whiskey.name, ascending: true)],
        predicate: NSPredicate(format: "status == %@ OR status == nil", "owned"),
        animation: .default)
    private var currentWhiskeys: FetchedResults<Whiskey>
    
    var body: some View {
        ZStack {
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
                        Text("Number of Active Bottles:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Stepper(value: Binding(
                            get: { activeBottles },
                            set: { newValue in
                                activeBottles = newValue
                                // If reducing active bottles, ensure open bottles don't exceed active
                                if openBottles > activeBottles {
                                    openBottles = activeBottles
                                }
                                HapticManager.shared.lightImpact()
                            }
                        ), in: 1...999) {
                            Text("\(activeBottles)")
                                .frame(minWidth: 30)
                                .multilineTextAlignment(.center)
                        }
                    }
                    
                    HStack {
                        Text("Number of Dead Bottles:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Stepper(value: Binding(
                            get: { deadBottles },
                            set: { newValue in
                                deadBottles = newValue
                                HapticManager.shared.lightImpact()
                            }
                        ), in: 0...999) {
                            Text("\(deadBottles)")
                                .frame(minWidth: 30)
                                .multilineTextAlignment(.center)
                        }
                    }
                    
                    if activeBottles > 1 {
                        HStack {
                            Text("Number of Open Bottles:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Stepper(value: Binding(
                                get: { openBottles },
                                set: { newValue in
                                    openBottles = newValue
                                    HapticManager.shared.lightImpact()
                                }
                            ), in: 0...activeBottles) {
                                Text("\(openBottles)")
                                    .frame(minWidth: 30)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    } else {
                        Toggle("Open", isOn: Binding(
                            get: { openBottles > 0 },
                            set: { newValue in
                                openBottles = newValue ? 1 : 0
                                HapticManager.shared.lightImpact()
                            }
                        ))
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
                }
            }
            .navigationTitle("Add Whiskey")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        HapticManager.shared.lightImpact()
                        dismiss()
                    }
                }
                // MARK: Bottle Scanner toolbar button
                ToolbarItem(placement: .navigationBarTrailing) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showingBottleScanner = true } label: {
                            Image(systemName: "camera")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        HapticManager.shared.mediumImpact()
                        if subscriptionManager.canAddWhiskey(currentCount: currentWhiskeys.count) {
                            saveWhiskey()
                        } else {
                            showingPaywall = true
                        }
                    }
                    .disabled(name.isEmpty)
                }
            }
            // MARK: Bottle Scanner sheet + result alert
            .sheet(isPresented: $showingBottleScanner) {
                BottleScannerView(isPresented: $showingBottleScanner) { data in
                    applyScan(data)
                }
            }
            .alert("Couldn't Read Label", isPresented: $scannerFoundNothing) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The label wasn't clear enough to read. Try again with better lighting or hold the camera closer.")
            }
        }
            if showingAddWhiskeyTutorialOverlay {
                AddWhiskeyTutorialOverlay(onDismiss: {
                    hasSeenAddWhiskeyTutorial = true
                    showingAddWhiskeyTutorialOverlay = false
                    HapticManager.shared.lightImpact()
                })
            }
        }
        .onAppear {
            if !hasSeenAddWhiskeyTutorial {
                showingAddWhiskeyTutorialOverlay = true
            }
        }
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallView(isPresented: $showingPaywall)
        }
    }
    
    // MARK: Bottle Scanner — apply scanned data to form fields
    private func applyScan(_ data: ScannedBottleData) {
        if data.isEmpty {
            scannerFoundNothing = true
            return
        }
        if let v = data.name,       name.isEmpty       { name       = v }
        if let v = data.distillery, distillery.isEmpty { distillery = v }
        if let v = data.type,       type.isEmpty       { type       = v }
        if let v = data.proof,      proof.isEmpty      { proof      = v }
        if let v = data.age,        age.isEmpty        { age        = v }
    }

    // Helper function to normalize whiskey type and prevent duplicates
    private func normalizeType(_ inputType: String, existingTypes: [String]) -> String {
        return normalizeWhiskeyType(inputType, existingTypes: existingTypes)
    }
    
    // UTILITY: Function to clean up duplicate types in the database
    // This can be called manually to fix existing duplicates
    static func cleanupDuplicateTypes(in context: NSManagedObjectContext) {
        let fetchRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
        guard let allWhiskeys = try? context.fetch(fetchRequest) else { return }
        
        // Group whiskeys by normalized type name
        var typeGroups: [String: [Whiskey]] = [:]
        
        for whiskey in allWhiskeys {
            guard let type = whiskey.type, !type.isEmpty else { continue }
            let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            typeGroups[normalizedType, default: []].append(whiskey)
        }
        
        // For each group with multiple variations, standardize to the first occurrence
        for (_, whiskeys) in typeGroups {
            if whiskeys.count > 1 {
                // Find the most common capitalization
                let typeCounts = whiskeys.reduce(into: [String: Int]()) { counts, whiskey in
                    if let type = whiskey.type {
                        counts[type, default: 0] += 1
                    }
                }
                let mostCommonEntry = typeCounts.max(by: { $0.value < $1.value })
                let mostCommonType = mostCommonEntry?.key
                let fallbackType = whiskeys.first?.type ?? ""
                let standardType = mostCommonType ?? fallbackType
                
                // Update all whiskeys to use the standard type
                for whiskey in whiskeys {
                    whiskey.type = standardType
                }
            }
        }
        
        try? context.save()
        print("🧹 Cleaned up duplicate whiskey types")
    }
    
    private func saveWhiskey() {
        withAnimation {
            // Get all existing types from the context to prevent duplicates
            let fetchRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
            let allWhiskeys = (try? viewContext.fetch(fetchRequest)) ?? []
            let existingTypes = Array(Set(allWhiskeys.compactMap { $0.type }.filter { !$0.isEmpty }))
            
            let newWhiskey = Whiskey(context: viewContext)
            newWhiskey.id = UUID()
            newWhiskey.name = name
            newWhiskey.type = normalizeType(type, existingTypes: existingTypes)
            newWhiskey.age = age
            newWhiskey.proof = Double(proof) ?? 0.0
            newWhiskey.finish = finish
            newWhiskey.distillery = distillery
            newWhiskey.numberOfBottles = Int16(activeBottles)
            newWhiskey.price = Double(price) ?? 0.0
            newWhiskey.isFinished = Int16(deadBottles)
            newWhiskey.isOpen = openBottles > 0
            newWhiskey.isBiB = isBiB
            newWhiskey.isSiB = isSiB
            newWhiskey.isStorePick = isStorePick
            newWhiskey.storePickName = isStorePick ? storePickName : nil
            newWhiskey.notes = notes.isEmpty ? nil : notes
            newWhiskey.status = WhiskeyStatus.owned.rawValue
            
            // Set addedDate to track when the whiskey was first added
            newWhiskey.addedDate = Date()
            
            // Set modificationDate for proper dateAdded sorting
            newWhiskey.modificationDate = Date()
            
            do {
                // First save the whiskey to get a permanent ID and allow proper relationships
                try viewContext.save()
                
                // Create bottle instances for each active bottle - with safety checks
                if activeBottles > 0 {
                    for i in 1...activeBottles {
                        let bottle = BottleInstance(context: viewContext)
                        bottle.id = UUID()
                        bottle.whiskey = newWhiskey
                        bottle.bottleNumber = Int16(i)
                        bottle.dateAdded = Date()
                        bottle.price = newWhiskey.price  // Set individual bottle price
                        bottle.isOpen = i <= openBottles  // Mark appropriate number of bottles as open
                        bottle.isDead = false
                    }
                }
                
                // Create bottle instances for each dead bottle - with safety checks
                if deadBottles > 0 {
                    for i in 1...deadBottles {
                        let bottle = BottleInstance(context: viewContext)
                        bottle.id = UUID()
                        bottle.whiskey = newWhiskey
                        bottle.bottleNumber = Int16(activeBottles + i)  // Number dead bottles after active bottles
                        bottle.dateAdded = Date()
                        bottle.price = newWhiskey.price  // Set individual bottle price
                        bottle.isOpen = false
                        bottle.isDead = true
                        bottle.dateFinished = Date()
                    }
                }
                
                // Save the newly created bottle instances
                try viewContext.save()
                
                // Renumber bottles to ensure proper consecutive numbering within each group
                newWhiskey.renumberBottles()
                
                HapticManager.shared.successFeedback()
                
                // Post notification to refresh collection view
                NotificationCenter.default.post(name: NSNotification.Name("WhiskeyUpdated"), object: newWhiskey)
                
                dismiss()
            } catch {
                HapticManager.shared.errorFeedback()
                print("Error saving new whiskey: \(error)")
                // Don't crash, just print the error
                dismiss()
            }
        }
    }
}

// MARK: - Add Whiskey tutorial (first time adding a bottle)
private struct AddWhiskeyTutorialOverlay: View {
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
                                Text("Add a whiskey")
                                    .font(.headline)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                addWhiskeyTutorialRow(icon: "1.circle.fill", text: "**Name** is required. You must fill in at least the name for it to save to your collection. Everything else is optional.")
                                addWhiskeyTutorialRow(icon: "2.circle.fill", text: "**Basic Info**: Enter the distillery, type, proof, age, finish, and price. All are optional but are tracked and used for sorting and filtering.")
                                addWhiskeyTutorialRow(icon: "3.circle.fill", text: "**Inventory**: Set how many bottles you have of this whiskey (active and \"dead\"). If you have more than one, you can say how many are open. The app tracks open and closed bottles and you can sort and filter by them.")
                                addWhiskeyTutorialRow(icon: "4.circle.fill", text: "**Bottle Notes** and **Special Attributes** (BiB, Single Barrel, Store Pick): are saved like the other fields so you can sort and filter by each one.")
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
    
    private func addWhiskeyTutorialRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(ColorManager.primaryBrandColor)
                .font(.subheadline)
            Text(LocalizedStringKey(text))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// Helper function to normalize whiskey type and prevent duplicates - shared between views
private func normalizeWhiskeyType(_ inputType: String, existingTypes: [String]) -> String {
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

// View for converting wishlist item to collection with pre-filled data
struct WishlistToCollectionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let wishlistWhiskey: Whiskey
    
    @State private var name: String
    @State private var type: String
    @State private var age: String
    @State private var proof: String
    @State private var finish: String
    @State private var distillery: String
    @State private var activeBottles = 1
    @State private var openBottles = 0
    @State private var price: String
    @State private var deadBottles = 0
    @State private var isBiB: Bool
    @State private var isSiB: Bool
    @State private var isStorePick: Bool
    @State private var storePickName: String
    @State private var notes: String
    
    init(wishlistWhiskey: Whiskey) {
        self.wishlistWhiskey = wishlistWhiskey
        
        // Pre-fill all the data from wishlist
        _name = State(initialValue: wishlistWhiskey.name ?? "")
        _type = State(initialValue: wishlistWhiskey.type ?? "")
        _age = State(initialValue: wishlistWhiskey.age ?? "")
        _proof = State(initialValue: wishlistWhiskey.proof > 0 ? String(format: "%.1f", wishlistWhiskey.proof) : "")
        _finish = State(initialValue: wishlistWhiskey.finish ?? "")
        _distillery = State(initialValue: wishlistWhiskey.distillery ?? "")
        _price = State(initialValue: wishlistWhiskey.targetPrice > 0 ? String(format: "%.2f", wishlistWhiskey.targetPrice) : "")
        _isBiB = State(initialValue: wishlistWhiskey.isBiB)
        _isSiB = State(initialValue: wishlistWhiskey.isSiB)
        _isStorePick = State(initialValue: wishlistWhiskey.isStorePick)
        _storePickName = State(initialValue: wishlistWhiskey.storePickName ?? "")
        _notes = State(initialValue: wishlistWhiskey.notes ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Info (Pre-filled from Wishlist)")) {
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
                        Text("Number of Active Bottles:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Stepper(value: Binding(
                            get: { activeBottles },
                            set: { newValue in
                                activeBottles = newValue
                                if openBottles > activeBottles {
                                    openBottles = activeBottles
                                }
                                HapticManager.shared.lightImpact()
                            }
                        ), in: 1...999) {
                            Text("\(activeBottles)")
                                .frame(minWidth: 30)
                                .multilineTextAlignment(.center)
                        }
                    }
                    
                    HStack {
                        Text("Number of Dead Bottles:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Stepper(value: Binding(
                            get: { deadBottles },
                            set: { newValue in
                                deadBottles = newValue
                                HapticManager.shared.lightImpact()
                            }
                        ), in: 0...999) {
                            Text("\(deadBottles)")
                                .frame(minWidth: 30)
                                .multilineTextAlignment(.center)
                        }
                    }
                    
                    if activeBottles > 1 {
                        HStack {
                            Text("Number of Open Bottles:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Stepper(value: Binding(
                                get: { openBottles },
                                set: { newValue in
                                    openBottles = newValue
                                    HapticManager.shared.lightImpact()
                                }
                            ), in: 0...activeBottles) {
                                Text("\(openBottles)")
                                    .frame(minWidth: 30)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    } else {
                        Toggle("Open", isOn: Binding(
                            get: { openBottles > 0 },
                            set: { newValue in
                                openBottles = newValue ? 1 : 0
                                HapticManager.shared.lightImpact()
                            }
                        ))
                    }
                }
                
                Section(header: Text("Additional Options")) {
                    Toggle("Bottled in Bond", isOn: $isBiB)
                    Toggle("Single Barrel", isOn: $isSiB)
                    Toggle("Store Pick", isOn: $isStorePick)
                    if isStorePick {
                        TextField("Store Pick Name", text: $storePickName)
                    }
                }
                
                Section(header: Text("Notes")) {
                    TextField("Additional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        convertAndSave()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func convertAndSave() {
        withAnimation {
            // Get all existing types from the context to prevent duplicates
            let fetchRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
            let allWhiskeys = (try? viewContext.fetch(fetchRequest)) ?? []
            let existingTypes = Array(Set(allWhiskeys.compactMap { $0.type }.filter { !$0.isEmpty }))
            
            // Update the existing whiskey object
            wishlistWhiskey.name = name
            wishlistWhiskey.type = normalizeWhiskeyType(type, existingTypes: existingTypes)
            wishlistWhiskey.age = age
            wishlistWhiskey.proof = Double(proof) ?? 0.0
            wishlistWhiskey.finish = finish
            wishlistWhiskey.distillery = distillery
            wishlistWhiskey.price = Double(price) ?? 0.0
            wishlistWhiskey.isBiB = isBiB
            wishlistWhiskey.isSiB = isSiB
            wishlistWhiskey.isStorePick = isStorePick
            wishlistWhiskey.storePickName = isStorePick ? storePickName : nil
            wishlistWhiskey.notes = notes
            
            // Convert from wishlist to owned
            wishlistWhiskey.statusEnum = .owned
            wishlistWhiskey.numberOfBottles = Int16(activeBottles)
            wishlistWhiskey.isOpen = (activeBottles == 1 && openBottles > 0)
            wishlistWhiskey.isFinished = Int16(deadBottles)  // Explicitly set finished bottles count
            wishlistWhiskey.modificationDate = Date()
            
            do {
                // First save the whiskey to get a permanent ID and allow proper relationships
                try viewContext.save()
                
                // Check for existing bottle instances first to prevent duplicates
                let bottleFetchRequest: NSFetchRequest<BottleInstance> = BottleInstance.fetchRequest()
                bottleFetchRequest.predicate = NSPredicate(format: "whiskey == %@", wishlistWhiskey)
                let existingBottles = try viewContext.fetch(bottleFetchRequest)
                
                // Only create bottles if none exist already
                if existingBottles.isEmpty {
                    // Create bottle instances for each active bottle - matching AddWhiskeyView pattern
                    if activeBottles > 0 {
                        for i in 1...activeBottles {
                            let bottle = BottleInstance(context: viewContext)
                            bottle.id = UUID()
                            bottle.whiskey = wishlistWhiskey
                            bottle.bottleNumber = Int16(i)
                            bottle.dateAdded = Date()
                            bottle.price = Double(price) ?? 0.0  // Set individual bottle price
                            bottle.isOpen = i <= openBottles  // Mark appropriate number of bottles as open
                            bottle.isDead = false
                        }
                    }
                    
                    // Create bottle instances for each dead bottle - matching AddWhiskeyView pattern
                    if deadBottles > 0 {
                        for i in 1...deadBottles {
                            let bottle = BottleInstance(context: viewContext)
                            bottle.id = UUID()
                            bottle.whiskey = wishlistWhiskey
                            bottle.bottleNumber = Int16(activeBottles + i)  // Number dead bottles after active bottles
                            bottle.dateAdded = Date()
                            bottle.price = Double(price) ?? 0.0  // Set individual bottle price
                            bottle.isOpen = false
                            bottle.isDead = true
                            bottle.dateFinished = Date()
                        }
                    }
                } else {
                    print("DEBUG: Whiskey already has \(existingBottles.count) bottle instances, skipping creation")
                }
                
                // Save the newly created bottle instances
                try viewContext.save()
                
                // Renumber bottles to ensure proper consecutive numbering within each group
                wishlistWhiskey.renumberBottles()
                
                HapticManager.shared.successFeedback()
                
                // Post notification to refresh collection view (matching AddWhiskeyView pattern)
                NotificationCenter.default.post(name: NSNotification.Name("WhiskeyUpdated"), object: wishlistWhiskey)
                
                dismiss()
            } catch {
                HapticManager.shared.errorFeedback()
                print("Error converting wishlist to collection: \(error)")
            }
        }
    }
}

struct AddWhiskeyView_Previews: PreviewProvider {
    static var previews: some View {
        AddWhiskeyView()
    }
} 