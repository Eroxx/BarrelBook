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

extension View {
    /// Large form-style sheet chrome on iPad; unchanged on iPhone.
    @ViewBuilder
    func iPadFormSheetChrome() -> some View {
        if DeviceTypeHelper.isIPad {
            self
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        } else {
            self
        }
    }
    
    /// Paywall: large sheet on iPad, full-screen cover on iPhone.
    @ViewBuilder
    func barrelPaywallPresentation(isPresented: Binding<Bool>) -> some View {
        if DeviceTypeHelper.isIPad {
            self.sheet(isPresented: isPresented) {
                PaywallView(isPresented: isPresented)
                    .iPadFormSheetChrome()
            }
        } else {
            self.fullScreenCover(isPresented: isPresented) {
                PaywallView(isPresented: isPresented)
            }
        }
    }
}

/// Empty detail placeholder for iPad split columns (iOS 16–compatible).
struct iPadEmptyDetailView: View {
    let title: String
    let systemImage: String
    let description: String
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.weight(.semibold))
            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(Color(UIColor.systemGroupedBackground))
    }
}
