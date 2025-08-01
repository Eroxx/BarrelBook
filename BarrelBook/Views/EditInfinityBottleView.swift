import SwiftUI
import CoreData

struct EditInfinityBottleView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @ObservedObject var bottle: InfinityBottle
    
    @State private var name: String
    @State private var notes: String
    @State private var typeCategory: String
    
    private let bottleTypes = ["Bourbon", "Rye", "Scotch", "Irish", "Japanese", "Canadian", "Other"]
    
    // Initialize state with current values
    init(bottle: InfinityBottle) {
        self.bottle = bottle
        _name = State(initialValue: bottle.name ?? "")
        _notes = State(initialValue: bottle.notes ?? "")
        _typeCategory = State(initialValue: bottle.typeCategory ?? "Bourbon")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Bottle Information")) {
                    TextField("Name", text: $name)
                    
                    Picker("Type", selection: $typeCategory) {
                        ForEach(bottleTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                }
                
                Section(header: Text("Notes")) {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Infinity Bottle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                        HapticManager.shared.lightImpact()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveBottleChanges()
                        HapticManager.shared.successFeedback()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func saveBottleChanges() {
        bottle.name = name
        bottle.typeCategory = typeCategory
        bottle.notes = notes.isEmpty ? nil : notes
        bottle.modificationDate = Date()
        
        do {
            try viewContext.save()
            
            // Post notification to refresh the detail view
            NotificationCenter.default.post(
                name: Notification.Name("InfinityBottleUpdated"),
                object: bottle
            )
        } catch {
            print("Error saving infinity bottle changes: \(error)")
        }
    }
} 