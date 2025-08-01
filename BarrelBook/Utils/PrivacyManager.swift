import SwiftUI
import Combine

class PrivacyManager: ObservableObject {
    static let shared = PrivacyManager()
    
    @Published var hidePrices: Bool {
        didSet {
            FilterSettingsManager.saveHidePricesSetting(hidePrices)
        }
    }
    
    private init() {
        // Load from UserDefaults
        hidePrices = FilterSettingsManager.loadHidePricesSetting()
    }
    
    func toggleHidePrices() {
        hidePrices.toggle()
    }
    
    // Helper to format a price with privacy considerations
    func formatPrice(_ price: Double, formatter: NumberFormatter? = nil) -> String {
        if hidePrices {
            return "Hidden"
        } else {
            let priceFormatter: NumberFormatter
            if let f = formatter {
                priceFormatter = f
            } else {
                priceFormatter = NumberFormatter()
                priceFormatter.numberStyle = .currency
                priceFormatter.currencyCode = "USD"
            }
            
            return priceFormatter.string(from: NSNumber(value: price)) ?? "$0"
        }
    }
} 