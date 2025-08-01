import SwiftUI

enum DeviceType {
    case iPhone
    case iPad
    case mac
    case unknown
}

struct DeviceTypeHelper {
    static var current: DeviceType {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return .iPad
        } else if UIDevice.current.userInterfaceIdiom == .phone {
            return .iPhone
        } else {
            return .unknown
        }
        #elseif os(macOS)
        return .mac
        #else
        return .unknown
        #endif
    }
    
    static var isIPad: Bool {
        return current == .iPad
    }
    
    static var isIPhone: Bool {
        return current == .iPhone
    }
    
    static var isMac: Bool {
        return current == .mac
    }
} 