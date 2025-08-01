import SwiftUI

struct CollectionValueSection: View {
    let whiskeys: FetchedResults<Whiskey>
    @Environment(\.colorScheme) var colorScheme
    
    private var currencyFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("COLLECTION VALUE")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                StatCounter(
                    value: currencyFormatter.string(from: NSNumber(value: whiskeys.totalCurrentValue)) ?? "$0",
                    label: "Current Value"
                )
                
                StatCounter(
                    value: currencyFormatter.string(from: NSNumber(value: whiskeys.totalHistoricalValue)) ?? "$0",
                    label: "Total Invested"
                )
            }
            
            let replacements = whiskeys.filter { $0.replaces != nil }
            if !replacements.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Replacement Analysis")
                        .font(.headline)
                        .padding(.top, 8)
                    
                    HStack {
                        Text("Average Replacement Cost:")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(currencyFormatter.string(from: NSNumber(value: whiskeys.averageReplacementCost)) ?? "$0")
                            .fontWeight(.medium)
                    }
                    
                    // Show frequently replaced bottles
                    let frequent = whiskeys.frequentlyReplaced
                    if !frequent.isEmpty {
                        Text("Frequently Replaced")
                            .font(.headline)
                            .padding(.top, 8)
                        
                        ForEach(frequent) { whiskey in
                            WhiskeyPriceTrendRow(whiskey: whiskey)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: Color(.systemGray4), radius: 3)
    }
}

struct WhiskeyPriceTrendRow: View {
    let whiskey: Whiskey
    
    private var currencyFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(whiskey.name ?? "Unknown")
                .font(.subheadline)
                .fontWeight(.medium)
            
            // Show price trend
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(whiskey.priceTrend) { point in
                        VStack(spacing: 4) {
                            Text(currencyFormatter.string(from: NSNumber(value: point.price)) ?? "$0")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            Text(point.date, style: .date)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

#Preview {
    CollectionValueSection(whiskeys: FetchRequest<Whiskey>(
        entity: Whiskey.entity(),
        sortDescriptors: []
    ).wrappedValue)
} 