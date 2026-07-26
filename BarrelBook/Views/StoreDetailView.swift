import SwiftUI
import CoreData

struct StoreDetailView: View {
    @ObservedObject var store: Store
    @Environment(\.managedObjectContext) private var viewContext
    
    var body: some View {
        List {
            Section {
                Text(store.name ?? "Unknown Store")
                    .font(.title)
                if let address = store.address {
                    Text(address)
                        .foregroundColor(.secondary)
                }
            }
            
            Section {
                Button(action: toggleFavorite) {
                    HStack {
                        Image(systemName: store.isFavorite ? "star.fill" : "star")
                            .foregroundColor(.yellow)
                        Text(store.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                    }
                }
            }
            
            // ... existing code ...
        }
        .navigationTitle("Store Details")
    }
    
    private func toggleFavorite() {
        withAnimation {
            if !store.isFavorite {
                // Adding to favorites: ensure no other favorite has same name/address
                let name = (store.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let address = (store.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let request = Store.fetchRequest()
                request.predicate = NSPredicate(format: "isFavorite == YES AND name == %@ AND address == %@", name, address)
                request.fetchLimit = 2
                do {
                    let existing = try viewContext.fetch(request)
                    let otherExists = existing.contains { $0.objectID != store.objectID }
                    if otherExists {
                        return // Already a favorite with this name/address
                    }
                } catch {
                    return
                }
            }
            store.isFavorite.toggle()
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

#Preview {
    NavigationView {
        StoreDetailView(store: Store(context: PersistenceController.preview.container.viewContext))
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
} 