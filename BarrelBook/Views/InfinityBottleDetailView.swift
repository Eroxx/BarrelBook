import SwiftUI
import CoreData

struct InfinityBottleDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @ObservedObject var bottle: InfinityBottle
    
    @State private var showingAddWhiskeySheet = false
    @State private var showingEditBottleSheet = false
    @State private var showingAddTastingSheet = false
    @State private var selectedTab = 0
    
    // Computed properties for summary information
    private var currentProof: Double {
        guard let additions = bottle.additions as? Set<BottleAddition>, !additions.isEmpty else {
            return 0.0
        }
        
        let totalVolume = additions.reduce(0) { $0 + $1.amount }
        let weightedProof = additions.reduce(0) { $0 + ($1.amount * $1.proof) }
        
        return totalVolume > 0 ? weightedProof / totalVolume : 0
    }
    
    private var totalVolume: Double {
        guard let additions = bottle.additions as? Set<BottleAddition> else { return 0.0 }
        return additions.reduce(0) { $0 + $1.amount }
    }
    
    private var startDate: String {
        guard let date = bottle.creationDate else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // Sorted additions for display
    private var sortedAdditions: [BottleAddition] {
        guard let additions = bottle.additions as? Set<BottleAddition> else { return [] }
        return additions.sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
    }
    
    // Sorted tastings for display
    private var sortedTastings: [BottleTasting] {
        guard let tastings = bottle.tastings as? Set<BottleTasting> else { return [] }
        return tastings.sorted { ($0.date ?? Date.distantPast) > ($1.date ?? Date.distantPast) }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Bottle image and basic info
                HStack(alignment: .top, spacing: 16) {
                    // Basic info
                    VStack(alignment: .leading, spacing: 8) {
                        Text(bottle.name ?? "Unnamed Bottle")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(bottle.typeCategory ?? "Mixed")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Created:")
                                .fontWeight(.medium)
                            Text(startDate)
                        }
                        .font(.subheadline)
                        
                        HStack {
                            Text("Proof:")
                                .fontWeight(.medium)
                            Text(String(format: "%.1f", bottle.calculatedProof))
                        }
                        .font(.subheadline)
                        
                        HStack {
                            Text("Current Infinity Volume:")
                                .fontWeight(.medium)
                            Text("\(bottle.remainingVolume, specifier: "%.1f") oz")
                        }
                        .font(.subheadline)
                        
                        HStack {
                            Text("Additions:")
                                .fontWeight(.medium)
                            Text("\(bottle.sortedAdditions.count)")
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.horizontal)
                
                // Notes
                if let notes = bottle.notes, !notes.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Notes")
                            .font(.headline)
                        
                        Text(notes)
                            .font(.body)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal)
                }
                
                // Tab selection for Additions and Tastings
                Picker("View", selection: $selectedTab) {
                    Text("Additions").tag(0)
                    Text("Tastings").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // Content based on selected tab
                if selectedTab == 0 {
                    // Additions
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Whiskey Additions")
                                .font(.headline)
                            Spacer()
                            Button {
                                showingAddWhiskeySheet = true
                                HapticManager.shared.mediumImpact()
                            } label: {
                                Label("Add", systemImage: "plus")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        if sortedAdditions.isEmpty {
                            VStack(spacing: 8) {
                                Text("No whiskeys added yet")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                                Text("Tap the + button to add your first whiskey")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                        } else {
                            // Use a List instead of ForEach for better swipe action support
                            List {
                                ForEach(sortedAdditions) { addition in
                                    AdditionRowView(addition: addition)
                                        .padding(.vertical, 2)
                                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                deleteAddition(addition)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                                .listRowBackground(Color.clear)
                            }
                            .listStyle(PlainListStyle())
                            .frame(minHeight: CGFloat(sortedAdditions.count * 80))
                            .background(Color.clear)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    // Tastings
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Tasting Notes")
                                .font(.headline)
                            Spacer()
                            Button {
                                showingAddTastingSheet = true
                                HapticManager.shared.mediumImpact()
                            } label: {
                                Label("Add", systemImage: "plus")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        if sortedTastings.isEmpty {
                            VStack(spacing: 8) {
                                Text("No tasting notes yet")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                                Text("Tap the + button to record your first tasting")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                        } else {
                            // Use a List instead of ForEach for better swipe action support
                            List {
                                ForEach(sortedTastings) { tasting in
                                    TastingRowView(tasting: tasting)
                                        .padding(.vertical, 2)
                                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                        .swipeActions(edge: .trailing) {
                                            Button(role: .destructive) {
                                                deleteTasting(tasting)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                        }
                                }
                                .listRowBackground(Color.clear)
                            }
                            .listStyle(PlainListStyle())
                            .frame(minHeight: CGFloat(sortedTastings.count * 100))
                            .background(Color.clear)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationBarTitle("", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingEditBottleSheet = true
                        HapticManager.shared.mediumImpact()
                    } label: {
                        Label("Edit Bottle", systemImage: "pencil")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        deleteBottle()
                        HapticManager.shared.warningFeedback()
                        dismiss()
                    } label: {
                        Label("Delete Bottle", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingAddWhiskeySheet, onDismiss: {
            // Force refresh when whiskey addition sheet is dismissed
            viewContext.refresh(bottle, mergeChanges: true)
        }) {
            AddWhiskeyToBottleView(bottle: bottle)
        }
        .sheet(isPresented: $showingAddTastingSheet, onDismiss: {
            // Force refresh when tasting sheet is dismissed
            viewContext.refresh(bottle, mergeChanges: true)
        }) {
            AddTastingView(bottle: bottle)
        }
        .sheet(isPresented: $showingEditBottleSheet, onDismiss: {
            // Force refresh the bottle object when edit sheet is dismissed
            viewContext.refresh(bottle, mergeChanges: true)
        }) {
            EditInfinityBottleView(bottle: bottle)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InfinityBottleUpdated"))) { notification in
            // Refresh the bottle object when we receive an update notification
            if let updatedBottle = notification.object as? InfinityBottle,
               updatedBottle.objectID == bottle.objectID {
                viewContext.refresh(bottle, mergeChanges: true)
            }
        }
        .onAppear {
            // Refresh the bottle object whenever the view appears to ensure latest data
            viewContext.refresh(bottle, mergeChanges: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Refresh when app comes to foreground in case data was updated elsewhere
            viewContext.refresh(bottle, mergeChanges: true)
        }
    }
    
    private func deleteBottle() {
        viewContext.delete(bottle)
        
        do {
            try viewContext.save()
        } catch {
            print("Error deleting infinity bottle: \(error)")
        }
    }
    
    private func deleteAddition(_ addition: BottleAddition) {
        withAnimation {
            // Remove the addition from the bottle
            bottle.removeFromAdditions(addition)
            
            // Sync the current volume with the computed remaining volume
            bottle.syncCurrentVolume()
            
            do {
                try viewContext.save()
                HapticManager.shared.successFeedback()
            } catch {
                print("Error deleting addition: \(error)")
                HapticManager.shared.errorFeedback()
            }
        }
    }
    
    private func deleteTasting(_ tasting: BottleTasting) {
        withAnimation {
            bottle.removeFromTastings(tasting)
            
            do {
                try viewContext.save()
                HapticManager.shared.successFeedback()
            } catch {
                print("Error deleting tasting: \(error)")
                HapticManager.shared.errorFeedback()
            }
        }
    }
}

struct AdditionRowView: View {
    @ObservedObject var addition: BottleAddition
    
    private var formattedDate: String {
        guard let date = addition.date else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(addition.whiskey?.name ?? "Unknown Whiskey")
                    .font(.headline)
                Spacer()
                Text("\(addition.amount, specifier: "%.2f") oz")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("\(addition.whiskey?.distillery ?? "Unknown Distillery")")
                    .font(.subheadline)
                Spacer()
                Text("\(String(format: "%.1f", addition.proof)) proof")
                    .font(.subheadline)
            }
            .foregroundColor(.secondary)
            
            Text(formattedDate)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct TastingRowView: View {
    @ObservedObject var tasting: BottleTasting
    
    private var formattedDate: String {
        guard let date = tasting.date else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(formattedDate)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                // Star rating
                HStack(spacing: 4) {
                    ForEach(1...5, id: \.self) { star in
                        Image(systemName: star <= Int(tasting.rating) ? "star.fill" : "star")
                            .foregroundColor(.yellow)
                            .font(.caption)
                    }
                }
            }
            
            if let nose = tasting.nose, !nose.isEmpty {
                Text("Nose: \(nose)")
                    .font(.subheadline)
            }
            
            if let palate = tasting.palate, !palate.isEmpty {
                Text("Palate: \(palate)")
                    .font(.subheadline)
            }
            
            if let finish = tasting.finish, !finish.isEmpty {
                Text("Finish: \(finish)")
                    .font(.subheadline)
            }
            
            if let notes = tasting.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
            }
        }
    }
}

struct AddWhiskeyToBottleView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let bottle: InfinityBottle
    
    @State private var selectedWhiskey: Whiskey?
    @State private var amount: Double = 1.0
    @State private var notes = ""
    
    // Fetch all whiskeys from the collection
    @FetchRequest(
        entity: Whiskey.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Whiskey.name, ascending: true)],
        predicate: NSPredicate(format: "status == %@ OR status == nil", "owned")
    ) private var availableWhiskeys: FetchedResults<Whiskey>
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Whiskey")) {
                    Picker("Select Whiskey", selection: $selectedWhiskey) {
                        Text("Select a whiskey...").tag(nil as Whiskey?)
                        ForEach(availableWhiskeys) { whiskey in
                            Text(whiskey.name ?? "Unknown").tag(whiskey as Whiskey?)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    if let whiskey = selectedWhiskey {
                        HStack {
                            Text("Proof")
                            Spacer()
                            Text(String(format: "%.1f", whiskey.proof))
                        }
                        
                        if let distillery = whiskey.distillery, !distillery.isEmpty {
                            HStack {
                                Text("Distillery")
                                Spacer()
                                Text(distillery)
                            }
                        }
                        
                        if let type = whiskey.type, !type.isEmpty {
                            HStack {
                                Text("Type")
                                Spacer()
                                Text(type)
                            }
                        }
                    }
                }
                
                Section(header: Text("Amount (oz)")) {
                    VStack {
                        HStack {
                            Text("0 oz")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("6.8 oz")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Slider(value: $amount, in: 0.25...6.8, step: 0.25)
                        
                        Text("\(amount, specifier: "%.2f") oz")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                
                Section(header: Text("Notes (Optional)")) {
                    TextField("Notes about this addition", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Whiskey")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                        HapticManager.shared.lightImpact()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addWhiskeyToBottle()
                        HapticManager.shared.successFeedback()
                        dismiss()
                    }
                    .disabled(selectedWhiskey == nil)
                }
            }
        }
    }
    
    private func addWhiskeyToBottle() {
        guard let whiskey = selectedWhiskey else { return }
        
        let newAddition = BottleAddition(context: viewContext)
        newAddition.id = UUID()
        newAddition.whiskey = whiskey
        newAddition.amount = amount
        newAddition.proof = whiskey.proof
        newAddition.date = Date()
        newAddition.notes = notes.isEmpty ? nil : notes
        newAddition.infinityBottle = bottle
        
        // Update the bottle's modification date
        bottle.modificationDate = Date()
        
        // Sync the current volume with the computed remaining volume
        bottle.syncCurrentVolume()
        
        do {
            try viewContext.save()
            
            // Post notification to refresh the detail view since volume was added
            NotificationCenter.default.post(
                name: Notification.Name("InfinityBottleUpdated"),
                object: bottle
            )
        } catch {
            print("Error adding whiskey to infinity bottle: \(error)")
        }
    }
}

struct AddTastingView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let bottle: InfinityBottle
    
    @State private var date = Date()
    @State private var overallRating: Double = 5.0
    @State private var nose = ""
    @State private var palate = ""
    @State private var finish = ""
    @State private var review = ""
    @State private var servingMethod: ServingMethod = .neat
    @State private var customServingMethod = ""
    @State private var setting = ""
    @State private var volumeConsumed: String = "1.0"
    
    // Focus management for tasting notes
    enum TastingField: CaseIterable {
        case nose, palate, finish, review, setting
    }
    @FocusState private var focusedField: TastingField?
    
    enum ServingMethod: String, CaseIterable {
        case neat = "Neat"
        case rocks = "Rocks"
        case splashOfWater = "w/ Water"
        case custom = "Custom"
        
        var icon: String {
            switch self {
            case .neat: return "🥃"
            case .rocks: return "🧊"
            case .splashOfWater: return "💧"
            case .custom: return "✏️"
            }
        }
        
        var description: String {
            switch self {
            case .neat: return "Served at room temperature without any water or ice"
            case .rocks: return "Served over ice cubes"
            case .splashOfWater: return "Served with a small amount of water added"
            case .custom: return "Specify your own serving method"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Info")) {
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                    
                    VStack(alignment: .leading) {
                        Text("Overall Rating")
                        HStack {
                            Slider(value: $overallRating.onChange { _ in
                                HapticManager.shared.selectionFeedback()
                            }, in: 1...10, step: 0.5)
                            Text(String(format: "%.1f", overallRating))
                                .frame(width: 40)
                        }
                    }
                }
                
                Section(header: Text("Tasting Notes")) {
                    TextField("Nose", text: $nose, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .nose)
                    TextField("Palate", text: $palate, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .palate)
                    TextField("Finish", text: $finish, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .finish)
                    TextField("Review", text: $review, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focusedField, equals: .review)
                }
                
                Section(header: Text("Additional Details")) {
                    HStack {
                        Text("Serving Method:")
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: $servingMethod) {
                            ForEach(ServingMethod.allCases, id: \.self) { method in
                                Text("\(method.icon) \(method.rawValue)").tag(method)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    if servingMethod != .custom {
                        Text(servingMethod.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    
                    if servingMethod == .custom {
                        TextField("Custom Serving Method", text: $customServingMethod)
                    }
                    
                    HStack {
                        Text("Volume Consumed:")
                            .foregroundColor(.secondary)
                        Spacer()
                        TextField("1.0", text: $volumeConsumed)
                            .keyboardType(.decimalPad)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                        Text("oz")
                            .foregroundColor(.secondary)
                    }
                    
                    TextField("Setting", text: $setting)
                        .focused($focusedField, equals: .setting)
                }
                
                // Infinity bottle info section
                Section(header: Text("Infinity Bottle")) {
                    HStack {
                        Text("Bottle:")
                            .foregroundColor(.secondary)
                        Text(bottle.name ?? "Unnamed Bottle")
                            .foregroundColor(.primary)
                    }
                    
                    HStack {
                        Text("Type:")
                            .foregroundColor(.secondary)
                        Text(bottle.typeCategory ?? "Mixed")
                            .foregroundColor(.primary)
                    }
                    
                    HStack {
                        Text("Current Proof:")
                            .foregroundColor(.secondary)
                        Text(String(format: "%.1f", bottle.calculatedProof))
                            .foregroundColor(.primary)
                    }
                    
                    HStack {
                        Text("Current Infinity Volume:")
                            .foregroundColor(.secondary)
                        Text("\(bottle.remainingVolume, specifier: "%.1f") oz")
                            .foregroundColor(.primary)
                    }
                }
            }
            .navigationTitle("New Tasting Entry")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Button("Previous") {
                        moveToPreviousField()
                    }
                    .disabled(!canMoveToPrevious())
                    
                    Spacer()
                    
                    Button("Next") {
                        moveToNextField()
                    }
                    .disabled(!canMoveToNext())
                    
                    Spacer()
                    
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        HapticManager.shared.lightImpact()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        HapticManager.shared.mediumImpact()
                        saveEntry()
                    }
                }
            }
        }
    }
    
    // MARK: - Field Navigation Helpers
    private func moveToPreviousField() {
        guard let currentField = focusedField else { return }
        let fields = TastingField.allCases
        if let currentIndex = fields.firstIndex(of: currentField), currentIndex > 0 {
            focusedField = fields[currentIndex - 1]
        }
    }
    
    private func moveToNextField() {
        guard let currentField = focusedField else { return }
        let fields = TastingField.allCases
        if let currentIndex = fields.firstIndex(of: currentField), currentIndex < fields.count - 1 {
            focusedField = fields[currentIndex + 1]
        }
    }
    
    private func canMoveToPrevious() -> Bool {
        guard let currentField = focusedField else { return false }
        return TastingField.allCases.firstIndex(of: currentField) != 0
    }
    
    private func canMoveToNext() -> Bool {
        guard let currentField = focusedField else { return false }
        let fields = TastingField.allCases
        return fields.firstIndex(of: currentField) != fields.count - 1
    }
    
    private func saveEntry() {
        withAnimation {
            // Create both a regular JournalEntry and a BottleTasting
            
            // 1. Create the regular journal entry
            let newEntry = JournalEntry(context: viewContext)
            newEntry.id = UUID()
            newEntry.date = date
            // No whiskey for infinity bottle entries
            newEntry.infinityBottle = bottle // Assuming there's a relationship in the model
            newEntry.overallRating = overallRating
            newEntry.nose = nose.isEmpty ? nil : nose
            newEntry.palate = palate.isEmpty ? nil : palate
            newEntry.finish = finish.isEmpty ? nil : finish
            newEntry.review = review.isEmpty ? nil : review
            newEntry.servingMethod = servingMethod == .custom ? customServingMethod : servingMethod.rawValue
            newEntry.setting = setting.isEmpty ? nil : setting
            newEntry.isInfinityBottle = true // Flag to identify this as an infinity bottle entry
            
            // 2. Also create a BottleTasting for tracking in the infinity bottle
            let newTasting = BottleTasting(context: viewContext)
            newTasting.id = UUID()
            newTasting.infinityBottle = bottle
            newTasting.date = date
            newTasting.nose = nose.isEmpty ? nil : nose
            newTasting.palate = palate.isEmpty ? nil : palate
            newTasting.finish = finish.isEmpty ? nil : finish
            newTasting.notes = review.isEmpty ? nil : review
            newTasting.rating = overallRating / 2.0 // Convert 10-point scale to 5-point scale for consistency
            
            // 3. Record volume consumed
            let consumedAmount = Double(volumeConsumed) ?? 0.0
            newTasting.volumeConsumed = consumedAmount
            
            // Sync the current volume with the computed remaining volume
            bottle.syncCurrentVolume()
            
            bottle.modificationDate = Date()
            
            do {
                try viewContext.save()
                
                // Post notification to refresh the detail view since volume was consumed
                NotificationCenter.default.post(
                    name: Notification.Name("InfinityBottleUpdated"),
                    object: bottle
                )
                
                HapticManager.shared.successFeedback()
                dismiss()
            } catch {
                HapticManager.shared.errorFeedback()
                print("Error saving infinity bottle tasting: \(error)")
            }
        }
    }
} 