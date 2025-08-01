import SwiftUI
import Foundation
import WebKit
import CoreData

// Main web reader view
struct WebReaderView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    
    let whiskey: Whiskey
    let url: URL
    
    // Strong reference to the extractor to prevent it from being deallocated
    @StateObject private var extractorManager = ExtractorManager()
    
    @State private var isLoading = true
    @State private var error: Error?
    @State private var extractedContent = ""
    @State private var extractedTitle = ""
    @State private var extractionComplete = false
    @State private var extractionFailed = false
    @State private var shouldDismissToWhiskeyDetail = false
    @State private var isSaving = false
    @State private var showingManualExtractOption = false
    @State private var isShowingWebView = false
    @State private var showingDuplicateAlert = false
    @State private var showingContentPreview = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isLoading {
                    VStack(spacing: 20) {
                        ProgressView("Extracting review content...")
                        Text("Please wait while we extract the review from the webpage")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                    .padding(.top, 40)
                } else if extractionFailed {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        
                        Text("Could not extract review content")
                            .font(.headline)
                        
                        Text("This website may use a complex layout that makes automatic extraction difficult. You can still save the link for reference.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        VStack(spacing: 15) {
                            Button {
                                isLoading = true
                                extractionFailed = false
                                extractContent()
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Try Extraction Again")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            
                            Button {
                                isShowingWebView = true
                            } label: {
                                HStack {
                                    Image(systemName: "safari")
                                    Text("View in Embedded Browser")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(10)
                            }
                            
                            Button {
                                extractedTitle = url.host ?? "Review"
                                extractedContent = "Review from: \(url.absoluteString)\n\nThis review was saved manually from the provided URL. Visit the original website to read the full review content."
                                extractionFailed = false
                                showingManualExtractOption = true
                            } label: {
                                HStack {
                                    Image(systemName: "link")
                                    Text("Save Link Only")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .foregroundColor(.primary)
                                .cornerRadius(10)
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else if showingManualExtractOption {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Save Link to Review")
                            .font(.headline)
                            .padding(.bottom)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        Text(extractedTitle)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("The following information will be saved:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Source:")
                                .fontWeight(.medium)
                            Text(url.host ?? url.absoluteString)
                                .foregroundColor(.blue)
                        }
                        
                        Text("This will save a link to the review for future reference.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top)
                        
                        Button("Save Link to Review") {
                            checkAndSaveReview()
                        }
                        .disabled(isSaving)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding(.top, 20)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    // Successful content extraction
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Review Extracted")
                            .font(.headline)
                            .padding(.bottom)
                            .frame(maxWidth: .infinity, alignment: .center)
                        
                        Text(extractedTitle)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        if !url.absoluteString.isEmpty {
                            HStack {
                                Text("Source:")
                                    .fontWeight(.medium)
                                Text(url.host ?? url.absoluteString)
                                    .foregroundColor(.blue)
                            }
                            .font(.caption)
                            .padding(.bottom, 8)
                        }
                        
                        // Save button moved to top
                        Button {
                            showingContentPreview = true
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.down")
                                Text("Preview & Save")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                        }
                        .disabled(isSaving)
                        .padding(.vertical, 10)
                        
                        // Content with proper text formatting
                        let paragraphs = extractedContent.components(separatedBy: "\n\n")
                        ForEach(paragraphs, id: \.self) { paragraph in
                            if !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(paragraph)
                                    .font(.body)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.bottom, 8)
                            }
                        }
                    }
                    .padding()
                }
            }
            .padding(.bottom, 40)
        }
        .onAppear {
            extractContent()
        }
        .onChange(of: shouldDismissToWhiskeyDetail) { newValue in
            if newValue {
                // Post notification to refresh views
                NotificationCenter.default.post(name: NSNotification.Name("WebContentSaved"), object: nil)
                NotificationCenter.default.post(name: NSNotification.Name("WebContentSavedForWhiskey"), object: nil, userInfo: ["whiskeyID": whiskey.id?.uuidString ?? ""])
                
                // Dismiss all the way back to the whiskey detail view
                dismiss()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $isShowingWebView) {
            NavigationView {
                WebViewContainer(url: url, onExtractContent: { extractedText in
                    if !extractedText.isEmpty {
                        extractedContent = extractedText
                        extractedTitle = url.host ?? "Review from \(url.host ?? "website")"
                        extractionFailed = false
                        isShowingWebView = false
                    } else {
                        // Couldn't extract
                        extractionFailed = true
                        isShowingWebView = false
                    }
                })
                .navigationTitle(url.host ?? "Review")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            isShowingWebView = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingContentPreview) {
            ContentPreviewView(
                title: extractedTitle,
                content: extractedContent,
                sourceURL: url.absoluteString,
                onSave: { title, content in
                    saveReviewWithContent(title: title, content: content)
                }
            )
        }
        .alert("Review Already Exists", isPresented: $showingDuplicateAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Save Anyway") {
                saveReviewWithContent(title: extractedTitle.isEmpty ? (url.host ?? "Review") : extractedTitle,
                                    content: extractedContent.isEmpty ? "Saved link to review: \(url.absoluteString)" : extractedContent)
            }
        } message: {
            Text("A review from this source has already been saved for this whiskey. Do you want to save it anyway?")
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func extractContent() {
        print("Starting content extraction from URL: \(url.absoluteString)")
        
        // Use our extractor manager which holds a strong reference
        extractorManager.extract(from: url) { title, content, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Extraction error: \(error)")
                    self.extractionFailed = true
                    self.isLoading = false
                    return
                }
                
                // Set the extracted title and content
                if !title.isEmpty {
                    self.extractedTitle = title
                } else {
                    self.extractedTitle = self.url.host ?? "Review"
                }
                
                if !content.isEmpty && content.count > 200 {
                    self.extractedContent = content
                    print("Successfully extracted \(content.count) characters of content")
                    self.extractionComplete = true
                    self.extractionFailed = false
                } else {
                    print("Extracted content is too short or empty, showing extraction failed view")
                    self.extractionFailed = true
                }
                
                self.isLoading = false
            }
        }
    }
    
    // MARK: - Duplicate Detection
    private func checkForDuplicateReview() -> Bool {
        let fetchRequest: NSFetchRequest<WebContent> = WebContent.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "whiskey == %@ AND sourceURL == %@", whiskey, url.absoluteString)
        
        do {
            let existing = try viewContext.fetch(fetchRequest)
            return !existing.isEmpty
        } catch {
            print("Error checking for duplicate review: \(error)")
            return false
        }
    }
    
    // MARK: - Main Save Functions
    private func checkAndSaveReview() {
        // Check for duplicates first
        if checkForDuplicateReview() {
            showingDuplicateAlert = true
            return
        }
        
        // For link-only saves (when extraction failed)
        saveReviewWithContent(title: extractedTitle.isEmpty ? (url.host ?? "Review") : extractedTitle, 
                            content: "Saved link to review: \(url.absoluteString)")
    }
    
    private func saveReviewWithContent(title: String, content: String) {
        guard !title.isEmpty && !content.isEmpty else {
            showError("Cannot save review: title and content are required")
            return
        }
        
        isSaving = true
        
        let webContent = WebContent(context: viewContext)
        webContent.id = UUID()
        webContent.title = title
        webContent.content = content
        webContent.sourceURL = url.absoluteString
        webContent.date = Date()
        webContent.whiskey = whiskey
        
        do {
            try viewContext.save()
            
            // Post notification to refresh views
            NotificationCenter.default.post(name: NSNotification.Name("WebContentSaved"), object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("WebContentSavedForWhiskey"), object: nil, userInfo: ["whiskeyID": whiskey.id?.uuidString ?? ""])
            
            // Success - dismiss to whiskey detail
            shouldDismissToWhiskeyDetail = true
            HapticManager.shared.successFeedback()
            
        } catch {
            showError("Failed to save review: \(error.localizedDescription)")
        }
        
        isSaving = false
    }
    
    // MARK: - Error Handling
    private func showError(_ message: String) {
        errorMessage = message
        showingErrorAlert = true
        HapticManager.shared.errorFeedback()
    }
}

// Web view container for manual browsing and extraction
struct WebViewContainer: UIViewRepresentable {
    let url: URL
    let onExtractContent: (String) -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let preferences = WKPreferences()
        preferences.javaScriptEnabled = true
        
        let configuration = WKWebViewConfiguration()
        configuration.preferences = preferences
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        let request = URLRequest(url: url)
        webView.load(request)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Nothing to update
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let parent: WebViewContainer
        
        init(_ parent: WebViewContainer) {
            self.parent = parent
        }
        
        // Add a toolbar with extraction button after page loads
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Add a toolbar button for extraction
            let extractionScript = """
            (function() {
                // Create a floating button if it doesn't exist yet
                if (!document.getElementById('extraction-button')) {
                    var button = document.createElement('div');
                    button.id = 'extraction-button';
                    button.style.position = 'fixed';
                    button.style.bottom = '20px';
                    button.style.right = '20px';
                    button.style.backgroundColor = '#007AFF';
                    button.style.color = 'white';
                    button.style.padding = '12px 20px';
                    button.style.borderRadius = '25px';
                    button.style.fontFamily = '-apple-system, BlinkMacSystemFont, sans-serif';
                    button.style.fontSize = '16px';
                    button.style.fontWeight = 'bold';
                    button.style.boxShadow = '0 4px 12px rgba(0,0,0,0.2)';
                    button.style.zIndex = '9999';
                    button.innerText = 'Extract Content';
                    
                    // Add click event
                    button.addEventListener('click', function() {
                        // Change button style to show it's working
                        button.innerText = 'Extracting...';
                        button.style.backgroundColor = '#555555';
                        
                        // Get main content
                        var content = '';
                        var paragraphs = document.getElementsByTagName('p');
                        for (var i = 0; i < paragraphs.length; i++) {
                            var p = paragraphs[i];
                            if (p.textContent.trim().length > 40) {
                                content += p.textContent.trim() + '\\n\\n';
                            }
                        }
                        
                        // Call the completion handler
                        window.webkit.messageHandlers.extractContent.postMessage(content);
                    });
                    
                    document.body.appendChild(button);
                }
            })();
            """
            
            // Add a message handler
            webView.configuration.userContentController.add(self, name: "extractContent")
            
            // Run the script to add the button
            webView.evaluateJavaScript(extractionScript, completionHandler: nil)
        }
        
        // Handle messages from JavaScript
        @objc func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "extractContent", let content = message.body as? String {
                DispatchQueue.main.async {
                    self.parent.onExtractContent(content)
                }
            }
        }
    }
}

// Class to manage the extractor and keep it alive
class ExtractorManager: ObservableObject {
    // Strong reference to the extractor
    private var extractor: ReadabilityExtractor?
    
    func extract(from url: URL, completion: @escaping (String, String, Error?) -> Void) {
        // Create a new extractor and store it
        extractor = ReadabilityExtractor()
        
        // Use the extractor to extract content
        extractor?.extractContent(from: url, completion: { [weak self] title, content, error in
            // Call the completion handler
            completion(title, content, error)
            
            // Clear the reference to allow deallocation after completed
            self?.extractor = nil
        })
    }
    
    deinit {
        print("ExtractorManager deinitialized")
    }
}

// MARK: - Content Preview View
struct ContentPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var editableTitle: String
    @State private var editableContent: String
    let sourceURL: String
    let onSave: (String, String) -> Void
    
    init(title: String, content: String, sourceURL: String, onSave: @escaping (String, String) -> Void) {
        self._editableTitle = State(initialValue: title)
        self._editableContent = State(initialValue: content.isEmpty ? "Saved link to review: \(sourceURL)" : content)
        self.sourceURL = sourceURL
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Review Details")) {
                    TextField("Title", text: $editableTitle)
                    
                    if let url = URL(string: sourceURL) {
                        HStack {
                            Text("Source")
                            Spacer()
                            Text(url.host ?? sourceURL)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Section(header: Text("Content")) {
                    TextEditor(text: $editableContent)
                        .frame(minHeight: 200)
                }
                
                Section {
                    Text("You can edit the title and content before saving. The original source URL will be preserved.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Preview Review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        onSave(editableTitle, editableContent)
                        dismiss()
                    }
                    .disabled(editableTitle.isEmpty || editableContent.isEmpty)
                }
            }
        }
    }
}

// Preview
struct WebReaderView_Previews: PreviewProvider {
    static var previews: some View {
        WebReaderView(
            whiskey: Whiskey(),
            url: URL(string: "https://www.google.com")!
        )
    }
} 