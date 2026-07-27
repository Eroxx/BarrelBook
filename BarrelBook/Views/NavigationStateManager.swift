import SwiftUI

// Global navigation state manager
class NavigationStateManager: ObservableObject {
    static let shared = NavigationStateManager()
    
    @Published var shouldMaintainNavigation = false
    @Published var selectedWhiskeyID: UUID? = nil
    @Published var activeTab: TabSelection? = nil
    
    /// Pending selections for iPad Home → split-detail deep links.
    @Published var pendingCollectionWhiskeyID: UUID? = nil
    @Published var pendingWishlistWhiskeyID: UUID? = nil
    @Published var pendingJournalEntryID: UUID? = nil
    @Published var pendingInfinityBottleID: UUID? = nil
    /// When opening an infinity bottle from Home, switch Collection to Infinity mode.
    @Published var preferInfinityCollectionMode = false
    
    private init() {}
    
    func maintainNavigation(for whiskeyID: UUID) {
        shouldMaintainNavigation = true
        selectedWhiskeyID = whiskeyID
    }
    
    func resetNavigation() {
        shouldMaintainNavigation = false
        selectedWhiskeyID = nil
    }
    
    func isNavigationMaintained(for whiskeyID: UUID) -> Bool {
        return shouldMaintainNavigation && selectedWhiskeyID == whiskeyID
    }
    
    func openOwnedWhiskey(_ whiskey: Whiskey) {
        guard let id = whiskey.id else { return }
        pendingCollectionWhiskeyID = id
        preferInfinityCollectionMode = false
        activeTab = .collection
    }
    
    func openWishlistWhiskey(_ whiskey: Whiskey) {
        guard let id = whiskey.id else { return }
        pendingWishlistWhiskeyID = id
        activeTab = .wishlist
    }
    
    func openJournalEntry(_ entry: JournalEntry) {
        guard let id = entry.id else { return }
        pendingJournalEntryID = id
        activeTab = .journal
    }
    
    func openInfinityBottle(_ bottle: InfinityBottle) {
        guard let id = bottle.id else { return }
        pendingInfinityBottleID = id
        preferInfinityCollectionMode = true
        activeTab = .collection
    }
}
