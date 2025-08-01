import SwiftUI

struct JournalEntryDetailView: View {
    let entry: JournalEntry
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Whiskey/Infinity Bottle Info
                if entry.isInfinityBottle {
                    if let infinityBottle = entry.infinityBottle {
                        // Infinity Bottle Header
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Text("∞ \(infinityBottle.name ?? "Infinity Bottle")")
                                    .font(.headline)
                            }
                            
                            Text("\(infinityBottle.calculatedProof, specifier: "%.1f") proof")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                } else if let whiskey = entry.whiskey {
                    // Whiskey Header
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(whiskey.name ?? "Unknown Whiskey")
                                .font(.headline)
                            
                            if whiskey.status == "external" {
                                Text("External")
                                    .font(.system(size: 10))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(Color.orange)
                                    .cornerRadius(4)
                            }
                        }
                        
                        if whiskey.proof > 0 {
                            Text("\(whiskey.proof, specifier: "%.1f") proof")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Date and Rating
                HStack {
                    Text(entry.date ?? Date(), style: .date)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if entry.overallRating > 0 {
                        RatingView(rating: entry.overallRating, largeDisplay: true)
                    }
                }
                
                // Tasting Notes
                Group {
                    if let nose = entry.nose, !nose.isEmpty {
                        TastingNoteSection(title: "Nose", content: nose)
                    }
                    
                    if let palate = entry.palate, !palate.isEmpty {
                        TastingNoteSection(title: "Palate", content: palate)
                    }
                    
                    if let finish = entry.finish, !finish.isEmpty {
                        TastingNoteSection(title: "Finish", content: finish)
                    }
                    
                    if let review = entry.review, !review.isEmpty {
                        TastingNoteSection(title: "Review", content: review)
                    }
                }
                
                // Flavor Profile Attributes by Phase
                if let flavorProfile = entry.flavorProfileData {
                    FlavorAttributesView(flavorProfile: flavorProfile)
                }
                
                // Serving Details
                if let servingMethod = entry.servingMethod, !servingMethod.isEmpty {
                    TastingNoteSection(title: "Serving Method", content: servingMethod)
                }
                
                if let setting = entry.setting, !setting.isEmpty {
                    TastingNoteSection(title: "Setting", content: setting)
                }
                
                // Custom Fields
                if let customFields = entry.customFields?.allObjects as? [JournalCustomField] {
                    ForEach(customFields, id: \.self) { field in
                        if let name = field.name, let value = field.value as? String, !name.isEmpty, !value.isEmpty {
                            TastingNoteSection(title: name, content: value)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label("Edit Entry", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete Entry", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditJournalEntryView(entry: entry)
        }
        .alert("Delete Entry", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteEntry()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this tasting entry? This action cannot be undone.")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    private func deleteEntry() {
        withAnimation {
            // Delete from Core Data
            viewContext.delete(entry)
            try? viewContext.save()
            
            HapticManager.shared.successFeedback()
            dismiss()
        }
    }
}

struct EditJournalEntryView: View {
    let entry: JournalEntry
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var date: Date
    @State private var overallRating: Double
    @State private var nose: String
    @State private var palate: String
    @State private var finish: String
    @State private var review: String
    @State private var servingMethod: ServingMethod
    @State private var customServingMethod: String
    @State private var setting: String
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
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
    
    init(entry: JournalEntry) {
        self.entry = entry
        
        // Initialize state with current values
        _date = State(initialValue: entry.date ?? Date())
        _overallRating = State(initialValue: entry.overallRating)
        _nose = State(initialValue: entry.nose ?? "")
        _palate = State(initialValue: entry.palate ?? "")
        _finish = State(initialValue: entry.finish ?? "")
        _review = State(initialValue: entry.review ?? "")
        
        // Parse the serving method from the stored string
        let storedServingMethod = entry.servingMethod ?? ""
        if storedServingMethod == "Neat" {
            _servingMethod = State(initialValue: .neat)
            _customServingMethod = State(initialValue: "")
        } else if storedServingMethod == "Rocks" {
            _servingMethod = State(initialValue: .rocks)
            _customServingMethod = State(initialValue: "")
        } else if storedServingMethod == "w/ Water" {
            _servingMethod = State(initialValue: .splashOfWater)
            _customServingMethod = State(initialValue: "")
        } else if !storedServingMethod.isEmpty {
            _servingMethod = State(initialValue: .custom)
            _customServingMethod = State(initialValue: storedServingMethod)
        } else {
            _servingMethod = State(initialValue: .neat)
            _customServingMethod = State(initialValue: "")
        }
        
        _setting = State(initialValue: entry.setting ?? "")
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Whiskey")) {
                    Text(entry.whiskey?.name ?? "Unknown Whiskey")
                        .foregroundColor(.primary)
                }
                
                Section(header: Text("Basic Info")) {
                    DatePicker("Date", selection: $date, displayedComponents: [.date])
                    
                    VStack(alignment: .leading) {
                        Text("Overall Rating")
                        HStack {
                            Slider(value: $overallRating, in: 1...10, step: 0.5)
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
                    Picker("Serving Method", selection: $servingMethod) {
                        ForEach(ServingMethod.allCases, id: \.self) { method in
                            Label(method.rawValue, systemImage: method.icon)
                                .tag(method)
                        }
                    }
                    
                    if servingMethod == .custom {
                        TextField("Custom Serving Method", text: $customServingMethod)
                    }
                    
                    TextField("Setting", text: $setting)
                        .focused($focusedField, equals: .setting)
                }
            }
            .navigationTitle("Edit Tasting Entry")
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
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                }
            }
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
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
    
    private func saveChanges() {
        withAnimation {
            // Update the entry with new values
            entry.date = date
            entry.overallRating = overallRating
            entry.nose = nose.isEmpty ? nil : nose
            entry.palate = palate.isEmpty ? nil : palate
            entry.finish = finish.isEmpty ? nil : finish
            entry.review = review.isEmpty ? nil : review
            entry.servingMethod = servingMethod == .custom ? customServingMethod : servingMethod.rawValue
            entry.setting = setting.isEmpty ? nil : setting
            entry.modificationDate = Date() // Update modification date
            
            do {
                try viewContext.save()
                print("Successfully saved journal entry to Core Data: \(entry.id?.uuidString ?? "unknown")")
                dismiss()
            } catch {
                errorMessage = "Failed to save changes: \(error.localizedDescription)"
                showingErrorAlert = true
            }
        }
    }
}

struct RatingView: View {
    let rating: Double
    var largeDisplay: Bool = false
    
    // Get color based on rating value
    private var ratingColor: Color {
        switch rating {
        case 1.0..<3.0:
            return ColorManager.ratingPoor
        case 3.0..<5.0:
            return ColorManager.ratingFair
        case 5.0..<7.0:
            return ColorManager.ratingGood // Amber/gold color
        case 7.0..<9.0:
            return ColorManager.ratingGreat
        case 9.0...10.0:
            return ColorManager.ratingExceptional
        default:
            return .gray
        }
    }
    
    // Get label based on rating value
    private var ratingLabel: String {
        switch rating {
        case 1.0..<3.0:
            return "Poor"
        case 3.0..<5.0:
            return "Fair"
        case 5.0..<7.0:
            return "Good"
        case 7.0..<9.0:
            return "Great"
        case 9.0...10.0:
            return "Exceptional"
        default:
            return ""
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(String(format: "%.1f", rating))
                .fontWeight(.bold)
                .foregroundColor(ratingColor)
                .font(largeDisplay ? .title3 : .subheadline)
            
            Image(systemName: "star.fill")
                .foregroundColor(ratingColor)
                .font(largeDisplay ? .body : .caption)
                
            if largeDisplay {
                Text(ratingLabel)
                    .foregroundColor(ratingColor)
                    .font(.subheadline)
                    .padding(.leading, 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(ratingColor.opacity(0.1))
        )
    }
}

struct TastingNoteSection: View {
    let title: String
    let content: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(content)
                .font(.body)
        }
    }
}

struct FlavorAttributesView: View {
    let flavorProfile: FlavorProfile
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Only show phases that have selected attributes
            ForEach(TastingPhase.allCases, id: \.self) { phase in
                let selectedAttributes = getSelectedAttributesForPhase(phase)
                if !selectedAttributes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(phase.rawValue) Attributes")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        FlowLayout(spacing: 6) {
                            ForEach(selectedAttributes, id: \.self) { attribute in
                                Text(attribute)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule()
                                            .fill(Color.accentColor.opacity(0.2))
                                    )
                                    .foregroundColor(.accentColor)
                                    .overlay(
                                        Capsule()
                                            .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                                    )
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }
    
    private func getSelectedAttributesForPhase(_ phase: TastingPhase) -> [String] {
        let intensities = phase == .nose ? flavorProfile.nose : 
                         (phase == .palate ? flavorProfile.palate : flavorProfile.finish)
        
        var attributes: [String] = []
        
        // Go through each category and collect selected subflavors
        for intensity in intensities {
            if intensity.intensity > 0 && !intensity.selectedSubflavors.isEmpty {
                attributes.append(contentsOf: intensity.selectedSubflavors.sorted())
            }
        }
        
        return attributes.sorted()
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions(),
            subviews: subviews,
            spacing: spacing
        )
        return result.bounds
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions(),
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX,
                                    y: bounds.minY + result.frames[index].minY),
                         proposal: ProposedViewSize(result.frames[index].size))
        }
    }
}

struct FlowResult {
    var bounds = CGSize.zero
    var frames: [CGRect] = []
    
    init(in maxSize: CGSize, subviews: LayoutSubviews, spacing: CGFloat) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if x + size.width > maxSize.width && x > 0 {
                // Move to next row
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        
        bounds = CGSize(width: maxSize.width, height: y + rowHeight)
    }
}

struct JournalEntryDetailView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            JournalEntryDetailView(entry: JournalEntry())
        }
    }
} 