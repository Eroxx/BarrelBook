import SwiftUI
import UIKit

struct JournalSearchOptions {
    var searchText = ""
    var ratingRange: ClosedRange<Double> = 1...10
    var selectedServingMethods: Set<String> = []
    var selectedFlavorCategories: Set<FlavorCategory> = []
    var selectedSubflavors: Set<String> = []

    var sortOption: JournalSortOption = .dateDesc
    
    mutating func toggleServingMethod(_ method: String) {
        if selectedServingMethods.contains(method) {
            selectedServingMethods.remove(method)
        } else {
            selectedServingMethods.insert(method)
        }
    }
    
    mutating func toggleFlavorCategory(_ category: FlavorCategory) {
        if selectedFlavorCategories.contains(category) {
            selectedFlavorCategories.remove(category)
            // Remove all subflavors from this category when category is deselected
            let categorySubflavors = Set(category.subflavors)
            selectedSubflavors = selectedSubflavors.subtracting(categorySubflavors)
        } else {
            selectedFlavorCategories.insert(category)
        }
    }
    
    mutating func toggleSubflavor(_ subflavor: String, category: FlavorCategory) {
        if selectedSubflavors.contains(subflavor) {
            selectedSubflavors.remove(subflavor)
        } else {
            selectedSubflavors.insert(subflavor)
            // Auto-select the category if not already selected
            if !selectedFlavorCategories.contains(category) {
                selectedFlavorCategories.insert(category)
            }
        }
    }
    
    enum JournalSortOption: String, CaseIterable {
        case dateDesc = "Newest First"
        case dateAsc = "Oldest First"
        case ratingDesc = "Highest Rated"
        case ratingAsc = "Lowest Rated"
    }
}

struct JournalView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var toolbarManager = ToolbarVisibilityManager.shared
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \JournalEntry.date, ascending: false)],
        animation: .default)
    private var entries: FetchedResults<JournalEntry>
    
    @State private var showingAddEntry = false
    @State private var editingEntry: JournalEntry?
    @State private var showingEditSheet = false
    @State private var viewMode: ViewMode = .list
    @State private var selectedDate: Date = Date()
    @State private var searchOptions = JournalSearchOptions()
    @State private var showingFilterSheet = false
    @State private var showingSettings = false
    @State private var selectedEntry: JournalEntry?
    @FocusState private var isSearchFocused: Bool
    
    enum ViewMode {
        case list, calendar
    }
    
    // Get flavor categories that have been used in journal entries
    private var usedFlavorCategories: [FlavorCategory] {
        var categoriesWithSelections: Set<FlavorCategory> = []
        
        for entry in entries {
            if let flavorProfileData = entry.flavorProfileData {
                // Check all phases for selected flavors
                for phase in [flavorProfileData.nose, flavorProfileData.palate, flavorProfileData.finish] {
                    for intensity in phase {
                        if intensity.intensity > 0 || !intensity.selectedSubflavors.isEmpty {
                            categoriesWithSelections.insert(intensity.category)
                        }
                    }
                }
            }
        }
        
        return Array(categoriesWithSelections).sorted { $0.rawValue < $1.rawValue }
    }
    
    // Get subflavors that have been used in journal entries
    private var usedSubflavors: [String] {
        var subflavorsByCategory: [FlavorCategory: Set<String>] = [:]
        
        for entry in entries {
            if let flavorProfileData = entry.flavorProfileData {
                // Check all phases for selected subflavors
                for phase in [flavorProfileData.nose, flavorProfileData.palate, flavorProfileData.finish] {
                    for intensity in phase {
                        if !intensity.selectedSubflavors.isEmpty {
                            if subflavorsByCategory[intensity.category] == nil {
                                subflavorsByCategory[intensity.category] = Set<String>()
                            }
                            subflavorsByCategory[intensity.category]?.formUnion(intensity.selectedSubflavors)
                        }
                    }
                }
            }
        }
        
        // Return sorted subflavors
        var allSubflavors: [String] = []
        for category in FlavorCategory.allCases.sorted(by: { $0.rawValue < $1.rawValue }) {
            if let subflavors = subflavorsByCategory[category] {
                allSubflavors.append(contentsOf: subflavors.sorted())
            }
        }
        return allSubflavors
    }
    
    // Get subflavors for selected categories
    private var subflavorsBySelectedCategory: [FlavorCategory: [String]] {
        var result: [FlavorCategory: [String]] = [:]
        
        for category in searchOptions.selectedFlavorCategories {
            var categorySubflavors: Set<String> = []
            
            for entry in entries {
                if let flavorProfileData = entry.flavorProfileData {
                    for phase in [flavorProfileData.nose, flavorProfileData.palate, flavorProfileData.finish] {
                        for intensity in phase where intensity.category == category {
                            categorySubflavors.formUnion(intensity.selectedSubflavors)
                        }
                    }
                }
            }
            
            if !categorySubflavors.isEmpty {
                result[category] = Array(categorySubflavors).sorted()
            }
        }
        
        return result
    }
    
    private var filteredEntries: [JournalEntry] {
        // Move filtering to a background queue
        let entries = self.entries
        let searchText = self.searchOptions.searchText
        let ratingRange = self.searchOptions.ratingRange
        let selectedServingMethods = self.searchOptions.selectedServingMethods
        let selectedFlavorCategories = self.searchOptions.selectedFlavorCategories

        let sortOption = self.searchOptions.sortOption
        
        return DispatchQueue.global(qos: .userInitiated).sync {
            entries.filter { entry in
                var searchText = searchText.trimmingCharacters(in: .whitespaces)
                
                // Check for serving method keywords and toggle filters
                let servingMethodKeywords: [(method: String, keywords: [String])] = [
                    ("Neat", ["neat"]),
                    ("Rocks", ["rocks", "ice"]),
                    ("w/ Water", ["water", "w/ water", "with water"]),
                    ("Custom", ["custom"])
                ]
                
                for (method, keywords) in servingMethodKeywords {
                    for keyword in keywords {
                        if searchText.localizedCaseInsensitiveContains(keyword) {
                            searchText = searchText.replacingOccurrences(of: keyword, with: "", options: [.caseInsensitive])
                            if !selectedServingMethods.contains(method) {
                                DispatchQueue.main.async {
                                    self.searchOptions.toggleServingMethod(method)
                                }
                            }
                        }
                    }
                }
                
                searchText = searchText.trimmingCharacters(in: .whitespaces)
                
                // Check for flavor category and subflavor keywords in search text
                for category in FlavorCategory.allCases {
                    // Check category name
                    if searchText.localizedCaseInsensitiveContains(category.rawValue.lowercased()) {
                        searchText = searchText.replacingOccurrences(of: category.rawValue, with: "", options: [.caseInsensitive])
                        if !searchOptions.selectedFlavorCategories.contains(category) {
                            DispatchQueue.main.async {
                                self.searchOptions.toggleFlavorCategory(category)
                            }
                        }
                    }
                    
                    // Check subflavors
                    for subflavor in category.subflavors {
                        if searchText.localizedCaseInsensitiveContains(subflavor.lowercased()) {
                            searchText = searchText.replacingOccurrences(of: subflavor, with: "", options: [.caseInsensitive])
                            if !searchOptions.selectedSubflavors.contains(subflavor) {
                                DispatchQueue.main.async {
                                    self.searchOptions.toggleSubflavor(subflavor, category: category)
                                }
                            }
                        }
                    }
                }
                
                searchText = searchText.trimmingCharacters(in: .whitespaces)
                
                // Handle field-specific searches
                if searchText.contains(":") {
                    let components = searchText.split(separator: ":", maxSplits: 1)
                    if components.count == 2 {
                        let field = components[0].trimmingCharacters(in: .whitespaces).lowercased()
                        let term = components[1].trimmingCharacters(in: .whitespaces)
                        
                        switch field {
                        case "nose":
                            return entry.nose?.localizedCaseInsensitiveContains(term) == true
                        case "palate":
                            return entry.palate?.localizedCaseInsensitiveContains(term) == true
                        case "finish":
                            return entry.finish?.localizedCaseInsensitiveContains(term) == true
                        case "review":
                            return entry.review?.localizedCaseInsensitiveContains(term) == true
                        case "whiskey":
                            return entry.whiskey?.name?.localizedCaseInsensitiveContains(term) == true
                        default:
                            return false
                        }
                    }
                }
                
                // Regular search across all fields (including flavor profiles)
                let matchesText = searchText.isEmpty ||
                    entry.nose?.localizedCaseInsensitiveContains(searchText) == true ||
                    entry.palate?.localizedCaseInsensitiveContains(searchText) == true ||
                    entry.finish?.localizedCaseInsensitiveContains(searchText) == true ||
                    entry.review?.localizedCaseInsensitiveContains(searchText) == true ||
                    entry.whiskey?.name?.localizedCaseInsensitiveContains(searchText) == true ||
                    matchesFlavorProfileText(entry: entry, searchText: searchText)
                
                let matchesRating = searchOptions.ratingRange.contains(entry.overallRating)
                
                let matchesServingMethod = searchOptions.selectedServingMethods.isEmpty ||
                    (entry.servingMethod != nil && searchOptions.selectedServingMethods.contains(entry.servingMethod!))
                
                let matchesFlavorCategories = searchOptions.selectedFlavorCategories.isEmpty ||
                    matchesSelectedFlavorCategories(entry: entry, categories: searchOptions.selectedFlavorCategories)
                
                let matchesSubflavors = searchOptions.selectedSubflavors.isEmpty ||
                    matchesSelectedSubflavors(entry: entry, subflavors: searchOptions.selectedSubflavors)
                
                return matchesText && matchesRating && matchesServingMethod && matchesFlavorCategories && matchesSubflavors
            }
            .sorted { entry1, entry2 in
                switch searchOptions.sortOption {
                case .dateDesc: return entry1.date ?? Date() > entry2.date ?? Date()
                case .dateAsc: return entry1.date ?? Date() < entry2.date ?? Date()
                case .ratingDesc: return entry1.overallRating > entry2.overallRating
                case .ratingAsc: return entry1.overallRating < entry2.overallRating
                }
            }
        }
    }
    
    // Helper function to match flavor profile text search
    private func matchesFlavorProfileText(entry: JournalEntry, searchText: String) -> Bool {
        guard let flavorProfileData = entry.flavorProfileData else { return false }
        
        for phase in [flavorProfileData.nose, flavorProfileData.palate, flavorProfileData.finish] {
            for intensity in phase {
                // Check category name
                if intensity.category.rawValue.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                // Check subflavors
                for subflavor in intensity.selectedSubflavors {
                    if subflavor.localizedCaseInsensitiveContains(searchText) {
                        return true
                    }
                }
            }
        }
        return false
    }
    
    // Helper function to match selected flavor categories
    private func matchesSelectedFlavorCategories(entry: JournalEntry, categories: Set<FlavorCategory>) -> Bool {
        guard let flavorProfileData = entry.flavorProfileData else { return false }
        
        let phasesToCheck: [(TastingPhase, [FlavorIntensity])] = [
            (.nose, flavorProfileData.nose),
            (.palate, flavorProfileData.palate),
            (.finish, flavorProfileData.finish)
        ]
        
        for category in categories {
            var foundInAnyPhase = false
            
            for (_, intensities) in phasesToCheck {
                if let intensity = intensities.first(where: { $0.category == category }),
                   intensity.intensity > 0 || !intensity.selectedSubflavors.isEmpty {
                    foundInAnyPhase = true
                    break
                }
            }
            
            if !foundInAnyPhase {
                return false // All selected categories must be found
            }
        }
        
        return true
    }
    
    // Helper function to match selected subflavors
    private func matchesSelectedSubflavors(entry: JournalEntry, subflavors: Set<String>) -> Bool {
        guard let flavorProfileData = entry.flavorProfileData else { return false }
        
        let phasesToCheck: [(TastingPhase, [FlavorIntensity])] = [
            (.nose, flavorProfileData.nose),
            (.palate, flavorProfileData.palate),
            (.finish, flavorProfileData.finish)
        ]
        
        for subflavor in subflavors {
            var foundInAnyPhase = false
            
            for (_, intensities) in phasesToCheck {
                for intensity in intensities {
                    if intensity.selectedSubflavors.contains(subflavor) {
                        foundInAnyPhase = true
                        break
                    }
                }
                
                if foundInAnyPhase {
                    break
                }
            }
            
            if !foundInAnyPhase {
                return false // All selected subflavors must be found
            }
        }
        
        return true
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom search bar
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search journal...", text: $searchOptions.searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                    
                    if !searchOptions.searchText.isEmpty {
                        Button {
                            searchOptions.searchText = ""
                            isSearchFocused = false
                            HapticManager.shared.lightImpact()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                
                Button {
                    showingFilterSheet = true
                } label: {
                    Image(systemName: searchOptions.selectedServingMethods.isEmpty && 
                          searchOptions.ratingRange == (1...10) && 
                          searchOptions.selectedFlavorCategories.isEmpty && 
                          searchOptions.selectedSubflavors.isEmpty
                        ? "line.3.horizontal.decrease.circle" 
                        : "line.3.horizontal.decrease.circle.fill")
                        .foregroundColor(Color(red: 0.8, green: 0.6, blue: 0.3))
                        .font(.system(size: 22))
                }
                
                Picker("View Mode", selection: $viewMode) {
                    Image(systemName: "list.bullet").tag(ViewMode.list)
                    Image(systemName: "calendar").tag(ViewMode.calendar)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 80)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(UIColor.systemGroupedBackground))
            
            if viewMode == .list {
                listView
            } else {
                calendarView
            }
        }
        .background(Color(UIColor.systemGroupedBackground))
        .onTapGesture {
            if isSearchFocused {
                isSearchFocused = false
            }
        }
        .overlay(
            FloatingAddButton(action: {
                showingAddEntry = true
                HapticManager.shared.mediumImpact()
            })
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Tastings")
                    .font(.headline)
                    .fontWeight(.bold)
                    .opacity(UIDevice.current.userInterfaceIdiom == .pad ? 0 : 1)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 12) {
                    // Filter button
                    Button {
                        showingFilterSheet = true
                        HapticManager.shared.mediumImpact()
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    
                    // Sort menu
                    Menu {
                        ForEach(JournalSearchOptions.JournalSortOption.allCases, id: \.self) { option in
                            Button {
                                searchOptions.sortOption = option
                                HapticManager.shared.selectionFeedback()
                            } label: {
                                HStack {
                                    Text(option.rawValue)
                                    if searchOptions.sortOption == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                }
                .opacity(UIDevice.current.userInterfaceIdiom == .pad ? 0 : 1)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingSettings = true
                    HapticManager.shared.lightImpact()
                }) {
                    Image(systemName: "gear")
                }
                .opacity(UIDevice.current.userInterfaceIdiom == .pad ? 0 : 1)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isSearchFocused = false
                }
            }
        }
        .sheet(isPresented: $showingAddEntry) {
            AddJournalEntryView()
        }
        .sheet(isPresented: $showingEditSheet, onDismiss: {
            editingEntry = nil
        }) {
            if let entry = editingEntry {
                EditJournalEntryView(entry: entry)
            }
        }
        .sheet(isPresented: $showingFilterSheet) {
            NavigationView {
                Form {
                    Section(header: Text("Rating Range")) {
                        RangeSliderView(value: $searchOptions.ratingRange, in: 1...10)
                            .padding(.vertical)
                    }
                    
                    Section(header: Text("Serving Method")) {
                        ForEach(AddJournalEntryView.ServingMethod.allCases, id: \.self) { method in
                            let methodName = method == .custom ? "Custom" : method.rawValue
                            Toggle(isOn: Binding(
                                get: { searchOptions.selectedServingMethods.contains(methodName) },
                                set: { isSelected in
                                    if isSelected {
                                        searchOptions.selectedServingMethods.insert(methodName)
                                    } else {
                                        searchOptions.selectedServingMethods.remove(methodName)
                                    }
                                }
                            )) {
                                HStack {
                                    Text(method.icon)
                                    Text(method.rawValue)
                                }
                            }
                        }
                    }
                    
                    if !usedFlavorCategories.isEmpty {
                        Section(header: Text("Flavor Categories")) {
                            ForEach(usedFlavorCategories, id: \.self) { category in
                                Toggle(isOn: Binding(
                                    get: { searchOptions.selectedFlavorCategories.contains(category) },
                                    set: { isSelected in
                                        if isSelected {
                                            searchOptions.selectedFlavorCategories.insert(category)
                                        } else {
                                            searchOptions.selectedFlavorCategories.remove(category)
                                        }
                                    }
                                )) {
                                    HStack {
                                        Circle()
                                            .fill(category.color)
                                            .frame(width: 12, height: 12)
                                        Text(category.rawValue)
                                    }
                                }
                            }
                        }
                        
                        if !usedSubflavors.isEmpty {
                            Section(header: Text("Subflavors")) {
                                ForEach(usedSubflavors, id: \.self) { subflavor in
                                    if let category = FlavorCategory.allCases.first(where: { $0.subflavors.contains(subflavor) }) {
                                        Toggle(isOn: Binding(
                                            get: { searchOptions.selectedSubflavors.contains(subflavor) },
                                            set: { isSelected in
                                                if isSelected {
                                                    searchOptions.toggleSubflavor(subflavor, category: category)
                                                } else {
                                                    searchOptions.selectedSubflavors.remove(subflavor)
                                                }
                                            }
                                        )) {
                                            HStack {
                                                Circle()
                                                    .fill(category.color)
                                                    .frame(width: 8, height: 8)
                                                Text(subflavor)
                                                    .font(.caption)
                                                Spacer()
                                                Text(category.rawValue)
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        

                    }
                    
                    Section(header: Text("Sort By")) {
                        Picker("Sort By", selection: $searchOptions.sortOption) {
                            ForEach(JournalSearchOptions.JournalSortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                    
                    Section {
                        Button(role: .destructive) {
                            searchOptions.ratingRange = 1...10
                            searchOptions.selectedServingMethods.removeAll()
                            searchOptions.selectedFlavorCategories.removeAll()
                            searchOptions.selectedSubflavors.removeAll()

                            searchOptions.sortOption = .dateDesc
                            showingFilterSheet = false
                        } label: {
                            HStack {
                                Spacer()
                                Text("Reset Filters")
                                Spacer()
                            }
                        }
                    }
                }
                .navigationTitle("Filter & Sort")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingFilterSheet = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(item: $selectedEntry) { entry in
            NavigationView {
                JournalEntryDetailView(entry: entry)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                selectedEntry = nil
                            }
                        }
                    }
            }
        }
    }
    
    private var listView: some View {
        List {
            ForEach(filteredEntries) { entry in
                Button(action: {
                    selectedEntry = entry
                }) {
                    JournalEntryRowView(entry: entry)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .onDelete { indexSet in
                deleteEntries(indexSet: indexSet)
            }
        }
    }
    
    private var calendarView: some View {
        VStack {
            CalendarView(selectedDate: $selectedDate, entries: entries)
                .padding(.bottom)
            
            Divider()
            
            entriesForSelectedDate
        }
    }
    
    private var entriesForSelectedDate: some View {
        let entriesOnSelectedDate = entriesOnDate(selectedDate)
        
        return Group {
            if entriesOnSelectedDate.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    Text("No entries on \(selectedDate, formatter: dateFormatter)")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Button {
                        showingAddEntry = true
                    } label: {
                        Label("Add Entry", systemImage: "plus")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entriesOnSelectedDate, id: \.self) { entry in
                            VStack(spacing: 0) {
                                Button(action: {
                                    selectedEntry = entry
                                }) {
                                    JournalEntryRowView(entry: entry)
                                        .padding(.horizontal)
                                }
                                .buttonStyle(PlainButtonStyle())
                                
                                Divider()
                                    .padding(.horizontal)
                            }
                        }
                    }
                }
            }
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
    
    private func entriesOnDate(_ date: Date) -> [JournalEntry] {
        entries.filter { entry in
            if let entryDate = entry.date {
                return Calendar.current.isDate(entryDate, inSameDayAs: date)
            }
            return false
        }
    }
    
    private func editEntry(_ entry: JournalEntry) {
        editingEntry = entry
        showingEditSheet = true
    }
    
    private func deleteEntry(_ entry: JournalEntry) {
        withAnimation {
            // Delete from Core Data
            viewContext.delete(entry)
            saveContext()
        }
    }
    
    private func deleteEntries(indexSet: IndexSet) {
        withAnimation {
            let entriesToDelete = indexSet.map { entries[$0] }
            
            // Delete from Core Data
            for entry in entriesToDelete {
                viewContext.delete(entry)
            }
            saveContext()
        }
    }
    
    private func saveContext() {
        do {
            try viewContext.save()
        } catch {
            let nsError = error as NSError
            print("Error saving context: \(nsError), \(nsError.userInfo)")
            viewContext.rollback()
        }
    }
}

struct CalendarView: View {
    @Binding var selectedDate: Date
    let entries: FetchedResults<JournalEntry>
    
    @State private var currentMonth: Date = Date()
    
    private let calendar = Calendar.current
    private let daysOfWeek = ["S", "M", "T", "W", "T", "F", "S"]
    
    var body: some View {
        VStack {
            monthHeader
            
            daysOfWeekHeader
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 10) {
                ForEach(daysInMonth(), id: \.self) { day in
                    if day.date != nil {
                        dayView(day)
                    } else {
                        Color.clear
                            .frame(height: 40)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var monthHeader: some View {
        HStack {
            Button {
                withAnimation {
                    currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth)!
                }
            } label: {
                Image(systemName: "chevron.left")
            }
            
            Spacer()
            
            Text(currentMonth, formatter: monthFormatter)
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            Button {
                withAnimation {
                    currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth)!
                }
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal)
    }
    
    private var daysOfWeekHeader: some View {
        HStack(spacing: 0) {
            ForEach(daysOfWeek, id: \.self) { day in
                Text(day)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
    }
    
    private func dayView(_ day: CalendarDay) -> some View {
        Button {
            if let date = day.date {
                selectedDate = date
            }
        } label: {
            ZStack {
                Circle()
                    .fill(
                        calendar.isDate(day.date ?? Date(), inSameDayAs: selectedDate)
                            ? Color.accentColor.opacity(0.3)
                            : Color.clear
                    )
                    .frame(height: 40)
                
                VStack(spacing: 2) {
                    Text("\(day.dayNumber)")
                        .font(.subheadline)
                        .fontWeight(calendar.isDateInToday(day.date ?? Date()) ? .bold : .regular)
                    
                    if day.hasEntries {
                        Circle()
                            .fill(entryColor(for: day.date ?? Date()))
                            .frame(width: 6, height: 6)
                    } else {
                        Circle()
                            .fill(Color.clear)
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(
            calendar.isDateInToday(day.date ?? Date())
                ? .primary
                : (day.isCurrentMonth ? .primary : .secondary)
        )
    }
    
    private var monthFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }
    
    private func daysInMonth() -> [CalendarDay] {
        guard let monthRange = calendar.range(of: .day, in: .month, for: currentMonth),
              let firstDayOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: currentMonth)) else {
            return []
        }
        
        let firstDayOfWeek = calendar.component(.weekday, from: firstDayOfMonth)
        let offsetDays = (firstDayOfWeek - calendar.firstWeekday + 7) % 7
        
        var days: [CalendarDay] = []
        
        // Add offset days
        for _ in 0..<offsetDays {
            days.append(CalendarDay(dayNumber: 0, date: nil, isCurrentMonth: false, hasEntries: false))
        }
        
        // Add days of the current month
        for day in monthRange {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: firstDayOfMonth) else { continue }
            let hasEntries = hasEntriesOn(date)
            days.append(CalendarDay(dayNumber: day, date: date, isCurrentMonth: true, hasEntries: hasEntries))
        }
        
        return days
    }
    
    private func hasEntriesOn(_ date: Date) -> Bool {
        entries.contains { entry in
            guard let entryDate = entry.date else { return false }
            return calendar.isDate(entryDate, inSameDayAs: date)
        }
    }
    
    private func entryColor(for date: Date) -> Color {
        // Get all entries for the given date
        let entriesOnDate = entries.filter { entry in
            guard let entryDate = entry.date else { return false }
            return calendar.isDate(entryDate, inSameDayAs: date)
        }
        
        // If no entries, return clear color
        if entriesOnDate.isEmpty {
            return .clear
        }
        
        // Find the highest rating among entries
        let highestRating = entriesOnDate.compactMap { entry in
            entry.overallRating > 0 ? entry.overallRating : nil
        }.max() ?? 0
        
        // Return color based on highest rating
        switch highestRating {
        case 1.0..<3.0:
            return ColorManager.ratingPoor
        case 3.0..<5.0:
            return ColorManager.ratingFair
        case 5.0..<7.0:
            return ColorManager.ratingGood
        case 7.0..<9.0:
            return ColorManager.ratingGreat
        case 9.0...10.0:
            return ColorManager.ratingExceptional
        default:
            return .gray
        }
    }
}

struct CalendarDay: Hashable {
    let dayNumber: Int
    let date: Date?
    let isCurrentMonth: Bool
    let hasEntries: Bool
}

struct RangeSliderView: View {
    @Binding var value: ClosedRange<Double>
    let bounds: ClosedRange<Double>
    
    init(value: Binding<ClosedRange<Double>>, in bounds: ClosedRange<Double>) {
        self._value = value
        self.bounds = bounds
    }
    
    var body: some View {
        VStack {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Rating labels
                    HStack {
                        Text(String(format: "%.1f", value.lowerBound))
                            .font(.caption)
                            .foregroundColor(.primary)
                            .frame(width: 24)
                            .offset(x: position(for: value.lowerBound, in: geometry))
                        
                        Spacer()
                        
                        Text(String(format: "%.1f", value.upperBound))
                            .font(.caption)
                            .foregroundColor(.primary)
                            .frame(width: 24)
                            .offset(x: position(for: value.upperBound, in: geometry) - geometry.size.width + 24)
                    }
                    .offset(y: -20)
                    
                    // Background track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)
                    
                    // Active track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: width(for: value, in: geometry), height: 4)
                        .offset(x: position(for: value.lowerBound, in: geometry))
                    
                    // Circles
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 24, height: 24)
                        .position(x: position(for: value.lowerBound, in: geometry) + 12, y: geometry.size.height / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    let newValue = value(at: gesture.location.x, in: geometry)
                                    if newValue < value.upperBound {
                                        value = newValue...value.upperBound
                                    }
                                }
                        )
                    
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 24, height: 24)
                        .position(x: position(for: value.upperBound, in: geometry) + 12, y: geometry.size.height / 2)
                        .gesture(
                            DragGesture()
                                .onChanged { gesture in
                                    let newValue = value(at: gesture.location.x, in: geometry)
                                    if newValue > value.lowerBound {
                                        value = value.lowerBound...newValue
                                    }
                                }
                        )
                }
            }
            .frame(height: 44) // Increased height to accommodate labels
            .padding(.horizontal, 12)
            .padding(.top, 20) // Add padding at the top for the labels
        }
    }
    
    private func position(for value: Double, in geometry: GeometryProxy) -> CGFloat {
        let range = bounds.upperBound - bounds.lowerBound
        let percentage = (value - bounds.lowerBound) / range
        return percentage * (geometry.size.width - 24)
    }
    
    private func width(for range: ClosedRange<Double>, in geometry: GeometryProxy) -> CGFloat {
        let totalRange = bounds.upperBound - bounds.lowerBound
        let lowerPercentage = (range.lowerBound - bounds.lowerBound) / totalRange
        let upperPercentage = (range.upperBound - bounds.lowerBound) / totalRange
        return (upperPercentage - lowerPercentage) * (geometry.size.width - 24) + 24
    }
    
    private func value(at position: CGFloat, in geometry: GeometryProxy) -> Double {
        let percentage = max(0, min(1, position / (geometry.size.width - 24)))
        let range = bounds.upperBound - bounds.lowerBound
        return bounds.lowerBound + range * Double(percentage)
    }
}

struct JournalView_Previews: PreviewProvider {
    static var previews: some View {
        JournalView()
    }
} 