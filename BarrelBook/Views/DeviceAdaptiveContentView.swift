import SwiftUI

struct DeviceAdaptiveContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("isDemoDataActive") private var isDemoDataActive = false

    var body: some View {
        Group {
            // Idiom only — once the target includes iPad (TARGETED_DEVICE_FAMILY 1,2),
            // UIDevice reports .pad and we always use the native split shell.
            // NavigationSplitView already collapses correctly in Slide Over / compact width.
            // Do NOT also require .regular: an iPhone-only build runs on iPad in
            // compatibility mode (idiom == .phone) and would never reach iPadContentView.
            if DeviceTypeHelper.isIPad {
                iPadContentView()
            } else {
                ContentView()
            }
        }
        // Onboarding must live here — iPadContentView never used ContentView's cover,
        // so Replay / first launch on iPad never got a wide walkthrough.
        .fullScreenCover(isPresented: Binding(
            get: { !hasSeenOnboarding },
            set: { _ in } // only completeOnboarding() closes this
        )) {
            OnboardingView(onLoadDemoData: loadDemoData)
                .interactiveDismissDisabled(true)
        }
    }

    private func loadDemoData() {
        DemoDataService.load(context: viewContext) { _ in
            isDemoDataActive = true
            HapticManager.shared.successFeedback()
        }
    }
}

#Preview {
    DeviceAdaptiveContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
