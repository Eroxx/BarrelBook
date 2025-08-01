import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(DeveloperToolsSupport)
import DeveloperToolsSupport
#endif

#if SWIFT_PACKAGE
private let resourceBundle = Foundation.Bundle.module
#else
private class ResourceBundleClass {}
private let resourceBundle = Foundation.Bundle(for: ResourceBundleClass.self)
#endif

// MARK: - Color Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ColorResource {

    /// The "PriceHigh" asset catalog color resource.
    static let priceHigh = DeveloperToolsSupport.ColorResource(name: "PriceHigh", bundle: resourceBundle)

    /// The "PriceLow" asset catalog color resource.
    static let priceLow = DeveloperToolsSupport.ColorResource(name: "PriceLow", bundle: resourceBundle)

    /// The "PriceMedium" asset catalog color resource.
    static let priceMedium = DeveloperToolsSupport.ColorResource(name: "PriceMedium", bundle: resourceBundle)

    /// The "PricePremium" asset catalog color resource.
    static let pricePremium = DeveloperToolsSupport.ColorResource(name: "PricePremium", bundle: resourceBundle)

    /// The "PrimaryBrandColor" asset catalog color resource.
    static let primaryBrand = DeveloperToolsSupport.ColorResource(name: "PrimaryBrandColor", bundle: resourceBundle)

    /// The "ProgressHigh" asset catalog color resource.
    static let progressHigh = DeveloperToolsSupport.ColorResource(name: "ProgressHigh", bundle: resourceBundle)

    /// The "ProgressLow" asset catalog color resource.
    static let progressLow = DeveloperToolsSupport.ColorResource(name: "ProgressLow", bundle: resourceBundle)

    /// The "ProgressMedium" asset catalog color resource.
    static let progressMedium = DeveloperToolsSupport.ColorResource(name: "ProgressMedium", bundle: resourceBundle)

    /// The "RatingExceptional" asset catalog color resource.
    static let ratingExceptional = DeveloperToolsSupport.ColorResource(name: "RatingExceptional", bundle: resourceBundle)

    /// The "RatingFair" asset catalog color resource.
    static let ratingFair = DeveloperToolsSupport.ColorResource(name: "RatingFair", bundle: resourceBundle)

    /// The "RatingGood" asset catalog color resource.
    static let ratingGood = DeveloperToolsSupport.ColorResource(name: "RatingGood", bundle: resourceBundle)

    /// The "RatingGreat" asset catalog color resource.
    static let ratingGreat = DeveloperToolsSupport.ColorResource(name: "RatingGreat", bundle: resourceBundle)

    /// The "RatingPoor" asset catalog color resource.
    static let ratingPoor = DeveloperToolsSupport.ColorResource(name: "RatingPoor", bundle: resourceBundle)

}

// MARK: - Image Symbols -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension DeveloperToolsSupport.ImageResource {

}

// MARK: - Color Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    /// The "PriceHigh" asset catalog color.
    static var priceHigh: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .priceHigh)
#else
        .init()
#endif
    }

    /// The "PriceLow" asset catalog color.
    static var priceLow: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .priceLow)
#else
        .init()
#endif
    }

    /// The "PriceMedium" asset catalog color.
    static var priceMedium: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .priceMedium)
#else
        .init()
#endif
    }

    /// The "PricePremium" asset catalog color.
    static var pricePremium: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .pricePremium)
#else
        .init()
#endif
    }

    /// The "PrimaryBrandColor" asset catalog color.
    static var primaryBrand: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .primaryBrand)
#else
        .init()
#endif
    }

    /// The "ProgressHigh" asset catalog color.
    static var progressHigh: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .progressHigh)
#else
        .init()
#endif
    }

    /// The "ProgressLow" asset catalog color.
    static var progressLow: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .progressLow)
#else
        .init()
#endif
    }

    /// The "ProgressMedium" asset catalog color.
    static var progressMedium: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .progressMedium)
#else
        .init()
#endif
    }

    /// The "RatingExceptional" asset catalog color.
    static var ratingExceptional: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .ratingExceptional)
#else
        .init()
#endif
    }

    /// The "RatingFair" asset catalog color.
    static var ratingFair: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .ratingFair)
#else
        .init()
#endif
    }

    /// The "RatingGood" asset catalog color.
    static var ratingGood: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .ratingGood)
#else
        .init()
#endif
    }

    /// The "RatingGreat" asset catalog color.
    static var ratingGreat: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .ratingGreat)
#else
        .init()
#endif
    }

    /// The "RatingPoor" asset catalog color.
    static var ratingPoor: AppKit.NSColor {
#if !targetEnvironment(macCatalyst)
        .init(resource: .ratingPoor)
#else
        .init()
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    /// The "PriceHigh" asset catalog color.
    static var priceHigh: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .priceHigh)
#else
        .init()
#endif
    }

    /// The "PriceLow" asset catalog color.
    static var priceLow: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .priceLow)
#else
        .init()
#endif
    }

    /// The "PriceMedium" asset catalog color.
    static var priceMedium: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .priceMedium)
#else
        .init()
#endif
    }

    /// The "PricePremium" asset catalog color.
    static var pricePremium: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .pricePremium)
#else
        .init()
#endif
    }

    /// The "PrimaryBrandColor" asset catalog color.
    static var primaryBrand: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .primaryBrand)
#else
        .init()
#endif
    }

    /// The "ProgressHigh" asset catalog color.
    static var progressHigh: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .progressHigh)
#else
        .init()
#endif
    }

    /// The "ProgressLow" asset catalog color.
    static var progressLow: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .progressLow)
#else
        .init()
#endif
    }

    /// The "ProgressMedium" asset catalog color.
    static var progressMedium: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .progressMedium)
#else
        .init()
#endif
    }

    /// The "RatingExceptional" asset catalog color.
    static var ratingExceptional: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .ratingExceptional)
#else
        .init()
#endif
    }

    /// The "RatingFair" asset catalog color.
    static var ratingFair: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .ratingFair)
#else
        .init()
#endif
    }

    /// The "RatingGood" asset catalog color.
    static var ratingGood: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .ratingGood)
#else
        .init()
#endif
    }

    /// The "RatingGreat" asset catalog color.
    static var ratingGreat: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .ratingGreat)
#else
        .init()
#endif
    }

    /// The "RatingPoor" asset catalog color.
    static var ratingPoor: UIKit.UIColor {
#if !os(watchOS)
        .init(resource: .ratingPoor)
#else
        .init()
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    /// The "PriceHigh" asset catalog color.
    static var priceHigh: SwiftUI.Color { .init(.priceHigh) }

    /// The "PriceLow" asset catalog color.
    static var priceLow: SwiftUI.Color { .init(.priceLow) }

    /// The "PriceMedium" asset catalog color.
    static var priceMedium: SwiftUI.Color { .init(.priceMedium) }

    /// The "PricePremium" asset catalog color.
    static var pricePremium: SwiftUI.Color { .init(.pricePremium) }

    /// The "PrimaryBrandColor" asset catalog color.
    static var primaryBrand: SwiftUI.Color { .init(.primaryBrand) }

    /// The "ProgressHigh" asset catalog color.
    static var progressHigh: SwiftUI.Color { .init(.progressHigh) }

    /// The "ProgressLow" asset catalog color.
    static var progressLow: SwiftUI.Color { .init(.progressLow) }

    /// The "ProgressMedium" asset catalog color.
    static var progressMedium: SwiftUI.Color { .init(.progressMedium) }

    /// The "RatingExceptional" asset catalog color.
    static var ratingExceptional: SwiftUI.Color { .init(.ratingExceptional) }

    /// The "RatingFair" asset catalog color.
    static var ratingFair: SwiftUI.Color { .init(.ratingFair) }

    /// The "RatingGood" asset catalog color.
    static var ratingGood: SwiftUI.Color { .init(.ratingGood) }

    /// The "RatingGreat" asset catalog color.
    static var ratingGreat: SwiftUI.Color { .init(.ratingGreat) }

    /// The "RatingPoor" asset catalog color.
    static var ratingPoor: SwiftUI.Color { .init(.ratingPoor) }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    /// The "PriceHigh" asset catalog color.
    static var priceHigh: SwiftUI.Color { .init(.priceHigh) }

    /// The "PriceLow" asset catalog color.
    static var priceLow: SwiftUI.Color { .init(.priceLow) }

    /// The "PriceMedium" asset catalog color.
    static var priceMedium: SwiftUI.Color { .init(.priceMedium) }

    /// The "PricePremium" asset catalog color.
    static var pricePremium: SwiftUI.Color { .init(.pricePremium) }

    /// The "PrimaryBrandColor" asset catalog color.
    static var primaryBrand: SwiftUI.Color { .init(.primaryBrand) }

    /// The "ProgressHigh" asset catalog color.
    static var progressHigh: SwiftUI.Color { .init(.progressHigh) }

    /// The "ProgressLow" asset catalog color.
    static var progressLow: SwiftUI.Color { .init(.progressLow) }

    /// The "ProgressMedium" asset catalog color.
    static var progressMedium: SwiftUI.Color { .init(.progressMedium) }

    /// The "RatingExceptional" asset catalog color.
    static var ratingExceptional: SwiftUI.Color { .init(.ratingExceptional) }

    /// The "RatingFair" asset catalog color.
    static var ratingFair: SwiftUI.Color { .init(.ratingFair) }

    /// The "RatingGood" asset catalog color.
    static var ratingGood: SwiftUI.Color { .init(.ratingGood) }

    /// The "RatingGreat" asset catalog color.
    static var ratingGreat: SwiftUI.Color { .init(.ratingGreat) }

    /// The "RatingPoor" asset catalog color.
    static var ratingPoor: SwiftUI.Color { .init(.ratingPoor) }

}
#endif

// MARK: - Image Symbol Extensions -

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSImage {

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

}
#endif

// MARK: - Thinnable Asset Support -

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ColorResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if AppKit.NSColor(named: NSColor.Name(thinnableName), bundle: bundle) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIColor(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(AppKit)
@available(macOS 14.0, *)
@available(macCatalyst, unavailable)
extension AppKit.NSColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !targetEnvironment(macCatalyst)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIColor {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

#if canImport(SwiftUI)
@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
extension SwiftUI.ShapeStyle where Self == SwiftUI.Color {

    private init?(thinnableResource: DeveloperToolsSupport.ColorResource?) {
        if let resource = thinnableResource {
            self.init(resource)
        } else {
            return nil
        }
    }

}
#endif

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
@available(watchOS, unavailable)
extension DeveloperToolsSupport.ImageResource {

    private init?(thinnableName: Swift.String, bundle: Foundation.Bundle) {
#if canImport(AppKit) && os(macOS)
        if bundle.image(forResource: NSImage.Name(thinnableName)) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#elseif canImport(UIKit) && !os(watchOS)
        if UIKit.UIImage(named: thinnableName, in: bundle, compatibleWith: nil) != nil {
            self.init(name: thinnableName, bundle: bundle)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}

#if canImport(UIKit)
@available(iOS 17.0, tvOS 17.0, *)
@available(watchOS, unavailable)
extension UIKit.UIImage {

    private convenience init?(thinnableResource: DeveloperToolsSupport.ImageResource?) {
#if !os(watchOS)
        if let resource = thinnableResource {
            self.init(resource: resource)
        } else {
            return nil
        }
#else
        return nil
#endif
    }

}
#endif

