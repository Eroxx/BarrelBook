import SwiftUI
import SafariServices
import CoreData

struct SavedWebContentView: View {
    let whiskey: Whiskey
    
    @Environment(\.managedObjectContext) private var viewContext
    @State private var editingContent: WebContent? = nil
    @State private var showingEditSheet = false
    
    @FetchRequest private var savedContent: FetchedResults<WebContent>
    
    init(whiskey: Whiskey) {
        self.whiskey = whiskey
        
        // Create a fetch request for this whiskey's web content
        // Sort alphabetically by source URL
        let fetchRequest: NSFetchRequest<WebContent> = WebContent.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "whiskey == %@", whiskey)
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \WebContent.sourceURL, ascending: true)]
        
        _savedContent = FetchRequest(fetchRequest: fetchRequest)
    }
    
    var body: some View {
        List {
            if savedContent.isEmpty {
                Text("No saved reviews yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(savedContent) { content in
                    NavigationLink {
                        WebContentDetailView(content: content)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(content.title ?? "Untitled Review")
                                .font(.headline)
                            
                            if let sourceURL = content.sourceURL, let url = URL(string: sourceURL) {
                                Text(url.host ?? sourceURL)
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            
                            if let date = content.date {
                                Text("Saved on \(date, formatter: itemFormatter)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteContent(content)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        
                        Button {
                            editingContent = content
                            showingEditSheet = true
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .navigationTitle("Saved Reviews")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditSheet) {
            if let content = editingContent {
                NavigationView {
                    EditWebContentView(content: content)
                }
            }
        }
    }
    
    private func deleteContent(_ content: WebContent) {
        withAnimation {
            viewContext.delete(content)
            
            do {
                try viewContext.save()
                HapticManager.shared.successFeedback()
            } catch {
                print("Error deleting content: \(error)")
                HapticManager.shared.errorFeedback()
            }
        }
    }
}

// View for editing a saved web review
struct EditWebContentView: View {
    @ObservedObject var content: WebContent
    
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String
    @State private var contentText: String
    
    init(content: WebContent) {
        self.content = content
        _title = State(initialValue: content.title ?? "")
        _contentText = State(initialValue: content.content ?? "")
    }
    
    var body: some View {
        Form {
            Section(header: Text("Review Details")) {
                TextField("Title", text: $title)
                
                if let sourceURL = content.sourceURL, let url = URL(string: sourceURL) {
                    HStack {
                        Text("Source")
                        Spacer()
                        Text(url.host ?? sourceURL)
                            .foregroundColor(.blue)
                    }
                }
                
                if let date = content.date {
                    HStack {
                        Text("Saved on")
                        Spacer()
                        Text("\(date, formatter: itemFormatter)")
                    }
                }
            }
            
            Section(header: Text("Content")) {
                TextEditor(text: $contentText)
                    .frame(minHeight: 200)
            }
        }
        .navigationTitle("Edit Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Save") {
                    saveChanges()
                }
                .disabled(title.isEmpty || contentText.isEmpty)
            }
        }
    }
    
    private func saveChanges() {
        withAnimation {
            content.title = title
            content.content = contentText
            
            do {
                try viewContext.save()
                HapticManager.shared.successFeedback()
                dismiss()
            } catch {
                HapticManager.shared.errorFeedback()
                print("Error saving edited content: \(error)")
            }
        }
    }
}

// Wrapper view to prevent navigation issues
struct SavedWebContentContainerView: View {
    let whiskey: Whiskey

    var body: some View {
        NavigationView {
            SavedWebContentView(whiskey: whiskey)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct WebContentDetailView: View {
    let content: WebContent
    
    @State private var showingSourceWebsite = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Title
                Text(content.title ?? "Untitled Review")
                    .font(.title)
                    .fontWeight(.bold)
                
                // Source and date
                VStack(alignment: .leading, spacing: 4) {
                    if let date = content.date {
                        Text("Saved on \(date, formatter: itemFormatter)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let sourceURL = content.sourceURL, let url = URL(string: sourceURL) {
                        Button {
                            showingSourceWebsite = true
                        } label: {
                            Text("Source: \(url.host ?? sourceURL)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Divider()
                
                // Content
                Text(content.content ?? "No content available")
                    .font(.body)
            }
            .padding()
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingSourceWebsite) {
            if let sourceURL = content.sourceURL, let url = URL(string: sourceURL) {
                SafariView(url: url)
            }
        }
    }
}

// Helper for opening URLs in Safari
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No updates needed
    }
}

// Formatter for dates
private let itemFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
}() 