import SwiftUI
import UniformTypeIdentifiers

struct CSVExportView: View {
    let whiskeys: [Whiskey]
    @State private var isExporting = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var csvContent = ""
    @State private var exportFilename = "BarrelBook-Export.csv"
    
    var body: some View {
        VStack(spacing: 20) {
            // Header image and title
            VStack {
                Image(systemName: "arrow.up.doc.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                    .padding(.bottom, 8)
                
                Text("Export Whiskey Collection")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .padding()
            
            // Filename input field
            GroupBox(label: Label("Export Settings", systemImage: "gear")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Filename:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    TextField("BarrelBook-Export.csv", text: $exportFilename)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    // Add .csv extension if not present
                    .onChange(of: exportFilename) { newValue in
                        if !newValue.hasSuffix(".csv") {
                            exportFilename = newValue.replacingOccurrences(of: ".csv", with: "") + ".csv"
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .padding(.horizontal)
            
            // Collection stats
            GroupBox(label: 
                Label("Collection Summary", systemImage: "list.bullet.clipboard")
                    .font(.headline)
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Total items: \(whiskeys.count)")
                    
                    // Count by type
                    let typeCounts = countWhiskeysByType()
                    ForEach(Array(typeCounts.keys.sorted()), id: \.self) { type in
                        if let count = typeCounts[type], count > 0 {
                            Text("\(type): \(count)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            .padding(.horizontal)
            
            // Export button
            Button(action: prepareAndExport) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export CSV File")
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .disabled(whiskeys.isEmpty)
            
            if whiskeys.isEmpty {
                Text("No whiskeys to export. Add some whiskeys first.")
                    .foregroundColor(.secondary)
                    .italic()
                    .padding()
            }
            
            Spacer()
            
            // Information about the export
            GroupBox(label:
                Label("About CSV Export", systemImage: "info.circle")
                    .font(.headline)
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("The exported CSV file includes:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("• All whiskeys in your collection")
                    Text("• Details such as name, type, proof, age, etc.")
                    Text("• Perfect for backup or analysis in spreadsheet apps")
                    
                    Divider()
                    
                    Text("CSV files can be opened with:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text("• Microsoft Excel")
                    Text("• Apple Numbers")
                    Text("• Google Sheets")
                    Text("• Any text editor")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
        .alert(isPresented: $showingError) {
            Alert(
                title: Text("Export Error"),
                message: Text(errorMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .fileExporter(
            isPresented: $isExporting,
            document: CSVFileSaver(text: csvContent),
            contentType: .commaSeparatedText,
            defaultFilename: exportFilename,
            onCompletion: { result in
                switch result {
                case .success(let url):
                    print("CSV exported successfully to \(url.path)")
                case .failure(let error):
                    errorMessage = "Export failed: \(error.localizedDescription)"
                    showingError = true
                }
            }
        )
    }
    
    private func prepareAndExport() {
        do {
            csvContent = try CSVService.shared.exportWhiskeys(whiskeys)
            
            // Only add timestamp if filename is the default one
            if exportFilename == "BarrelBook-Export.csv" {
                let timestamp = Int(Date().timeIntervalSince1970)
                exportFilename = "BarrelBook-Export-\(timestamp).csv"
            }
            
            // Ensure .csv extension
            if !exportFilename.hasSuffix(".csv") {
                exportFilename += ".csv"
            }
            
            isExporting = true
        } catch {
            errorMessage = "Failed to prepare CSV data: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    private func countWhiskeysByType() -> [String: Int] {
        var counts: [String: Int] = [:]
        
        for whiskey in whiskeys {
            if let type = whiskey.type, !type.isEmpty {
                counts[type, default: 0] += 1
            } else {
                counts["Unknown", default: 0] += 1
            }
        }
        
        return counts
    }
}

#Preview {
    CSVExportView(whiskeys: [])
} 