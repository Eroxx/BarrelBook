import SwiftUI

struct AddWhiskeyToWishlistView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var type = ""
    @State private var age = ""
    @State private var proof = ""
    @State private var finish = ""
    @State private var distillery = ""
    @State private var targetPrice = ""
    @State private var isBiB = false
    @State private var isSiB = false
    @State private var isStorePick = false
    @State private var storePickName = ""
    @State private var selectedStores: Set<Store> = []
    @State private var notes = ""
    @State private var priority: Double = 3
    @State private var rarity: WhiskeyRarity = .notSure
    @State private var showingStoreSelection = false
    @State private var bottleCount = 1
    @State private var showingAddAnother = false
    
    // Removed location manager delegate - no longer auto-detecting stores
    
    var body: some View {
        NavigationView {
            Form {
                // Removed auto-detected store section - users now manually select stores
                
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
            .navigationTitle("Add to Wishlist")
            .sheet(isPresented: $showingStoreSelection) {
                StoreSelectionView(currentlySelectedStores: selectedStores) { store in
                    if let store = store {
                        selectedStores.insert(store)
                    } else {
                        // User selected "No Store Selected"
                        selectedStores.removeAll()
                    }
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
            // Removed onAppear location setup - no longer auto-detecting stores
            .alert("Add Another Bottle?", isPresented: $showingAddAnother) {
                Button("No") {
                    dismiss()
                }
                Button("Yes") {
                    name = ""
                    type = ""
                    age = ""
                    proof = ""
                    finish = ""
                    distillery = ""
                    targetPrice = ""
                    notes = ""
                    bottleCount += 1
                }
            } message: {
                if let store = selectedStores.first {
                    Text("Would you like to add another bottle from \(store.name ?? "this store")?")
                } else {
                    Text("Would you like to add another bottle?")
                }
            }
        }
    }
    
    // Removed location manager and store detection functions - users now manually select stores
    
    private func saveWishlistItem() {
        print("Saving wishlist item")
        withAnimation {
            let newWhiskey = Whiskey(context: viewContext)
            newWhiskey.id = UUID()
            newWhiskey.name = name
            newWhiskey.type = type
            newWhiskey.age = age
            newWhiskey.proof = Double(proof) ?? 0.0
            newWhiskey.finish = finish
            newWhiskey.distillery = distillery
            newWhiskey.status = "wishlist"
            newWhiskey.targetPrice = Double(targetPrice) ?? 0.0
            newWhiskey.priority = Int16(Int(priority))
            newWhiskey.notes = notes
            newWhiskey.isBiB = isBiB
            newWhiskey.isSiB = isSiB
            newWhiskey.isStorePick = isStorePick
            newWhiskey.storePickName = isStorePick ? storePickName : nil
            newWhiskey.rarity = rarity.rawValue
            
            // Add selected stores
            for store in selectedStores {
                newWhiskey.addToStores(store)
            }
            
            newWhiskey.addedDate = Date()
            newWhiskey.modificationDate = Date()
            
            do {
                try viewContext.save()
                NotificationCenter.default.post(name: NSNotification.Name("WishlistUpdated"), object: nil)
                
                // Show "Add Another" alert if any store is selected
                print("Checking if any store is selected: \(!selectedStores.isEmpty)")
                if !selectedStores.isEmpty {
                    print("Showing add another alert")
                    showingAddAnother = true
                } else {
                    print("No store selected, dismissing")
                    dismiss()
                }
                
                HapticManager.shared.successFeedback()
            } catch {
                HapticManager.shared.errorFeedback()
                let nsError = error as NSError
                print("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

struct AddWhiskeyToWishlistView_Previews: PreviewProvider {
    static var previews: some View {
        AddWhiskeyToWishlistView()
    }
} 