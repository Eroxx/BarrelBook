import Foundation

enum WhiskeyStatus: String, CaseIterable, Identifiable {
    case owned = "owned"
    case wishlist = "wishlist"
    case external = "external"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .owned:
            return "Owned"
        case .wishlist:
            return "Wishlist"
        case .external:
            return "External"
        }
    }
}

extension Whiskey {
    var statusEnum: WhiskeyStatus {
        get {
            guard let statusString = status, let status = WhiskeyStatus(rawValue: statusString) else {
                return .owned // Default to owned if status is nil or invalid
            }
            return status
        }
        set {
            status = newValue.rawValue
        }
    }
    
    // Convenience method to check if a whiskey is in the wishlist
    var isWishlist: Bool {
        return statusEnum == .wishlist
    }
    
    // Convenience method to check if a whiskey is owned
    var isOwned: Bool {
        return statusEnum == .owned
    }
    
    // Convenience method to check if a whiskey is external (not in collection)
    var isExternal: Bool {
        return statusEnum == .external
    }
} 