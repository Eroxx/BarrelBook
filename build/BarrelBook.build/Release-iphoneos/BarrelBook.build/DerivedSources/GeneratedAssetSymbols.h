#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"Linder.BarrelBook";

/// The "PriceHigh" asset catalog color resource.
static NSString * const ACColorNamePriceHigh AC_SWIFT_PRIVATE = @"PriceHigh";

/// The "PriceLow" asset catalog color resource.
static NSString * const ACColorNamePriceLow AC_SWIFT_PRIVATE = @"PriceLow";

/// The "PriceMedium" asset catalog color resource.
static NSString * const ACColorNamePriceMedium AC_SWIFT_PRIVATE = @"PriceMedium";

/// The "PricePremium" asset catalog color resource.
static NSString * const ACColorNamePricePremium AC_SWIFT_PRIVATE = @"PricePremium";

/// The "PrimaryBrandColor" asset catalog color resource.
static NSString * const ACColorNamePrimaryBrandColor AC_SWIFT_PRIVATE = @"PrimaryBrandColor";

/// The "ProgressHigh" asset catalog color resource.
static NSString * const ACColorNameProgressHigh AC_SWIFT_PRIVATE = @"ProgressHigh";

/// The "ProgressLow" asset catalog color resource.
static NSString * const ACColorNameProgressLow AC_SWIFT_PRIVATE = @"ProgressLow";

/// The "ProgressMedium" asset catalog color resource.
static NSString * const ACColorNameProgressMedium AC_SWIFT_PRIVATE = @"ProgressMedium";

/// The "RatingExceptional" asset catalog color resource.
static NSString * const ACColorNameRatingExceptional AC_SWIFT_PRIVATE = @"RatingExceptional";

/// The "RatingFair" asset catalog color resource.
static NSString * const ACColorNameRatingFair AC_SWIFT_PRIVATE = @"RatingFair";

/// The "RatingGood" asset catalog color resource.
static NSString * const ACColorNameRatingGood AC_SWIFT_PRIVATE = @"RatingGood";

/// The "RatingGreat" asset catalog color resource.
static NSString * const ACColorNameRatingGreat AC_SWIFT_PRIVATE = @"RatingGreat";

/// The "RatingPoor" asset catalog color resource.
static NSString * const ACColorNameRatingPoor AC_SWIFT_PRIVATE = @"RatingPoor";

#undef AC_SWIFT_PRIVATE
