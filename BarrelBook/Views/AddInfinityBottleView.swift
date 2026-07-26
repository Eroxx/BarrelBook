import SwiftUI
import CoreData

struct AddInfinityBottleView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) var dismiss
    @AppStorage("hasSeenAddInfinityBottleTutorial") private var hasSeenAddInfinityBottleTutorial = false
    @State private var showingTutorialOverlay = false
    
    @State private var name = ""
    @State private var notes = ""
    @State private var typeCategory = "Bourbon"
    
    private let bottleTypes = ["Bourbon", "Rye", "Scotch", "Irish", "Japanese", "Canadian", "Other"]
    
    var body: some View {
        ZStack {
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
            if showingTutorialOverlay {
                AddInfinityBottleTutorialOverlay(onDismiss: {
                    hasSeenAddInfinityBottleTutorial = true
                    showingTutorialOverlay = false
                    HapticManager.shared.lightImpact()
                })
            }
        }
        .onAppear {
            if !hasSeenAddInfinityBottleTutorial {
                showingTutorialOverlay = true
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

// MARK: - Add Infinity Bottle tutorial (first time after tapping +)

private struct AddInfinityBottleTutorialOverlay: View {
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
                                Image(systemName: "wineglass.fill")
                        .font(.title2)
                        .foregroundColor(ColorManager.primaryBrandColor)
                    Text("Create your bottle")
                        .font(.headline)
                }
                VStack(alignment: .leading, spacing: 10) {
                    addInfinityTutorialRow(icon: "1.circle.fill", text: "Give your infinity bottle a **name** and pick a **type** (e.g. Bourbon, Rye). Tap **Save** when you’re done.")
                    addInfinityTutorialRow(icon: "2.circle.fill", text: "After saving, open the bottle from your list and tap **Add whiskey**. Choose a whiskey from your collection and enter the amount — proof and volume are calculated for you.")
                    addInfinityTutorialRow(icon: "3.circle.fill", text: "You can keep adding whiskeys over time. The app tracks every addition so you always know what’s in the blend.")
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
    
    private func addInfinityTutorialRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(ColorManager.primaryBrandColor)
                .font(.subheadline)
            Text(LocalizedStringKey(text))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}