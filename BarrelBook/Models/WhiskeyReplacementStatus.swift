import Foundation

enum WhiskeyReplacementStatus: String, Codable {
    case none           // Default state
    case wantToReplace  // Marked for future replacement
    case isReplacement  // This bottle is a replacement for another
} 