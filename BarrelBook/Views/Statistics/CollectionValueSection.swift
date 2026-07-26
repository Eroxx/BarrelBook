import SwiftUI

struct CollectionValueSection: View {
    let whiskeys: FetchedResults<Whiskey>

    private var totalBottles: Int {
        whiskeys.reduce(0) { $0 + ($1.bottleInstances?.count ?? 0) }
    }

    private var uniqueCount: Int { whiskeys.count }

    private var avgPerBottle: Double {
        guard totalBottles > 0 else { return 0 }
        return whiskeys.totalCurrentValue / Double(totalBottles)
    }

    private var avgPPP: Double {
        let valid = whiskeys.filter { $0.price > 0 && $0.proof > 0 }
        guard !valid.isEmpty else { return 0 }
        return valid.reduce(0.0) { $0 + ($1.price / $1.proof) } / Double(valid.count)
    }

    private var currencyFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        return f
    }

    @State private var showingInfo = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("COLLECTION VALUE")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(ColorManager.primaryBrandColor)
                    .tracking(0.8)
                Button {
                    showingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(ColorManager.primaryBrandColor.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            .alert("Collection Value", isPresented: $showingInfo) {
                Button("Got it", role: .cancel) {}
            } message: {
                Text("Total Value — sum of all recorded purchase prices.\n\nAvg — average price per bottle across your entire collection.\n\nPPP (Price Per Proof) — average cost per proof degree across your collection. A lower number means better value for the alcohol content. Only bottles with both a price and proof recorded are included.")
            }

            Text(currencyFormatter.string(from: NSNumber(value: whiskeys.totalCurrentValue)) ?? "$0")
                .font(.system(size: 46, weight: .light))
                .foregroundColor(ColorManager.primaryText)

            HStack(spacing: 4) {
                Text("Across \(totalBottles) bottle\(totalBottles == 1 ? "" : "s")")
                    .foregroundColor(ColorManager.primaryText)
                Text("(\(uniqueCount) unique)")
                    .foregroundColor(ColorManager.secondaryText)
                Text("·")
                    .foregroundColor(ColorManager.secondaryText)
                Text("\(currencyFormatter.string(from: NSNumber(value: avgPerBottle)) ?? "$0") avg")
                    .foregroundColor(ColorManager.secondaryText)
                if avgPPP > 0 {
                    Text("·")
                        .foregroundColor(ColorManager.secondaryText)
                    Text(String(format: "$%.2f PPP", avgPPP))
                        .foregroundColor(ColorManager.secondaryText)
                }
            }
            .font(.subheadline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ColorManager.secondaryBackground)
        .cornerRadius(16)
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