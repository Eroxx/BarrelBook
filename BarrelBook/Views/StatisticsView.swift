import SwiftUI
import CoreData
import Charts

// Define a filter type that can be passed to CollectionView
struct WhiskeyFilter: Equatable {
    enum FilterType {
        case type(String)
        case proof(Double, Double)
        case attribute(String, Bool)
        case distillery(String)
        case finishType(String)
        case subtype(String, String) // Parent type, subtype
        case tastedStatus(Bool) // True for tasted, false for untasted
        case price(Double, Double)
    }
    
    enum FilterSection {
        case collectionOverview
        case specialAttributes
        case topDistilleries
        case collectionComposition
        case proofAnalysis
        case priceAnalysis
        case tastingCoverage
        case coverageByType
    }
    
    let type: FilterType
    let displayName: String
    let section: FilterSection
    
    var isTastedStatusFilter: Bool {
        if case .tastedStatus(_) = type {
            return true
        }
        return false
    }
    
    var isTastingCoverageFilter: Bool {
        // Check if this filter is part of the Tasting Coverage section
        // This includes type filters, attribute filters, and distillery filters
        switch type {
        case .type(_), .attribute(_, _), .distillery(_):
            return true
        default:
            return false
        }
    }
    
    static func == (lhs: WhiskeyFilter, rhs: WhiskeyFilter) -> Bool {
        switch (lhs.type, rhs.type) {
        case (.type(let lhs), .type(let rhs)):
            return lhs == rhs
        case (.proof(let lhsMin, let lhsMax), .proof(let rhsMin, let rhsMax)):
            return lhsMin == rhsMin && lhsMax == rhsMax
        case (.attribute(let lhsKey, let lhsValue), .attribute(let rhsKey, let rhsValue)):
            return lhsKey == rhsKey && lhsValue == rhsValue
        case (.distillery(let lhs), .distillery(let rhs)):
            return lhs == rhs
        case (.finishType(let lhs), .finishType(let rhs)):
            return lhs == rhs
        case (.subtype(let lhsParent, let lhsChild), .subtype(let rhsParent, let rhsChild)):
            return lhsParent == rhsParent && lhsChild == rhsChild
        case (.tastedStatus(let lhs), .tastedStatus(let rhs)):
            return lhs == rhs
        case (.price(let lhsMin, let lhsMax), .price(let rhsMin, let rhsMax)):
            return lhsMin == rhsMin && lhsMax == rhsMax
        default:
            return false
        }
    }
}

// Category tree structure for hierarchical statistics
struct CategoryNode: Identifiable {
    let id = UUID()
    let name: String
    let count: Int
    let tastedCount: Int
    var children: [CategoryNode]?
    var depth: Int
    var nodeId: String // Using a stable ID for tracking expansion state
    var isExpanded: Bool
    var parentType: String? // Add this to track the parent type
    
    var coveragePercentage: Double {
        return count > 0 ? Double(tastedCount) / Double(count) * 100 : 0
    }
    
    init(name: String, count: Int, tastedCount: Int, children: [CategoryNode]? = nil, depth: Int, isExpanded: Bool, parentType: String? = nil) {
        self.name = name
        self.count = count
        self.tastedCount = tastedCount
        self.children = children
        self.depth = depth
        self.nodeId = "\(depth)_\(name)"
        self.isExpanded = isExpanded
        self.parentType = parentType
    }
}

// Extension to extract useful data from Whiskey objects
extension Whiskey {
    // Derived property to determine finish type
    var finishType: String? {
        // Extract from finish field or name using pattern matching
        if let finish = self.finish, !finish.isEmpty {
            return finish
        } else if let name = self.name?.lowercased() {
            // Pattern matching for common finish mentions
            if name.contains("port") { return "Port" }
            if name.contains("sherry") { return "Sherry" }
            if name.contains("madeira") { return "Madeira" }
            if name.contains("rum") { return "Rum" }
            if name.contains("cognac") { return "Cognac" }
            // Can add more common finishes
        }
        return nil
    }
    
    // Helper for whiskey subtypes
    var subtypeCategory: String? {
        if let _ = finishType { 
            return "Finished" 
        }
        if self.isSiB { return "Single Barrel" }
        if self.isBiB { return "Bottled in Bond" }
        if self.isStorePick { return "Store Pick" }
        return "Standard"
    }
}

// Manager class to handle hierarchical data and state
class StatisticsManager: ObservableObject {
    @Published var categoryTree: [CategoryNode] = []
    @Published var expansionState: [String: Bool] = [:]
    
    // Store references for refreshing the tree
    var whiskeys: [Whiskey]?
    var whiskeyIds: Set<NSManagedObjectID>?
    
    // Generate category tree from whiskeys
    func generateCategoryTree(whiskeys: [Whiskey], whiskeyIds: Set<NSManagedObjectID>) {
        // Store references for refreshing
        self.whiskeys = whiskeys
        self.whiskeyIds = whiskeyIds
        
        // Group whiskeys by primary type
        var typeGroups: [String: [Whiskey]] = [:]
        
        for whiskey in whiskeys {
            let type = whiskey.type ?? "Unspecified"
            if typeGroups[type] == nil {
                typeGroups[type] = []
            }
            typeGroups[type]?.append(whiskey)
        }
        
        // Build tree
        var rootNodes: [CategoryNode] = []
        
        for (type, typeWhiskeys) in typeGroups {
            // Count tasted in this type
            let tastedCount = typeWhiskeys.filter { whiskeyIds.contains($0.objectID) }.count
            
            // Group by subtype 
            var subtypeGroups: [String: [Whiskey]] = [:]
            for whiskey in typeWhiskeys {
                let subtype = whiskey.subtypeCategory ?? "Standard"
                if subtypeGroups[subtype] == nil {
                    subtypeGroups[subtype] = []
                }
                subtypeGroups[subtype]?.append(whiskey)
            }
            
            // Create subtype nodes
            var subtypeNodes: [CategoryNode] = []
            for (subtype, subtypeWhiskeys) in subtypeGroups {
                let subtypeTastedCount = subtypeWhiskeys.filter { whiskeyIds.contains($0.objectID) }.count
                
                // For finishes, go one level deeper
                var finishNodes: [CategoryNode]? = nil
                if subtype == "Finished" {
                    var finishGroups: [String: [Whiskey]] = [:]
                    for whiskey in subtypeWhiskeys {
                        if let finish = whiskey.finishType {
                            if finishGroups[finish] == nil {
                                finishGroups[finish] = []
                            }
                            finishGroups[finish]?.append(whiskey)
                        }
                    }
                    
                    if !finishGroups.isEmpty {
                        finishNodes = finishGroups.map { finish, finishWhiskeys in
                            let finishTastedCount = finishWhiskeys.filter { whiskeyIds.contains($0.objectID) }.count
                            let nodeID = "2_\(finish)"
                            let isExpanded = expansionState[nodeID] ?? shouldAutoExpand(name: finish, count: finishWhiskeys.count, tastedCount: finishTastedCount, depth: 2)
                            
                            return CategoryNode(
                                name: finish,
                                count: finishWhiskeys.count,
                                tastedCount: finishTastedCount,
                                children: nil,
                                depth: 2,
                                isExpanded: isExpanded,
                                parentType: subtype
                            )
                        }.sorted { $0.count > $1.count }
                    }
                }
                
                // Create subtype node
                let subtypeNodeID = "1_\(subtype)"
                let isSubtypeExpanded = expansionState[subtypeNodeID] ?? shouldAutoExpand(name: subtype, count: subtypeWhiskeys.count, tastedCount: subtypeTastedCount, depth: 1)
                
                let subtypeNode = CategoryNode(
                    name: subtype,
                    count: subtypeWhiskeys.count,
                    tastedCount: subtypeTastedCount,
                    children: finishNodes,
                    depth: 1,
                    isExpanded: isSubtypeExpanded,
                    parentType: type
                )
                subtypeNodes.append(subtypeNode)
            }
            
            // Create type node with subtype children
            let typeNodeID = "0_\(type)"
            let isTypeExpanded = expansionState[typeNodeID] ?? shouldAutoExpand(name: type, count: typeWhiskeys.count, tastedCount: tastedCount, depth: 0)
            
            let typeNode = CategoryNode(
                name: type,
                count: typeWhiskeys.count,
                tastedCount: tastedCount,
                children: subtypeNodes.sorted { $0.count > $1.count },
                depth: 0,
                isExpanded: isTypeExpanded,
                parentType: nil
            )
            
            rootNodes.append(typeNode)
        }
        
        categoryTree = rootNodes.sorted { $0.count > $1.count }
    }
    
    // Logic to determine if a node should auto-expand
    private func shouldAutoExpand(name: String, count: Int, tastedCount: Int, depth: Int) -> Bool {
        let coverage = tastedCount > 0 ? Double(tastedCount) / Double(count) * 100 : 0
        
        // Primary types should always be expanded by default
        if depth == 0 {
            return true
        }
        
        // Subtypes with low coverage should be expanded
        if depth == 1 && coverage < 50 && count > 2 {
            return true
        }
        
        // Finishes should generally start collapsed
        if depth == 2 {
            return false
        }
        
        return false
    }
    
    // Toggle expansion state of a node
    func toggleExpansion(for nodeID: String) {
        // Update the expansion state dictionary
        expansionState[nodeID] = !(expansionState[nodeID] ?? false)
        
        // Rebuild the tree with the updated expansion states
        // This ensures the UI will refresh with the new state
        if let lastTree = categoryTree.first {
            objectWillChange.send()
            updateNodeExpansion(in: &categoryTree, nodeID: nodeID)
        }
    }
    
    // Helper to update node expansion throughout the tree
    private func updateNodeExpansion(in nodes: inout [CategoryNode], nodeID: String) {
        for i in 0..<nodes.count {
            if nodes[i].nodeId == nodeID {
                // Update this node's expansion state
                nodes[i] = CategoryNode(
                    name: nodes[i].name,
                    count: nodes[i].count,
                    tastedCount: nodes[i].tastedCount,
                    children: nodes[i].children,
                    depth: nodes[i].depth,
                    isExpanded: !(nodes[i].isExpanded),
                    parentType: nodes[i].parentType
                )
                return
            }
            
            // Recursively check children
            if var children = nodes[i].children {
                updateNodeExpansion(in: &children, nodeID: nodeID)
                nodes[i] = CategoryNode(
                    name: nodes[i].name,
                    count: nodes[i].count,
                    tastedCount: nodes[i].tastedCount,
                    children: children,
                    depth: nodes[i].depth,
                    isExpanded: nodes[i].isExpanded,
                    parentType: nodes[i].parentType
                )
            }
        }
    }
}

// UI component for displaying a single category node
struct CategoryView: View {
    let node: CategoryNode
    let onToggle: (String) -> Void
    let onSelect: (CategoryNode) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header button (name and expand/collapse)
            Button(action: {
                onToggle(node.nodeId)
            }) {
                HStack {
                    Text(node.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text("\(node.count)")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    
                    Image(systemName: node.isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle()) // Make the entire row tappable
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.leading, CGFloat(node.depth * 16))
            
            if node.isExpanded {
                // Coverage bar
                Button(action: { onSelect(node) }) {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: Double(node.tastedCount), total: Double(node.count))
                            .progressViewStyle(LinearProgressViewStyle(tint: coverageColor(node.coveragePercentage)))
                        
                        Text("\(node.tastedCount)/\(node.count) (\(Int(node.coveragePercentage))%)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle()) // Make the entire progress bar tappable
                }
                .padding(.leading, CGFloat(node.depth * 16 + 16))
                .buttonStyle(PlainButtonStyle())
                
                // Render children if expanded
                if let children = node.children, !children.isEmpty {
                    ForEach(children) { child in
                        CategoryView(node: child, onToggle: onToggle, onSelect: onSelect)
                    }
                }
            }
        }
    }
    
    private func coverageColor(_ percentage: Double) -> Color {
        if percentage < 30 {
            return ColorManager.progressLow
        } else if percentage < 70 {
            return ColorManager.progressMedium
        } else {
            return ColorManager.progressHigh
        }
    }
}

// Main view for hierarchical category display
struct HierarchicalCoverageView: View {
    @ObservedObject var manager: StatisticsManager
    @Binding var selectedFilter: WhiskeyFilter?
    @Binding var showingFilteredView: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title and Expand/Collapse Buttons
            HStack {
                Text("Coverage by Type")
                    .font(.headline)
                
                Spacer()
                
                // Add collapse/expand all buttons
                Button(action: {
                    HapticManager.shared.selectionFeedback()
                    toggleAll(expanded: true)
                }) {
                    Label("Expand All", systemImage: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.trailing, 8)
                
                Button(action: {
                    HapticManager.shared.selectionFeedback()
                    toggleAll(expanded: false)
                }) {
                    Label("Collapse All", systemImage: "chevron.up")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 4)
            
            if manager.categoryTree.isEmpty {
                Text("No type data available")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                // Hierarchical tree view
                ForEach(manager.categoryTree) { node in
                    CategoryView(
                        node: node,
                        onToggle: { nodeID in
                            HapticManager.shared.selectionFeedback()
                            manager.toggleExpansion(for: nodeID)
                        },
                        onSelect: { node in
                            HapticManager.shared.selectionFeedback()
                            createFilter(from: node)
                        }
                    )
                    .padding(.bottom, 4)
                }
            }
        }
    }
    
    // Helper to toggle all categories
    private func toggleAll(expanded: Bool) {
        // Set all top-level nodes (and their children) to the desired expansion state
        for node in manager.categoryTree {
            // Set the current node
            manager.expansionState[node.nodeId] = expanded
            
            // Set all children recursively
            if let children = node.children {
                setChildrenExpansion(children: children, expanded: expanded)
            }
        }
        
        // Refresh the tree
        if let whiskeys = manager.whiskeys, let whiskeyIds = manager.whiskeyIds {
            manager.generateCategoryTree(whiskeys: whiskeys, whiskeyIds: whiskeyIds)
        }
    }
    
    // Helper to recursively set expansion state for children
    private func setChildrenExpansion(children: [CategoryNode], expanded: Bool) {
        for child in children {
            manager.expansionState[child.nodeId] = expanded
            
            if let grandchildren = child.children {
                setChildrenExpansion(children: grandchildren, expanded: expanded)
            }
        }
    }
    
    private func createFilter(from node: CategoryNode) {
        // Create appropriate filter based on node type and depth
        switch node.depth {
        case 0: // Top level - Type
            if node.name == "Other" {
                // For the "Other" category, don't create a direct filter
                // as it would be confusing since it contains mixed types
                return
            } else {
                selectedFilter = WhiskeyFilter(
                    type: .type(node.name),
                    displayName: "Type: \(node.name)",
                    section: .collectionOverview
                )
            }
        case 1: // Second level - Subtype
            if let parentType = node.parentType {
                if node.name == "Finished" {
                    selectedFilter = WhiskeyFilter(
                        type: .subtype(parentType, "Finished"),
                        displayName: "Finished \(parentType)",
                        section: .specialAttributes
                    )
                } else if node.name == "Single Barrel" {
                    selectedFilter = WhiskeyFilter(
                        type: .subtype(parentType, "Single Barrel"),
                        displayName: "Single Barrel \(parentType)",
                        section: .specialAttributes
                    )
                } else if node.name == "Bottled in Bond" {
                    selectedFilter = WhiskeyFilter(
                        type: .subtype(parentType, "Bottled in Bond"),
                        displayName: "Bottled in Bond \(parentType)",
                        section: .specialAttributes
                    )
                } else if node.name == "Store Pick" {
                    selectedFilter = WhiskeyFilter(
                        type: .subtype(parentType, "Store Pick"),
                        displayName: "Store Pick \(parentType)",
                        section: .specialAttributes
                    )
                } else if node.name == "No Special Attributes" {
                    selectedFilter = WhiskeyFilter(
                        type: .subtype(parentType, "Standard"),
                        displayName: "Regular \(parentType) (No Special Attributes)",
                        section: .specialAttributes
                    )
                }
            }
        case 2: // Third level - Finish type
            if let parentType = node.parentType {
                selectedFilter = WhiskeyFilter(
                    type: .finishType(node.name),
                    displayName: "Finish: \(node.name)",
                    section: .specialAttributes
                )
            }
        default:
            break
        }
        
        if selectedFilter != nil {
            showingFilteredView = true
        }
    }
}

// Add this extension at the top of the file, before any struct definitions
extension EnvironmentValues {
    struct StatisticsNavigationResetKey: EnvironmentKey {
        static let defaultValue: UUID = UUID()
    }
    
    var statisticsNavigationReset: UUID {
        get { self[StatisticsNavigationResetKey.self] }
        set { self[StatisticsNavigationResetKey.self] = newValue }
    }
}

struct StatisticsView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        entity: Whiskey.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Whiskey.name, ascending: true)],
        predicate: NSPredicate(format: "status == %@ AND status != %@", "owned", "wishlist"),
        animation: .default
    ) private var whiskeys: FetchedResults<Whiskey>
    
    @State private var selectedFilter: WhiskeyFilter?
    @Binding var showingFilteredView: Bool
    @State private var showingSettings = false
    @State private var scrollPosition: CGFloat = 0
    @State private var lastScrolledSection: String?
    
    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                ScrollView {
                    VStack(spacing: 24) {
                        // Collection Overview Card
                        StatCard(title: "Collection Overview") {
                            CombinedCollectionStats(
                                whiskeys: whiskeys, 
                                onAttributeSelected: { attribute, value in
                                    selectedFilter = WhiskeyFilter(
                                        type: .attribute(attribute, value),
                                        displayName: attribute,
                                        section: .collectionOverview
                                    )
                                    showingFilteredView = true
                                }, 
                                onDistillerySelected: { distillery in
                                    selectedFilter = WhiskeyFilter(
                                        type: .distillery(distillery),
                                        displayName: "Distillery: \(distillery)",
                                        section: .specialAttributes
                                    )
                                    showingFilteredView = true
                                }
                            )
                        }
                        .id("overview")
                        
                        // Collection Composition Card
                        StatCard(title: "Collection Composition") {
                            WhiskeyTypeStats(whiskeys: whiskeys, onTypeSelected: { type in
                                selectedFilter = WhiskeyFilter(
                                    type: .type(type),
                                    displayName: "Type: \(type)",
                                    section: .collectionComposition
                                )
                                showingFilteredView = true
                            })
                        }
                        .id("composition")
                        
                        // Proof Analysis Card
                        StatCard(title: "Proof Analysis") {
                            ProofAnalysisStats(whiskeys: whiskeys, onProofRangeSelected: { min, max, label in
                                selectedFilter = WhiskeyFilter(
                                    type: .proof(min, max),
                                    displayName: "Proof: \(label)",
                                    section: .proofAnalysis
                                )
                                showingFilteredView = true
                            })
                        }
                        .id("proof")
                        
                        // Price Analysis Card
                        StatCard(title: "Price Analysis") {
                            PriceAnalysisStats(whiskeys: whiskeys, onPriceRangeSelected: { min, max, label in
                                selectedFilter = WhiskeyFilter(
                                    type: .price(min, max),
                                    displayName: "Price: \(label)",
                                    section: .priceAnalysis
                                )
                                showingFilteredView = true
                            })
                        }
                        .id("price")
                        
                        // Tasting Coverage Card
                        StatCard(title: "Tasting Coverage") {
                            TastingCoverageStats(context: viewContext, whiskeys: whiskeys, selectedFilter: $selectedFilter, showingFilteredView: $showingFilteredView)
                        }
                        .id("tasting")
                    }
                    .padding()
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(key: ScrollOffsetPreferenceKey.self, value: geometry.frame(in: .named("scroll")).minY)
                        }
                    )
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollPosition = value
                }
                .onAppear {
                    // Only restore to the last scrolled section if we have one
                    if let section = lastScrolledSection {
                        withAnimation {
                            proxy.scrollTo(section, anchor: .top)
                        }
                    }
                }
                
                // Navigation link for filtered view
                NavigationLink(
                    destination: FilteredCollectionView(filter: selectedFilter),
                    isActive: $showingFilteredView
                ) {
                    EmptyView()
                }
            }
            .onChange(of: selectedFilter) { filter in
                if let filter = filter {
                    // Store the current section before navigating
                    switch filter.section {
                    case .collectionOverview:
                        lastScrolledSection = "overview"
                    case .collectionComposition:
                        lastScrolledSection = "composition"
                    case .proofAnalysis:
                        lastScrolledSection = "proof"
                    case .priceAnalysis:
                        lastScrolledSection = "price"
                    case .tastingCoverage, .coverageByType:
                        lastScrolledSection = "tasting"
                    default:
                        break
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Statistics")
                    .font(.headline)
                    .fontWeight(.bold)
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
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

// Preference key to track scroll position
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// New Combined Collection Overview + Special Attributes Stats
struct CombinedCollectionStats: View {
    let whiskeys: FetchedResults<Whiskey>
    let onAttributeSelected: (String, Bool) -> Void
    let onDistillerySelected: (String) -> Void
    
    // Cache calculations
    private var totalInventory: Int {
        // Calculate total bottles directly from each whiskey's numberOfBottles property
        // rather than counting bottle instances, which may be inconsistent
        whiskeys.reduce(0) { total, whiskey in
            return total + Int(whiskey.numberOfBottles)
        }
    }
    
    private var totalValue: Double {
        whiskeys.reduce(0) { total, whiskey in
            total + (whiskey.price * Double(whiskey.numberOfBottles))
        }
    }
    
    private var tastedCount: Int {
        whiskeys.filter { ($0.journalEntries?.count ?? 0) > 0 || $0.isTasted }.count
    }
    
    private var caskStrengthCount: Int {
        whiskeys.filter { $0.isCaskStrength }.count
    }
    
    private var biBCount: Int {
        whiskeys.filter { $0.isBiB }.count
    }
    
    private var siBCount: Int {
        whiskeys.filter { $0.isSiB }.count
    }
    
    private var storePickCount: Int {
        whiskeys.filter { $0.isStorePick }.count
    }
    
    private var highProofCount: Int {
        whiskeys.filter { $0.proof > 100 }.count
    }
    
    // Lazy calculated property for distillery data
    private var distilleryBreakdown: [TypeCount] {
        var distilleryCounts: [String: Int] = [:]
        
        for whiskey in whiskeys {
            if let distillery = whiskey.distillery, !distillery.isEmpty {
                distilleryCounts[distillery, default: 0] += 1
            }
        }
        
        return distilleryCounts.map { TypeCount(type: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Primary metrics in a grid layout
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                // First row: Unique Bottles, Total Inventory
                StatMetricView(
                    title: "Unique Bottles",
                    value: "\(whiskeys.count)",
                    systemImage: "wineglass"
                )
                StatMetricView(
                    title: "Total Inventory",
                    value: "\(totalInventory)",
                    systemImage: "shippingbox"
                )
                // Second row: Whiskeys Tasted, Dead Bottles
                StatMetricView(
                    title: "Whiskeys Tasted",
                    value: "\(tastedCount)",
                    systemImage: "checkmark.seal"
                )
                StatMetricView(
                    title: "Dead Bottles",
                    value: "\(whiskeys.reduce(0) { $0 + Int($1.deadBottleCount) })",
                    systemImage: "xmark.bin"
                )
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Special Attributes Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Special Attributes")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                // Special attributes in a grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    // Bottles Tasted
                    AttributeButton(
                        title: "Bottles Tasted",
                        count: tastedCount,
                        action: { onAttributeSelected("Tasted", true) }
                    )
                    
                    // Cask Strength
                    AttributeButton(
                        title: "Cask Strength",
                        count: caskStrengthCount,
                        action: { onAttributeSelected("Cask Strength", true) }
                    )

                    // Bottled in Bond
                    AttributeButton(
                        title: "Bottled in Bond",
                        count: biBCount,
                        action: { onAttributeSelected("Bottled in Bond", true) }
                    )
                    
                    // Single Barrel
                    AttributeButton(
                        title: "Single Barrel",
                        count: siBCount,
                        action: { onAttributeSelected("Single Barrel", true) }
                    )
                    
                    // Store Picks
                    AttributeButton(
                        title: "Store Picks",
                        count: storePickCount,
                        action: { onAttributeSelected("Store Picks", true) }
                    )
                    
                    // High Proof
                    AttributeButton(
                        title: "High Proof",
                        count: highProofCount,
                        action: { onAttributeSelected("High Proof", true) }
                    )
                }
            }
            
            // Distillery breakdown if we have distillery data
            let topDistilleries = distilleryBreakdown.prefix(6)
            if !topDistilleries.isEmpty {
                Divider()
                    .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Top Distilleries")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    // Distilleries in a grid layout
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(topDistilleries) { item in
                            DistilleryButton(
                                name: item.type,
                                count: item.count,
                                action: { onDistillerySelected(item.type) }
                            )
                        }
                    }
                }
            }
        }
    }
    
    // Format currency values
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}

// Helper view for metric display
struct StatMetricView: View {
    let title: String
    let value: String
    let systemImage: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(8)
    }
}

// Helper view for attribute buttons
struct AttributeButton: View {
    let title: String
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text("\(count)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.accentColor)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: Color(.systemGray4), radius: 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Helper view for distillery buttons
struct DistilleryButton: View {
    let name: String
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            HapticManager.shared.selectionFeedback()
            action()
        }) {
            HStack {
                Text(name)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                Text("\(count)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Color(UIColor.secondarySystemGroupedBackground))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FilteredCollectionView: View {
    let filter: WhiskeyFilter?
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest private var whiskeys: FetchedResults<Whiskey>
    @State private var displayTitle: String = ""
    @State private var topTypes: [String] = [] // Store top types for filtering
    
    // Add the FilterType enum
    private enum FilterType {
        case tasted
        case untasted
    }
    
    // Add the filterType computed property
    private var filterType: FilterType {
        if case .tastedStatus(let isTasted) = filter?.type {
            return isTasted ? .tasted : .untasted
        }
        return .tasted // Default to tasted if not specified
    }
    
    init(filter: WhiskeyFilter?) {
        self.filter = filter
        
        // Create the appropriate predicate based on the filter type
        let predicate: NSPredicate?
        
        if let filter = filter {
            // Create a more efficient predicate based on the filter type
            predicate = Self.createPredicate(for: filter)
        } else {
            predicate = nil
        }
        
        // Initialize FetchRequest with our predicate
        _whiskeys = FetchRequest<Whiskey>(
            sortDescriptors: [NSSortDescriptor(keyPath: \Whiskey.name, ascending: true)],
            predicate: predicate,
            animation: .default
        )
    }
    
    // Static method to create optimized predicates
    private static func createPredicate(for filter: WhiskeyFilter) -> NSPredicate? {
        // Base predicate to exclude external whiskeys - only owned whiskeys should be shown
        let baseStatusPredicate = NSPredicate(format: "(status == %@ OR status == nil)", "owned")
        
        // Filter-specific predicate
        let filterPredicate: NSPredicate?
        
        switch filter.type {
        case .type(let type):
            filterPredicate = NSPredicate(format: "type == %@", type)
            
        case .proof(let min, let max):
            if max == Double.infinity {
                filterPredicate = NSPredicate(format: "proof >= %f", min)
            } else {
                filterPredicate = NSPredicate(format: "proof >= %f AND proof < %f", min, max)
            }
            
        case .attribute(let attribute, let value):
            // For "Other Types" attributes, use a permissive predicate
            if attribute.hasSuffix("in Other Types") {
                // For "Other" category filters, don't apply any predicate initially
                // We'll filter them manually in the view to exclude top types
                return baseStatusPredicate
            } else if attribute == "finish" {
                filterPredicate = NSPredicate(format: "finish != nil AND finish != ''")
            } else {
                // Handle regular attribute filters
                switch attribute {
                case "Bottled in Bond":
                    filterPredicate = NSPredicate(format: "isBiB == %@", NSNumber(value: value))
                case "Single Barrel":
                    filterPredicate = NSPredicate(format: "isSiB == %@", NSNumber(value: value))
                case "Store Picks", "Store Pick":
                    filterPredicate = NSPredicate(format: "isStorePick == %@", NSNumber(value: value))
                case "High Proof":
                    filterPredicate = NSPredicate(format: "proof > 100")
                case "Tasted":
                    filterPredicate = NSPredicate(format: "(SUBQUERY(journalEntries, $entry, $entry != nil).@count > 0) OR (isTasted == %@)", NSNumber(value: true))
                case "Cask Strength":
                    filterPredicate = NSPredicate(format: "isCaskStrength == %@", NSNumber(value: true))
                default:
                    return baseStatusPredicate
                }
            }
            
        case .distillery(let distillery):
            filterPredicate = NSPredicate(format: "distillery == %@", distillery)
            
        case .finishType(let finishType):
            let finishPredicate = NSPredicate(format: "finish CONTAINS[cd] %@", finishType)
            let namePredicate = NSPredicate(format: "name CONTAINS[cd] %@", finishType)
            filterPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                finishPredicate, namePredicate
            ])
            
        case .subtype(let parent, let child):
            // Create a basic predicate for the parent type
            let typePredicate = NSPredicate(format: "type == %@", parent)
            
            // Create a predicate for the specific subtype attribute
            var subtypePredicate: NSPredicate
            switch child {
            case "Finished":
                subtypePredicate = NSPredicate(format: "finish != nil AND finish != ''")
            case "Single Barrel":
                subtypePredicate = NSPredicate(format: "isSiB == %@", NSNumber(value: true))
            case "Bottled in Bond":
                subtypePredicate = NSPredicate(format: "isBiB == %@", NSNumber(value: true))
            case "Store Pick":
                subtypePredicate = NSPredicate(format: "isStorePick == %@", NSNumber(value: true))
            case "Standard":
                subtypePredicate = NSPredicate(format: "(finish == nil OR finish == '') AND isSiB == %@ AND isBiB == %@ AND isStorePick == %@",
                                             NSNumber(value: false),
                                             NSNumber(value: false),
                                             NSNumber(value: false))
            default:
                // If we don't recognize the subtype, just use the parent type
                subtypePredicate = NSPredicate(value: true)
            }
            
            // Combine the type predicate and subtype predicate with AND
            filterPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                typePredicate, subtypePredicate
            ])
            
        case .tastedStatus(let isTasted):
            if isTasted {
                // A whiskey is considered tasted if it has journal entries OR isTasted is true
                filterPredicate = NSPredicate(format: "(SUBQUERY(journalEntries, $entry, $entry != nil).@count > 0) OR (isTasted == %@)", NSNumber(value: true))
            } else {
                // A whiskey is considered untasted if it has NO journal entries AND isTasted is false
                filterPredicate = NSPredicate(format: "(SUBQUERY(journalEntries, $entry, $entry != nil).@count == 0) AND (isTasted == %@)", NSNumber(value: false))
            }
            
        case .price(let min, let max):
            if max == Double.infinity {
                filterPredicate = NSPredicate(format: "price >= %f", min)
            } else {
                filterPredicate = NSPredicate(format: "price >= %f AND price < %f", min, max)
            }
        }
        
        // Combine base status predicate with filter predicate
        if let filterPredicate = filterPredicate {
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                baseStatusPredicate, filterPredicate
            ])
        } else {
            return baseStatusPredicate
        }
    }
    
    // After initialization, we use this to check if we're filtering for "Other" types
    private var isOtherTypesFilter: Bool {
        if case .attribute(let attribute, _) = filter?.type {
            return attribute.hasSuffix("in Other Types")
        }
        return false
    }
    
    var body: some View {
        Group {
            if filteredWhiskeys.isEmpty {
                VStack(spacing: 20) {
                    Text("No matching whiskeys found")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    if isOtherTypesFilter {
                        Text("There are no matching whiskeys in the 'Other' category.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemGroupedBackground))
            } else {
                List {
                    ForEach(filteredWhiskeys) { whiskey in
                        NavigationLink(destination: WhiskeyDetailView(whiskey: whiskey)
                            .onDisappear {
                                // Only refresh the whiskey itself without updating the filtered list
                                viewContext.refresh(whiskey, mergeChanges: true)
                            }
                        ) {
                            WhiskeyRowView(whiskey: whiskey)
                        }
                    }
                }
            }
        }
        .navigationTitle(filter?.displayName ?? "Filtered Collection")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Text("\(filteredWhiskeys.count) bottle\(filteredWhiskeys.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onAppear {
            // Set the correct title
            displayTitle = filter?.displayName ?? "Filtered Collection"
            
            // Update the filter for "Other Types" filters
            if isOtherTypesFilter {
                loadTopTypes()
            }
            
            // Add debug logging to verify correct filtering
            if case let .tastedStatus(isTasted) = filter?.type {
                print("FilteredCollectionView: Filtering for \(isTasted ? "tasted" : "untasted") whiskeys")
                print("FilteredCollectionView: Found \(filteredWhiskeys.count) matching whiskeys")
                
                // Print the first few whiskeys to verify they match the filter
                let sampleWhiskeys = Array(filteredWhiskeys.prefix(3))
                for whiskey in sampleWhiskeys {
                    print("Sample whiskey: \(whiskey.name ?? "Unknown") - isTasted=\(whiskey.isTasted), journalEntries=\(whiskey.journalEntries?.count ?? 0)")
                }
                
                // Print all whiskeys to verify they match the filter
                print("All filtered whiskeys:")
                for whiskey in filteredWhiskeys {
                    let hasJournalEntries = (whiskey.journalEntries?.count ?? 0) > 0
                    let isTastedProperty = whiskey.isTasted
                    let isActuallyTasted = hasJournalEntries || isTastedProperty
                    print("  - \(whiskey.name ?? "Unknown"): isTasted=\(isTastedProperty), journalEntries=\(hasJournalEntries), isActuallyTasted=\(isActuallyTasted)")
                }
                
                // Check if the 1792 12 year is in the results
                let targetWhiskey = filteredWhiskeys.first { $0.name?.contains("1792 12 year") ?? false }
                if let targetWhiskey = targetWhiskey {
                    print("DEBUG: Found 1792 12 year in filtered results")
                    print("DEBUG: isTasted property: \(targetWhiskey.isTasted)")
                    print("DEBUG: journalEntries count: \(targetWhiskey.journalEntries?.count ?? 0)")
                } else {
                    print("DEBUG: 1792 12 year not found in filtered results")
                    
                    // Check if it's in the original whiskeys
                    let originalWhiskeys = Array(whiskeys)
                    let originalTargetWhiskey = originalWhiskeys.first { $0.name?.contains("1792 12 year") ?? false }
                    if let originalTargetWhiskey = originalTargetWhiskey {
                        print("DEBUG: Found 1792 12 year in original whiskeys")
                        print("DEBUG: isTasted property: \(originalTargetWhiskey.isTasted)")
                        print("DEBUG: journalEntries count: \(originalTargetWhiskey.journalEntries?.count ?? 0)")
                        
                        // Check if it should be included based on our filtering logic
                        let hasJournalEntries = (originalTargetWhiskey.journalEntries?.count ?? 0) > 0
                        let isTastedProperty = originalTargetWhiskey.isTasted
                        let isActuallyTasted = hasJournalEntries || isTastedProperty
                        print("DEBUG: Should be included? \(isActuallyTasted == isTasted)")
                    } else {
                        print("DEBUG: 1792 12 year not found in original whiskeys")
                    }
                }
                
                // Check if the Core Data predicate is working correctly
                print("DEBUG: Checking Core Data predicate results")
                let allWhiskeys = Array(whiskeys)
                print("DEBUG: Total whiskeys from Core Data: \(allWhiskeys.count)")
                
                // Count how many whiskeys match our manual filtering criteria
                let manuallyFilteredCount = allWhiskeys.filter { whiskey in
                    let hasJournalEntries = (whiskey.journalEntries?.count ?? 0) > 0
                    let isTastedProperty = whiskey.isTasted
                    let isActuallyTasted = hasJournalEntries || isTastedProperty
                    return isActuallyTasted == isTasted
                }.count
                
                print("DEBUG: Manually filtered count: \(manuallyFilteredCount)")
                print("DEBUG: Difference between Core Data and manual filtering: \(abs(manuallyFilteredCount - filteredWhiskeys.count))")
            }
            
            // Add debug logging to verify correct filtering
            if case let .subtype(parentType, subtypeValue) = filter?.type {
                print("Filtering with subtype: \(parentType) - \(subtypeValue)")
                print("Found \(filteredWhiskeys.count) matching whiskeys")
                
                // Print the first few whiskeys to verify they match the filter
                let sampleWhiskeys = Array(filteredWhiskeys.prefix(3))
                for whiskey in sampleWhiskeys {
                    print("Sample whiskey: \(whiskey.name ?? "Unknown") - Type: \(whiskey.type ?? "Unknown")")
                }
                
                // Verify all whiskeys match the parent type
                let wrongTypeCount = filteredWhiskeys.filter { $0.type != parentType }.count
                if wrongTypeCount > 0 {
                    print("WARNING: \(wrongTypeCount) whiskeys don't match parent type \(parentType)")
                }
            }
        }
    }
    
    // This is our new filtered whiskeys list that handles the "Other" category
    private var filteredWhiskeys: [Whiskey] {
        var filtered = Array(whiskeys)
        
        // Apply base filter if present
        if let currentFilter = filter {
            switch currentFilter.type {
            case .type(let type):
                print("DEBUG: Applying type filter for: \(type)")
                filtered = filtered.filter { $0.type == type }
                print("DEBUG: After type filter: \(filtered.count) whiskeys")
            case .proof(let min, let max):
                print("DEBUG: Applying proof filter: \(min)-\(max)")
                filtered = filtered.filter { $0.proof >= min && (max == Double.infinity || $0.proof < max) }
                print("DEBUG: After proof filter: \(filtered.count) whiskeys")
            case .attribute(let attribute, _):
                print("DEBUG: Applying attribute filter: \(attribute)")
                // Handle attribute filtering...
                if attribute.hasSuffix("in Other Types") {
                    print("DEBUG: Handling 'Other Types' attribute filter")
                    // Handle "Other" types filtering...
                } else {
                    print("DEBUG: Handling regular attribute filter")
                    // Handle regular attributes...
                }
            case .distillery(let distillery):
                print("DEBUG: Applying distillery filter: \(distillery)")
                filtered = filtered.filter { $0.distillery == distillery }
                print("DEBUG: After distillery filter: \(filtered.count) whiskeys")
            case .finishType(let finishType):
                print("DEBUG: Applying finish type filter: \(finishType)")
                filtered = filtered.filter { 
                    ($0.finish?.contains(finishType) ?? false) || 
                    ($0.name?.localizedCaseInsensitiveContains(finishType) ?? false)
                }
                print("DEBUG: After finish type filter: \(filtered.count) whiskeys")
            case .subtype(let parent, let child):
                print("DEBUG: Applying subtype filter: \(parent) - \(child)")
                filtered = filtered.filter { whiskey in
                    guard whiskey.type == parent else { return false }
                    switch child {
                    case "Finished":
                        return whiskey.finish != nil && !whiskey.finish!.isEmpty
                    case "Single Barrel":
                        return whiskey.isSiB
                    case "Bottled in Bond":
                        return whiskey.isBiB
                    case "Store Pick":
                        return whiskey.isStorePick
                    case "Standard":
                        return (whiskey.finish == nil || whiskey.finish!.isEmpty) &&
                               !whiskey.isSiB && !whiskey.isBiB && !whiskey.isStorePick
                    default:
                        return true
                    }
                }
                print("DEBUG: After subtype filter: \(filtered.count) whiskeys")
            case .tastedStatus(_):
                // Only apply tasted status filter for tasting-related views
                if displayTitle.contains("Tasting Coverage") {
                    print("DEBUG: Applying tasted status filter for tasting coverage view")
                    filtered = filtered.filter { whiskey in
                        switch filterType {
                        case .tasted:
                            let hasJournalEntries = (whiskey.journalEntries?.count ?? 0) > 0
                            let isMarkedAsTasted = whiskey.isTasted
                            return hasJournalEntries || isMarkedAsTasted
                        case .untasted:
                            let hasJournalEntries = (whiskey.journalEntries?.count ?? 0) > 0
                            let isMarkedAsTasted = whiskey.isTasted
                            return !hasJournalEntries && !isMarkedAsTasted
                        }
                    }
                } else {
                    print("DEBUG: Skipping tasted status filter for non-tasting view")
                }
                print("DEBUG: After tasted filter: \(filtered.count) whiskeys")
            case .price(let min, let max):
                print("DEBUG: Applying price filter: \(min)-\(max)")
                filtered = filtered.filter { $0.price >= min && (max == Double.infinity || $0.price < max) }
                print("DEBUG: After price filter: \(filtered.count) whiskeys")
            }
        }
        
        return filtered
    }
    
    // This function loads the top whiskey types
    private func loadTopTypes() {
        topTypes = getTopTypes(count: 3)
        
        // Log what we're doing to help debug
        print("Filtering for Other Types. Top types excluded: \(topTypes)")
        
        if case .attribute(let attribute, _) = filter?.type {
            print("Attribute filter: \(attribute)")
        }
    }
    
    // Get top whiskey types by count
    private func getTopTypes(count: Int) -> [String] {
        let fetchRequest: NSFetchRequest<Whiskey> = Whiskey.fetchRequest()
        
        do {
            let results = try viewContext.fetch(fetchRequest)
            let typeCounts = Dictionary(grouping: results, by: { $0.type ?? "Unspecified" }).mapValues { $0.count }
            return typeCounts.sorted { $0.value > $1.value }.prefix(count).map { $0.key }
        } catch {
            print("Error fetching whiskey types: \(error)")
            return []
        }
    }
    
    // Handle the filtering for "Other Types" after initialization
    private func getFilteredOtherTypesWhiskeys() -> [Whiskey] {
        guard case .attribute(let attribute, _) = filter?.type, attribute.hasSuffix("in Other Types") else {
            return Array(whiskeys)
        }
        
        // Use the cached top types if we already have them
        let typesToExclude = topTypes.isEmpty ? getTopTypes(count: 3) : topTypes
        
        // Filter the whiskeys manually:
        let filtered = whiskeys.filter { whiskey in
            // 1. It must NOT be one of the top types
            guard let type = whiskey.type, !typesToExclude.contains(type) else {
                return false
            }
            
            // 2. It must match the attribute - we'll check each case
            if attribute.hasPrefix("Finished Whiskeys in Other") {
                return whiskey.finish != nil && !whiskey.finish!.isEmpty
            } else if attribute.hasPrefix("Single Barrel in Other") {
                return whiskey.isSiB
            } else if attribute.hasPrefix("Bottled in Bond in Other") {
                return whiskey.isBiB
            } else if attribute.hasPrefix("Store Picks in Other") {
                return whiskey.isStorePick
            } else if attribute.hasPrefix("No Special Attributes in Other") {
                // This is a new case for whiskeys with no special attributes
                return (whiskey.finish == nil || whiskey.finish!.isEmpty) && 
                       !whiskey.isSiB && 
                       !whiskey.isBiB && 
                       !whiskey.isStorePick
            }
            
            // Default case
            return true
        }
        
        return filtered
    }
}

// Reusable card component for statistics
struct StatCard<Content: View>: View {
    let title: String
    let systemImage: String?
    let content: Content
    
    init(title: String, systemImage: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(.bottom, 4)
            
            content
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

// Collection Overview Statistics
struct CollectionOverviewStats: View {
    let whiskeys: FetchedResults<Whiskey>
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                StatCounter(
                    value: "\(whiskeys.count)",
                    label: "Unique Bottles"
                )
                
                // Count whiskeys with journal entries as "opened"
                StatCounter(
                    value: "\(whiskeys.filter { ($0.journalEntries?.count ?? 0) > 0 }.count)",
                    label: "Opened"
                )
                
                StatCounter(
                    value: "\(whiskeys.filter { $0.deadBottleCount > 0 }.count)",
                    label: "Finished"
                )
            }
            
            HStack(spacing: 20) {
                StatCounter(
                    value: "\(whiskeys.filter { $0.proof > 100 }.count)",
                    label: "High Proof"
                )
                
                StatCounter(
                    value: "\(whiskeys.map { Int($0.numberOfBottles) }.reduce(0, +))",
                    label: "Total Inventory"
                )
            }
        }
    }
}

// Whiskey Type Breakdown
struct WhiskeyTypeStats: View {
    let whiskeys: FetchedResults<Whiskey>
    let onTypeSelected: (String) -> Void
    
    var body: some View {
        let typeData = calculateTypeBreakdown()
        
        if typeData.isEmpty {
            Text("No type data available")
                .foregroundColor(.secondary)
                .italic()
        } else {
            // Clean list of whiskey types
            VStack(alignment: .leading, spacing: 12) {
                ForEach(typeData) { item in
                    Button(action: {
                        HapticManager.shared.selectionFeedback()
                        onTypeSelected(item.type)
                    }) {
                        HStack {
                            Circle()
                                .fill(colorForIndex(typeData.firstIndex(where: { $0.id == item.id }) ?? 0))
                                .frame(width: 12, height: 12)
                            Text(item.type)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(item.count)")
                                .foregroundColor(.secondary)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    private func calculateTypeBreakdown() -> [TypeCount] {
        var typeCounts: [String: Int] = [:]
        
        for whiskey in whiskeys {
            if let type = whiskey.type, !type.isEmpty {
                typeCounts[type, default: 0] += 1
            } else {
                typeCounts["Unspecified", default: 0] += 1
            }
        }
        
        return typeCounts.map { TypeCount(type: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
    
    private func colorForIndex(_ index: Int) -> Color {
        return ColorManager.chartColor(at: index)
    }
}

// Proof Analysis
struct ProofAnalysisStats: View {
    let whiskeys: FetchedResults<Whiskey>
    let onProofRangeSelected: (Double, Double, String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Proof Ranges
            let proofRanges = calculateProofRanges()
            
            Text("Proof Distribution")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 8)
            
            if #available(iOS 16.0, *), !proofRanges.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(proofRanges) { range in
                            let maxCount = proofRanges.map(\.count).max() ?? 1
                            let height = 150.0 * Double(range.count) / Double(maxCount)
                            
                            Button {
                                HapticManager.shared.selectionFeedback()
                                onProofRangeSelected(range.min, range.max, range.label)
                            } label: {
                                VStack {
                                    Rectangle()
                                        .fill(ColorManager.priceLow.gradient)
                                        .frame(height: height)
                                    
                                    Text(range.label)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 180)
                    
                    HStack {
                        ForEach(proofRanges) { range in
                            Text("\(range.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                // Fallback for iOS 15 or empty data
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(proofRanges) { range in
                        Button(action: {
                            HapticManager.shared.selectionFeedback()
                            onProofRangeSelected(range.min, range.max, range.label)
                        }) {
                            HStack {
                                Text(range.label)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(range.count)")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                if proofRanges.isEmpty {
                    Text("No proof data available")
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
    }
    
    private func calculateProofRanges() -> [ProofRange] {
        let proofs = whiskeys.map { $0.proof }
        let validProofs = proofs.filter { $0 > 0 }
        if validProofs.isEmpty { return [] }
        
        // Define proof ranges with exact boundaries
        let ranges: [(min: Double, max: Double, label: String)] = [
            (0, 80, "Under 80°"),
            (80, 90, "80-90°"),
            (90, 100, "90-100°"),
            (100, 110, "100-110°"),
            (110, 120, "110-120°"),
            (120, 200, "120+°")  // Use 200 as a reasonable upper bound instead of infinity
        ]
        
        return ranges.map { range in
            let count = validProofs.filter { proof in
                // For the last range (120+), include all values >= 120
                if range.min == 120 {
                    return proof >= range.min
                } else {
                    return proof >= range.min && proof < range.max
                }
            }.count
            
            return ProofRange(
                min: range.min,
                max: range.max,
                label: range.label,
                count: count
            )
        }
    }
}

// Price Analysis
struct PriceAnalysisStats: View {
    let whiskeys: FetchedResults<Whiskey>
    let onPriceRangeSelected: (Double, Double, String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Price Ranges
            let priceRanges = calculatePriceRanges()
            
            Text("Price Distribution")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 8)
            
            if #available(iOS 16.0, *), !priceRanges.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(priceRanges) { range in
                            let maxCount = priceRanges.map(\.count).max() ?? 1
                            let height = 150.0 * Double(range.count) / Double(maxCount)
                            
                            Button {
                                HapticManager.shared.selectionFeedback()
                                onPriceRangeSelected(range.min, range.max, range.label)
                            } label: {
                                VStack {
                                    Rectangle()
                                        .fill(ColorManager.priceLow.gradient)
                                        .frame(height: height)
                                    
                                    Text(range.label)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 180)
                    
                    HStack {
                        ForEach(priceRanges) { range in
                            Text("\(range.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                // Fallback for iOS 15 or empty data
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(priceRanges) { range in
                        Button(action: {
                            HapticManager.shared.selectionFeedback()
                            onPriceRangeSelected(range.min, range.max, range.label)
                        }) {
                            HStack {
                                Text(range.label)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(range.count)")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                if priceRanges.isEmpty {
                    Text("No price data available")
                        .foregroundColor(.secondary)
                        .italic()
                }
            }
        }
    }
    
    private func calculatePriceRanges() -> [PriceRange] {
        let prices = whiskeys.map { $0.price }
        let validPrices = prices.filter { $0 > 0 }
        if validPrices.isEmpty { return [] }
        
        // Define price ranges with exact boundaries
        let ranges: [(min: Double, max: Double, label: String)] = [
            (0, 30, "Under $30"),
            (30, 50, "$30-$50"),
            (50, 70, "$50-$70"),
            (70, 100, "$70-$100"),
            (100, 150, "$100-$150"),
            (150, 1000, "$150+")  // Use 1000 as a reasonable upper bound instead of infinity
        ]
        
        return ranges.map { range in
            let count = validPrices.filter { price in
                // For the last range ($150+), include all values >= 150
                if range.min == 150 {
                    return price >= range.min
                } else {
                    return price >= range.min && price < range.max
                }
            }.count
            
            return PriceRange(
                min: range.min,
                max: range.max,
                label: range.label,
                count: count
            )
        }
    }
}

// Price range model
struct PriceRange: Identifiable {
    let id = UUID()
    let min: Double
    let max: Double
    let label: String
    let count: Int
}

// Special Attributes Stats
struct SpecialAttributesStats: View {
    let whiskeys: FetchedResults<Whiskey>
    let onAttributeSelected: (String, Bool) -> Void
    let onDistillerySelected: (String) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                Button(action: {
                    onAttributeSelected("Bottled in Bond", true)
                }) {
                    StatCounter(
                        value: "\(whiskeys.filter { $0.isBiB }.count)",
                        label: "Bottled in Bond"
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    onAttributeSelected("Single Barrel", true)
                }) {
                    StatCounter(
                        value: "\(whiskeys.filter { $0.isSiB }.count)",
                        label: "Single Barrel"
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    onAttributeSelected("Store Picks", true)
                }) {
                    StatCounter(
                        value: "\(whiskeys.filter { $0.isStorePick }.count)",
                        label: "Store Picks"
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Distillery breakdown if we have distillery data
            let distilleryData = calculateDistilleryBreakdown()
            if !distilleryData.isEmpty {
                Divider()
                    .padding(.vertical)
                
                Text("Top Distilleries")
                    .font(.headline)
                    .padding(.bottom, 4)
                
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(distilleryData.prefix(5)) { item in
                        Button(action: {
                            onDistillerySelected(item.type)
                        }) {
                            HStack {
                                Text(item.type)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("\(item.count)")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }
    
    private func calculateDistilleryBreakdown() -> [TypeCount] {
        var distilleryCounts: [String: Int] = [:]
        
        for whiskey in whiskeys {
            if let distillery = whiskey.distillery, !distillery.isEmpty {
                distilleryCounts[distillery, default: 0] += 1
            }
        }
        
        return distilleryCounts.map { TypeCount(type: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }
}

// Reusable counter view
struct StatCounter: View {
    let value: String
    let label: String
    let systemImage: String?
    
    init(value: String, label: String, systemImage: String? = nil) {
        self.value = value
        self.label = label
        self.systemImage = systemImage
    }
    
    var body: some View {
        VStack {
            Text(value)
                .font(.title)
                .fontWeight(.bold)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// Helper model structures
struct TypeCount: Identifiable {
    let id = UUID()
    let type: String
    let count: Int
}

struct ProofRange: Identifiable {
    let id = UUID()
    let min: Double
    let max: Double
    let label: String
    let count: Int
}

struct SpecialCount: Identifiable {
    let id = UUID()
    let type: String
    let count: Int
}

// Tasting Coverage Statistics
struct TastingCoverageStats: View {
    let context: NSManagedObjectContext
    let whiskeys: FetchedResults<Whiskey>
    
    @StateObject private var statisticsManager = StatisticsManager()
    @Binding var selectedFilter: WhiskeyFilter?
    @Binding var showingFilteredView: Bool
    
    @State private var tastedWhiskeys: [Whiskey] = []
    @State private var typeStatistics: [TypeStatistic] = []
    @State private var expandedTypes: Set<String> = []
    @State private var isLoading: Bool = true
    
    var body: some View {
        VStack(spacing: 16) {
            if isLoading {
                ProgressView()
                    .padding()
            } else {
                // Overall Coverage Progress
                VStack {
                    if !whiskeys.isEmpty {
                        // Use the extracted progress circle component
                        TastingProgressCircle(
                            tastedCount: Double(tastedWhiskeys.count),
                            totalCount: Double(whiskeys.count)
                        )
                        .padding(.bottom, 8)
                        
                        Text("\(tastedWhiskeys.count) of \(whiskeys.count) bottles tasted")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        // Use the extracted action buttons component
                        TastingActionButtons(
                            selectedFilter: $selectedFilter,
                            showingFilteredView: $showingFilteredView
                        )
                        .padding(.top, 8)
                    } else {
                        Text("No whiskeys in collection")
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                
                typeStatisticsView
            }
        }
        .onAppear {
            loadTastingData()
        }
    }
    
    private var typeStatisticsView: some View {
        Group {
            if !typeStatistics.isEmpty {
                Divider()
                    .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 12) {
                    // Header with expand/collapse all button
                    HStack {
                        Text("Coverage by Type")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button(action: toggleAllTypes) {
                            Text(expandedTypes.count == typeStatistics.count ? "Collapse All" : "Expand All")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(.bottom, 4)
                    
                    // Type rows
                    ForEach(typeStatistics) { typeStat in
                        typeRow(for: typeStat)
                    }
                }
            }
        }
    }
    
    private func toggleAllTypes() {
        if expandedTypes.count == typeStatistics.count {
            expandedTypes.removeAll()
        } else {
            expandedTypes = Set(typeStatistics.map { $0.name })
        }
    }
    
    private func loadTastingData() {
        isLoading = true
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Make a copy of the whiskeys to work with on the background thread
            let whiskeysArray = Array(whiskeys)
            
            // Process whiskey data directly using isTasted property
            let (tasted, typeStats) = self.processWhiskeyData(whiskeys: whiskeysArray)
            
            // Determine which types to auto-expand
            let expandedTypes = self.determineExpandedTypes(typeStats: typeStats)
            
            // Update UI on main thread
            DispatchQueue.main.async {
                self.tastedWhiskeys = tasted
                self.typeStatistics = typeStats
                self.expandedTypes = expandedTypes
                self.isLoading = false
            }
        }
    }
    
    // Helper function to process whiskey data and generate statistics
    private func processWhiskeyData(whiskeys: [Whiskey]) -> (tasted: [Whiskey], typeStats: [TypeStatistic]) {
        // Sort whiskeys into tasted
        var tasted: [Whiskey] = []
        
        // Group whiskeys by type for type-level statistics
        var typeMap: [String: (total: Int, tasted: Int, attributes: [String: (total: Int, tasted: Int)])] = [:]
        
        for whiskey in whiskeys {
            // Get basic properties with safe unwrapping
            let type = whiskey.type ?? "Unspecified"
            // Check both journal entries and isTasted property
            let isTasted = (whiskey.journalEntries?.count ?? 0) > 0 || whiskey.isTasted
            
            // Add to tasted list
            if isTasted {
                tasted.append(whiskey)
            }
            
            // Initialize type entry if needed
            if typeMap[type] == nil {
                typeMap[type] = (total: 0, tasted: 0, attributes: [:])
            }
            
            // Increment type counts
            typeMap[type]!.total += 1
            if isTasted {
                typeMap[type]!.tasted += 1
            }
            
            // Now handle attributes - initialize all attribute counters if needed
            let attributeTypes = ["Finished", "Single Barrel", "Bottled in Bond", "Store Pick", "No Special Attributes"]
            for attrType in attributeTypes {
                if typeMap[type]!.attributes[attrType] == nil {
                    typeMap[type]!.attributes[attrType] = (total: 0, tasted: 0)
                }
            }
            
            // Track if this whiskey has any special attributes
            var hasSpecialAttributes = false
            
            // Check each attribute independently and update counts
            if whiskey.finish != nil && !whiskey.finish!.isEmpty {
                hasSpecialAttributes = true
                typeMap[type]!.attributes["Finished"]!.total += 1
                if isTasted {
                    typeMap[type]!.attributes["Finished"]!.tasted += 1
                }
            }
            
            if whiskey.isSiB {
                hasSpecialAttributes = true
                typeMap[type]!.attributes["Single Barrel"]!.total += 1
                if isTasted {
                    typeMap[type]!.attributes["Single Barrel"]!.tasted += 1
                }
            }
            
            if whiskey.isBiB {
                hasSpecialAttributes = true
                typeMap[type]!.attributes["Bottled in Bond"]!.total += 1
                if isTasted {
                    typeMap[type]!.attributes["Bottled in Bond"]!.tasted += 1
                }
            }
            
            if whiskey.isStorePick {
                hasSpecialAttributes = true
                typeMap[type]!.attributes["Store Pick"]!.total += 1
                if isTasted {
                    typeMap[type]!.attributes["Store Pick"]!.tasted += 1
                }
            }
            
            // If no special attributes, count in the "No Special Attributes" category
            if !hasSpecialAttributes {
                typeMap[type]!.attributes["No Special Attributes"]!.total += 1
                if isTasted {
                    typeMap[type]!.attributes["No Special Attributes"]!.tasted += 1
                }
            }
        }
        
        // Convert the map to an array of TypeStatistic objects
        let typeStats = createTypeStatistics(from: typeMap, allWhiskeys: whiskeys)
        
        return (tasted, typeStats)
    }
    
    // Helper function to create TypeStatistic objects from the typeMap
    private func createTypeStatistics(from typeMap: [String: (total: Int, tasted: Int, attributes: [String: (total: Int, tasted: Int)])], allWhiskeys: [Whiskey]) -> [TypeStatistic] {
        var typeStats: [TypeStatistic] = []
        
        // Get all types sorted by total count (descending)
        let sortedTypes = typeMap.sorted { $0.value.total > $1.value.total }
        
        // Display top 3 types individually
        let maxIndividualTypes = 3
        let displayTypes = sortedTypes.prefix(min(maxIndividualTypes, sortedTypes.count))
        
        // Get the names of the top types
        let topTypeNames = displayTypes.map { $0.key }
        
        // Create TypeStatistic objects for the top types
        for (typeName, stats) in displayTypes {
            var attributes: [SubtypeStatistic] = []
            
            // Convert attribute stats to SubtypeStatistic objects
            for (attributeName, attrStats) in stats.attributes {
                // Only include attributes that have bottles
                if attrStats.total > 0 {
                    let tastedCount = attrStats.tasted
                    let totalCount = attrStats.total
                    let percentage = totalCount > 0 ? Double(tastedCount) / Double(totalCount) * 100 : 0
                    
                    attributes.append(SubtypeStatistic(
                        id: UUID(),
                        name: attributeName,
                        tastedCount: tastedCount,
                        totalCount: totalCount,
                        percentage: percentage
                    ))
                }
            }
            
            // Sort attributes by total count (descending), but always put "No Special Attributes" last
            attributes.sort { (a, b) -> Bool in
                if a.name == "No Special Attributes" {
                    return false
                }
                if b.name == "No Special Attributes" {
                    return true
                }
                return a.totalCount > b.totalCount
            }
            
            typeStats.append(TypeStatistic(
                id: UUID(),
                name: typeName,
                tastedCount: stats.tasted,
                totalCount: stats.total,
                subtypes: attributes
            ))
        }
        
        // Create an "Other" category for remaining types if needed
        if sortedTypes.count > maxIndividualTypes {
            // Reset all counters for "Other" category
            var otherTotalCount = 0
            var otherTastedCount = 0
            var otherAttributes: [String: (tasted: Int, total: Int)] = [
                "Finished": (0, 0),
                "Single Barrel": (0, 0),
                "Bottled in Bond": (0, 0),
                "Store Pick": (0, 0),
                "No Special Attributes": (0, 0)
            ]
            
            // Count whiskeys not in the top types
            for whiskey in allWhiskeys {
                // Skip whiskeys in the top types
                guard let type = whiskey.type, !topTypeNames.contains(type) else {
                    continue
                }
                
                // Check both journal entries and isTasted property
                let isTasted = (whiskey.journalEntries?.count ?? 0) > 0 || whiskey.isTasted
                
                // Count for "Other" total
                otherTotalCount += 1
                if isTasted {
                    otherTastedCount += 1
                }
                
                // Track if this whiskey has any special attributes
                var hasSpecialAttributes = false
                
                // Check each attribute independently
                if whiskey.finish != nil && !whiskey.finish!.isEmpty {
                    hasSpecialAttributes = true
                    otherAttributes["Finished"]!.total += 1
                    if isTasted {
                        otherAttributes["Finished"]!.tasted += 1
                    }
                }
                
                if whiskey.isSiB {
                    hasSpecialAttributes = true
                    otherAttributes["Single Barrel"]!.total += 1
                    if isTasted {
                        otherAttributes["Single Barrel"]!.tasted += 1
                    }
                }
                
                if whiskey.isBiB {
                    hasSpecialAttributes = true
                    otherAttributes["Bottled in Bond"]!.total += 1
                    if isTasted {
                        otherAttributes["Bottled in Bond"]!.tasted += 1
                    }
                }
                
                if whiskey.isStorePick {
                    hasSpecialAttributes = true
                    otherAttributes["Store Pick"]!.total += 1
                    if isTasted {
                        otherAttributes["Store Pick"]!.tasted += 1
                    }
                }
                
                // If no special attributes, count in the "No Special Attributes" category
                if !hasSpecialAttributes {
                    otherAttributes["No Special Attributes"]!.total += 1
                    if isTasted {
                        otherAttributes["No Special Attributes"]!.tasted += 1
                    }
                }
            }
            
            // Create SubtypeStatistic objects for the "Other" category
            var otherAttributeStats: [SubtypeStatistic] = []
            for (attributeName, stats) in otherAttributes {
                // Only include attributes that have bottles
                if stats.total > 0 {
                    let percentage = Double(stats.tasted) / Double(stats.total) * 100
                    otherAttributeStats.append(SubtypeStatistic(
                        id: UUID(),
                        name: attributeName,
                        tastedCount: stats.tasted,
                        totalCount: stats.total,
                        percentage: percentage
                    ))
                }
            }
            
            // Sort Other attributes by total count (descending), but put "No Special Attributes" last
            otherAttributeStats.sort { (a, b) -> Bool in
                if a.name == "No Special Attributes" {
                    return false
                }
                if b.name == "No Special Attributes" {
                    return true
                }
                return a.totalCount > b.totalCount
            }
            
            // Add the "Other" category to typeStats
            typeStats.append(TypeStatistic(
                id: UUID(),
                name: "Other",
                tastedCount: otherTastedCount,
                totalCount: otherTotalCount,
                subtypes: otherAttributeStats
            ))
        }
        
        return typeStats
    }
    
    // Helper function to generate diverse recommendations
    private func generateDiverseRecommendations(untastedWhiskeys: [Whiskey]) -> [Whiskey] {
        if untastedWhiskeys.isEmpty {
            return []
        }
        
        var diverseUntasted = [Whiskey]()
        
        // Group untasted whiskeys by type
        var whiskeysGroupedByType: [String: [Whiskey]] = [:]
        for whiskey in untastedWhiskeys {
            let type = whiskey.type ?? "Unspecified"
            if whiskeysGroupedByType[type] == nil {
                whiskeysGroupedByType[type] = []
            }
            whiskeysGroupedByType[type]?.append(whiskey)
        }
        
        // Get types sorted by number of untasted bottles (descending)
        let typesSortedByCount = whiskeysGroupedByType.keys.sorted {
            whiskeysGroupedByType[$0]?.count ?? 0 > whiskeysGroupedByType[$1]?.count ?? 0
        }
        
        // Early return if no types
        if typesSortedByCount.isEmpty {
            return untastedWhiskeys.sorted { ($0.name ?? "") < ($1.name ?? "") }
        }
        
        // Take one from each type until we have enough or run out of types
        var typeIndex = 0
        while diverseUntasted.count < untastedWhiskeys.count && typeIndex < typesSortedByCount.count {
            let type = typesSortedByCount[typeIndex]
            if let whiskeyGroup = whiskeysGroupedByType[type], !whiskeyGroup.isEmpty {
                // Sort by proof within type to get variety
                let sortedByProof = whiskeyGroup.sorted { $0.proof > $1.proof }
                
                // Get the bottle with highest proof from this type
                if let whiskey = sortedByProof.first {
                    diverseUntasted.append(whiskey)
                    // Remove the selected whiskey from the group
                    whiskeysGroupedByType[type] = Array(sortedByProof.dropFirst())
                }
            }
            
            // Move to next type or loop back to beginning
            typeIndex = (typeIndex + 1) % typesSortedByCount.count
            
            // If we've gone through all types once, break if we have at least 3 recommendations
            if typeIndex == 0 && diverseUntasted.count >= 3 {
                break
            }
        }
        
        // Fallback to alphabetical sort if we couldn't create diverse recommendations
        if diverseUntasted.isEmpty {
            return untastedWhiskeys.sorted { ($0.name ?? "") < ($1.name ?? "") }
        }
        
        return diverseUntasted
    }
    
    // Helper function to determine which types should be auto-expanded
    private func determineExpandedTypes(typeStats: [TypeStatistic]) -> Set<String> {
        var expandedTypes = Set<String>()
        
        // Auto-expand top types
        if typeStats.count > 0 {
            expandedTypes.insert(typeStats[0].name)
        }
        if typeStats.count > 1 {
            expandedTypes.insert(typeStats[1].name)
        }
        
        // Always auto-expand "Other" category if it exists
        if let otherStat = typeStats.first(where: { $0.name == "Other" }) {
            expandedTypes.insert(otherStat.name)
        }
        
        // Always auto-expand "Whiskey" category if it exists
        if let whiskeyStat = typeStats.first(where: { $0.name == "Whiskey" }) {
            expandedTypes.insert(whiskeyStat.name)
        }
        
        return expandedTypes
    }
    
    // Helper to check if a type is expanded
    private func isExpanded(_ typeName: String) -> Bool {
        return expandedTypes.contains(typeName)
    }
    
    // Toggle expanded state for a type
    private func toggleExpanded(_ typeName: String) {
        if expandedTypes.contains(typeName) {
            expandedTypes.remove(typeName)
        } else {
            expandedTypes.insert(typeName)
        }
    }
    
    // Handle subtype selection
    private func subtypeSelected(_ typeName: String, _ subtypeName: String) {
        print("Selected subtype: \(subtypeName) under type: \(typeName)")
        
        // For the "Other" category, we need to filter by subtype AND limit to types in the "Other" category
        if typeName == "Other" {
            // Get the top 3 types that are displayed individually (not in "Other")
            let topTypes = typeStatistics.filter { $0.name != "Other" }.prefix(3).map { $0.name }
            
            switch subtypeName {
            case "Finished":
                selectedFilter = WhiskeyFilter(
                    type: .attribute("Finished Whiskeys in Other Types", true),
                    displayName: "Finished Whiskeys in Other Types",
                    section: .coverageByType
                )
            case "Single Barrel":
                selectedFilter = WhiskeyFilter(
                    type: .attribute("Single Barrel in Other Types", true),
                    displayName: "Single Barrel in Other Types",
                    section: .coverageByType
                )
            case "Bottled in Bond":
                selectedFilter = WhiskeyFilter(
                    type: .attribute("Bottled in Bond in Other Types", true),
                    displayName: "Bottled in Bond in Other Types",
                    section: .coverageByType
                )
            case "Store Pick":
                selectedFilter = WhiskeyFilter(
                    type: .attribute("Store Picks in Other Types", true),
                    displayName: "Store Picks in Other Types",
                    section: .coverageByType
                )
            case "No Special Attributes":
                selectedFilter = WhiskeyFilter(
                    type: .attribute("No Special Attributes in Other Types", true),
                    displayName: "Regular Whiskeys in Other Types",
                    section: .coverageByType
                )
            default:
                selectedFilter = WhiskeyFilter(
                    type: .attribute(subtypeName + " in Other Types", true),
                    displayName: subtypeName + " in Other Types",
                    section: .coverageByType
                )
            }
        } else {
            // For regular types, create a filter that combines type AND subtype
            switch subtypeName {
            case "Finished":
                selectedFilter = WhiskeyFilter(
                    type: .subtype(typeName, "Finished"),
                    displayName: "Finished \(typeName)",
                    section: .coverageByType
                )
            case "Single Barrel":
                selectedFilter = WhiskeyFilter(
                    type: .subtype(typeName, "Single Barrel"),
                    displayName: "Single Barrel \(typeName)",
                    section: .coverageByType
                )
            case "Bottled in Bond":
                selectedFilter = WhiskeyFilter(
                    type: .subtype(typeName, "Bottled in Bond"),
                    displayName: "Bottled in Bond \(typeName)",
                    section: .coverageByType
                )
            case "Store Pick":
                selectedFilter = WhiskeyFilter(
                    type: .subtype(typeName, "Store Pick"),
                    displayName: "Store Pick \(typeName)",
                    section: .coverageByType
                )
            case "No Special Attributes":
                selectedFilter = WhiskeyFilter(
                    type: .subtype(typeName, "Standard"),
                    displayName: "Regular \(typeName) (No Special Attributes)",
                    section: .coverageByType
                )
            default:
                selectedFilter = WhiskeyFilter(
                    type: .subtype(typeName, subtypeName),
                    displayName: "\(subtypeName) \(typeName)",
                    section: .coverageByType
                )
            }
        }
        
        showingFilteredView = true
        HapticManager.shared.selectionFeedback()
    }
    
    private func coverageColor(_ percentage: Double) -> Color {
        if percentage < 30 {
            return ColorManager.progressLow
        } else if percentage < 70 {
            return ColorManager.progressMedium
        } else {
            return ColorManager.progressHigh
        }
    }
    
    private func typeRow(for typeStat: TypeStatistic) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Type header row (collapsible)
            Button(action: {
                if typeStat.name == "Other" {
                    // For "Other", we want to filter by all types not in the top types
                    let topTypes = typeStatistics.filter { $0.name != "Other" }.prefix(3).map { $0.name }
                    let otherTypesFilter = WhiskeyFilter(
                        type: .attribute("Other Types", true),
                        displayName: "Other Types",
                        section: .coverageByType
                    )
                    selectedFilter = otherTypesFilter
                    showingFilteredView = true
                    HapticManager.shared.selectionFeedback()
                } else {
                    // If already expanded, clicking again should filter by this type
                    if isExpanded(typeStat.name) {
                        // Filter by this type
                        selectedFilter = WhiskeyFilter(
                            type: .type(typeStat.name),
                            displayName: typeStat.name,
                            section: .coverageByType
                        )
                        showingFilteredView = true
                        HapticManager.shared.selectionFeedback()
                    } else {
                        // Otherwise just toggle expansion
                        toggleExpanded(typeStat.name)
                    }
                }
            }) {
                TypeHeaderRow(
                    typeStat: typeStat,
                    isExpanded: isExpanded(typeStat.name)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            // Subtype rows (when expanded)
            if isExpanded(typeStat.name) && !typeStat.subtypes.isEmpty {
                subtypeRows(for: typeStat)
            }
            
            if typeStatistics.last?.id != typeStat.id {
                Divider()
                    .padding(.vertical, 4)
            }
        }
    }
    
    private func subtypeRows(for typeStat: TypeStatistic) -> some View {
        VStack(spacing: 8) {
            // Add an "ATTRIBUTES:" header
            Text("ATTRIBUTES:")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                .padding(.bottom, 2)
                .padding(.leading, 16)
            
            ForEach(typeStat.subtypes) { subtype in
                Button(action: {
                    subtypeSelected(typeStat.name, subtype.name)
                    HapticManager.shared.selectionFeedback()
                }) {
                    SubtypeRow(subtype: subtype)
                }
                .contentShape(Rectangle())
                .buttonStyle(PlainButtonStyle())
                .padding(.leading, 4)
            }
        }
        .padding(.leading, 4)
        .padding(.vertical, 4)
    }
}

// Type statistics model
struct TypeStatistic: Identifiable {
    let id: UUID
    let name: String
    let tastedCount: Int
    let totalCount: Int
    let subtypes: [SubtypeStatistic]
    
    var percentage: Double {
        totalCount > 0 ? Double(tastedCount) / Double(totalCount) * 100 : 0
    }
}

// Subtype statistics model
struct SubtypeStatistic: Identifiable {
    let id: UUID
    let name: String
    let tastedCount: Int
    let totalCount: Int
    let percentage: Double
}

// Section header for grouping statistics
struct StatisticsSectionHeader: View {
    let title: String
    let systemImage: String
    
    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundColor(.accentColor)
                .font(.headline)
            
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }
}

// Around line 1103 - Find the TastingCoverageStats struct
// Extract the complex progress circle into a separate view component
struct TastingProgressCircle: View {
    let tastedCount: Double
    let totalCount: Double
    
    var percentage: Double {
        return (tastedCount / totalCount) * 100
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 10)
                .frame(width: 120, height: 120)
            
            Circle()
                .trim(from: 0, to: CGFloat(min(percentage / 100, 1.0)))
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .frame(width: 120, height: 120)
                .rotationEffect(.degrees(-90))
                .animation(.linear, value: percentage)
            
            VStack {
                Text("\(Int(percentage))%")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Tasted")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// Extract the action buttons into a separate view
struct TastingActionButtons: View {
    @Binding var selectedFilter: WhiskeyFilter?
    @Binding var showingFilteredView: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Button(action: {
                HapticManager.shared.selectionFeedback()
                selectedFilter = WhiskeyFilter(
                    type: .tastedStatus(true),
                    displayName: "Tasted Bottles",
                    section: .tastingCoverage
                )
                showingFilteredView = true
            }) {
                Label("View Tasted", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .cornerRadius(8)
                    .contentShape(Rectangle())
            }
            
            Button(action: {
                HapticManager.shared.selectionFeedback()
                selectedFilter = WhiskeyFilter(
                    type: .tastedStatus(false),
                    displayName: "Untasted Bottles",
                    section: .tastingCoverage
                )
                showingFilteredView = true
            }) {
                Label("View Untasted", systemImage: "circle")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.orange)
                    .cornerRadius(8)
                    .contentShape(Rectangle())
            }
        }
    }
}

// Extract type header row into a separate view
struct TypeHeaderRow: View {
    let typeStat: TypeStatistic
    let isExpanded: Bool
    
    // Pre-calculate percentage
    private var percentage: Double {
        typeStat.percentage
    }
    
    // Pre-calculate coverage color
    private var coverageColor: Color {
        if percentage < 30 {
            return ColorManager.progressLow
        } else if percentage < 70 {
            return ColorManager.progressMedium
        } else {
            return ColorManager.progressHigh
        }
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .foregroundColor(.secondary)
                .font(.caption)
                .frame(width: 16, height: 16)
            
            Text(typeStat.name)
                .font(.subheadline)
                .fontWeight(.semibold)
            
            Spacer()
            
            // Progress indicator with cached values
            ProgressView(value: Double(typeStat.tastedCount), total: Double(typeStat.totalCount))
                .progressViewStyle(LinearProgressViewStyle(tint: coverageColor))
                .frame(width: 50, height: 6)
                .accessibility(label: Text("\(Int(percentage))% tasted"))
            
            // Stats with spacing
            Text("\(typeStat.tastedCount)/\(typeStat.totalCount)")
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(width: 45, alignment: .trailing)
                .padding(.leading, 8)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .background(ColorManager.secondaryBackground.opacity(0.5))
        .cornerRadius(6)
        .contentShape(Rectangle())
    }
}

// Extract subtype row into a separate view
struct SubtypeRow: View {
    let subtype: SubtypeStatistic
    
    var body: some View {
        HStack(alignment: .center) {
            // Indentation
            Rectangle()
                .fill(Color.clear)
                .frame(width: 16)
            
            // Connection line
            VStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 1, height: 16)
            }
            .frame(width: 12, alignment: .leading)
            
            // Subtype name
            Text(subtype.name)
                .font(.subheadline)
                .foregroundColor(.primary)
                .frame(minWidth: 80, alignment: .leading)
                .lineLimit(1)
            
            Spacer()
            
            // Progress bar
            ProgressView(value: Double(subtype.tastedCount), total: Double(subtype.totalCount))
                .progressViewStyle(LinearProgressViewStyle(tint: coverageColor(subtype.percentage)))
                .frame(width: 50, height: 6)
            
            // Stats with spacing
            Text("\(subtype.tastedCount)/\(subtype.totalCount)")
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(width: 45, alignment: .trailing)
                .padding(.leading, 8)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
    
    private func coverageColor(_ percentage: Double) -> Color {
        if percentage < 30 {
            return .red
        } else if percentage < 70 {
            return .orange
        } else {
            return .green
        }
    }
}

// Extract recommendations section into a separate view
struct RecommendationsSection: View {
    let untastedWhiskeys: [Whiskey]
    @Binding var selectedFilter: WhiskeyFilter?
    @Binding var showingFilteredView: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Recommendations to Taste")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    selectedFilter = WhiskeyFilter(
                        type: .tastedStatus(false),
                        displayName: "All Untasted Bottles",
                        section: .tastingCoverage
                    )
                    showingFilteredView = true
                }) {
                    Text("View All")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.bottom, 4)
            
            // Recommended untasted whiskeys
            let maxRecommendations = 3
            
            // Convert to array first to avoid the ForEach with .prefix issue
            let recommendationArray = Array(untastedWhiskeys.prefix(maxRecommendations))
            
            ForEach(recommendationArray) { whiskey in
                RecommendationRow(whiskey: whiskey)
            }
            
            // Remaining untasted count
            let totalUntasted = untastedWhiskeys.count
            let remainingCount = totalUntasted - maxRecommendations
            
            if remainingCount > 0 {
                Text("+ \(remainingCount) more untasted")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }
}

// Extract recommendation row into a separate view
struct RecommendationRow: View {
    let whiskey: Whiskey
    
    var body: some View {
        NavigationLink(destination: AddJournalEntryView(preSelectedWhiskey: whiskey)) {
            HStack {
                VStack(alignment: .leading) {
                    Text(whiskey.name ?? "Unknown Whiskey")
                        .font(.subheadline)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                    
                    if let type = whiskey.type, !type.isEmpty {
                        Text(type)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Text("Add Tasting")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
            .padding(.vertical, 4)
        }
    }
}

struct StatisticsView_Previews: PreviewProvider {
    static var previews: some View {
        StatisticsView(showingFilteredView: .constant(false))
    }
}

// Add the PriceOverviewStats struct after the PriceAnalysisStats

struct PriceOverviewStats: View {
    let whiskeys: FetchedResults<Whiskey>
    
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Avg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Price")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Divider()
                        .frame(width: 60)
                    Text(formatCurrency(averagePrice))
                        .font(.title)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 8) {
                    Text("Collection")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Value")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Divider()
                        .frame(width: 60)
                    Text(formatCurrency(totalValue))
                        .font(.title)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity)
                
                VStack(spacing: 8) {
                    Text("Avg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("PPP")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Divider()
                        .frame(width: 60)
                    Text(formatPricePerProof(averagePricePerProof))
                        .font(.title)
                        .fontWeight(.bold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            Text("Average Price by Type")
                .font(.headline)
                .padding(.bottom, 4)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(priceByTypeData.prefix(4)) { item in
                    HStack {
                        Text(item.type)
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Text(formatCurrency(item.averagePrice))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
    
    private var averagePrice: Double {
        let validPrices = whiskeys.map { $0.price }.filter { $0 > 0 }
        if validPrices.isEmpty { return 0 }
        return validPrices.reduce(0, +) / Double(validPrices.count)
    }
    
    private var totalValue: Double {
        return whiskeys.map { $0.price * Double($0.numberOfBottles) }.reduce(0, +)
    }
    
    private var averagePricePerProof: Double {
        let validWhiskeys = whiskeys.filter { $0.price > 0 && $0.proof > 0 }
        if validWhiskeys.isEmpty { return 0 }
        
        let totalPPP = validWhiskeys.reduce(0.0) { total, whiskey in
            return total + (whiskey.price / whiskey.proof)
        }
        
        return totalPPP / Double(validWhiskeys.count)
    }
    
    private var priceByTypeData: [TypePriceData] {
        var typeGroups: [String: [Double]] = [:]
        
        for whiskey in whiskeys {
            if whiskey.price > 0, let type = whiskey.type, !type.isEmpty {
                if typeGroups[type] == nil {
                    typeGroups[type] = []
                }
                typeGroups[type]?.append(whiskey.price)
            }
        }
        
        return typeGroups.map { type, prices in
            let average = prices.reduce(0, +) / Double(prices.count)
            return TypePriceData(type: type, averagePrice: average, count: prices.count)
        }.sorted { $0.count > $1.count }
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
    
    private func formatPricePerProof(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}

struct TypePriceData: Identifiable {
    let id = UUID()
    let type: String
    let averagePrice: Double
    let count: Int
}

// StatDetailView is now implemented in its own file (StatDetailView.swift)


