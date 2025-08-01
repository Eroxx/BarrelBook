import SwiftUI
import MapKit
import CoreData
import CoreLocation

struct StoreSelectionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var selectedStore: Store?
    @State private var isSearching = false
    @State private var locationManager = CLLocationManager()
    @State private var userLocation: CLLocation?
    @State private var locationError: String?
    @State private var hasRequestedLocation = false
    @State private var hasInitialSearch = false
    @State private var locationDelegate: LocationManagerDelegate?
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Store.name, ascending: true)],
        predicate: NSPredicate(format: "isFavorite == YES"),
        animation: .default)
    private var favoriteStores: FetchedResults<Store>
    
    let currentlySelectedStores: Set<Store>
    let onStoreSelected: (Store?) -> Void
    
    private func getNearbyFavoriteStores() -> [Store] {
        guard let userLocation = userLocation else { return [] }
        
        return favoriteStores.filter { store in
            let storeLocation = CLLocation(latitude: store.latitude, longitude: store.longitude)
            let distance = userLocation.distance(from: storeLocation)
            return distance <= 32186.9 // 20 miles in meters
        }.sorted { $0.name ?? "" < $1.name ?? "" }
    }
    
    private func getFilteredSearchResults() -> [MKMapItem] {
        let nearbyFavorites = getNearbyFavoriteStores()
        return searchResults.filter { item in
            // Check if this search result matches any nearby favorite store
            !nearbyFavorites.contains { favorite in
                favorite.name == item.name && 
                favorite.latitude == item.placemark.coordinate.latitude &&
                favorite.longitude == item.placemark.coordinate.longitude
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Fixed search field at the top
                VStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("Search for liquor stores...", text: $searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onChange(of: searchText) { newValue in
                                if newValue.isEmpty {
                                    // If the search bar is cleared, always show nearby stores
                                    if userLocation != nil {
                                        searchNearbyStores()
                                    } else {
                                        locationError = "Location access is required to find nearby stores. Please enable location services in Settings."
                                    }
                                } else {
                                    performSearch()
                                }
                            }
                    }
                    .padding()
                }
                .background(Color(.systemBackground))
                
                // Scrollable content below
                if isSearching {
                    ProgressView()
                } else {
                    List {
                        // "No Store" option at the top
                        Section {
                                                    Button(action: {
                            onStoreSelected(nil)
                            dismiss()
                        }) {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                    VStack(alignment: .leading) {
                                        Text("No Store Selected")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        Text("I don't have a specific store in mind")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                        
                        // Show nearby favorite stores first
                        if !getNearbyFavoriteStores().isEmpty {
                            Section(header: Text("Nearby Favorite Stores")) {
                                ForEach(getNearbyFavoriteStores(), id: \.self) { store in
                                    Button(action: {
                                        onStoreSelected(store)
                                        dismiss()
                                    }) {
                                        HStack {
                                            Image(systemName: "star.fill")
                                                .foregroundColor(.yellow)
                                            VStack(alignment: .leading) {
                                                Text(store.name ?? "Unknown Store")
                                                    .font(.headline)
                                                if let address = store.address {
                                                    Text(address)
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                }
                                                if let location = userLocation {
                                                    let storeLocation = CLLocation(latitude: store.latitude, longitude: store.longitude)
                                                    let distance = location.distance(from: storeLocation)
                                                    // Convert meters to miles (1 meter = 0.000621371 miles)
                                                    let miles = distance * 0.000621371
                                                    Text(String(format: "%.1f miles away", miles))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            Spacer()
                                            // Show checkmark if already selected
                                            if currentlySelectedStores.contains(store) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.blue)
                                                    .font(.title2)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Show search results or nearby stores
                        let filteredResults = getFilteredSearchResults()
                        if !filteredResults.isEmpty {
                            Section(header: Text(searchText.isEmpty ? "Nearby Stores" : "Search Results")) {
                                ForEach(filteredResults, id: \.self) { item in
                                    Button(action: {
                                        createStore(from: item)
                                    }) {
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(item.name ?? "Unknown Store")
                                                    .font(.headline)
                                                if let address = item.placemark.title {
                                                    Text(address)
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                }
                                                if let location = userLocation,
                                                   let distance = calculateDistance(from: location, to: item.placemark.location) {
                                                    // Convert meters to miles (1 meter = 0.000621371 miles)
                                                    let miles = distance * 0.000621371
                                                    Text(String(format: "%.1f miles away", miles))
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                            Spacer()
                                            // Check if this search result matches any selected store
                                            if currentlySelectedStores.contains(where: { selectedStore in
                                                selectedStore.name == item.name &&
                                                selectedStore.latitude == item.placemark.coordinate.latitude &&
                                                selectedStore.longitude == item.placemark.coordinate.longitude
                                            }) {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.blue)
                                                    .font(.title2)
                                            }
                                        }
                                    }
                                }
                            }
                        } else if searchText.isEmpty && getNearbyFavoriteStores().isEmpty {
                            Section {
                                VStack {
                                    Image(systemName: "location.slash")
                                        .font(.largeTitle)
                                        .foregroundColor(.secondary)
                                    Text(locationError ?? "No stores found")
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding()
                                }
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("Select Store")
            .navigationBarItems(trailing: Button("Cancel") {
                dismiss()
            })
            .onAppear {
                print("StoreSelectionView appeared")
                setupLocationManager()
                // Perform initial search when view appears
                if userLocation != nil {
                    print("Performing initial search")
                    searchNearbyStores()
                }
            }
        }
    }
    
    private func performSearch() {
        print("Performing search with text: \(searchText)")
        if searchText.isEmpty {
            if userLocation != nil {
                print("Search bar empty, searching nearby stores")
                searchNearbyStores()
            } else {
                print("Search bar empty but no location available")
                locationError = "Location access is required to find nearby stores. Please enable location services in Settings."
            }
        } else {
            print("Searching with text: \(searchText)")
            searchStores()
        }
    }
    
    private func calculateDistance(from userLocation: CLLocation, to storeLocation: CLLocation?) -> CLLocationDistance? {
        guard let storeLocation = storeLocation else { return nil }
        return userLocation.distance(from: storeLocation)
    }
    
    private func setupLocationManager() {
        print("Setting up location manager")
        
        // Create a new location manager instance
        let newManager = CLLocationManager()
        let delegate = LocationManagerDelegate { [self] location in
            print("Got location update: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            userLocation = location
            // Perform search when we get the first location update
            if !hasInitialSearch {
                hasInitialSearch = true
                print("Performing initial search with location")
                DispatchQueue.main.async {
                    self.searchNearbyStores()
                }
            }
        }
        newManager.delegate = delegate
        locationDelegate = delegate
        
        newManager.desiredAccuracy = kCLLocationAccuracyBest
        newManager.distanceFilter = 10 // Update location every 10 meters
        newManager.pausesLocationUpdatesAutomatically = false
        
        print("Location manager settings:")
        print("- Desired accuracy: \(newManager.desiredAccuracy)")
        print("- Distance filter: \(newManager.distanceFilter)")
        print("- Pauses updates: \(newManager.pausesLocationUpdatesAutomatically)")
        
        switch newManager.authorizationStatus {
        case .notDetermined:
            print("Location status: not determined")
            if !hasRequestedLocation {
                hasRequestedLocation = true
                print("Requesting location authorization")
                newManager.requestWhenInUseAuthorization()
            }
        case .restricted, .denied:
            print("Location status: restricted/denied")
            locationError = "Location access is required to find nearby stores. Please enable location services in Settings."
        case .authorizedAlways, .authorizedWhenInUse:
            print("Location status: authorized")
            print("Starting location updates")
            newManager.startUpdatingLocation()
        @unknown default:
            print("Location status: unknown")
            locationError = "Unable to determine location authorization status."
        }
        
        locationManager = newManager
    }
    
    private func searchNearbyStores() {
        print("Starting searchNearbyStores")
        guard let location = userLocation else {
            print("No location available for search")
            locationError = "Location not available. Please wait for location services to update."
            return
        }
        
        print("Searching nearby stores at location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        isSearching = true
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "liquor store"
        request.resultTypes = .pointOfInterest
        
        // Set the region to search around the user's location
        let region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 15000, // 15km radius
            longitudinalMeters: 15000
        )
        request.region = region
        
        print("Search request details:")
        print("- Query: \(request.naturalLanguageQuery ?? "nil")")
        print("- Region center: \(region.center.latitude), \(region.center.longitude)")
        print("- Region span: \(region.span.latitudeDelta), \(region.span.longitudeDelta)")
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            if let error = error {
                print("Search error: \(error.localizedDescription)")
                self.locationError = "Error searching for stores: \(error.localizedDescription)"
                return
            }
            
            print("Search returned \(response?.mapItems.count ?? 0) results")
            
            // Sort results by distance
            if let items = response?.mapItems {
                self.searchResults = items.sorted { item1, item2 in
                    guard let loc1 = item1.placemark.location,
                          let loc2 = item2.placemark.location else {
                        return false
                    }
                    let dist1 = location.distance(from: loc1)
                    let dist2 = location.distance(from: loc2)
                    print("Comparing distances: \(dist1) vs \(dist2)")
                    return dist1 < dist2
                }
                print("Sorted \(self.searchResults.count) results by distance")
            } else {
                print("No items in response")
                self.searchResults = []
            }
            
            if self.searchResults.isEmpty {
                print("No stores found in search")
                self.locationError = "No liquor stores found nearby. Try searching for a specific location."
            } else {
                print("Found \(self.searchResults.count) stores")
                for store in self.searchResults {
                    print("- \(store.name ?? "Unknown"): \(store.placemark.title ?? "No address")")
                }
            }
            
            DispatchQueue.main.async {
                self.isSearching = false
            }
        }
    }
    
    private func searchStores() {
        guard !searchText.isEmpty else {
            searchNearbyStores()
            return
        }
        
        isSearching = true
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(searchText) liquor store"
        request.resultTypes = .pointOfInterest
        
        // If we have a user location, use it to bias the search
        if let location = userLocation {
            let region = MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 15000,
                longitudinalMeters: 15000
            )
            request.region = region
        }
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            isSearching = false
            
            if let error = error {
                print("Search error: \(error.localizedDescription)")
                locationError = "Error searching for stores: \(error.localizedDescription)"
                return
            }
            
            // Sort results by distance
            if let items = response?.mapItems, let location = userLocation {
                searchResults = items.sorted { item1, item2 in
                    guard let loc1 = item1.placemark.location,
                          let loc2 = item2.placemark.location else {
                        return false
                    }
                    return location.distance(from: loc1) < location.distance(from: loc2)
                }
            } else {
                searchResults = response?.mapItems ?? []
            }
            
            if searchResults.isEmpty {
                locationError = "No stores found matching your search."
            }
        }
    }
    
    private func createStore(from mapItem: MKMapItem) {
        let store = Store(context: viewContext)
        store.id = UUID()
        store.name = mapItem.name
        store.address = mapItem.placemark.title
        store.latitude = mapItem.placemark.coordinate.latitude
        store.longitude = mapItem.placemark.coordinate.longitude
        store.modificationDate = Date()
        
        do {
            try viewContext.save()
            onStoreSelected(store)
            dismiss()
        } catch {
            print("Error saving store: \(error)")
        }
    }
}

// Helper class to handle location updates
class LocationManagerDelegate: NSObject, CLLocationManagerDelegate {
    let onLocationUpdate: (CLLocation) -> Void
    
    init(onLocationUpdate: @escaping (CLLocation) -> Void) {
        self.onLocationUpdate = onLocationUpdate
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print("Location manager received \(locations.count) updates")
        if let location = locations.last {
            print("Location manager got update: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            print("Location accuracy: \(location.horizontalAccuracy) meters")
            onLocationUpdate(location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        print("Location authorization changed to: \(manager.authorizationStatus.rawValue)")
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("Starting location updates after authorization change")
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.startUpdatingLocation()
        case .denied, .restricted:
            print("Location access denied")
        case .notDetermined:
            print("Location access not determined")
        @unknown default:
            print("Unknown location authorization status")
        }
    }
}

#Preview {
    StoreSelectionView(currentlySelectedStores: Set<Store>()) { _ in }
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
} 