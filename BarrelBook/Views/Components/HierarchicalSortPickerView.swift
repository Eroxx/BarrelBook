import SwiftUI

// MARK: - Collection/Whiskey Sort Picker

private let hasSeenSortTutorialKey = "hasSeenSortTutorial"

struct HierarchicalSortPickerView: View {
    @Binding var sortConfig: HierarchicalSortConfig
    @Environment(\.dismiss) private var dismiss
    @AppStorage(hasSeenSortTutorialKey) private var hasSeenSortTutorial = false
    
    @State private var draggedItem: SortCriterionIdentifiable?
    @State private var showingTutorialOverlay = false
    
    private let allOptions = SortOption.allCases
    
    var body: some View {
        ZStack {
        NavigationView {
            List {
                // Active Sorts Section
                Section {
                    if sortConfig.activeSorts.isEmpty {
                        Text("At least one sort criterion required")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(sortConfig.activeSorts) { criterion in
                            HStack {
                                // Drag handle
                                Image(systemName: "line.3.horizontal")
                                    .foregroundColor(.secondary)
                                    .font(.title3)
                                
                                Text(criterion.option.rawValue)
                                    .font(.body)
                                
                                Spacer()
                                
                                // Remove button (disabled if it's the only one)
                                Button(action: {
                                    removeFromActive(criterion)
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(sortConfig.activeSorts.count > 1 ? .red : .gray)
                                }
                                .disabled(sortConfig.activeSorts.count <= 1)
                            }
                            .padding(.vertical, 4)
                            .moveDisabled(false)
                        }
                        .onMove { source, destination in
                            sortConfig.activeSorts.move(fromOffsets: source, toOffset: destination)
                            HapticManager.shared.selectionFeedback()
                        }
                    }
                } header: {
                    HStack {
                        Text("Active Sorts")
                        Spacer()
                        Text("Priority Order")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text("Drag to reorder. Items are sorted by the first criterion, then by the second within each group, and so on.")
                        .font(.caption)
                }
                
                // Available Sorts Section
                Section {
                    let available = sortConfig.availableSorts(allOptions: allOptions)
                    if available.isEmpty {
                        Text("All sort options are active or would conflict")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(available, id: \.self) { option in
                            HStack {
                                Text(option.rawValue)
                                    .font(.body)
                                
                                Spacer()
                                
                                Button(action: {
                                    addToActive(option)
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Available Sorts")
                } footer: {
                    Text("Tap + to add a sort criterion. Conflicting options (e.g., 'High-Low' vs 'Low-High' for the same attribute) are automatically filtered out.")
                        .font(.caption)
                }
            }
                .navigationTitle("Sort Options")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Reset") {
                            resetToDefault()
                        }
                    }
                    
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
                .environment(\.editMode, .constant(.active)) // Always enable edit mode for drag handles
        }
            // First-time tutorial overlay
            if showingTutorialOverlay {
                SortTutorialOverlay(onDismiss: {
                    hasSeenSortTutorial = true
                    showingTutorialOverlay = false
                    HapticManager.shared.lightImpact()
                })
            }
        }
        .onAppear {
            if !hasSeenSortTutorial {
                showingTutorialOverlay = true
            }
        }
    }
    
    private func addToActive(_ option: SortOption) {
        let criterion = SortCriterionIdentifiable(option: option)
        sortConfig.activeSorts.append(criterion)
        HapticManager.shared.lightImpact()
    }
    
    private func removeFromActive(_ criterion: SortCriterionIdentifiable) {
        if sortConfig.activeSorts.count > 1 {
            sortConfig.activeSorts.removeAll { $0.id == criterion.id }
            HapticManager.shared.lightImpact()
        }
    }
    
    private func resetToDefault() {
        sortConfig.activeSorts = [SortCriterionIdentifiable(option: .nameAsc)]
        HapticManager.shared.lightImpact()
    }
}

// MARK: - Sort Tutorial (first-time overlay)

private struct SortTutorialOverlay: View {
    var onDismiss: () -> Void
    
    var body: some View {
        ColorManager.tutorialScrim
            .ignoresSafeArea()
            .onTapGesture { }
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Image(systemName: "arrow.up.arrow.down.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(ColorManager.primaryBrandColor)
                                Text("How sorting works")
                                    .font(.headline)
                            }
                            VStack(alignment: .leading, spacing: 10) {
                                tutorialRow(icon: "1.circle.fill", text: "Use one criterion (e.g. Name A–Z) or combine several for more control.")
                                tutorialRow(icon: "2.circle.fill", text: "Order matters: the first sort groups items; the next refines within each group (e.g. Type, then Proof).")
                                tutorialRow(icon: "3.circle.fill", text: "In **Active Sorts** drag to change priority; in **Available Sorts** tap + to add another.")
                                tutorialRow(icon: "arrow.counterclockwise", text: "Tap **Reset** to go back to the default \"Name (A–Z)\" order.")
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
    
    private func tutorialRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(ColorManager.primaryBrandColor)
                .font(.subheadline)
            Text(LocalizedStringKey(text))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Wishlist Sort Picker

struct WishlistHierarchicalSortPickerView: View {
    @Binding var sortConfig: WishlistHierarchicalSortConfig
    @Environment(\.dismiss) private var dismiss
    
    private let allOptions = WishlistSortOption.allCases
    
    var body: some View {
        NavigationView {
            List {
                // Active Sorts Section
                Section {
                    if sortConfig.activeSorts.isEmpty {
                        Text("At least one sort criterion required")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(sortConfig.activeSorts) { criterion in
                            HStack {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundColor(.secondary)
                                    .font(.title3)
                                
                                Text(criterion.option.rawValue)
                                    .font(.body)
                                
                                Spacer()
                                
                                Button(action: {
                                    removeFromActive(criterion)
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(sortConfig.activeSorts.count > 1 ? .red : .gray)
                                }
                                .disabled(sortConfig.activeSorts.count <= 1)
                            }
                            .padding(.vertical, 4)
                            .moveDisabled(false)
                        }
                        .onMove { source, destination in
                            sortConfig.activeSorts.move(fromOffsets: source, toOffset: destination)
                            HapticManager.shared.selectionFeedback()
                        }
                    }
                } header: {
                    HStack {
                        Text("Active Sorts")
                        Spacer()
                        Text("Priority Order")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text("Drag to reorder. Items are sorted by the first criterion, then by the second within each group, and so on.")
                        .font(.caption)
                }
                
                // Available Sorts Section
                Section {
                    let available = sortConfig.availableSorts(allOptions: allOptions)
                    if available.isEmpty {
                        Text("All sort options are active or would conflict")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(available, id: \.self) { option in
                            HStack {
                                Text(option.rawValue)
                                    .font(.body)
                                
                                Spacer()
                                
                                Button(action: {
                                    addToActive(option)
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Available Sorts")
                } footer: {
                    Text("Tap + to add a sort criterion. Conflicting options (e.g., 'High-Low' vs 'Low-High' for the same attribute) are automatically filtered out.")
                        .font(.caption)
                }
            }
            .navigationTitle("Sort Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        resetToDefault()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
        }
        }
        
        private func addToActive(_ option: WishlistSortOption) {
        let criterion = WishlistSortCriterionIdentifiable(option: option)
        sortConfig.activeSorts.append(criterion)
        HapticManager.shared.lightImpact()
    }
    
    private func removeFromActive(_ criterion: WishlistSortCriterionIdentifiable) {
        if sortConfig.activeSorts.count > 1 {
            sortConfig.activeSorts.removeAll { $0.id == criterion.id }
            HapticManager.shared.lightImpact()
        }
    }
    
    private func resetToDefault() {
        sortConfig.activeSorts = [WishlistSortCriterionIdentifiable(option: .nameAsc)]
        HapticManager.shared.lightImpact()
    }
}

// MARK: - Journal Sort Picker

struct JournalHierarchicalSortPickerView: View {
    @Binding var sortConfig: JournalHierarchicalSortConfig
    @Environment(\.dismiss) private var dismiss
    
    // Journal sort options as strings
    private let allOptions = ["dateDesc", "dateAsc", "ratingDesc", "ratingAsc"]
    private let optionDisplayNames: [String: String] = [
        "dateDesc": "Newest First",
        "dateAsc": "Oldest First",
        "ratingDesc": "Highest Rated",
        "ratingAsc": "Lowest Rated"
    ]
    
    var body: some View {
        NavigationView {
            List {
                // Active Sorts Section
                Section {
                    if sortConfig.activeSorts.isEmpty {
                        Text("At least one sort criterion required")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(sortConfig.activeSorts) { criterion in
                            HStack {
                                Image(systemName: "line.3.horizontal")
                                    .foregroundColor(.secondary)
                                    .font(.title3)
                                
                                Text(optionDisplayNames[criterion.option] ?? criterion.option)
                                    .font(.body)
                                
                                Spacer()
                                
                                Button(action: {
                                    removeFromActive(criterion)
                                }) {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(sortConfig.activeSorts.count > 1 ? .red : .gray)
                                }
                                .disabled(sortConfig.activeSorts.count <= 1)
                            }
                            .padding(.vertical, 4)
                            .moveDisabled(false)
                        }
                        .onMove { source, destination in
                            sortConfig.activeSorts.move(fromOffsets: source, toOffset: destination)
                            HapticManager.shared.selectionFeedback()
                        }
                    }
                } header: {
                    HStack {
                        Text("Active Sorts")
                        Spacer()
                        Text("Priority Order")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } footer: {
                    Text("Drag to reorder. Entries are sorted by the first criterion, then by the second within each group, and so on.")
                        .font(.caption)
                }
                
                // Available Sorts Section
                Section {
                    let available = sortConfig.availableSorts(allOptions: allOptions)
                    if available.isEmpty {
                        Text("All sort options are active or would conflict")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(available, id: \.self) { option in
                            HStack {
                                Text(optionDisplayNames[option] ?? option)
                                    .font(.body)
                                
                                Spacer()
                                
                                Button(action: {
                                    addToActive(option)
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Available Sorts")
                } footer: {
                    Text("Tap + to add a sort criterion. Conflicting options (e.g., 'Newest' vs 'Oldest') are automatically filtered out.")
                        .font(.caption)
                }
            }
            .navigationTitle("Sort Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset") {
                        resetToDefault()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
        }
        }
        
        private func addToActive(_ option: String) {
        let criterion = JournalSortCriterionIdentifiable(optionRawValue: option)
        sortConfig.activeSorts.append(criterion)
        HapticManager.shared.lightImpact()
    }
    
    private func removeFromActive(_ criterion: JournalSortCriterionIdentifiable) {
        if sortConfig.activeSorts.count > 1 {
            sortConfig.activeSorts.removeAll { $0.id == criterion.id }
            HapticManager.shared.lightImpact()
        }
    }
    
    private func resetToDefault() {
        sortConfig.activeSorts = [JournalSortCriterionIdentifiable(optionRawValue: "dateDesc")]
        HapticManager.shared.lightImpact()
    }
}
