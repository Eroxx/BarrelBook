import SwiftUI

struct InfinityBottleRowView: View {
    let bottle: InfinityBottle
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(bottle.name ?? "Unnamed Bottle")
                    .font(.headline)
                Spacer()
                Text("\(bottle.remainingVolume, specifier: "%.1f") oz")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("\(bottle.sortedAdditions.count) additions")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Show the proof if there are additions
                if bottle.sortedAdditions.count > 0 {
                    Text("\(bottle.calculatedProof, specifier: "%.1f") proof")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Show current volume indicator with a gradient to visualize amount
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)
                    
                    // Use a scaling factor for visualization purposes based on remaining volume
                    // Scale based on common bottle sizes - most infinity bottles will be 750ml/25.4oz or less
                    let scaleFactor = min(1.0, bottle.remainingVolume / 25.4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor)
                        .frame(width: max(0, min(geometry.size.width, geometry.size.width * scaleFactor)), height: 4)
                }
            }
            .frame(height: 4)
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }
} 