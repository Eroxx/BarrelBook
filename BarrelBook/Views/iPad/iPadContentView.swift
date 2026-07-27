import SwiftUI

struct iPadContentView: View {
    @State private var selectedTab: TabSelection? = .home
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @StateObject private var navigationState = NavigationStateManager.shared
    @State private var showingSettings = false
    @State private var statisticsShowingFilteredView = false
    
    private var selectedTabBinding: Binding<TabSelection> {
        Binding(
            get: { selectedTab ?? .home },
            set: { selectedTab = $0 }
        )
    }
    
    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        .tint(ColorManager.primaryBrandColor)
        .onChange(of: navigationState.activeTab) { newTab in
            if let tab = newTab {
                selectedTab = tab
                DispatchQueue.main.async {
                    navigationState.activeTab = nil
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
    }
    
    // MARK: - Sidebar
    
    private var sidebar: some View {
        List(selection: $selectedTab) {
            Section {
                ForEach(TabSelection.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("BarrelBook")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                showingSettings = true
                HapticManager.shared.lightImpact()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(ColorManager.primaryBrandColor)
            .background(.bar)
        }
    }
    
    // MARK: - Detail
    
    @ViewBuilder
    private var detailColumn: some View {
        switch selectedTab ?? .home {
        case .home:
            NavigationStack {
                iPadDashboardView(selectedTab: selectedTabBinding)
                    .navigationTitle("Home")
                    .navigationBarTitleDisplayMode(.large)
            }
        case .collection:
            iPadCollectionGridView()
        case .wishlist:
            iPadWishlistView()
        case .journal:
            JournalView()
        case .statistics:
            NavigationStack {
                StatisticsView(showingFilteredView: $statisticsShowingFilteredView)
            }
        }
    }
}

#Preview {
    iPadContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
