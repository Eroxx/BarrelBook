import SwiftUI

struct AddJournalEntryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Whiskey.name, ascending: true)],
        animation: .default)
    private var whiskeys: FetchedResults<Whiskey>
    
    @State private var selectedWhiskey: Whiskey?
    @State private var date: Date = Date()
    @State private var overallRating: Double = 5.0
    @State private var nose: String = ""
    @State private var palate: String = ""
    @State private var finish: String = ""
    @State private var review: String = ""
    @State private var servingMethod: ServingMethod = .neat
    @State private var customServingMethod = ""
    @State private var setting = ""
    @State private var showingWhiskeySelection = false
    @State private var flavorProfile: FlavorProfile = FlavorProfile()
    @State private var selectedPhase: TastingPhase = .nose
    
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
            case .neat: return "Served at room temperature without any water"
            case .rocks: return "Served over ice cubes"
            case .splashOfWater: return "Served with a small amount of water added"
            case .custom: return "Specify your own serving method"
            }
        }
    }
    
    // Initialize with an optional pre-selected whiskey
    init(preSelectedWhiskey: Whiskey? = nil) {
        _selectedWhiskey = State(initialValue: preSelectedWhiskey)
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Whiskey Selection")) {
                    Button {
                        showingWhiskeySelection = true
                    } label: {
                        HStack {
                            Text(selectedWhiskey?.name ?? "Select a whiskey")
                                .foregroundColor(selectedWhiskey == nil ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }
                
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
                
                Section(header: Text("Flavor Profile")) {
                    Picker("Tasting Phase", selection: $selectedPhase) {
                        ForEach(TastingPhase.allCases, id: \.self) { phase in
                            Text(phase.rawValue).tag(phase)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    FlavorWheelView(flavorProfile: $flavorProfile, phase: selectedPhase)
                        .frame(height: 400)
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
                    
                    TextField("Setting", text: $setting)
                        .focused($focusedField, equals: .setting)
                }
            }
            .navigationTitle("Add Tasting")
            .navigationBarTitleDisplayMode(.inline)
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
                    .disabled(selectedWhiskey == nil)
                }
            }
            .sheet(isPresented: $showingWhiskeySelection) {
                WhiskeySelectionView(selectedWhiskey: $selectedWhiskey)
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
            let newEntry = JournalEntry(context: viewContext)
            newEntry.id = UUID()
            
            // Ensure date is saved in the correct time zone
            // Create a date with just the date components from the selected date
            // but using the current time in the user's time zone
            let calendar = Calendar.current
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
            let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: Date())
            
            var fullComponents = DateComponents()
            fullComponents.year = dateComponents.year
            fullComponents.month = dateComponents.month
            fullComponents.day = dateComponents.day
            fullComponents.hour = timeComponents.hour
            fullComponents.minute = timeComponents.minute
            fullComponents.second = timeComponents.second
            fullComponents.timeZone = TimeZone.current
            
            newEntry.date = calendar.date(from: fullComponents) ?? date
            newEntry.modificationDate = Date() // Add modification date
            
            // Only set non-empty values to avoid nil reference issues
            newEntry.whiskey = selectedWhiskey
            newEntry.overallRating = overallRating
            newEntry.nose = nose.isEmpty ? nil : nose
            newEntry.palate = palate.isEmpty ? nil : palate
            newEntry.finish = finish.isEmpty ? nil : finish
            newEntry.review = review.isEmpty ? nil : review
            newEntry.servingMethod = servingMethod == .custom ? customServingMethod : servingMethod.rawValue
            newEntry.setting = setting.isEmpty ? nil : setting
            newEntry.flavorProfileData = flavorProfile
            
            // Set isTasted to true since we're creating a new journal entry
            if let whiskey = selectedWhiskey {
                whiskey.isTasted = true
            }
            
            do {
                try viewContext.save()
                print("Successfully saved new journal entry to Core Data: \(newEntry.id?.uuidString ?? "unknown")")
                
                HapticManager.shared.successFeedback()
                dismiss()
            } catch {
                HapticManager.shared.errorFeedback()
                print("Error saving entry: \(error)")
                viewContext.rollback()
            }
        }
    }
}

struct WhiskeySelectionView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedWhiskey: Whiskey?
    
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Whiskey.name, ascending: true)],
        animation: .default)
    private var whiskeys: FetchedResults<Whiskey>
    
    @State private var searchText = ""
    @State private var showingExternalWhiskeyEntry = false
    
    // All possible letters that could appear
    private let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    
    private var groupedWhiskeys: [(key: String, whiskeys: [Whiskey])] {
        let filtered = whiskeys.filter { whiskey in
            searchText.isEmpty || 
            (whiskey.name?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        
        let grouped = Dictionary(grouping: filtered) { whiskey in
            String(whiskey.name?.prefix(1).uppercased() ?? "#")
        }
        
        return grouped.map { (key: $0.key, whiskeys: $0.value) }
            .sorted { $0.key < $1.key }
    }
    
    var body: some View {
        NavigationView {
            ScrollViewReader { scrollProxy in
                List {
                    Section {
                        Button {
                            showingExternalWhiskeyEntry = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.blue)
                                Text("Log Whiskey Not in Collection")
                                    .foregroundColor(.primary)
                            }
                        }
                    }
                    
                    ForEach(groupedWhiskeys, id: \.key) { section in
                        Section {
                            ForEach(section.whiskeys) { whiskey in
                                Button {
                                    selectedWhiskey = whiskey
                                    HapticManager.shared.selectionFeedback()
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(whiskey.name ?? "Unknown")
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        if whiskey.id == selectedWhiskey?.id {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text(section.key)
                                .id(section.key)
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "Search whiskeys")
                .overlay(
                    VStack(spacing: 0) {
                        // Insert spacer to push the alphabet index down to align with first whiskey
                        Spacer().frame(height: 115)
                        
                        VStack(spacing: 0) {
                            ForEach(alphabet, id: \.self) { letter in
                                let letterStr = String(letter)
                                let exists = groupedWhiskeys.contains { $0.key == letterStr }
                                
                                Text(letterStr)
                                    .font(.system(size: 10, weight: .medium))
                                    .frame(width: 20, height: 13)
                                    .foregroundColor(exists ? .accentColor : .gray)
                                    .opacity(exists ? 1 : 0.6)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if exists {
                                            withAnimation {
                                                scrollProxy.scrollTo(letterStr, anchor: .top)
                                            }
                                        }
                                    }
                            }
                        }
                        .padding(.vertical, 4)
                        .background(Color(.systemBackground).opacity(0.85))
                        .cornerRadius(8)
                        
                        Spacer()
                    }
                    .padding(.trailing, 5),
                    alignment: .trailing
                )
                .navigationTitle("Select Whiskey")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel", role: .cancel) {
                            dismiss()
                        }
                    }
                }
                .sheet(isPresented: $showingExternalWhiskeyEntry) {
                    ExternalWhiskeyEntryView(selectedWhiskey: $selectedWhiskey, onSave: {
                        // Dismiss this view when external whiskey is saved
                        dismiss()
                    })
                }
            }
        }
    }
}

// View for entering details about a whiskey that's not in the collection
struct ExternalWhiskeyEntryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedWhiskey: Whiskey?
    
    // Add callback to dismiss parent view
    var onSave: (() -> Void)?
    
    @State private var name = ""
    @State private var type = ""
    @State private var distillery = ""
    @State private var proof = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Whiskey Details")) {
                    TextField("Name *", text: $name)
                    TextField("Type", text: $type)
                    TextField("Distillery", text: $distillery)
                    TextField("Proof", text: $proof)
                        .keyboardType(.decimalPad)
                }
                
                Section(footer: Text("This whiskey will be created for tasting only and will not be added to your collection.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Enter Whiskey Details")
            .navigationBarTitleDisplayMode(.inline)
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
                        saveExternalWhiskey()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func saveExternalWhiskey() {
        let newWhiskey = Whiskey(context: viewContext)
        newWhiskey.id = UUID()
        newWhiskey.name = name
        newWhiskey.type = type
        newWhiskey.distillery = distillery
        newWhiskey.proof = Double(proof) ?? 0.0
        newWhiskey.addedDate = Date()
        newWhiskey.modificationDate = Date()
        newWhiskey.status = "external" // Special status for whiskeys not in collection
        newWhiskey.numberOfBottles = 0  // No bottles owned
        
        do {
            try viewContext.save()
            selectedWhiskey = newWhiskey
            HapticManager.shared.successFeedback()
            dismiss()
            
            // Dismiss parent view after a small delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                onSave?()
            }
        } catch {
            HapticManager.shared.errorFeedback()
            print("Error saving external whiskey: \(error)")
        }
    }
}

struct AddJournalEntryView_Previews: PreviewProvider {
    static var previews: some View {
        AddJournalEntryView()
    }
}

// Custom view modifier to ensure alphabet index is positioned correctly
extension View {
    func alphabetIndexOverlay<T>(
        proxy: ScrollViewProxy, 
        letters: [Character], 
        sectionKeys: [(key: String, whiskeys: [T])]
    ) -> some View {
        self.overlay(
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ForEach(letters, id: \.self) { letter in
                        let letterStr = String(letter)
                        let exists = sectionKeys.contains { $0.key == letterStr }
                        
                        Button {
                            if exists {
                                withAnimation {
                                    proxy.scrollTo(letterStr, anchor: .top)
                                }
                            }
                        } label: {
                            Text(letterStr)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(exists ? .accentColor : .gray)
                                .opacity(exists ? 1 : 0.6)
                        }
                        .frame(width: 18, height: 16)
                        .contentShape(Rectangle())
                        .disabled(!exists)
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 3)
                .background(Color(.systemBackground).opacity(0.85))
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.1), radius: 1)
                .padding(.trailing, 2)
                // Position the alphabet index with explicit coordinates
                .position(
                    x: geometry.size.width - 15,
                    y: geometry.size.height * 0.3 // Position it at 30% from the top
                )
            }
        )
    }
} 
