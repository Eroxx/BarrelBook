import SwiftUI

// Global navigation state manager
class NavigationStateManager: ObservableObject {
    static let shared = NavigationStateManager()
    
    @Published var shouldMaintainNavigation = false
    @Published var selectedWhiskeyID: UUID? = nil
    @Published var activeTab: TabSelection? = nil
    
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
} 