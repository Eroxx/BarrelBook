import SwiftUI

struct JournalEntryRowView: View {
    let entry: JournalEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if entry.isInfinityBottle, let infinityBottle = entry.infinityBottle {
                    Text("∞ \(infinityBottle.name ?? "Infinity Bottle")")
                        .font(.headline)
                } else if let whiskey = entry.whiskey {
                    HStack(spacing: 4) {
                        Text(whiskey.name ?? "Unknown Whiskey")
                            .font(.headline)
                        
                        if whiskey.status == "external" {
                            Text("External")
                                .font(.system(size: 9))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2))
                                .foregroundColor(Color.orange)
                                .cornerRadius(4)
                        }
                    }
                } else {
                    Text("Unknown Entry")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(entry.date ?? Date(), style: .date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if entry.overallRating > 0 {
                RatingView(rating: entry.overallRating)
            }
            
            if let notes = entry.nose {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            // Show infinity bottle proof for infinity bottle entries
            if entry.isInfinityBottle, let infinityBottle = entry.infinityBottle {
                HStack {
                    Text("Infinity Bottle • \(infinityBottle.calculatedProof, specifier: "%.1f") proof")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct JournalEntryRowView_Previews: PreviewProvider {
    static var previews: some View {
        JournalEntryRowView(entry: JournalEntry())
    }
} 