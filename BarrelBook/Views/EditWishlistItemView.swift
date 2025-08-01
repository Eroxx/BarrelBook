import SwiftUI

struct EditWishlistItemView: View {
    let whiskey: Whiskey
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String
    @State private var type: String
    @State private var age: String
    @State private var proof: String
    @State private var finish: String
    @State private var distillery: String
    @State private var targetPrice: String
    @State private var isBiB: Bool
    @State private var isSiB: Bool
    @State private var isStorePick: Bool
    @State private var storePickName: String
    @State private var selectedStores: Set<Store> = []
    @State private var notes: String
    @State private var priority: Double
    @State private var rarity: WhiskeyRarity
    @State private var showingStoreSelection = false
    
    init(whiskey: Whiskey) {
        self.whiskey = whiskey
        
        // Initialize state variables with whiskey properties
        _name = State(initialValue: whiskey.name ?? "")
        _type = State(initialValue: whiskey.type ?? "")
        _age = State(initialValue: whiskey.age ?? "")
        _proof = State(initialValue: whiskey.proof > 0 ? String(whiskey.proof) : "")
        _finish = State(initialValue: whiskey.finish ?? "")
        _distillery = State(initialValue: whiskey.distillery ?? "")
        _targetPrice = State(initialValue: whiskey.targetPrice > 0 ? String(whiskey.targetPrice) : "")
        _isBiB = State(initialValue: whiskey.isBiB)
        _isSiB = State(initialValue: whiskey.isSiB)
        _isStorePick = State(initialValue: whiskey.isStorePick)
        _storePickName = State(initialValue: whiskey.storePickName ?? "")
        _selectedStores = State(initialValue: Set(whiskey.stores as? [Store] ?? []))
        _notes = State(initialValue: whiskey.notes ?? "")
        _priority = State(initialValue: Double(whiskey.priority))
        _rarity = State(initialValue: WhiskeyRarity(rawValue: whiskey.rarity ?? "not_sure") ?? .notSure)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Info")) {
                    TextField("Name", text: $name)
                    TextField("Target Price", text: $targetPrice)
                        .keyboardType(.decimalPad)
                    Picker("Rarity", selection: $rarity) {
                        ForEach(WhiskeyRarity.allCases) { rarity in
                            Text(rarity.displayName).tag(rarity)
                        }
                    }
                    TextField("Type", text: $type)
                    TextField("Distillery", text: $distillery)
                    TextField("Age Statement", text: $age)
                    TextField("Proof", text: $proof)
                        .keyboardType(.decimalPad)
                    TextField("Finish", text: $finish)
                }
                
                Section(header: Text("Wishlist Details")) {
                    // Always show the main "Where to Find" button for first store or when no stores
                    if selectedStores.isEmpty {
                        Button(action: {
                            showingStoreSelection = true
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Where to Find")
                                        .foregroundColor(.primary)
                                    Text("Tap to add stores or leave blank")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                HStack {
                                    Image(systemName: "plus.circle")
                                    Text("Add Store")
                                }
                                .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    if !selectedStores.isEmpty {
                        // Show selected stores
                        ForEach(Array(selectedStores), id: \.id) { store in
                            HStack {
                                Image(systemName: "storefront")
                                    .foregroundColor(.blue)
                                Text(store.name ?? "Unknown Store")
                                    .foregroundColor(.primary)
                                Spacer()
                                Button(action: {
                                    selectedStores.remove(store)
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                        }
                        
                        // Add Another Store button
                        Button(action: {
                            showingStoreSelection = true
                        }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.blue)
                                Text("Add Another Store")
                                    .foregroundColor(.blue)
                                Spacer()
                            }
                        }
                        
                        // Clear all stores button
                        Button(action: {
                            selectedStores.removeAll()
                        }) {
                            HStack {
                                Image(systemName: "xmark.circle")
                                    .foregroundColor(.orange)
                                Text("Clear All Stores")
                                    .foregroundColor(.orange)
                                Spacer()
                            }
                        }
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $notes)
                            .frame(minHeight: 100)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("1")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Priority: \(Int(priority))")
                                .font(.system(size: 15, weight: .medium))
                            Spacer()
                            Text("5")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: $priority, in: 1...5, step: 1)
                    }
                }
            }
            .navigationTitle("Edit Wishlist Item")
            .sheet(isPresented: $showingStoreSelection) {
                StoreSelectionView(currentlySelectedStores: selectedStores) { store in
                    if let store = store {
                        selectedStores.insert(store)
                    }
                    // Note: In edit mode, "No Store Selected" doesn't clear existing stores
                    // User can manually remove stores using the minus buttons
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        HapticManager.shared.lightImpact()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        HapticManager.shared.mediumImpact()
                        saveWishlistItem()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                // Initialize selected stores from the whiskey's existing stores
                if let stores = whiskey.stores as? Set<Store> {
                    selectedStores = stores
                }
            }
        }
    }
    
    private func saveWishlistItem() {
        withAnimation {
            whiskey.name = name
            whiskey.type = type
            whiskey.age = age
            whiskey.proof = Double(proof) ?? 0.0
            whiskey.finish = finish
            whiskey.distillery = distillery
            whiskey.targetPrice = Double(targetPrice) ?? 0.0
            whiskey.priority = Int16(Int(priority))
            whiskey.notes = notes
            whiskey.isBiB = isBiB
            whiskey.isSiB = isSiB
            whiskey.isStorePick = isStorePick
            whiskey.storePickName = isStorePick ? storePickName : nil
            whiskey.rarity = rarity.rawValue
            
            // Update stores
            if let existingStores = whiskey.stores as? Set<Store> {
                for store in existingStores {
                    if !selectedStores.contains(store) {
                        whiskey.removeFromStores(store)
                    }
                }
            }
            for store in selectedStores {
                whiskey.addToStores(store)
            }
            
            // Update modification date
            whiskey.modificationDate = Date()
            
            do {
                try viewContext.save()
                
                // Force immediate UI update by posting notification with a slight delay
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("WishlistUpdated"), object: nil)
                }
                
                // Dismiss the view
                dismiss()
                
                HapticManager.shared.successFeedback()
            } catch {
                HapticManager.shared.errorFeedback()
                let nsError = error as NSError
                print("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

struct EditWishlistItemView_Previews: PreviewProvider {
    static var previews: some View {
        // This preview is placeholder only since we need a real Whiskey instance
        Text("Preview unavailable")
    }
} 