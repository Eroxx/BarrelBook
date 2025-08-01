import SwiftUI

// Custom row view for wishlist items
struct WishlistRowView: View {
    let whiskey: Whiskey
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // Main content
            VStack(alignment: .leading, spacing: 4) {
                // Top row: Name
                HStack {
                    Text(whiskey.name ?? "Unnamed Whiskey")
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                }
                
                // Middle row: Proof, Type, Distillery
                HStack(spacing: 8) {
                    if whiskey.proof > 0.0 {
                        Text("\(Int(whiskey.proof)) Proof")
                    }
                    
                    if whiskey.proof > 0.0 && (whiskey.type?.isEmpty == false) {
                        Text("•")
                    }
                    
                    if let type = whiskey.type, !type.isEmpty {
                        Text(type)
                    }
                    
                    if let type = whiskey.type, !type.isEmpty,
                       let distillery = whiskey.distillery, !distillery.isEmpty {
                        Text("•")
                        Text(distillery)
                    } else if let distillery = whiskey.distillery, !distillery.isEmpty {
                        Text(distillery)
                    }
                }
                .font(.subheadline)
                .foregroundColor(.secondary)
                
                // Location and Rarity row
                HStack(spacing: 8) {
                    if let whereToFind = whiskey.whereToFind, !whereToFind.isEmpty {
                        Text("Location: \(whereToFind)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if whiskey.isStorePick, let storePickName = whiskey.storePickName, !storePickName.isEmpty {
                        Text("Store Pick: \(storePickName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let rarityStr = whiskey.rarity, let rarity = WhiskeyRarity(rawValue: rarityStr) {
                        if let whereToFind = whiskey.whereToFind, !whereToFind.isEmpty || 
                           (whiskey.isStorePick && whiskey.storePickName?.isEmpty == false) {
                            Text("•")
                        }
                        Text("Rarity: \(rarity.displayName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Special tags row
                if whiskey.hasSpecialAttributes {
                    WhiskeyTagsView(whiskey: whiskey)
                        .padding(.top, 2)
                }
                
                // Store names row
                if let stores = whiskey.stores as? Set<Store>, !stores.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(Array(stores), id: \.self) { store in
                                Text(store.name ?? "Unknown Store")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.trailing, 80) // Make space for the price/priority
            
            // Price and Priority overlay (right-aligned)
            if whiskey.targetPrice > 0.0 || whiskey.priority > 0 {
                HStack(spacing: 12) {
                    if whiskey.targetPrice > 0.0 {
                        Text("Target: $\(String(format: "%.2f", whiskey.targetPrice))")
                            .font(.headline)
                            .foregroundColor(.blue)
                    }
                    if whiskey.priority > 0 {
                        PriorityStarsView(priority: Int(whiskey.priority))
                    }
                }
                .padding(.trailing, 12)
            }
        }
    }
}

// Priority badge view
struct PriorityStarsView: View {
    let priority: Int
    
    var body: some View {
        if priority > 0 {
            Text("\(priority)")
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(priorityColor)
                .foregroundColor(.white)
                .clipShape(Capsule())
        }
    }
    
    private var priorityColor: Color {
        // A nice AA-compliant brown color
        return Color(red: 0.6, green: 0.4, blue: 0.2)  // This is a warm brown color that should be AA compliant with white text
    }
}

// Special tags view
struct WhiskeyTagsView: View {
    let whiskey: Whiskey
    
    var body: some View {
        HStack(spacing: 4) {
            if whiskey.isBiB {
                WhiskeyTag(text: "BiB", color: Color(red: 0.8, green: 0.6, blue: 0.3))
            }
            
            if whiskey.isSiB {
                WhiskeyTag(text: "SiB", color: .blue)
            }
            
            if whiskey.isStorePick {
                WhiskeyTag(text: whiskey.storePickName != nil ? "SP: \(whiskey.storePickName!)" : "SP", 
                          color: .purple)
            }
        }
    }
}

// Individual tag view
struct WhiskeyTag: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color)
            .foregroundColor(.white)
            .cornerRadius(4)
    }
}

// Helper extension to check if whiskey has any special attributes
private extension Whiskey {
    var hasSpecialAttributes: Bool {
        return isBiB || isSiB || isStorePick
    }
}

// Preview
struct WishlistRowView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a mock whiskey for preview
        let whiskey = Whiskey()
        whiskey.name = "Buffalo Trace"
        whiskey.type = "Bourbon"
        whiskey.proof = 90
        whiskey.targetPrice = 49.99
        whiskey.priority = 3
        whiskey.distillery = "Buffalo Trace"
        whiskey.isBiB = true
        whiskey.isSiB = true
        whiskey.isStorePick = true
        whiskey.storePickName = "Total Wine"
        whiskey.whereToFind = "Total Wine Downtown"
        
        // Add mock stores
        let store1 = Store()
        store1.name = "Total Wine"
        whiskey.addToStores(store1)
        
        let store2 = Store()
        store2.name = "BevMo"
        whiskey.addToStores(store2)
        
        let store3 = Store()
        store3.name = "Local Liquor Store"
        whiskey.addToStores(store3)
        
        return WishlistRowView(whiskey: whiskey)
            .previewLayout(.sizeThatFits)
            .padding()
    }
} 