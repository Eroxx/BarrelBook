import SwiftUI

struct iPadContentView: View {
    @State private var selectedTab: TabSelection = .home
    @StateObject private var navigationState = NavigationStateManager.shared
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Navigation Bar
                HStack {
                    Spacer()
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 22))
                    }
                    .padding(.trailing, 16)
                }
                .frame(height: 44)
                .background(Color(.systemBackground))
                
                // Custom Tab Bar
                HStack(spacing: 0) {
                    TabButton(selection: $selectedTab, tab: .home, icon: "house", label: "Home")
                    TabButton(selection: $selectedTab, tab: .collection, icon: "square.grid.2x2", label: "Collection")
                    TabButton(selection: $selectedTab, tab: .wishlist, icon: "heart.fill", label: "Wishlist")
                    TabButton(selection: $selectedTab, tab: .journal, icon: "book", label: "Tastings")
                    TabButton(selection: $selectedTab, tab: .statistics, icon: "chart.bar.fill", label: "Statistics")
                }
                .frame(height: 60)
                .background(Color(.systemBackground))
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(Color(.separator)),
                    alignment: .bottom
                )
                
                // Content
                TabView(selection: $selectedTab) {
                    iPadDashboardView(selectedTab: $selectedTab)
                        .tag(TabSelection.home)
                        .navigationBarHidden(true)
                    
                    iPadCollectionGridView()
                        .tag(TabSelection.collection)
                        .navigationBarHidden(true)
                    
                    iPadWishlistView()
                        .tag(TabSelection.wishlist)
                        .navigationBarHidden(true)
                    
                    JournalView()
                        .tag(TabSelection.journal)
                        .navigationBarHidden(true)
                    
                    StatisticsView(showingFilteredView: .constant(false))
                        .tag(TabSelection.statistics)
                        .navigationBarHidden(true)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .fullScreenCover(isPresented: $showingSettings) {
            SettingsView()
        }
    }
}

struct TabButton: View {
    @Binding var selection: TabSelection
    let tab: TabSelection
    let icon: String
    let label: String
    
    var body: some View {
        Button(action: {
            withAnimation {
                selection = tab
                HapticManager.shared.lightImpact()
            }
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(selection == tab ? .blue : .secondary)
        }
    }
}

#Preview {
    iPadContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
} 