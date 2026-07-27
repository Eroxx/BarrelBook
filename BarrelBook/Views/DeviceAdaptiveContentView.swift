import SwiftUI
import UIKit

struct DeviceAdaptiveContentView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("isDemoDataActive") private var isDemoDataActive = false
    @State private var didPrepareMarketingShot = false

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
        .task {
            await prepareMarketingScreenshotIfNeeded()
        }
    }

    private func loadDemoData() {
        DemoDataService.load(context: viewContext) { _ in
            isDemoDataActive = true
            HapticManager.shared.successFeedback()
        }
    }

    /// Launch with `-marketingScreenshot` to seed demo data, skip onboarding,
    /// and request landscape for website captures.
    @MainActor
    private func prepareMarketingScreenshotIfNeeded() async {
        guard !didPrepareMarketingShot else { return }
        guard ProcessInfo.processInfo.arguments.contains("-marketingScreenshot") else { return }
        didPrepareMarketingShot = true

        hasSeenOnboarding = true
        // Hide first-run tips so marketing frames stay clean.
        let tipKeys = [
            "hasSeenStatisticsTutorial",
            "hasSeenCollectionTutorial",
            "hasSeenEmptyCollectionTutorial",
            "hasSeenWishlistTutorial",
            "hasSeenReplacementsTutorial",
            "hasSeenJournalTutorial",
            "hasSeenBottleViewTutorial",
            "hasSeenBottleViewTutorialPart2",
            "hasSeenWebReviewsTip",
            "hasSeenEmptyStateTip",
            "hasSeenSortTutorial",
            "hasSeenInfinityBottleTutorial",
            "bb_hasSeenScannerTip"
        ]
        for key in tipKeys {
            UserDefaults.standard.set(true, forKey: key)
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DemoDataService.load(context: viewContext) { _ in
                isDemoDataActive = true
                cont.resume()
            }
        }

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
        }
        // Let sidebar + home settle with seeded content before external capture.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        // Optional deep-link for other marketing frames.
        if ProcessInfo.processInfo.arguments.contains("-marketingCollection") {
            // Open list+detail with a dense owned bottle selected.
            let req = Whiskey.fetchRequest()
            req.predicate = NSPredicate(format: "status == %@", "owned")
            req.fetchLimit = 1
            req.sortDescriptors = [NSSortDescriptor(keyPath: \Whiskey.name, ascending: true)]
            if let first = try? viewContext.fetch(req).first, let id = first.id {
                NavigationStateManager.shared.pendingCollectionWhiskeyID = id
            }
            NavigationStateManager.shared.activeTab = .collection
            try? await Task.sleep(nanoseconds: 1_600_000_000)
        } else if ProcessInfo.processInfo.arguments.contains("-marketingStatistics") {
            NavigationStateManager.shared.activeTab = .statistics
            try? await Task.sleep(nanoseconds: 1_600_000_000)
        } else if ProcessInfo.processInfo.arguments.contains("-marketingWishlist") {
            let req = Whiskey.fetchRequest()
            req.predicate = NSPredicate(format: "status == %@", "wishlist")
            req.fetchLimit = 1
            req.sortDescriptors = [NSSortDescriptor(keyPath: \Whiskey.name, ascending: true)]
            if let first = try? viewContext.fetch(req).first, let id = first.id {
                NavigationStateManager.shared.pendingWishlistWhiskeyID = id
            }
            NavigationStateManager.shared.activeTab = .wishlist
            try? await Task.sleep(nanoseconds: 1_600_000_000)
        } else if ProcessInfo.processInfo.arguments.contains("-marketingJournal") {
            NavigationStateManager.shared.activeTab = .journal
            try? await Task.sleep(nanoseconds: 1_600_000_000)
        }
    }
}

#Preview {
    DeviceAdaptiveContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
