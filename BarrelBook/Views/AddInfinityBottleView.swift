import SwiftUI
import CoreData

struct AddInfinityBottleView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) var dismiss
    
    @State private var name = ""
    @State private var notes = ""
    @State private var typeCategory = "Bourbon"
    
    private let bottleTypes = ["Bourbon", "Rye", "Scotch", "Irish", "Japanese", "Canadian", "Other"]
    
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
                
                Section(header: Text("Notes (Optional)")) {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section {
                    Text("Add whiskeys to your infinity bottle after creating it. Volume and proof will be calculated automatically based on the whiskeys you add.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("New Infinity Bottle")
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
                        saveInfinityBottle()
                        HapticManager.shared.successFeedback()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func saveInfinityBottle() {
        // Verify we have a valid Core Data context
        if viewContext.persistentStoreCoordinator?.persistentStores.isEmpty ?? true {
            print("⚠️ ERROR: Cannot save infinity bottle - no persistent stores available!")
            
            // Show an error alert
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                let alert = UIAlertController(
                    title: "Error Saving",
                    message: "There was a problem saving your infinity bottle. Please try restarting the app.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                rootVC.present(alert, animated: true)
            }
            return
        }
        
        let newBottle = InfinityBottle(context: viewContext)
        newBottle.id = UUID()
        newBottle.name = name
        newBottle.typeCategory = typeCategory
        newBottle.notes = notes.isEmpty ? nil : notes
        newBottle.creationDate = Date()
        newBottle.modificationDate = Date()
        
        // Set default values for properties still in Core Data model but not used in UI
        newBottle.maxVolume = 750.0  // Default to standard 750ml bottle size
        newBottle.currentVolume = 0.0  // Start with empty bottle
        
        do {
            print("Saving infinity bottle: \(name)")
            try viewContext.save()
            print("✅ Successfully saved infinity bottle: \(name)")
            HapticManager.shared.successFeedback()
            dismiss()
        } catch {
            // Handle the error
            print("❌ Error saving infinity bottle: \(error)")
            
            // Show an error alert
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                let alert = UIAlertController(
                    title: "Error Saving",
                    message: "There was a problem saving your infinity bottle: \(error.localizedDescription)",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                rootVC.present(alert, animated: true)
            }
        }
    }
} 