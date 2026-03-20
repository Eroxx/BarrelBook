import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ObjectiveC
import CoreData
import CoreLocation

@propertyWrapper
struct Atomic<Value> {
    private var value: Value
    private let lock = NSLock()

    init(wrappedValue value: Value) {
        self.value = value
    }

    var wrappedValue: Value {
        get { 
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }
}

struct SettingsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Whiskey.name, ascending: true)],
        animation: .default)
    private var whiskeys: FetchedResults<Whiskey>
    
    @FetchRequest(sortDescriptors: [SortDescriptor(\.creationDate)]) private var infinityBottles: FetchedResults<InfinityBottle>
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Store.name, ascending: true)],
        predicate: NSPredicate(format: "isFavorite == YES"),
        animation: .default)
    private var favoriteStores: FetchedResults<Store>
    
    @State private var locationManager = CLLocationManager()
    
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var successMessage = ""
    @State private var isImporting = false
    @State private var isShowingCSVImportPicker = false
    @State private var isExporting = false
    @State private var isLoading = false
    @AppStorage("colorScheme") private var colorScheme: AppColorScheme = .system
    @State private var hasSeenOnboarding = false
    @State private var showingOnboarding = false
    @State private var showingImportOptions = false
    @State private var selectedCSVFile: URL?
    @State private var showingStartFreshWarning = false
    @State private var showingDeleteConfirmation = false
    
    // Environment value for theme
    @Environment(\.colorScheme) private var currentColorScheme
    
    // State for view refresh when theme changes
    @State private var viewRefreshTrigger = UUID()
    @State private var displayColorScheme: ColorScheme?
    
    @State private var showingTemplateAlert = false
    @State private var showingTemplatePicker = false
    
    // Add a new state variable for tracking custom export sheet
    @State private var isExportingToCustomLocation = false
    @State private var customExportData: String = ""
    @State private var customExportFilename: String = ""
    @State private var customExportCallback: ((URL) -> Void)? = nil
    
    // Add PrivacyManager
    @ObservedObject private var privacyManager = PrivacyManager.shared
    
    // Add state for conflict resolution
    @State private var showingConflict = false
    @State private var conflictMessage = ""
    @State private var conflictWhiskey = ""
    @State private var conflictContinuation: CheckedContinuation<Bool, Never>?
    
    @State private var showingAddStore = false
    @State private var showingStoreSelection = false
    
    // Add states for progress tracking
    @State private var importProgress: Double = 0.0
    @State private var importStatusMessage: String = ""
    
    // Add new @State variables for confirmation alerts at the top of the struct:
    @State private var showingDeleteCollectionConfirmation = false
    @State private var showingDeleteTastingConfirmation = false
    @State private var showingDeleteInfinityConfirmation = false
    @State private var showingDeleteWishlistConfirmation = false
    @State private var showingDeleteAllConfirmation = false
    @State private var showingLoadDemoDataConfirmation = false
    @State private var showingDemoDataInfo = false
    
    // Add new @State variables for DisclosureGroup and info alert:
    @State private var showingDeleteDataOptions = false
    @State private var showingBottleNumberingInfo = false
    @State private var showingPaywall = false
    @AppStorage("hasSeenSettingsTutorial") private var hasSeenSettingsTutorial = false
    @State private var showingSettingsTutorialOverlay = false
    @State private var settingsTutorialStep = 1
    
    var body: some View {
        ZStack {
        NavigationView {
            formContent
        }
            if showingSettingsTutorialOverlay {
                SettingsTutorialOverlay(step: settingsTutorialStep, onNext: {
                    settingsTutorialStep = 2
                }, onDismiss: {
                    hasSeenSettingsTutorial = true
                    showingSettingsTutorialOverlay = false
                    settingsTutorialStep = 1
                    HapticManager.shared.lightImpact()
                })
            }
        }
        .preferredColorScheme(displayColorScheme)
        .navigationViewStyle(StackNavigationViewStyle())
        .interactiveDismissDisabled() // Prevent dismissal by dragging down
        .sheet(isPresented: $isExportingToCustomLocation) {
            DocumentPickerExport(
                csvData: customExportData,
                filename: customExportFilename,
                onComplete: customExportCallback
            )
        }
        .sheet(isPresented: $isExporting) {
            DocumentPickerExport(
                csvData: {
                    do {
                        let csvContent = try CSVService.shared.exportWhiskeys(Array(whiskeys))
                        if csvContent.isEmpty {
                            errorMessage = "No data to export. Please add some whiskeys first."
                            showingError = true
                            return ""
                        }
                        return csvContent
                    } catch {
                        errorMessage = "Failed to prepare CSV data: \(error.localizedDescription)"
                        showingError = true
                        return ""
                    }
                }()
            )
        }
        .onAppear {
            setupConflictHandling()
            additionalSetup()
            if !hasSeenSettingsTutorial {
                settingsTutorialStep = 1
                showingSettingsTutorialOverlay = true
            }
        }
    }
    
    // MARK: - View Sections
    
    private var formContent: some View {
        Form {
            appearanceSection
            subscriptionSection
            dataManagementSection
            favoriteStoresSection
            helpSection
            aboutSection
            privacySection
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
            Button("Done") {
                dismiss()
                HapticManager.shared.lightImpact()
            }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Success", isPresented: $showingSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(successMessage)
        }
        .alert("Import Options", isPresented: $showingImportOptions) {
            Button("Start Fresh") {
                showingStartFreshWarning = true
            }
            Button("Merge with Existing") {
                if let file = selectedCSVFile {
                    Task {
                        do {
                            // Start accessing the file again
                            guard file.startAccessingSecurityScopedResource() else {
                                errorMessage = "Permission denied: Unable to access the selected file. Please try again."
                                showingError = true
                                return
                            }
                            
                            // Read the file content
                            let csvString = try String(contentsOf: file, encoding: .utf8)
                            
                            // Stop accessing the file
                            file.stopAccessingSecurityScopedResource()
                            
                            // Process the import
                            await processCSVString(csvString, isFreshImport: false)
                        } catch {
                            errorMessage = "Failed to read CSV file: \(error.localizedDescription)"
                            showingError = true
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("How would you like to import your CSV data?\n\n• Start Fresh: Delete all existing whiskeys and import only from the CSV\n• Merge with Existing: Keep existing whiskeys and add/update from the CSV")
        }
        .alert("Warning: Delete Collection", isPresented: $showingStartFreshWarning) {
            Button("Cancel", role: .cancel) { }
            Button("Delete and Import", role: .destructive) {
                if let file = selectedCSVFile {
                    Task {
                        do {
                            // Start accessing the file again
                            guard file.startAccessingSecurityScopedResource() else {
                                errorMessage = "Permission denied: Unable to access the selected file. Please try again."
                                showingError = true
                                return
                            }
                            
                            // Read the file content
                            let csvString = try String(contentsOf: file, encoding: .utf8)
                            
                            // Stop accessing the file
                            file.stopAccessingSecurityScopedResource()
                            
                            // Process the import
                            await processCSVString(csvString, isFreshImport: true)
                        } catch {
                            errorMessage = "Failed to read CSV file: \(error.localizedDescription)"
                            showingError = true
                        }
                    }
                }
            }
        } message: {
            Text("This process will delete all whiskeys currently in the app and replace them with your imported CSV file. This action cannot be undone.\n\nDo you want to continue?")
        }
        .alert("About CSV Templates", isPresented: $showingTemplateAlert) {
            Button("Download Template", role: .none) {
                createCSVTemplate()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("A CSV template helps you understand how to format your whiskey data for importing into BarrelBook.\n\nThe template includes:\n\n• Example entries showing proper formatting\n• A README with detailed instructions\n• Tips for using spreadsheet software\n\nThis is especially useful if you plan to maintain your collection data in a spreadsheet.")
        }
        .alert("Import Conflict", isPresented: $showingConflict) {
            Button("Skip", role: .cancel) {
                conflictContinuation?.resume(returning: false)
                conflictContinuation = nil
            }
            Button("Replace", role: .destructive) {
                conflictContinuation?.resume(returning: true)
                conflictContinuation = nil
            }
        } message: {
            Text(conflictMessage)
        }
        .fileImporter(
            isPresented: $isShowingCSVImportPicker,
            allowedContentTypes: [UTType.commaSeparatedText, UTType.text, UTType.data, .plainText],
            allowsMultipleSelection: false
        ) { result in
            importData(result)
        }
        .sheet(isPresented: $showingStoreSelection) {
            StoreSelectionView(currentlySelectedStores: Set<Store>()) { store in
                if let store = store {
                    // Don't add if another favorite with same name/address already exists
                    let name = (store.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let address = (store.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let request = Store.fetchRequest()
                    request.predicate = NSPredicate(format: "isFavorite == YES AND name == %@ AND address == %@", name, address)
                    request.fetchLimit = 2
                    do {
                        let existing = try viewContext.fetch(request)
                        let otherExists = existing.contains { $0.objectID != store.objectID }
                        if !otherExists {
                            store.isFavorite = true
                            try viewContext.save()
                        }
                    } catch {
                        let nsError = error as NSError
                        print("Error saving store: \(nsError), \(nsError.userInfo)")
                    }
                }
                // Note: "No Store Selected" doesn't make sense in settings context
            }
        }
    }
    
    private var appearanceSection: some View {
        Section(header: Text("Appearance")) {
            Picker("Appearance", selection: $colorScheme) {
                Text("Light").tag(AppColorScheme.light)
                Text("Dark").tag(AppColorScheme.dark)
                Text("System").tag(AppColorScheme.system)
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: colorScheme) { newValue in
                HapticManager.shared.selectionFeedback()
                applyTheme(newValue)
            }
        }
    }
    
    private var subscriptionSection: some View {
        Section(header: Text("Premium")) {
            subscriptionStatusView
        }
    }
    
    private var favoriteStoresSection: some View {
        Section(header: Text("Favorite Stores")) {
            if favoriteStores.isEmpty {
                VStack(alignment: .center, spacing: 8) {
                    Image(systemName: "star")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No favorite stores yet")
                        .foregroundColor(.secondary)
                    Text("Add stores to quickly find whiskeys")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                DisclosureGroup {
                    let nearbyStores = getNearbyStores()
                    let otherStores = getOtherStores()
                    
                    if !nearbyStores.isEmpty {
                        Section(header: Text("Nearby Stores")) {
                            ForEach(nearbyStores) { store in
                                StoreRowView(store: store)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            store.isFavorite = false
                                            try? viewContext.save()
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                    
                    if !otherStores.isEmpty {
                        Section(header: Text(nearbyStores.isEmpty ? "Favorite Stores" : "Other Favorite Stores")) {
                            ForEach(otherStores) { store in
                                StoreRowView(store: store)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            store.isFavorite = false
                                            try? viewContext.save()
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                            }
                        }
                    }
                } label: {
                    HStack {
                        Text("Favorite Stores (\(favoriteStores.count))")
                            .foregroundColor(.primary)
                        Spacer()
                    }
                }
            }
            
            Button(action: { showingStoreSelection = true }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                    Text("Add New Store")
                }
            }
        }
    }
    
    private var dataManagementSection: some View {
        Section(header: Text("Data Management")) {
            // DisclosureGroup for Delete Data
            DisclosureGroup(
                isExpanded: $showingDeleteDataOptions,
                content: {
                    deleteDataButtons
                },
                label: {
                    Label("Delete Data", systemImage: "trash")
                        .foregroundColor(.red)
                }
            )

            // Load Demo Data — separate from destructive delete options
            HStack(spacing: 10) {
                Button(action: {
                    showingLoadDemoDataConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(ColorManager.primaryBrandColor)
                        Text("Load Demo Data")
                            .foregroundColor(ColorManager.primaryBrandColor)
                    }
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: { showingDemoDataInfo = true }) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
                .alert("About Demo Data", isPresented: $showingDemoDataInfo) {
                    Button("Got it", role: .cancel) { }
                } message: {
                    Text("Demo data loads a sample bourbon collection so you can explore every feature of BarrelBook right away.\n\nIt includes:\n• A variety of owned bottles (open, sealed & empty)\n• Tasting notes with flavor profiles and ratings\n• Wishlist items with target prices\n• An example infinity bottle\n\n⚠️ Loading demo data will permanently delete your existing collection. Use this to take BarrelBook for a test drive before adding your own bottles.")
                }
                Spacer()
            }
            .alert("Load Demo Data?", isPresented: $showingLoadDemoDataConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Load Demo Data", role: .destructive) { loadDemoData() }
            } message: {
                Text("This will permanently delete all current data and replace it with a sample collection. This cannot be undone.")
            }

            importExportButtons
            
            // Loading indicator when import/export is in progress
            if isLoading {
                HStack {
                    Spacer()
                    VStack {
                        // Replace simple progress indicator with a progress bar and status
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: importProgress, total: 1.0)
                                .progressViewStyle(LinearProgressViewStyle())
                                .frame(height: 8)
                                .padding(.bottom, 2)

                            HStack {
                                Text("\(Int(importProgress * 100))% Complete")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Spacer()
                                Text(importStatusMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
            }
            
            // Template creation button
            HStack {
                Button {
                    createCSVTemplate()
                    HapticManager.shared.mediumImpact()
                } label: {
                        Label("Download BarrelBook CSV Template", systemImage: "doc.badge.plus")
                        .foregroundColor(.blue)
                    }
                .buttonStyle(PlainButtonStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Button {
                    showingTemplateAlert = true
                    HapticManager.shared.mediumImpact()
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private var deleteDataButtons: some View {
        Group {
            // Delete Collection (owned whiskeys only)
            Button(action: {
                showingDeleteCollectionConfirmation = true
            }) {
                HStack {
                    Image(systemName: "trash.circle.fill")
                        .foregroundColor(.red)
                    Text("Delete Collection (Owned Whiskeys)")
                        .foregroundColor(.red)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 10)
            .alert("Delete Collection?", isPresented: $showingDeleteCollectionConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Owned Whiskeys", role: .destructive) {
                    deleteOwnedCollection()
                }
            } message: {
                Text("This will permanently delete all owned whiskeys and their bottles. This action cannot be undone.")
            }

            // Delete all Tasting Data
            Button(action: {
                showingDeleteTastingConfirmation = true
            }) {
                HStack {
                    Image(systemName: "trash.circle.fill")
                        .foregroundColor(.red)
                    Text("Delete all Tasting Data")
                        .foregroundColor(.red)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .alert("Delete All Tasting Data?", isPresented: $showingDeleteTastingConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All Tasting Data", role: .destructive) {
                    deleteAllTastingData()
                }
            } message: {
                Text("This will permanently delete all tasting notes and journal entries. This action cannot be undone.")
            }

            // Delete Infinity Bottles
            Button(action: {
                showingDeleteInfinityConfirmation = true
            }) {
                HStack {
                    Image(systemName: "trash.circle.fill")
                        .foregroundColor(.red)
                    Text("Delete Infinity Bottles")
                        .foregroundColor(.red)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .alert("Delete All Infinity Bottles?", isPresented: $showingDeleteInfinityConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Infinity Bottles", role: .destructive) {
                    deleteAllInfinityBottles()
                }
            } message: {
                Text("This will permanently delete all infinity bottles and their data. This action cannot be undone.")
            }

            // Delete Wishlist/Replacement Bottles
            Button(action: {
                showingDeleteWishlistConfirmation = true
            }) {
                HStack {
                    Image(systemName: "trash.circle.fill")
                        .foregroundColor(.red)
                    Text("Delete Wishlist/Replacement Bottles")
                        .foregroundColor(.red)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .alert("Delete Wishlist/Replacement Bottles?", isPresented: $showingDeleteWishlistConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Wishlist/Replacement", role: .destructive) {
                    deleteWishlistAndReplacementBottles()
                }
            } message: {
                Text("This will permanently delete all wishlist and replacement bottles. This action cannot be undone.")
            }

            // Delete ALL Data
            Button(action: {
                showingDeleteAllConfirmation = true
            }) {
                HStack {
                    Image(systemName: "trash.circle.fill")
                        .foregroundColor(.red)
                    Text("Delete all Data")
                        .foregroundColor(.red)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .alert("Delete ALL Data?", isPresented: $showingDeleteAllConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete EVERYTHING", role: .destructive) {
                    deleteAllData()
                }
            } message: {
                Text("This will permanently delete ALL data in BarrelBook, including whiskeys, bottles, tastings, infinity bottles, wishlist, and replacement bottles. This action cannot be undone.")
            }
            

        }
    }
    
    private var importExportButtons: some View {
        VStack(spacing: 4) {
        HStack(spacing: 30) {
            Spacer()
            
            // Import button
                Button(action: {
                    triggerImport()
                }) {
                    VStack {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 28))
                            .padding(.bottom, 2)
                        Text("Import CSV")
                            .font(.caption)
                    }
                    .frame(width: 80, height: 80)
                .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isLoading)
                .opacity(isLoading ? 0.5 : 1.0)
            
            Spacer()
            
            // Export button
                Button(action: {
                    exportData()
                }) {
                    VStack {
                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: 28))
                            .padding(.bottom, 2)
                        Text("Export Collection")
                            .font(.caption)
                    }
                    .frame(width: 80, height: 80)
                .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(isLoading)
                .opacity(isLoading ? 0.5 : 1.0)
            
            Spacer()
        }
        .padding(.vertical, 10)

        Text("Export Collection saves your entire collection to a CSV file — great for backups or moving your data.")
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        } // end VStack
    }
    
    private var helpSection: some View {
        Section(header: Text("Help")) {
            Link(destination: URL(string: "mailto:barrelbookdev@gmail.com")!) {
                Label("Contact Developer", systemImage: "envelope")
                    .foregroundColor(.primary)
            }
            Link(destination: URL(string: "https://discord.gg/nfgGYnGWfA")!) {
                Label("Join BarrelBook Discord", systemImage: "bubble.left.and.bubble.right")
                    .foregroundColor(.primary)
            }
            Link(destination: URL(string: "https://youtu.be/WQjhyPm62KA")!) {
                Label("Video: Getting Started", systemImage: "play.rectangle.fill")
                    .foregroundColor(.primary)
            }
            Link(destination: URL(string: "https://youtu.be/yY71ND7r3hs")!) {
                Label("Video: Full Walkthrough", systemImage: "play.rectangle.fill")
                    .foregroundColor(.primary)
            }
            Button {
                UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
                HapticManager.shared.successFeedback()
                dismiss()
            } label: {
                Label("Reset Onboarding Tutorial", systemImage: "arrow.counterclockwise")
            }
            Button {
                resetAllTutorials()
            } label: {
                Label("Reset Individual Tutorials", systemImage: "lightbulb")
            }
        }
    }
    
    private func resetAllTutorials() {
        let keys = [
            "hasSeenSortTutorial",
            "hasSeenStoresTutorialInAddWishlist",
            "hasSeenWishlistTutorial",
            "hasSeenInfinityBottleTutorial",
            "hasSeenAddInfinityBottleTutorial",
            "hasSeenAddPourToInfinityBottleTutorial",
            "hasSeenJournalTutorial",
            "hasSeenStatisticsTutorial",
            "hasSeenBottleViewTutorial",
            "hasSeenCollectionTutorial",
            "hasSeenEmptyCollectionTutorial",
            "hasSeenAddWhiskeyTutorial",
            "hasSeenSettingsTutorial"
        ]
        for key in keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        successMessage = "Tutorials reset. You’ll see the tips again when you open Collection (empty or with bottles), Add Whiskey, Sort, Wishlist, Stores, Infinity Bottles, Tastings, Statistics, Settings, and a bottle."
        showingSuccess = true
        HapticManager.shared.lightImpact()
    }
    
    private var aboutSection: some View {
        Section(header: Text("About")) {

            // ── Developer note ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("🥃")
                        .font(.title2)
                    Text("A Tasting Note from the Developer")
                        .font(.headline)
                        .foregroundColor(ColorManager.primaryBrandColor)
                }

                Text("""
Hi! I'm Eric, the solo developer behind BarrelBook.

I tried several whiskey catalog apps and none of them quite clicked, especially when it came to seeing my collection clearly at a glance.

So I built the one I actually wanted. BarrelBook lets you track your collection and its value, log tastings, manage your wishlist, build infinity bottles, and more, all in one place.

Join the Discord (link above) and share your thoughts and feedback. Thank you!

Know thy shelf - Eric
""")
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)

            // ── Version ─────────────────────────────────────────────────
            HStack {
                Text("Version")
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var privacySection: some View {
        Section(header: Text("PRIVACY")) {
            Toggle(isOn: $privacyManager.hidePrices) {
                HStack {
                    Text("Hide Prices")
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if privacyManager.hidePrices {
                Text("Prices will be hidden throughout the app. Tap the lock icon to temporarily view a price.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Settings tutorial (page 1: Appearance, Stores, Privacy; page 2: Data Management)
    private struct SettingsTutorialOverlay: View {
        let step: Int
        let onNext: () -> Void
        let onDismiss: () -> Void
        
        var body: some View {
            ColorManager.tutorialScrim
                .ignoresSafeArea()
                .onTapGesture { }
            if step == 1 {
                settingsTutorialPage1(onNext: onNext)
            } else {
                settingsTutorialPage2(onDismiss: onDismiss)
            }
        }
        
        private func settingsTutorialPage1(onNext: @escaping () -> Void) -> some View {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Image(systemName: "gearshape.fill")
                                        .font(.title2)
                                        .foregroundColor(ColorManager.primaryBrandColor)
                                    Text("Settings")
                                        .font(.headline)
                                }
                                VStack(alignment: .leading, spacing: 10) {
                                    settingsTutorialRow(icon: "1.circle.fill", text: "**Appearance**: Choose Light, Dark, or System for the whole app.")
                                    settingsTutorialRow(icon: "2.circle.fill", text: "**Favorite Stores**: You can save stores as favorites here. When you add a bottle to your **wishlist**, you can attach one or more stores to that bottle so you remember where you found it (or where you're looking) and at what price. Add or remove favorite stores in this section.")
                                    settingsTutorialRow(icon: "3.circle.fill", text: "**Privacy**: **Hide Prices** hides dollar amounts app-wide; tap the lock icon when you want to reveal a price.")
                                }
                                .font(.subheadline)
                            }
                            .padding(24)
                            .background(Color(UIColor.secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(ColorManager.tutorialCardBorder, lineWidth: 1)
                            )
                            .cornerRadius(16)
                            .shadow(radius: 12)
                            .padding(.horizontal, 24)
                            Button(action: onNext) {
                                Text("Next")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ColorManager.primaryBrandColor)
                            .padding(.horizontal, 24)
                        }
                        .padding()
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: geometry.size.height)
                }
                .padding()
            }
        }
        
        private func settingsTutorialPage2(onDismiss: @escaping () -> Void) -> some View {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        VStack(spacing: 20) {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack {
                                    Image(systemName: "doc.badge.arrow.up")
                                        .font(.title2)
                                        .foregroundColor(ColorManager.primaryBrandColor)
                                    Text("Data Management")
                                        .font(.headline)
                                }
                                Text(LocalizedStringKey("The app lets you add whiskeys from a **CSV file** (a spreadsheet).\n\nIf you're **starting from scratch**, use **Download BarrelBook CSV Template** to get a ready-made file and instructions. Fill it in on your computer, then **Import CSV** to bring those bottles into the app.\n\nIf you already have bottles in the app, you can **merge** your CSV with them instead of replacing everything.\n\n**Export CSV** backs up your collection to a file.\n\n**Delete Data** (tap to expand) lets you remove specific things—owned whiskeys, tastings, infinity bottles, wishlist, or everything—each with its own confirmation so nothing is removed by accident."))
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(24)
                            .background(Color(UIColor.secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(ColorManager.tutorialCardBorder, lineWidth: 1)
                            )
                            .cornerRadius(16)
                            .shadow(radius: 12)
                            .padding(.horizontal, 24)
                            Button(action: onDismiss) {
                                Text("Got it")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(ColorManager.primaryBrandColor)
                            .padding(.horizontal, 24)
                        }
                        .padding()
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: geometry.size.height)
                }
                .padding()
            }
        }
        
        private func settingsTutorialRow(icon: String, text: String) -> some View {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(ColorManager.primaryBrandColor)
                    .font(.subheadline)
                Text(LocalizedStringKey(text))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    
    // MARK: - Theme Handling
    
    // Update the display color scheme based on the current setting
    private func updateDisplayColorScheme() {
            switch colorScheme {
            case .light:
            displayColorScheme = .light
            case .dark:
            displayColorScheme = .dark
            case .system:
            // Force a refresh when switching to system theme
            displayColorScheme = currentColorScheme == .dark ? .light : .dark
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                displayColorScheme = nil
            }
        }
    }
    
    // Apply theme and update display settings
    private func applyTheme(_ newValue: AppColorScheme) {
        // Set the global app theme
        setGlobalTheme(newValue)
        
        // Update the local display
        switch newValue {
        case .light:
            displayColorScheme = .light
        case .dark:
            displayColorScheme = .dark
        case .system:
            // Force a refresh when switching to system theme
            displayColorScheme = currentColorScheme == .dark ? .light : .dark
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                displayColorScheme = nil
            }
        }
    }
    
    // Set the global app theme
    private func setGlobalTheme(_ newValue: AppColorScheme) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return
        }
        
        switch newValue {
        case .light:
            window.overrideUserInterfaceStyle = .light
        case .dark:
            window.overrideUserInterfaceStyle = .dark
        case .system:
            // Force a refresh when switching to system theme
            let currentStyle = currentColorScheme == .dark ? UIUserInterfaceStyle.light : UIUserInterfaceStyle.dark
            window.overrideUserInterfaceStyle = currentStyle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            window.overrideUserInterfaceStyle = .unspecified
        }
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Import and Export Methods
    
    private func triggerImport() {
        HapticManager.shared.mediumImpact()
        
        guard subscriptionManager.hasAccess else {
            showingPaywall = true
            return
        }
        
        // Print debug information
        
        // To fix the presentation issue, we need to ensure no other presentations
        // are active before showing the file picker
        if let presentedVC = UIApplication.topViewController()?.presentedViewController {
            presentedVC.dismiss(animated: true) {
                // Wait for the dismissal to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.isShowingCSVImportPicker = true
                }
            }
        } else {
            // No existing presentation, safe to show picker
            self.isShowingCSVImportPicker = true
        }
    }
    
    private func importData(_ result: Result<[URL], Error>) {
        Task {
            do {
                let urls = try result.get()
                guard let selectedFile = urls.first else { return }
                
                guard selectedFile.startAccessingSecurityScopedResource() else {
                    await MainActor.run {
                        errorMessage = "Permission denied: Unable to access the selected file."
                        showingError = true
                        HapticManager.shared.errorFeedback()
                    }
                    return
                }
                
                let fileManager = FileManager.default
                guard fileManager.fileExists(atPath: selectedFile.path) else {
                    selectedFile.stopAccessingSecurityScopedResource()
                    await MainActor.run {
                        errorMessage = "The selected file doesn't exist or can't be accessed."
                        showingError = true
                        HapticManager.shared.errorFeedback()
                    }
                    return
                }
                
                guard let fileAttributes = try? fileManager.attributesOfItem(atPath: selectedFile.path),
                      let fileSize = fileAttributes[.size] as? NSNumber,
                      fileSize.intValue > 0, 
                      fileSize.intValue < 10_000_000 else {
                    selectedFile.stopAccessingSecurityScopedResource()
                    await MainActor.run {
                        errorMessage = "The file is either empty or too large."
                        showingError = true
                        HapticManager.shared.errorFeedback()
                    }
                    return
                }
                
                let encodingsToTry: [String.Encoding] = [.utf8, .ascii, .isoLatin1, .windowsCP1252]
                var csvString: String?
                var importError: Error?
                
                for encoding in encodingsToTry {
                    do {
                        csvString = try String(contentsOf: selectedFile, encoding: encoding)
                        break
                    } catch {
                        importError = error
                        continue
                    }
                }
                
                guard let finalCsvString = csvString else {
                    selectedFile.stopAccessingSecurityScopedResource()
                    await MainActor.run {
                        errorMessage = "Could not read the CSV file. Please ensure it uses a supported encoding."
                        showingError = true
                        HapticManager.shared.errorFeedback()
                    }
                    return
                }
                
                let firstLine = finalCsvString.components(separatedBy: .newlines).first ?? ""
                if !firstLine.contains(",") {
                    selectedFile.stopAccessingSecurityScopedResource()
                    await MainActor.run {
                        errorMessage = "The file doesn't appear to be a valid CSV."
                        showingError = true
                        HapticManager.shared.errorFeedback()
                    }
                    return
                }
                
                selectedFile.stopAccessingSecurityScopedResource()
                
                let collectionEmpty = await MainActor.run { whiskeys.isEmpty }
                if collectionEmpty {
                    await processCSVString(finalCsvString, isFreshImport: false)
                } else {
                    await MainActor.run {
                        selectedCSVFile = selectedFile
                        showingImportOptions = true
                    }
                }
                
            } catch {
                await MainActor.run {
                    errorMessage = "Import failed: \(error.localizedDescription)"
                    showingError = true
                    HapticManager.shared.errorFeedback()
                }
            }
        }
    }
    
    private func processCSVString(_ csvString: String, isFreshImport: Bool) async {
        let persistenceController = PersistenceController.shared
        var needToRestoreSync = false
        
        defer {
            if needToRestoreSync {
                persistenceController.container.viewContext.automaticallyMergesChangesFromParent = true
            }
        }
        
        do {
            let countBefore = whiskeys.count
            let startTime = Date()
            
            await MainActor.run {
                isLoading = true
                importProgress = 0.0
                importStatusMessage = "Preparing import..."
            }
            
            // Clear memory before starting the import
            clearMemory()
            
            // Set up a task for tracking timeout
            let timeout = Task {
                // Set a longer timeout for larger CSVs
                let timeoutDuration: TimeInterval = csvString.count > 100000 ? 900 : 600  // Increased from 600/300 to 900/600
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeoutDuration * 1_000_000_000))
                    // If we reach here, the import is taking too long
                    if isLoading {
                        await MainActor.run {
                            isLoading = false
                            errorMessage = "Import timed out after \(Int(timeoutDuration/60)) minutes. Try with a smaller CSV file or use the merge option instead."
                            showingError = true
                        }
                    }
                } catch {
                    // Task was cancelled, this is expected
                }
            }
            
            // Disable iCloud sync during import
            persistenceController.container.viewContext.automaticallyMergesChangesFromParent = false
            needToRestoreSync = true
            
            // Create a child context to perform the import
            let importContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            importContext.parent = viewContext
            
            // Set a batch size for import context to improve performance
            importContext.shouldDeleteInaccessibleFaults = true
            
            do {
                // Get the total count from the status message if it's in the format "Creating new whiskeys (x-y of z)"
                var totalImportCount = 0
                var lastProgressUpdate = Date()
                
                try await CSVService.shared.importWhiskeys(
                    from: csvString, 
                    context: importContext, 
                    isFreshImport: isFreshImport,
                    progressHandler: { progress, status in
                        Task { @MainActor in
                            // Limit progress updates to reduce UI overhead - at most every 0.5 seconds
                            let now = Date()
                            if now.timeIntervalSince(lastProgressUpdate) >= 0.5 || progress >= 1.0 || progress == 0.0 {
                                self.importProgress = progress
                                
                                // Track metrics but don't show them in UI
                                let elapsedTime = now.timeIntervalSince(startTime)
                                let speed = progress > 0 ? String(format: "%.1f", progress / elapsedTime * 100) : "0"
                                
                                // Simplified status message without timing info
                                self.importStatusMessage = status
                                
                                lastProgressUpdate = now
                            }
                            
                            // Extract the total count from the status message if it contains the pattern "of X)"
                            if status.contains("of ") && status.contains(")") {
                                if let ofRange = status.range(of: "of "),
                                   let closingParenRange = status.range(of: ")", options: .backwards) {
                                    let startIndex = status.index(ofRange.upperBound, offsetBy: 0)
                                    let endIndex = status.index(closingParenRange.lowerBound, offsetBy: 0)
                                    let countString = status[startIndex..<endIndex].trimmingCharacters(in: .whitespaces)
                                    totalImportCount = Int(countString) ?? 0
                                }
                            }
                            
                            // If the import is complete
                            if progress >= 1.0 {
                                // Save changes from child context to parent
                                do {
                                    // Calculate final performance metrics (for logging only)
                                    let totalTime = Date().timeIntervalSince(startTime)
                                    let itemsPerSecond = totalImportCount > 0 ? 
                                        String(format: "%.1f", Double(totalImportCount) / totalTime) : "N/A"
                                    
                                    // Log the final metrics
                                    
                                    // Show saving progress
                                    self.importStatusMessage = "Saving changes..."
                                    
                                    // Save the changes - this is the most intensive operation
                                    try importContext.save()
                                    
                                    self.importStatusMessage = "Finalizing..."
                                    try viewContext.save()
                                    
                                    // Cancel the timeout task
                                    timeout.cancel()
                                    
                                    self.isLoading = false
                                    let countAfter = whiskeys.count
                                    
                                    // Log performance metrics but don't include in UI
                                    
                                    if isFreshImport {
                                        // Use the actual count from the progress message instead of the final count
                                        if totalImportCount > 0 {
                                            self.successMessage = "Successfully imported \(totalImportCount) whiskeys from CSV."
                                        } else {
                                            self.successMessage = "Successfully imported \(countAfter) whiskeys from CSV."
                                        }
                                    } else {
                                        let importedCount = countAfter - countBefore
                                        if importedCount > 0 {
                                            // Use the actual count from the progress message if available
                                            if totalImportCount > 0 {
                                                self.successMessage = "Successfully imported \(totalImportCount) whiskeys from CSV."
                                            } else {
                                                self.successMessage = "Successfully merged \(importedCount) whiskeys from CSV."
                                            }
                                        } else {
                                            self.successMessage = "CSV processed. All items were either already in your collection or updated."
                                        }
                                    }
                                    self.showingSuccess = true
                                    
                                    // Clear memory after a successful import
                                    self.clearMemory()
                                } catch {
                                    // Handle save error
                                    self.isLoading = false
                                    self.errorMessage = "Error saving imported data: \(error.localizedDescription)"
                                    self.showingError = true
                                }
                            }
                        }
                    }
                )
            } catch let error as CSVError {
                timeout.cancel()
                needToRestoreSync = false
                await handleCSVError(error)
            } catch {
                timeout.cancel()
                needToRestoreSync = false
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Import failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
        } catch {
            needToRestoreSync = false
            await MainActor.run {
                isLoading = false
                errorMessage = "Import preparation failed: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    private func handleCSVError(_ error: CSVError) async {
        await MainActor.run {
            isLoading = false
            
            // For permission errors, give the user options to solve the problem
            if error == .permissionError {
                // Create a detailed alert with multiple actions
                let alert = UIAlertController(
                    title: "Import Failed: Permission Error",
                    message: "BarrelBook couldn't save the imported data due to Core Data permission issues. You can try again later, or if the problem persists, you can reset the Core Data store, which will restart the app (your data will remain safe).",
                    preferredStyle: .alert
                )
                
                // Option 1: Just dismiss the error
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                
                // Option 2: Attempt to reload the Core Data container
                alert.addAction(UIAlertAction(title: "Reset Core Data & Retry", style: .destructive) { _ in
                    // Reset the Core Data stack and restart the app
                    self.resetCoreDataAndRestart()
                })
                
                // Show the alert
                if let topVC = UIApplication.topViewController() {
                    topVC.present(alert, animated: true)
                }
                
                HapticManager.shared.errorFeedback()
                return
            }
            
            // For other errors, show the regular alert
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                switch error {
                case .invalidData:
                    self.errorMessage = "The CSV file contains invalid data. Please check that all required fields (Name, Type, Proof, Distillery) are present and properly formatted."
                case .encodingError:
                    self.errorMessage = "There was a problem reading the CSV file. Please ensure it uses a supported encoding (UTF-8, ASCII, Latin1)."
                case .decodingError:
                    self.errorMessage = "There was a problem processing the CSV data. Please check that all fields are properly formatted."
                case .permissionError:
                    // This case is handled above
                    break
                }
                
                if error != .permissionError {
                    self.showingError = true
                    HapticManager.shared.errorFeedback()
                }
            }
            print("CSV specific error: \(error)")
        }
    }

    // Additional onAppear setup
    private func additionalSetup() {
        // Setup theme
        updateDisplayColorScheme()
        
        // Setup notifications
        setupExportNotification()
    }
    
    private func exportData() {
        HapticManager.shared.mediumImpact()
        
        // Print debug information
        
        // Generate export CSV data first
        if whiskeys.isEmpty {
            errorMessage = "No whiskeys to export. Add some whiskeys first."
            showingError = true
            HapticManager.shared.warningFeedback()
            return
        }
        
        do {
            let csvContent = try CSVService.shared.exportWhiskeys(Array(whiskeys))
            
            // Create a unique filename with timestamp
            let timestamp = Int(Date().timeIntervalSince1970)
            let filename = "BarrelBook-Export-\(timestamp).csv"
            
            // Use the app's Documents directory instead of temporary directory
            let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let tempDir = documentsDir.appendingPathComponent("TempExports", isDirectory: true)
            
            // Create the temp exports directory if it doesn't exist
            if !FileManager.default.fileExists(atPath: tempDir.path) {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            }
            
            let fileURL = tempDir.appendingPathComponent(filename)
            
            // Remove any existing file
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            
            // Write the CSV data
            try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Now show the document picker
            if let presentedVC = UIApplication.topViewController()?.presentedViewController {
                presentedVC.dismiss(animated: true) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.showExportDocumentPicker(with: fileURL)
                    }
                }
            } else {
                showExportDocumentPicker(with: fileURL)
            }
        } catch {
            print("Error generating export CSV: \(error)")
            errorMessage = "Failed to prepare CSV data: \(error.localizedDescription)"
            showingError = true
            HapticManager.shared.errorFeedback()
        }
    }
    
    private func showExportDocumentPicker(with fileURL: URL) {
        
        // Create and configure the document picker
        let picker = UIDocumentPickerViewController(forExporting: [fileURL])
        
        // Create a delegate to handle the result
        class PickerDelegate: NSObject, UIDocumentPickerDelegate {
            func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
                guard let url = urls.first else { return }
                
                // Post success message
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("CSVExportSuccessful"),
                        object: url.lastPathComponent
                    )
                    HapticManager.shared.successFeedback()
                }
            }
            
            func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            }
        }
        
        // Create and keep a reference to the delegate
        let delegate = PickerDelegate()
        picker.delegate = delegate
        
        // Store the delegate in the picker to keep it alive
        objc_setAssociatedObject(picker, "exportDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        
        // Present the picker
        if let rootViewController = UIApplication.topViewController() {
            rootViewController.present(picker, animated: true) {
            }
        }
    }
    
    // MARK: - CSV Sync Functions
    
    // MARK: - CSV Template Creation
    
    private func showTemplateInfo() {
        showingTemplateAlert = true
    }
    
    private func createCSVTemplate() {
        
        // Generate CSV and README content
        let csvContent = createTemplateCSVString()
        let readmeContent = createTemplateReadmeString()
        
        // Create a zip file with the contents
        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "BarrelBook_Template_\(timestamp).zip"
        
        do {
            // Use the app's Documents directory instead of temporary directory
            let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let tempDir = documentsDir.appendingPathComponent("TempExports", isDirectory: true)
            
            // Create the temp exports directory if it doesn't exist
            if !FileManager.default.fileExists(atPath: tempDir.path) {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            }
            
            let zipURL = tempDir.appendingPathComponent(filename)
            
            // Remove existing file if it exists
            if FileManager.default.fileExists(atPath: zipURL.path) {
                try FileManager.default.removeItem(at: zipURL)
            }
            
            // Create a temporary directory to hold our files
            let tempFilesDir = tempDir.appendingPathComponent("temp_files_\(timestamp)")
            try FileManager.default.createDirectory(at: tempFilesDir, withIntermediateDirectories: true)
            
            // Write CSV file
            let csvURL = tempFilesDir.appendingPathComponent("BarrelBook_Template.csv")
            try csvContent.write(to: csvURL, atomically: true, encoding: .utf8)
            
            // Write README file
            let readmeURL = tempFilesDir.appendingPathComponent("SyncingBarrelBookwithCSVReadMe.txt")
            try readmeContent.write(to: readmeURL, atomically: true, encoding: .utf8)
            
            // Create ZIP file using NSFileWrapper
            let rootWrapper = FileWrapper(directoryWithFileWrappers: [:])
            
            // Add CSV file to wrapper
            if let csvData = try? Data(contentsOf: csvURL) {
                let csvWrapper = FileWrapper(regularFileWithContents: csvData)
                csvWrapper.preferredFilename = "BarrelBook_Template.csv"
                rootWrapper.addFileWrapper(csvWrapper)
            }
            
            // Add README file to wrapper
            if let readmeData = try? Data(contentsOf: readmeURL) {
                let readmeWrapper = FileWrapper(regularFileWithContents: readmeData)
                readmeWrapper.preferredFilename = "SyncingBarrelBookwithCSVReadMe.txt"
                rootWrapper.addFileWrapper(readmeWrapper)
            }
            
            // Write the ZIP file
            try rootWrapper.write(to: zipURL, options: .atomic, originalContentsURL: nil)
            
            // Clean up temporary directory
            try FileManager.default.removeItem(at: tempFilesDir)
            
            
            // Use DispatchQueue to ensure we're not presenting on top of another presentation
            DispatchQueue.main.async {
                // Find the top view controller
                guard let rootViewController = UIApplication.topViewController() else {
                    print("⚠️ Failed to find top view controller for template export")
                    return
                }
                
                // Create and configure the document picker
                let picker = UIDocumentPickerViewController(forExporting: [zipURL])
                
                // Create a delegate to handle the result
                class PickerDelegate: NSObject, UIDocumentPickerDelegate {
                    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
                        guard let url = urls.first else { return }
                        
                        // Post success message
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("TemplateExportSuccessful"),
                                object: url.lastPathComponent
                            )
                            HapticManager.shared.successFeedback()
                        }
                    }
                    
                    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
                    }
                }
                
                // Create and keep a reference to the delegate
                let delegate = PickerDelegate()
                picker.delegate = delegate
                
                // Store the delegate in the picker to keep it alive
                objc_setAssociatedObject(picker, "templateDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
                
                // Present the picker
                rootViewController.present(picker, animated: true) {
                }
            }
        } catch {
            print("⚠️ Error creating template zip: \(error)")
            errorMessage = "Failed to create template: \(error.localizedDescription)"
            showingError = true
            HapticManager.shared.errorFeedback()
        }
    }
    
    private func escapeCSVField(_ field: String) -> String {
        // Escape quotes and wrap in quotes if needed
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            let escapedField = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escapedField)\""
        }
        return field
    }
    
    private func formatISODate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func formatDateWithTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: date)
    }
    
    private func createTemplateCSVString() -> String {
        // Define headers to match the import/export format
        let headers = [
            "Name", "Type", "Proof", "Age", "Distillery", 
            "Finish", "Cask Strength?", "BiB", "SiB", "SP", 
            "SP Name", "Current # of Bottles", "Open Bottles", "Dead Bottles",
            "Bottle Notes", "Average Price", "Tasted?", "External Reviews"
        ]
        
        // Create sample data rows with the new format
        let sampleRows = [
            [
                "Buffalo Trace", 
                "Bourbon", 
                "90.0",
                "", // Age
                "Buffalo Trace Distillery",
                "", // Finish
                "No", // Cask Strength?
                "No", // BiB
                "No", // SiB
                "No", // SP
                "", // SP Name
                "2", // Current # of Bottles
                "1", // Open Bottles
                "1", // Dead Bottles
                "Great everyday bourbon", // Bottle Notes
                "29.99", // Average Price
                "Yes", // Tasted?
                "" // External Reviews
            ],
            [
                "Lagavulin 16", 
                "Scotch", 
                "86.0",
                "16", 
                "Lagavulin",
                "Sherry", // Finish
                "No", // Cask Strength?
                "No", // BiB
                "No", // SiB
                "No", // SP
                "", // SP Name
                "1", // Current # of Bottles
                "1", // Open Bottles
                "0", // Dead Bottles
                "Classic Islay scotch with rich smoke and sea salt notes", // Bottle Notes
                "99.99", // Average Price
                "Yes", // Tasted?
                "https://www.whiskybase.com/whiskies/whisky/288/lagavulin-16-year-old" // External Reviews
            ],
            [
                "Blanton's", 
                "Bourbon", 
                "93.0",
                "", // Age
                "Buffalo Trace Distillery",
                "", // Finish
                "No", // Cask Strength?
                "No", // BiB
                "Yes", // SiB
                "No", // SP
                "", // SP Name
                "0", // Current # of Bottles
                "0", // Open Bottles
                "1", // Dead Bottles
                "Finished bottle", // Bottle Notes
                "65.99", // Average Price
                "Yes", // Tasted?
                "" // External Reviews
            ]
        ]
        
        // Create CSV content with UTF-8 BOM for proper character encoding
        var csvContent = "\u{FEFF}" + headers.joined(separator: ",") + "\n"
        
        // Add sample rows
        for row in sampleRows {
            csvContent += row.joined(separator: ",") + "\n"
        }
        
        return csvContent
    }
    
    private func createTemplateReadmeString() -> String {
        var readmeContent = "# BarrelBook CSV Template Guide\n\n"
        readmeContent += "This guide explains how to format your whiskey collection data for importing into BarrelBook.\n\n"
        readmeContent += "## Field Descriptions\n\n"
        readmeContent += "### Basic Information\n"
        readmeContent += "- Name: The name of the whiskey\n"
        readmeContent += "- Type: Bourbon, Rye, Scotch, Irish, etc.\n"
        readmeContent += "- Proof: The alcohol proof (use decimal point if needed)\n"
        readmeContent += "- Age: The age statement (leave empty if no age statement)\n"
        readmeContent += "- Distillery: The name of the distillery\n"
        readmeContent += "- Finish: Any finish applied to the whiskey (e.g., 'Sherry', 'Port', etc.)\n\n"
        
        readmeContent += "### Special Designations\n"
        readmeContent += "For these fields, use 'Yes' (or 'Y', case doesn't matter) or leave empty:\n"
        readmeContent += "- Cask Strength?: Is it cask/barrel strength?\n"
        readmeContent += "- BiB: Is it Bottled in Bond?\n"
        readmeContent += "- SiB: Is it Single Barrel?\n"
        readmeContent += "- SP: Is it a Store Pick?\n"
        readmeContent += "- SP Name: The name of the store pick (if applicable)\n\n"
        
        readmeContent += "### Bottle Tracking\n"
        readmeContent += "- Current # of Bottles: How many active bottles you currently have (defaults to 1 if empty)\n"
        readmeContent += "- Open Bottles: How many of your current bottles are open (defaults to 0 if empty)\n"
        readmeContent += "- Dead Bottles: How many bottles you've finished (defaults to 0 if empty)\n\n"
        
        readmeContent += "Example scenarios:\n"
        readmeContent += "1. One sealed bottle: Current=1 (or empty), Open=0 (or empty), Dead=0 (or empty)\n"
        readmeContent += "2. One open bottle: Current=1 (or empty), Open=1, Dead=0 (or empty)\n"
        readmeContent += "3. Two bottles (one open) plus one finished: Current=2, Open=1, Dead=1\n"
        readmeContent += "4. All bottles finished: Current=0, Open=0, Dead=1 (or more)\n\n"
        
        readmeContent += "### Additional Information\n"
        readmeContent += "- Bottle Notes: Any notes about this whiskey\n"
        readmeContent += "- Average Price: The average price paid across all bottles\n"
        readmeContent += "- Tasted?: Have you tasted this whiskey? (use 'Yes'/'Y' or leave empty)\n"
        readmeContent += "- External Reviews: Links to reviews or notes about reviews\n\n"
        
        readmeContent += "## Important Notes\n\n"
        readmeContent += "1. Required Fields: Name, Type, Proof, and Distillery must have values\n"
        readmeContent += "2. Yes/No Fields:\n"
        readmeContent += "   - Use 'Yes', 'Y', or leave empty (case doesn't matter)\n"
        readmeContent += "   - 'YES', 'yes', 'Y', and 'y' all work\n"
        readmeContent += "   - Empty fields are treated as 'No'\n"
        readmeContent += "3. Numbers:\n"
        readmeContent += "   - Proof should be a decimal number (e.g., 90.0, 114.2)\n"
        readmeContent += "   - Bottle counts should be whole numbers\n"
        readmeContent += "   - Average Price should be a decimal number\n"
        readmeContent += "4. Open Bottles cannot exceed Current # of Bottles\n"
        readmeContent += "5. Leave Age empty if there's no age statement\n\n"
        
        readmeContent += "The included template.csv file shows examples of different scenarios to help you understand the format.\n"
        
        return readmeContent
    }
    
    // Update the direct document picker presentation method
    private func showDirectDocumentPicker(csvData: String, filename: String, completion: @escaping (URL) -> Void) {
        
        // Create temporary file in Documents directory
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let tempDir = documentsDir.appendingPathComponent("TempExports", isDirectory: true)
        
        // Create the temp exports directory if it doesn't exist
        do {
            if !FileManager.default.fileExists(atPath: tempDir.path) {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
            }
            
            let fileURL = tempDir.appendingPathComponent(filename)
            
            // Remove any existing file
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            
            // Write the CSV data using coordinated file access
            Task {
                do {
                    try await CSVSyncService.shared.writeToFile(at: fileURL, content: csvData)
                    
                    // Continue with showing the document picker on the main thread
                    await MainActor.run {
                        // Use a more robust way to present the picker
                        // Find the top-most presented view controller
                        guard let rootViewController = UIApplication.topViewController() else {
                            print("⚠️ Failed to find top view controller")
                            return
                        }
                        
                        // Create and present the document picker controller
                        let picker = UIDocumentPickerViewController(forExporting: [fileURL])
                        
                        // Create a delegate to handle the result
                        class PickerDelegate: NSObject, UIDocumentPickerDelegate {
                            let completion: (URL) -> Void
                            
                            init(completion: @escaping (URL) -> Void) {
                                self.completion = completion
                                super.init()
                            }
                            
                            func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
                                guard let url = urls.first else { return }
                                completion(url)
                            }
                            
                            func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
                            }
                        }
                        
                        // Create and keep a reference to the delegate
                        let delegate = PickerDelegate(completion: completion)
                        picker.delegate = delegate
                        
                        // Store the delegate in the picker to keep it alive
                        objc_setAssociatedObject(picker, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
                        
                        rootViewController.present(picker, animated: true) {
                        }
                    }
                } catch {
                    print("⚠️ Failed to create temp file: \(error)")
                    await MainActor.run {
                        errorMessage = "Failed to create temporary file: \(error.localizedDescription)"
                        showingError = true
                    }
                }
            }
        } catch {
            print("⚠️ Failed to create temp directory: \(error)")
            errorMessage = "Failed to create temporary directory: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    // Update showDocumentPickerAfterAlert with longer delay
    private func showDocumentPickerAfterAlert(forTemplate: Bool = false) {
        // Debug the current presentation hierarchy
        
        // Use a longer delay to ensure alert is fully dismissed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            
            // Check again if there are any presentations still active
            if let presentedVC = UIApplication.topViewController()?.presentedViewController {
                presentedVC.dismiss(animated: true) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.showAppropriateDocumentPicker(forTemplate: forTemplate)
                    }
                }
            } else {
                self.showAppropriateDocumentPicker(forTemplate: forTemplate)
            }
        }
    }
    
    // Helper to show the appropriate document picker based on the context
    private func showAppropriateDocumentPicker(forTemplate: Bool) {
        if forTemplate {
            // Don't call createCSVTemplate here since it's called directly now
            return
        }
        
        // Handle export
        if self.whiskeys.isEmpty {
            self.errorMessage = "No whiskeys to export. Add some whiskeys first."
            self.showingError = true
            HapticManager.shared.warningFeedback()
            return
        }
        
        do {
            let csvContent = try CSVService.shared.exportWhiskeys(Array(self.whiskeys))
            
            // Generate a unique filename with timestamp
            let timestamp = Int(Date().timeIntervalSince1970)
            let filename = "BarrelBook-Export-\(timestamp).csv"
            
            // Use direct document picker
            self.showDirectDocumentPicker(csvData: csvContent, filename: filename) { url in
                // Handle export completion
                DispatchQueue.main.async {
                    self.successMessage = "CSV file exported successfully: \(url.lastPathComponent)"
                    self.showingSuccess = true
                    HapticManager.shared.successFeedback()
                }
            }
        } catch {
            print("⚠️ Error generating export CSV: \(error)")
            self.errorMessage = "Failed to prepare CSV data: \(error.localizedDescription)"
            self.showingError = true
            HapticManager.shared.errorFeedback()
        }
    }
    
    // MARK: - CSV Info Functions
    
    private func showDemoSpreadsheetInfo() {
        HapticManager.shared.selectionFeedback()
        let infoMessage = """
        This option is ideal for new users or anyone who wants to understand the sync process. It provides a sample spreadsheet with the correct format and a detailed guide explaining how to enter and manage your collection data.
        
        Choose this if you're setting up spreadsheet sync for the first time and want guidance on the proper format.
        """
        
        showInfoAlert(title: "About Demo Spreadsheet", message: infoMessage)
    }

    private func showExistingSyncInfo() {
        HapticManager.shared.selectionFeedback()
        let infoMessage = """
        This option is ideal for users who already have a properly formatted CSV file containing their whiskey collection data. 
        
        This is perfect for users who already have their own spreadsheets. Before doing this, please first download the sample spreadsheet so you can see how to organize your current spreadsheet for use with BarrelBook.
        """
        
        showInfoAlert(title: "About Sync with Existing File", message: infoMessage)
    }

    private func showCreateSyncInfo() {
        HapticManager.shared.selectionFeedback()
        let infoMessage = """
        Choose this option if you do not already have a spreadsheet and are starting "fresh." 

        When you select this option, the app exports your current collection to a new CSV file (at your chosen location), and that file will remain linked to the app, allowing changes made in either place to stay synchronized.
        """
        
        showInfoAlert(title: "About Create Sync File", message: infoMessage)
    }

    // Helper method to show info alerts
    private func showInfoAlert(title: String, message: String) {
        let alert = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        // Find the top view controller and present the alert
        if let topVC = UIApplication.topViewController() {
            topVC.present(alert, animated: true)
        }
    }


    
    // MARK: - Safe Alert Handling
    
    // Helper method to safely show alerts without overlap
    private func safelyShowAlert(type: AlertType, message: String) {
        // First, clear any existing alerts to avoid multiple alerts showing simultaneously
        if showingError || showingSuccess {
            showingError = false
            showingSuccess = false
            
            // Add a small delay to ensure previous alerts are dismissed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.displayAlert(type: type, message: message)
            }
        } else {
            // No existing alerts, show immediately
            displayAlert(type: type, message: message)
        }
    }
    
    private enum AlertType {
        case error
        case success
    }
    
    private func displayAlert(type: AlertType, message: String) {
        switch type {
        case .error:
            errorMessage = message
            showingError = true
            HapticManager.shared.errorFeedback()
        case .success:
            successMessage = message
            showingSuccess = true
            HapticManager.shared.successFeedback()
        }
    }

    // Add a method to reset Core Data and restart the app
    private func resetCoreDataAndRestart() {
        // First, reset Core Data
        PersistenceController.shared.resetAllObjects()
        
        // Show a confirmation message
        let alert = UIAlertController(
            title: "Core Data Reset",
            message: "Core Data has been reset. The app will now restart. This should fix permission issues with importing CSV files.",
            preferredStyle: .alert
        )
        
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            // Force a termination and restart
            exit(0)
        })
        
        // Show the confirmation
        if let topVC = UIApplication.topViewController() {
            topVC.present(alert, animated: true)
        }
    }
    
    private func setupConflictHandling() {
        NotificationCenter.default.addObserver(
            forName: .csvImportConflict,
            object: nil,
            queue: .main
        ) { notification in
            guard let message = notification.userInfo?["message"] as? String,
                  let whiskey = notification.userInfo?["whiskey"] as? String,
                  let continuation = notification.userInfo?["continuation"] as? CheckedContinuation<Bool, Never>
            else { return }
            
            self.conflictMessage = message
            self.conflictWhiskey = whiskey
            self.conflictContinuation = continuation
            self.showingConflict = true
        }
    }

    // Add this emergency cleanup function
    private func emergencyCleanupJournalEntries() {
        // Get a reference to the managed object context
        let context = viewContext
        
        // Create a batch delete request for the JournalEntry entity
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "JournalEntry")
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        
        // Configure the request to get object IDs back
        batchDeleteRequest.resultType = .resultTypeObjectIDs
        
        do {
            
            // Execute the batch delete
            let batchDelete = try context.execute(batchDeleteRequest) as? NSBatchDeleteResult
            let objectIDArray = batchDelete?.result as? [NSManagedObjectID] ?? []
            
            // Merge the changes into our context
            let changes = [NSDeletedObjectsKey: objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
            
            // Save the context to persist changes
            try context.save()
            
            successMessage = "Successfully deleted \(objectIDArray.count) journal entries."
            showingSuccess = true
            HapticManager.shared.successFeedback()
        } catch {
            print("Error during emergency cleanup: \(error)")
            errorMessage = "Error deleting entries: \(error.localizedDescription)"
            showingError = true
            HapticManager.shared.errorFeedback()
        }
    }

    // Add this function alongside the other debug functions
    private func directDeleteAllJournalEntries() async {
        // Get the persistent store coordinator and create a new private context for batch operations
        guard let coordinator = viewContext.persistentStoreCoordinator else {
            print("⚠️ No persistent store coordinator available")
            return
        }
        
        let privateContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        privateContext.persistentStoreCoordinator = coordinator
        
        // First approach: Using batch delete
        do {
            
            // Create a fetch request for all journal entries
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "JournalEntry")
            fetchRequest.includesPropertyValues = false // Don't fetch properties, just IDs for speed
            
            // Create and configure the batch delete request
            let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            batchDeleteRequest.resultType = .resultTypeCount // Just return the count
            
            // Execute the request in the private context
            let result = try privateContext.execute(batchDeleteRequest) as? NSBatchDeleteResult
            let count = result?.result as? Int ?? 0
            
            
            // Save the private context
            try privateContext.save()
            
            // Also try the direct fetch and delete approach as a backup
            let directFetchRequest = NSFetchRequest<NSManagedObject>(entityName: "JournalEntry")
            let entries = try viewContext.fetch(directFetchRequest)
            
            if !entries.isEmpty {
                
                for entry in entries {
                    viewContext.delete(entry)
                }
                
                try viewContext.save()
            }
            
            // Force a cross-context refresh
            viewContext.reset()
            
            // Final check
            let verifyRequest = NSFetchRequest<NSManagedObject>(entityName: "JournalEntry")
            let remainingCount = try viewContext.count(for: verifyRequest)
            
            
            // Show success or failure message
            await MainActor.run {
                if remainingCount == 0 {
                    successMessage = "Successfully deleted all \(count) journal entries!"
                    showingSuccess = true
                } else {
                    errorMessage = "Deleted \(count) entries but \(remainingCount) still remain."
                    showingError = true
                }
            }
        } catch {
            print("⚠️ ERROR DURING DIRECT DELETION: \(error)")
            
            await MainActor.run {
                errorMessage = "Error during deletion: \(error.localizedDescription)"
                showingError = true
            }
        }
    }

    // Add this function to delete the entire collection
    private func deleteEntireCollection() {
        do {
            let context = viewContext
            
            // Delete all whiskeys
            let whiskeys = try context.fetch(Whiskey.fetchRequest())
            
            for whiskey in whiskeys {
                context.delete(whiskey)
            }
            
            // Delete all journal entries
            let journalFetchRequest: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "JournalEntry")
            let journalEntries = try context.fetch(journalFetchRequest)
            
            for entry in journalEntries {
                context.delete(entry)
            }
            
            // Save changes
            try context.save()
            
            successMessage = "Successfully deleted all whiskeys and journal entries."
            showingSuccess = true
            HapticManager.shared.successFeedback()
            
        } catch {
            print("Error deleting collection: \(error)")
            errorMessage = "Error deleting collection: \(error.localizedDescription)"
            showingError = true
            HapticManager.shared.errorFeedback()
        }
    }

    private func deleteFavoriteStores(offsets: IndexSet) {
        withAnimation {
            offsets.map { favoriteStores[$0] }.forEach { store in
                store.isFavorite = false
            }
            
            do {
                try viewContext.save()
            } catch {
                let nsError = error as NSError
                fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
            }
        }
    }

    private func getNearbyStores() -> [Store] {
        guard let userLocation = locationManager.location else { return [] }
        return favoriteStores.filter { store in
            let storeLocation = CLLocation(latitude: store.latitude, longitude: store.longitude)
            return userLocation.distance(from: storeLocation) <= 32186.9 // 20 miles
        }
    }
    
    private func getOtherStores() -> [Store] {
        guard let userLocation = locationManager.location else { return Array(favoriteStores) }
        return favoriteStores.filter { store in
            let storeLocation = CLLocation(latitude: store.latitude, longitude: store.longitude)
            return userLocation.distance(from: storeLocation) > 32186.9 // 20 miles
        }
    }

    // Add this method to safely create new whiskeys
    // Add a function to run the bottle numbering fix
    private func fixBottleNumbering() {
        // Show loading indicator
        isLoading = true
        importProgress = 0.0
        importStatusMessage = "Fixing bottle numbering..."
        
        // Run the fix in a background task
        Task {
            do {
                // Create a service instance
                let csvService = CSVService.shared
                
                // Call the fix method
                await MainActor.run {
                    importProgress = 0.3
                    importStatusMessage = "Analyzing bottles..."
                }
                
                // Process the fix
                try await Task.sleep(nanoseconds: 500_000_000) // Small delay for UI feedback
                
                await MainActor.run {
                    importProgress = 0.6
                    importStatusMessage = "Renumbering bottles..."
                }
                
                csvService.fixBottleNumberingPublic(in: viewContext)
                
                await MainActor.run {
                    importProgress = 1.0
                    importStatusMessage = "Saving changes..."
                }
                
                // Short delay to show completion
                try await Task.sleep(nanoseconds: 500_000_000)
                
                // Show success message
                await MainActor.run {
                    isLoading = false
                    successMessage = "Bottle numbering fixed successfully!"
                    showingSuccess = true
                    HapticManager.shared.successFeedback()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Error fixing bottle numbering: \(error.localizedDescription)"
                    showingError = true
                    HapticManager.shared.errorFeedback()
                }
            }
        }
    }
    
    private func safeCreateWhiskey(name: String, bottles: Int = 1) {
        do {
            // Create a new managed object context for this operation
            let privateContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            privateContext.parent = viewContext
            
            // Perform the operation on the private context
            try privateContext.performAndWait {
                let whiskey = Whiskey(context: privateContext)
                whiskey.name = name
                whiskey.numberOfBottles = Int16(bottles)
                whiskey.isOpen = false
                whiskey.isFinished = 0
                whiskey.addedDate = Date()
                
                // Create bottle instances
                for i in 0..<bottles {
                    let bottle = BottleInstance(context: privateContext)
                    bottle.id = UUID()
                    bottle.dateAdded = Date()
                    bottle.isOpen = false
                    bottle.isDead = false
                    bottle.bottleNumber = Int16(i + 1)
                    bottle.whiskey = whiskey
                }
            }
            
            // Save the parent context only once after all operations are complete
            if viewContext.hasChanges {
                try viewContext.save()
            }
            
        } catch {
            print("❌ Error creating whiskey: \(error)")
            errorMessage = "Failed to create whiskey: \(error.localizedDescription)"
            showingError = true
            HapticManager.shared.errorFeedback()
        }
    }

    // Add this method to safely handle context operations
    private func safeContextOperation(_ operation: @escaping (NSManagedObjectContext) throws -> Void) {
        do {
            // Create a private context for the operation
            let privateContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            privateContext.parent = viewContext
            
            // Perform the operation on the private context
            try privateContext.performAndWait {
                try operation(privateContext)
                
                // Save the private context
                if privateContext.hasChanges {
                    try privateContext.save()
                }
            }
            
            // Save the parent context
            if viewContext.hasChanges {
                try viewContext.save()
            }
        } catch {
            print("❌ Error in context operation: \(error)")
            errorMessage = "Operation failed: \(error.localizedDescription)"
            showingError = true
            HapticManager.shared.errorFeedback()
        }
    }

    // Helper method to clear memory
    private func clearMemory() {
        // Force a cleanup of memory
        #if DEBUG
        #endif
        
        // Recommend system-level memory cleanup
        URLCache.shared.removeAllCachedResponses()
        
        // Use autoreleasepool to help release objects
        autoreleasepool {
            // Empty autorelease pool helps flush retained objects
        }
        
        // We can't directly trigger memory warnings in iOS apps,
        // but we can suggest garbage collection
        if #available(iOS 15.0, *) {
            // Use Task for structured concurrency on newer iOS
            Task {
                // Empty task that encourages system cleanup during the suspension point
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        } else {
            // On older iOS, use a brief DispatchQueue delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Empty completion handler
            }
        }
    }

    // Add the new deletion functions:
    private func deleteOwnedCollection() {
        do {
            let context = viewContext
            let fetchRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "status == %@ OR status == nil", "owned")
            let ownedWhiskeys = try context.fetch(fetchRequest)
            for whiskey in ownedWhiskeys {
                context.delete(whiskey)
            }
            try context.save()
            successMessage = "Successfully deleted all owned whiskeys."
            showingSuccess = true
            HapticManager.shared.successFeedback()
        } catch {
            errorMessage = "Error deleting owned whiskeys: \(error.localizedDescription)"
            showingError = true
            HapticManager.shared.errorFeedback()
        }
    }

    private func deleteAllTastingData() {
        do {
            let context = viewContext
            let fetchRequest: NSFetchRequest<JournalEntry> = JournalEntry.fetchRequest()
            let entries = try context.fetch(fetchRequest)
            for entry in entries {
                context.delete(entry)
            }
            try context.save()
            successMessage = "Successfully deleted all tasting data."
            showingSuccess = true
            HapticManager.shared.successFeedback()
        } catch {
            errorMessage = "Error deleting tasting data: \(error.localizedDescription)"
            showingError = true
            HapticManager.shared.errorFeedback()
        }
    }

    private func deleteAllInfinityBottles() {
        do {
            let context = viewContext
            let fetchRequest: NSFetchRequest<InfinityBottle> = InfinityBottle.fetchRequest()
            let bottles = try context.fetch(fetchRequest)
            for bottle in bottles {
                context.delete(bottle)
            }
            try context.save()
            successMessage = "Successfully deleted all infinity bottles."
            showingSuccess = true
            HapticManager.shared.successFeedback()
        } catch {
            errorMessage = "Error deleting infinity bottles: \(error.localizedDescription)"
            showingError = true
            HapticManager.shared.errorFeedback()
        }
    }

    private func deleteWishlistAndReplacementBottles() {
        do {
            let context = viewContext
            let fetchRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "status == %@ OR status == %@", "wishlist", "replacement")
            let whiskeys = try context.fetch(fetchRequest)
            for whiskey in whiskeys {
                context.delete(whiskey)
            }
            try context.save()
            successMessage = "Successfully deleted all wishlist and replacement bottles."
            showingSuccess = true
            HapticManager.shared.successFeedback()
        } catch {
            errorMessage = "Error deleting wishlist/replacement bottles: \(error.localizedDescription)"
            showingError = true
            HapticManager.shared.errorFeedback()
        }
    }

    private func deleteAllData() {
        do {
            let context = viewContext
            // Delete all whiskeys
            let whiskeys = try context.fetch(Whiskey.fetchRequest())
            for whiskey in whiskeys {
                context.delete(whiskey)
            }
            // Delete all journal entries
            let journalEntries = try context.fetch(JournalEntry.fetchRequest())
            for entry in journalEntries {
                context.delete(entry)
            }
            // Delete all infinity bottles
            let infinityBottles = try context.fetch(InfinityBottle.fetchRequest())
            for bottle in infinityBottles {
                context.delete(bottle)
            }
            try context.save()
            successMessage = "Successfully deleted ALL data."
            showingSuccess = true
            HapticManager.shared.successFeedback()
        } catch {
            errorMessage = "Error deleting all data: \(error.localizedDescription)"
            showingError = true
            HapticManager.shared.errorFeedback()
        }
    }
    
    /// Deletes all data then seeds a demo collection, tastings, and wishlist for trying the app or screenshots.
    private func loadDemoData() {
        DemoDataService.load(context: viewContext) { result in
            switch result {
            case .success:
                self.successMessage = "Demo data loaded. You now have a sample collection, tastings, and wishlist."
                self.showingSuccess = true
                HapticManager.shared.successFeedback()
            case .failure(let error):
                self.errorMessage = "Error loading demo data: \(error.localizedDescription)"
                self.showingError = true
                HapticManager.shared.errorFeedback()
            }
        }
    }

        // MARK: - Subscription Status View
    
    @ViewBuilder
    private var subscriptionStatusView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: subscriptionManager.isSubscribed ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(subscriptionManager.isSubscribed ? .green : .blue)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(subscriptionStatusText)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(subscriptionDetailText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
            
            if !subscriptionManager.isSubscribed {
                Button(action: { showingPaywall = true }) {
                    Text("Unlock Premium")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(ColorManager.primaryBrandColor)
                        .cornerRadius(8)
                }
                Button(action: restorePurchasesFromSettings) {
                    Text("Restore Purchases")
                        .font(.subheadline)
                        .foregroundColor(ColorManager.primaryBrandColor)
                }
            }
        }
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallView(isPresented: $showingPaywall)
        }
    }
    
    private var subscriptionStatusText: String {
        subscriptionManager.isSubscribed ? "BarrelBook Premium" : "BarrelBook Essentials"
    }
    
    private var subscriptionDetailText: String {
        if subscriptionManager.isSubscribed {
            return "Unlimited whiskeys, tastings, and premium features"
        } else {
            return "10 whiskeys • 5 tastings/month • Basic stats"
        }
    }
    
    private func restorePurchasesFromSettings() {
        Task {
            await subscriptionManager.restorePurchases()
        }
    }
}

// MARK: - Custom Document Picker
struct DocumentPicker: UIViewControllerRepresentable {
    var supportedTypes: [UTType]
    let onPick: (URL) -> Void
    
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Use asCopy: true to make a copy of the file in the app's temporary directory
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = false
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url)
        }
    }
}

// First, improve the DocumentPickerExport to handle both normal exports and sync file creation
struct DocumentPickerExport: UIViewControllerRepresentable {
    var csvData: String?
    var filename: String
    var onComplete: ((URL) -> Void)?
    
    init(csvData: String?, filename: String = "BarrelBook-Export.csv", onComplete: ((URL) -> Void)? = nil) {
        self.csvData = csvData
        self.filename = filename
        self.onComplete = onComplete
    }
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Create a temporary file with the CSV data
        let tempURL = createTempCSVFile()
        
        // Create a document picker in export mode - use exportToService instead of forExporting:asCopy:
        let controller = UIDocumentPickerViewController(forExporting: [tempURL])
        controller.delegate = context.coordinator
        controller.modalPresentationStyle = .fullScreen
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // Create a temporary CSV file for export
    private func createTempCSVFile() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        
        // Remove any existing file
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        
        // We need to use a synchronized approach since this method is not async
        let semaphore = DispatchSemaphore(value: 0)
        
        if let csvDataContent = csvData {
            Task.detached {
                do {
                    try await CSVSyncService.shared.writeToFile(at: fileURL, content: csvDataContent)
                } catch {
                    print("⚠️ Error creating temporary CSV file: \(error)")
                }
                semaphore.signal()
            }
            
            // Wait for the async operation to complete
            _ = semaphore.wait(timeout: .now() + 5) // 5 second timeout
        } else {
            print("⚠️ No CSV data available to write")
        }
        
        return fileURL
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPickerExport
        
        init(_ parent: DocumentPickerExport) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { 
                print("⚠️ Document picker returned no URLs")
                return 
            }
            
            
            // Call the completion handler if provided
            if let onComplete = parent.onComplete {
                onComplete(url)
            } else {
                // Otherwise post the default notification
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("CSVExportSuccessful"),
                        object: nil
                    )
                    HapticManager.shared.successFeedback()
                }
            }
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        }
    }
}

// Extension to handle export success notification
extension SettingsView {
    // Setup for export and conflict notification handling
    private func setupExportNotification() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CSVExportSuccessful"),
            object: nil,
            queue: .main
        ) { _ in
            self.successMessage = "CSV file exported successfully"
            self.showingSuccess = true
        }
        
        // Add observer for template export success
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TemplateExportSuccessful"),
            object: nil,
            queue: .main
        ) { notification in
            if let filename = notification.object as? String {
                self.successMessage = "Template files saved as \(filename)"
            } else {
                self.successMessage = "Template files saved successfully"
            }
            self.showingSuccess = true
        }
    }
}

// MARK: - Helper Extensions

// Helper extension to present alerts from anywhere in the app
extension UIApplication {
    static func showAlert(title: String, message: String, actions: [UIAlertAction]) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            let alert = UIAlertController(
                title: title,
                message: message, 
                preferredStyle: .alert
            )
            
            for action in actions {
                alert.addAction(action)
            }
            
            rootVC.present(alert, animated: true)
        }
    }
}

// Add a helper extension for finding the top view controller
extension UIApplication {
    static func topViewController(base: UIViewController? = nil) -> UIViewController? {
        // Get the base view controller (root if not provided)
        let baseVC = base ?? UIApplication.shared.windows.filter {$0.isKeyWindow}.first?.rootViewController
        
        // Handle navigation controller
        if let nav = baseVC as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        
        // Handle tab bar controller
        if let tab = baseVC as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(base: selected)
        }
        
        // Handle presented controller
        if let presented = baseVC?.presentedViewController {
            return topViewController(base: presented)
        }
        
        return baseVC
    }
}

// MARK: - Loading Overlay Extensions
extension View {
    func loadingOverlay(isShowing: Bool) -> some View {
        self.modifier(LoadingOverlay(isShowing: isShowing))
    }
}

struct LoadingOverlay: ViewModifier {
    let isShowing: Bool
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if isShowing {
                Color.black.opacity(0.3)
                    .edgesIgnoringSafeArea(.all)
                
                VStack {
                    ProgressView()
                        .scaleEffect(1.2)
                        .padding()
                    Text("Loading...")
                        .foregroundColor(.white)
                }
                .frame(width: 120, height: 120)
                .background(Color(.systemBackground))
                .cornerRadius(10)
                .shadow(radius: 10)
            }
        }
    }
} 
