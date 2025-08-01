import SwiftUI

struct WhiskeyRowView: View {
    @ObservedObject var whiskey: Whiskey
    
    init(whiskey: Whiskey) {
        self.whiskey = whiskey
        
        #if DEBUG
        // Remove debug print
        #endif
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title and Proof Row
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 4) {
                    ZStack {
                        // Base circle (always shown)
                        Circle()
                            .fill(hasAnyOpenActiveBottle ? Color.clear : Color(red: 0.6, green: 0.4, blue: 0.2))
                            .frame(width: 8, height: 8)
                        
                        // Circle outline (always shown)
                        Circle()
                            .stroke(Color(red: 0.6, green: 0.4, blue: 0.2), lineWidth: 1)
                            .frame(width: 8, height: 8)
                        
                        // Fill for open bottles (bottom half)
                        if hasAnyOpenActiveBottle {
                            Circle()
                                .trim(from: 0, to: 0.5)
                                .fill(Color(red: 0.6, green: 0.4, blue: 0.2))
                                .frame(width: 8, height: 8)
                                .rotationEffect(.degrees(0))
                        }
                    }
                    Text(whiskey.name ?? "Unknown Whiskey")
                        .font(.headline)
                        .lineLimit(1)
                        // Only apply strikethrough if ALL bottles are dead
                        .strikethrough(whiskey.activeBottleCount == 0 && whiskey.deadBottleCount > 0, color: .red)
                        // Only reduce opacity if ALL bottles are dead
                        .foregroundColor(whiskey.activeBottleCount == 0 && whiskey.deadBottleCount > 0 ? .secondary : .primary)
                        .opacity(whiskey.activeBottleCount == 0 && whiskey.deadBottleCount > 0 ? 0.7 : 1.0)
                }
                
                Spacer()
                
                if whiskey.proof > 0 {
                    Text("\(whiskey.proof.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", whiskey.proof) : String(format: "%.1f", whiskey.proof)) PROOF")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                }
            }
            
            // Type and Price Row - Moved price badge to the type row
            HStack {
                HStack(spacing: 4) {
                    if let type = whiskey.type, !type.isEmpty {
                        Text(type)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let age = whiskey.age, !age.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(formatAge(age))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    if let finish = whiskey.finish, !finish.isEmpty {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(finish)
                            .font(.subheadline)
                            .foregroundColor(Color(red: 0.4, green: 0.2, blue: 0.0))
                            .italic()  // Italics for the finish
                    }
                }
                
                Spacer()
                
                // Price Badge now on the same line as the type
                if whiskey.averagePrice > 0 {
                    PriceBadge(price: whiskey.averagePrice)
                }
            }
            
            // Distillery Row
            if let distillery = whiskey.distillery, !distillery.isEmpty {
                Text(distillery)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Bottle Notes Row (if available)
            if let notes = whiskey.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .italic()
                    .lineLimit(2)
            }
            
            // Show badges for special attributes or bottle counts
            if whiskey.isBiB || whiskey.isSiB || whiskey.isStorePick || whiskey.isFinished > 0 || whiskey.activeBottleCount > 1 || (whiskey.activeBottleCount > 0 && whiskey.deadBottleCount > 0) {
                HStack(spacing: 4) {
                    if whiskey.isBiB {
                        Text("BiB")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .clipShape(Capsule())
                    }
                    if whiskey.isSiB {
                        Text("SiB")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.1))
                            .foregroundColor(.purple)
                            .clipShape(Capsule())
                    }
                    if whiskey.isStorePick {
                        Text("SP")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                    
                    // Modified logic: Only show Dead badge if ALL bottles are dead
                    if whiskey.activeBottleCount == 0 && whiskey.deadBottleCount > 0 {
                        Text("Dead")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .clipShape(Capsule())
                    }
                    
                    // Show bottle counts with UPDATED LOGIC:
                    // 1. When there are multiple active bottles but no dead bottles, show "X active"
                    if whiskey.activeBottleCount > 1 && whiskey.deadBottleCount == 0 {
                        Text("\(whiskey.activeBottleCount) active")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                    
                    // 2. When there are both active and dead bottles, show both counts
                    else if whiskey.activeBottleCount > 0 && whiskey.deadBottleCount > 0 {
                        // Show active count
                        Text("\(whiskey.activeBottleCount) active")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.1))
                            .foregroundColor(.green)
                            .clipShape(Capsule())
                        
                        // Show dead count
                        Text("\(whiskey.deadBottleCount) dead")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .clipShape(Capsule())
                    }
                    // 3. Only show dead count badge if all bottles are dead and there's more than 1
                    else if whiskey.activeBottleCount == 0 && whiskey.deadBottleCount > 1 {
                        Text("\(whiskey.deadBottleCount) dead")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 6)
        // Only apply the dead styles if ALL bottles are dead
        .background(whiskey.activeBottleCount == 0 && whiskey.deadBottleCount > 0 ? Color.red.opacity(0.05) : Color.clear)
        // Only apply the dead styles if ALL bottles are dead
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(whiskey.activeBottleCount == 0 && whiskey.deadBottleCount > 0 ? Color.red.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }
    
    // Helper function to format age display
    private func formatAge(_ age: String) -> String {
        // Check if age is just a number
        if let ageNum = Int(age.trimmingCharacters(in: .whitespaces)) {
            return "\(ageNum) Years Old"
        }
        
        // If age already includes "year" or "old" text, return as is
        let lowercasedAge = age.lowercased()
        if lowercasedAge.contains("year") || lowercasedAge.contains("old") {
            return age
        }
        
        // Otherwise append "Years Old"
        return "\(age) Years Old"
    }
    
    private func updateBadges() {
        // Remove the debug print statement
        // ... existing code ...
    }
    
    // Helper property to check if any active bottle is open
    private var hasAnyOpenActiveBottle: Bool {
        guard let bottleInstances = whiskey.bottleInstances as? Set<BottleInstance> else { return false }
        return bottleInstances.contains { !$0.isDead && $0.isOpen }
    }
}

struct Badge: View {
    let text: String
    let color: Color
    
    var body: some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

struct PriceBadge: View {
    let price: Double
    
    @ObservedObject private var privacyManager = PrivacyManager.shared
    @State private var temporarilyShowPrice: Bool = false
    
    var body: some View {
        HStack(spacing: 4) {
            if privacyManager.hidePrices && !temporarilyShowPrice {
                Text("Hidden")
                    .font(.caption)
                    .fontWeight(.medium)
                
                Button(action: {
                    temporarilyShowPrice = true
                    // Auto-hide after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        temporarilyShowPrice = false
                    }
                    HapticManager.shared.selectionFeedback()
                }) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            } else {
                Text(formattedPrice)
                    .font(.caption)
                    .fontWeight(.medium)
                
                if privacyManager.hidePrices && temporarilyShowPrice {
                    // Show timer indicator when temporarily showing price
                    Image(systemName: "timer")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(priceColor(for: price).opacity(0.1))
        .foregroundColor(priceColor(for: price))
        .clipShape(Capsule())
    }
    
    private var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        let formatted = formatter.string(from: NSNumber(value: price)) ?? "$0"
        return formatted
    }
    
    private func priceColor(for price: Double) -> Color {
        switch price {
        case 0..<30:
            return .green
        case 30..<70:
            return .blue
        case 70..<150:
            return .orange
        default:
            return .red
        }
    }
}

struct WhiskeyRowView_Previews: PreviewProvider {
    static var previews: some View {
        List {
            WhiskeyRowView(whiskey: {
                let whiskey = Whiskey()
                whiskey.name = "Buffalo Trace"
                whiskey.type = "Bourbon"
                whiskey.age = "10 Year"
                whiskey.proof = 90
                whiskey.price = 29.99
                whiskey.finish = "Oak & Vanilla"
                whiskey.distillery = "Buffalo Trace Distillery"
                whiskey.isBiB = true
                whiskey.isSiB = true
                whiskey.isStorePick = true
                whiskey.storePickName = "ABC Store"
                return whiskey
            }())
            WhiskeyRowView(whiskey: {
                let whiskey = Whiskey()
                whiskey.name = "Maker's Mark"
                whiskey.type = "Bourbon"
                whiskey.proof = 90
                whiskey.price = 35.50
                whiskey.distillery = "Maker's Mark Distillery"
                return whiskey
            }())
            WhiskeyRowView(whiskey: {
                let whiskey = Whiskey()
                whiskey.name = "Eagle Rare"
                whiskey.type = "Bourbon"
                whiskey.age = "10 Year"
                whiskey.finish = "Caramel & Citrus"
                whiskey.proof = 90
                whiskey.price = 59.99
                whiskey.distillery = "Buffalo Trace Distillery"
                return whiskey
            }())
        }
    }
} 