import Foundation

@objc(SecureValueTransformer)
final class SecureValueTransformer: NSSecureUnarchiveFromDataTransformer {
    
    override static var allowedTopLevelClasses: [AnyClass] {
        // Add all the classes that you'll store in your transformable attributes
        return [NSString.self, NSNumber.self, NSArray.self, NSDictionary.self, NSDate.self]
    }
    
    static func register() {
        let transformer = SecureValueTransformer()
        ValueTransformer.setValueTransformer(transformer, forName: NSValueTransformerName(rawValue: "SecureValueTransformer"))
    }
} 