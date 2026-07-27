import Foundation

// Global TabSelection enum for consistent navigation across the app
enum TabSelection: String, Hashable, CaseIterable, Identifiable {
    case home
    case collection
    case wishlist
    case journal
    case statistics
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .home: return "Home"
        case .collection: return "Collection"
        case .wishlist: return "Wishlist"
        case .journal: return "Tastings"
        case .statistics: return "Statistics"
        }
    }
    
    var systemImage: String {
        switch self {
        case .home: return "house"
        case .collection: return "square.grid.2x2"
        case .wishlist: return "heart.fill"
        case .journal: return "book"
        case .statistics: return "chart.bar.fill"
        }
    }
}
