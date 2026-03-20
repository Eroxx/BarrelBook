import SwiftUI

// MARK: - Donut geometry helpers (extracted to avoid @ViewBuilder type-checker overload)

private enum WheelGeometry {
    static let innerFraction: CGFloat = 0.22   // inner hole as fraction of diameter
    static let gapDegrees:    Double  = 0.0    // no gap — solid continuous ring

    static func outerRadius(for size: CGFloat) -> CGFloat { size / 2 - 1 }
    static func innerRadius(for size: CGFloat) -> CGFloat { size * innerFraction }
    static func centerDiameter(for size: CGFloat) -> CGFloat { size * 0.40 }
    static func labelRadius(for size: CGFloat) -> CGFloat {
        // Midpoint of the ring — visually centred in each segment
        (outerRadius(for: size) + innerRadius(for: size)) / 2
    }

    /// Annular sector path for a single donut segment
    static func donutPath(size: CGFloat, start: Angle, end: Angle) -> Path {
        let center   = CGPoint(x: size / 2, y: size / 2)
        let outerR   = outerRadius(for: size)
        let innerR   = innerRadius(for: size)
        let gapRad   = gapDegrees * .pi / 180
        let adjStart = Angle(radians: start.radians + gapRad)
        let adjEnd   = Angle(radians: end.radians   - gapRad)

        // Convert Double radians → CGFloat so cos/sin overloads are unambiguous
        let sRad = CGFloat(adjStart.radians)
        let eRad = CGFloat(adjEnd.radians)

        var path = Path()
        path.move(to: CGPoint(x: center.x + innerR * cos(sRad),
                              y: center.y + innerR * sin(sRad)))
        path.addLine(to: CGPoint(x: center.x + outerR * cos(sRad),
                                 y: center.y + outerR * sin(sRad)))
        path.addArc(center: center, radius: outerR,
                    startAngle: adjStart, endAngle: adjEnd, clockwise: false)
        path.addLine(to: CGPoint(x: center.x + innerR * cos(eRad),
                                 y: center.y + innerR * sin(eRad)))
        path.addArc(center: center, radius: innerR,
                    startAngle: adjEnd, endAngle: adjStart, clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - FlavorWheelView

struct FlavorWheelView: View {
    @Binding var flavorProfile: FlavorProfile
    var phase: TastingPhase
    @State private var selectedCategory: FlavorCategory?
    @State private var showingSubflavorPicker = false

    private func wheelSize(for geometry: GeometryProxy) -> CGFloat {
        let available = min(geometry.size.width - 32, geometry.size.height - 140)
        return min(max(available, 240), 320)
    }

    private func startAngle(for index: Int) -> Angle {
        let slice = 360.0 / Double(FlavorCategory.allCases.count)
        return Angle(degrees: slice * Double(index) - 90)
    }

    private func endAngle(for index: Int) -> Angle {
        let slice = 360.0 / Double(FlavorCategory.allCases.count)
        return Angle(degrees: slice * Double(index + 1) - 90)
    }

    private func getAllSelectedFlavors() -> [(category: FlavorCategory, subflavor: String)] {
        var result: [(category: FlavorCategory, subflavor: String)] = []
        for category in FlavorCategory.allCases {
            for subflavor in flavorProfile.subflavors(for: category, in: phase).sorted() {
                result.append((category: category, subflavor: subflavor))
            }
        }
        return result
    }

    private func removeSubflavor(_ subflavor: String, from category: FlavorCategory) {
        var subs = flavorProfile.subflavors(for: category, in: phase)
        subs.remove(subflavor)
        updateSubflavors(for: category, value: subs)
        if subs.isEmpty { updateIntensity(for: category, value: 0.0) }
    }

    private func updateIntensity(for category: FlavorCategory, value: Double) {
        var profile    = flavorProfile
        var intensities = phase == .nose ? profile.nose : (phase == .palate ? profile.palate : profile.finish)
        if let i = intensities.firstIndex(where: { $0.category == category }) {
            intensities[i].intensity = value
            if phase == .nose          { profile.nose    = intensities }
            else if phase == .palate   { profile.palate  = intensities }
            else                       { profile.finish  = intensities }
            flavorProfile = profile
        }
    }

    private func updateSubflavors(for category: FlavorCategory, value: Set<String>) {
        var profile    = flavorProfile
        var intensities = phase == .nose ? profile.nose : (phase == .palate ? profile.palate : profile.finish)
        if let i = intensities.firstIndex(where: { $0.category == category }) {
            intensities[i].intensity          = value.isEmpty ? 0.0 : 0.5
            intensities[i].selectedSubflavors = value
            if phase == .nose          { profile.nose    = intensities }
            else if phase == .palate   { profile.palate  = intensities }
            else                       { profile.finish  = intensities }
            flavorProfile = profile
        }
    }

    private static let cardBG  = Color(red: 0.96, green: 0.92, blue: 0.86) // warm parchment
    private static let wheelBG = Color(red: 0.09, green: 0.06, blue: 0.02) // dark bourbon centre

    var body: some View {
        GeometryReader { geometry in
            let size = wheelSize(for: geometry)
            // ZStack centres content in GeometryReader (default is top-leading)
            ZStack {
                VStack(spacing: 0) {
                    wheelZStack(size: size)
                        .frame(width: size, height: size)

                    selectedFlavorsRow
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Self.cardBG)
        }
        .listRowBackground(Self.cardBG)
        .listRowInsets(EdgeInsets())
        .sheet(isPresented: Binding(
            get: { showingSubflavorPicker && selectedCategory != nil },
            set: { if !$0 { showingSubflavorPicker = false; selectedCategory = nil } }
        )) {
            sheetContent
        }
    }

    // MARK: - Sub-views (extracted to keep body simple)

    private func wheelZStack(size: CGFloat) -> some View {
        ZStack {
            // Dark backing circle — gaps between segments read as dark, not parchment
            Circle()
                .fill(Self.wheelBG)

            ForEach(Array(FlavorCategory.allCases.enumerated()), id: \.element) { index, category in
                FlavorSegment(
                    category:   category,
                    intensity:  flavorProfile.intensity(for: category, in: phase),
                    startAngle: startAngle(for: index),
                    endAngle:   endAngle(for: index),
                    wheelSize:  size
                )
                .contentShape(WheelGeometry.donutPath(
                    size:  size,
                    start: startAngle(for: index),
                    end:   endAngle(for: index)
                ))
                .onTapGesture {
                    DispatchQueue.main.async {
                        selectedCategory = category
                        showingSubflavorPicker = true
                    }
                }
            }
            centerHub(size: size)
        }
    }

    private func centerHub(size: CGFloat) -> some View {
        let diameter = WheelGeometry.centerDiameter(for: size)
        return Circle()
            .fill(Self.wheelBG)
            .frame(width: diameter, height: diameter)
            .overlay(
                Circle()
                    .strokeBorder(
                        Color(red: 0.55, green: 0.28, blue: 0.05).opacity(0.70),
                        lineWidth: 1.5
                    )
            )
            .overlay(
                Text(phase.rawValue)
                    .font(.system(size: size * 0.052, weight: .semibold))
                    .foregroundColor(Color(red: 0.84, green: 0.63, blue: 0.24))
            )
    }

    private var selectedFlavorsRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            let flavors = getAllSelectedFlavors()
            if flavors.isEmpty {
                Text("Tap on wheel segments to add flavors")
                    .font(.subheadline)
                    .foregroundColor(Color(red: 0.40, green: 0.25, blue: 0.08).opacity(0.70))
                    .padding(.horizontal)
            } else {
                Text("Selected Flavors")
                    .font(.headline)
                    .foregroundColor(Color(red: 0.30, green: 0.18, blue: 0.04))
                    .padding(.horizontal)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 8) {
                        ForEach(flavors, id: \.subflavor) { item in
                            FlavorTag(category: item.category, subflavor: item.subflavor) {
                                removeSubflavor(item.subflavor, from: item.category)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    @ViewBuilder
    private var sheetContent: some View {
        if let category = selectedCategory {
            SubflavorPickerView(
                category: category,
                intensity: Binding(
                    get: { flavorProfile.intensity(for: category, in: phase) },
                    set: { updateIntensity(for: category, value: $0) }
                ),
                selectedSubflavors: Binding(
                    get: { flavorProfile.subflavors(for: category, in: phase) },
                    set: { updateSubflavors(for: category, value: $0) }
                )
            )
            .presentationDetents([.medium, .large])
        } else {
            VStack {
                Text("Loading...").font(.headline).padding()
                Button("Close") { showingSubflavorPicker = false }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - Donut Segment

struct FlavorSegment: View {
    let category:   FlavorCategory
    let intensity:  Double
    let startAngle: Angle
    let endAngle:   Angle
    var wheelSize:  CGFloat = 300

    var body: some View {
        ZStack {
            WheelGeometry.donutPath(size: wheelSize, start: startAngle, end: endAngle)
                .fill(category.color)

            CategoryLabel(
                category:   category,
                startAngle: startAngle,
                endAngle:   endAngle,
                wheelSize:  wheelSize,
                intensity:  intensity
            )
        }
    }
}

// MARK: - Category Label

struct CategoryLabel: View {
    let category:   FlavorCategory
    let startAngle: Angle
    let endAngle:   Angle
    var wheelSize:  CGFloat = 300
    var intensity:  Double  = 0.0

    var body: some View {
        let labelR  = WheelGeometry.labelRadius(for: wheelSize)
        let midRad  = CGFloat((startAngle.radians + endAngle.radians) / 2)
        // Round to whole pixels so the glyph rasteriser never straddles a pixel boundary
        let px      = (wheelSize / 2 + labelR * cos(midRad)).rounded()
        let py      = (wheelSize / 2 + labelR * sin(midRad)).rounded()

        Text(category.rawValue)
            .font(.system(size: 11, weight: .heavy))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.65), radius: 0, x: 1, y: 1)
            .position(x: px, y: py)
    }
}

// MARK: - Subflavor Picker

struct SubflavorPickerView: View {
    let category: FlavorCategory
    @Binding var intensity: Double
    @Binding var selectedSubflavors: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(
                    header: Text("Intensity"),
                    footer: Text("How strong this flavor is (e.g. a hint vs. dominant).")
                ) {
                    HStack {
                        Text("Subtle").font(.caption).foregroundColor(.secondary)
                        Slider(value: $intensity, in: 0...1.0, step: 0.1)
                            .disabled(selectedSubflavors.isEmpty)
                        Text("Strong").font(.caption).foregroundColor(.secondary)
                    }
                    if !selectedSubflavors.isEmpty {
                        Text("\(Int(round(intensity * 10)))/10")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                }
                Section(header: Text("Subflavors")) {
                    ForEach(category.subflavors, id: \.self) { subflavor in
                        Toggle(subflavor, isOn: Binding(
                            get: { selectedSubflavors.contains(subflavor) },
                            set: { isOn in
                                if isOn {
                                    selectedSubflavors.insert(subflavor)
                                    if intensity == 0 { intensity = 0.5 }
                                } else {
                                    selectedSubflavors.remove(subflavor)
                                    if selectedSubflavors.isEmpty { intensity = 0 }
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
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Flavor Tag

struct FlavorTag: View {
    let category:  FlavorCategory
    let subflavor: String
    let onRemove:  () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(subflavor).font(.caption).fontWeight(.medium)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(category.color))
        .foregroundColor(.white)
        .shadow(radius: 2)
    }
}
