import SwiftUI

struct DeviceAdaptiveContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    var body: some View {
        if horizontalSizeClass == .regular && UIDevice.current.userInterfaceIdiom == .pad {
            // Use iPad-specific views on iPad
            iPadContentView()
        } else {
            // Use regular iPhone views for iPhone
            ContentView()
        }
    }
}

#Preview {
    DeviceAdaptiveContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
} 