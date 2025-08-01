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