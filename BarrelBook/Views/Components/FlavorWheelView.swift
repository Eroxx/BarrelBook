import SwiftUI

struct FlavorWheelView: View {
    @Binding var flavorProfile: FlavorProfile
    var phase: TastingPhase
    @State private var selectedCategory: FlavorCategory?
    @State private var showingSubflavorPicker = false
    
    private let wheelSize: CGFloat = 300
    private let centerSize: CGFloat = 60
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Flavor Wheel - centered in available space
                ZStack {
                    // Background circle
                    Circle()
                        .fill(Color(.systemBackground))
                        .shadow(radius: 5)
                    
                    // Flavor segments
                    ForEach(Array(FlavorCategory.allCases.enumerated()), id: \.element) { index, category in
                        FlavorSegment(
                            category: category,
                            intensity: flavorProfile.intensity(for: category, in: phase),
                            startAngle: startAngle(for: index),
                            endAngle: endAngle(for: index)
                        )
                        .contentShape(Path { path in
                            path.move(to: CGPoint(x: wheelSize/2, y: wheelSize/2))
                            path.addArc(
                                center: CGPoint(x: wheelSize/2, y: wheelSize/2),
                                radius: wheelSize/2,
                                startAngle: .radians(startAngle(for: index).radians),
                                endAngle: .radians(endAngle(for: index).radians),
                                clockwise: false
                            )
                            path.closeSubpath()
                        })
                        .onTapGesture {
                            // Ensure we don't have a race condition
                            DispatchQueue.main.async {
                                selectedCategory = category
                                showingSubflavorPicker = true
                            }
                        }
                    }
                    
                    // Center circle with phase name
                    Circle()
                        .fill(Color(.systemBackground))
                        .frame(width: centerSize, height: centerSize)
                        .overlay(
                            Text(phase.rawValue)
                                .font(.headline)
                                .foregroundColor(.primary)
                        )
                }
                .frame(width: wheelSize, height: wheelSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.clear)
                
                // Selected flavors as tags/chips
                VStack(alignment: .leading, spacing: 12) {
                    let selectedFlavors = getAllSelectedFlavors()
                    
                    if !selectedFlavors.isEmpty {
                        Text("Selected Flavors")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 8) {
                                ForEach(selectedFlavors, id: \.subflavor) { item in
                                    FlavorTag(
                                        category: item.category,
                                        subflavor: item.subflavor
                                    ) {
                                        removeSubflavor(item.subflavor, from: item.category)
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    } else {
                        Text("Tap on wheel segments to add flavors")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                    }
                }
                .frame(height: 120)
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: Binding(
            get: { showingSubflavorPicker && selectedCategory != nil },
            set: { newValue in 
                showingSubflavorPicker = newValue
                if !newValue {
                    selectedCategory = nil
                }
            }
        )) {
            if let category = selectedCategory {
                SubflavorPickerView(
                    category: category,
                    intensity: Binding(
                        get: { flavorProfile.intensity(for: category, in: phase) },
                        set: { newValue in
                            updateIntensity(for: category, value: newValue)
                        }
                    ),
                    selectedSubflavors: Binding(
                        get: { flavorProfile.subflavors(for: category, in: phase) },
                        set: { newValue in
                            updateSubflavors(for: category, value: newValue)
                        }
                    )
                )
                .presentationDetents([.medium, .large])
            } else {
                // Fallback view to prevent blank screen
                VStack {
                    Text("Loading...")
                        .font(.headline)
                        .padding()
                    
                    Button("Close") {
                        showingSubflavorPicker = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
        }
    }
    
    private func getAllSelectedFlavors() -> [(category: FlavorCategory, subflavor: String)] {
        var allFlavors: [(category: FlavorCategory, subflavor: String)] = []
        
        for category in FlavorCategory.allCases {
            let subflavors = flavorProfile.subflavors(for: category, in: phase)
            for subflavor in subflavors.sorted() {
                allFlavors.append((category: category, subflavor: subflavor))
            }
        }
        
        return allFlavors
    }
    
    private func removeSubflavor(_ subflavor: String, from category: FlavorCategory) {
        var currentSubflavors = flavorProfile.subflavors(for: category, in: phase)
        currentSubflavors.remove(subflavor)
        updateSubflavors(for: category, value: currentSubflavors)
        
        // If no subflavors remain, set intensity to 0
        if currentSubflavors.isEmpty {
            updateIntensity(for: category, value: 0.0)
        }
    }
    
    private func startAngle(for index: Int) -> Angle {
        let count = Double(FlavorCategory.allCases.count)
        let degreesPerSegment = 360.0 / count
        let degrees = degreesPerSegment * Double(index) - 90 // Start at top
        return Angle(degrees: degrees)
    }
    
    private func endAngle(for index: Int) -> Angle {
        let count = Double(FlavorCategory.allCases.count)
        let degreesPerSegment = 360.0 / count
        let degrees = degreesPerSegment * Double(index + 1) - 90 // Start at top
        return Angle(degrees: degrees)
    }
    
    private func updateIntensity(for category: FlavorCategory, value: Double) {
        var profile = flavorProfile
        var intensities = phase == .nose ? profile.nose : (phase == .palate ? profile.palate : profile.finish)
        if let index = intensities.firstIndex(where: { $0.category == category }) {
            intensities[index].intensity = value
            if phase == .nose {
                profile.nose = intensities
            } else if phase == .palate {
                profile.palate = intensities
            } else {
                profile.finish = intensities
            }
            flavorProfile = profile
        }
    }
    
    private func updateSubflavors(for category: FlavorCategory, value: Set<String>) {
        var profile = flavorProfile
        var intensities = phase == .nose ? profile.nose : (phase == .palate ? profile.palate : profile.finish)
        if let index = intensities.firstIndex(where: { $0.category == category }) {
            intensities[index].intensity = value.isEmpty ? 0.0 : 0.5
            intensities[index].selectedSubflavors = value
            
            if phase == .nose {
                profile.nose = intensities
            } else if phase == .palate {
                profile.palate = intensities
            } else {
                profile.finish = intensities
            }
            flavorProfile = profile
        }
    }
}

struct FlavorSegment: View {
    let category: FlavorCategory
    let intensity: Double
    let startAngle: Angle
    let endAngle: Angle
    
    private let wheelSize: CGFloat = 300
    
    var body: some View {
        ZStack {
            // Background segment
            Path { path in
                let center = CGPoint(x: wheelSize/2, y: wheelSize/2)
                path.move(to: center)
                path.addArc(
                    center: center,
                    radius: wheelSize/2,
                    startAngle: .radians(startAngle.radians),
                    endAngle: .radians(endAngle.radians),
                    clockwise: false
                )
                path.closeSubpath()
            }
            .fill(category.color.opacity(0.3))
            
            // Removed intensity segment to eliminate secondary color effect
            
            // Category label
            CategoryLabel(
                category: category,
                startAngle: startAngle,
                endAngle: endAngle
            )
        }
    }
}

struct CategoryLabel: View {
    let category: FlavorCategory
    let startAngle: Angle
    let endAngle: Angle
    
    private let wheelSize: CGFloat = 300
    private let labelRadius: CGFloat = 85
    
    var body: some View {
        let midAngle = Angle(radians: (startAngle.radians + endAngle.radians) / 2)
        let x = labelRadius * cos(midAngle.radians)
        let y = labelRadius * sin(midAngle.radians)
        
        Text(category.rawValue)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.35))
            )
            .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
            .position(x: wheelSize/2 + x, y: wheelSize/2 + y)
    }
}

struct SubflavorPickerView: View {
    let category: FlavorCategory
    @Binding var intensity: Double
    @Binding var selectedSubflavors: Set<String>
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Subflavors")) {
                    ForEach(category.subflavors, id: \.self) { subflavor in
                        Toggle(subflavor, isOn: Binding(
                            get: { selectedSubflavors.contains(subflavor) },
                            set: { isSelected in
                                if isSelected {
                                    selectedSubflavors.insert(subflavor)
                                    // Set intensity to 0.5 when any subflavor is selected
                                    if intensity == 0 {
                                        intensity = 0.5
                                    }
                                } else {
                                    selectedSubflavors.remove(subflavor)
                                    // Set intensity to 0 if no subflavors are selected
                                    if selectedSubflavors.isEmpty {
                                        intensity = 0
                                    }
                                }
                            }
                        ))
                    }
                }
            }
            .navigationTitle(category.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FlavorTag: View {
    let category: FlavorCategory
    let subflavor: String
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(subflavor)
                .font(.caption)
                .fontWeight(.medium)
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(category.color)
        )
        .foregroundColor(.white)
        .shadow(radius: 2)
    }
} 