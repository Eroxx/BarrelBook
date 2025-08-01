import SwiftUI
import CoreData
import CoreLocation

struct FavoriteStoresView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Store.name, ascending: true)],
        predicate: NSPredicate(format: "isFavorite == YES"),
        animation: .default)
    private var stores: FetchedResults<Store>
    
    var body: some View {
        List {
            ForEach(stores) { store in
                StoreRowView(store: store)
            }
            .onDelete(perform: deleteStores)
        }
        .navigationTitle("Favorite Stores")
    }
    
    private func deleteStores(offsets: IndexSet) {
        withAnimation {
            offsets.map { stores[$0] }.forEach { store in
                store.isFavorite = false
            }
            
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

struct StoreRowView: View {
    @ObservedObject var store: Store
    @Environment(\.managedObjectContext) private var viewContext
    @State private var locationManager = CLLocationManager()
    
    private var distance: String? {
        guard let userLocation = locationManager.location else { return nil }
        let storeLocation = CLLocation(latitude: store.latitude, longitude: store.longitude)
        let distance = userLocation.distance(from: storeLocation)
        // Convert meters to miles (1 meter = 0.000621371 miles)
        let miles = distance * 0.000621371
        return String(format: "%.1f miles away", miles)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(store.name ?? "Unknown Store")
                    .font(.headline)
                Spacer()
                if let distance = distance {
                    Text(distance)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if let address = store.address {
                Text(address)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    NavigationView {
        FavoriteStoresView()
            .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
    }
} 