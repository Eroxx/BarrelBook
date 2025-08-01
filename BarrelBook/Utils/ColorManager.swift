import SwiftUI

/// Manages color themes throughout the app with dark mode support
struct ColorManager {
    // MARK: - Whiskey Theme Colors
    
    /// The primary color used for branding and emphasis, a warm bourbon amber
    static var primaryBrandColor: Color {
        Color("PrimaryBrandColor")
    }
    
    // MARK: - Background Colors
    
    /// Primary background for views
    static var background: Color {
        Color(UIColor.systemBackground)
    }
    
    /// Secondary background for cards, cells, and section backgrounds
    static var secondaryBackground: Color {
        Color(UIColor.secondarySystemBackground)
    }
    
    // MARK: - Text Colors
    
    /// Primary text color
    static var primaryText: Color {
        Color.primary
    }
    
    /// Secondary text color for less important text
    static var secondaryText: Color {
        Color.secondary
    }
    
    // MARK: - Rating Colors
    
    /// Rating color for "Poor" ratings (1.0..<3.0)
    static var ratingPoor: Color {
        Color("RatingPoor")
    }
    
    /// Rating color for "Fair" ratings (3.0..<5.0)
    static var ratingFair: Color {
        Color("RatingFair")
    }
    
    /// Rating color for "Good" ratings (5.0..<7.0)
    static var ratingGood: Color {
        Color("RatingGood")
    }
    
    /// Rating color for "Great" ratings (7.0..<9.0)
    static var ratingGreat: Color {
        Color("RatingGreat")
    }
    
    /// Rating color for "Exceptional" ratings (9.0...10.0)
    static var ratingExceptional: Color {
        Color("RatingExceptional")
    }
    
    // MARK: - Chart Colors
    
    /// Returns a color for chart elements based on index
    static func chartColor(at index: Int) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .red, .purple, .yellow, .pink, .gray]
        return colors[index % colors.count]
    }
    
    // MARK: - Price Category Colors
    
    /// Color for low price range ($)
    static var priceLow: Color {
        Color("PriceLow")
    }
    
    /// Color for medium price range ($$)
    static var priceMedium: Color {
        Color("PriceMedium")
    }
    
    /// Color for high price range ($$$)
    static var priceHigh: Color {
        Color("PriceHigh")
    }
    
    /// Color for premium price range ($$$$)
    static var pricePremium: Color {
        Color("PricePremium")
    }
    
    // MARK: - Progress Colors
    
    /// Color for low progress (<30%)
    static var progressLow: Color {
        Color("ProgressLow")
    }
    
    /// Color for medium progress (30%-70%)
    static var progressMedium: Color {
        Color("ProgressMedium")
    }
    
    /// Color for high progress (>70%)
    static var progressHigh: Color {
        Color("ProgressHigh")
    }
} 