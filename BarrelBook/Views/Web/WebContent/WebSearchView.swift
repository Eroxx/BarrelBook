import SwiftUI
import WebKit

struct WebSearchView: View {
    let whiskey: Whiskey
    
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingWebReader = false
    @State private var selectedURL: URL? = nil
    @State private var shouldDismissToWhiskeyDetail = false
    
    var formattedSearchQuery: String {
        let name = whiskey.name ?? "whiskey"
        return "\(name) whiskey review"
    }
    
    var searchURL: URL {
        let formattedName = formattedSearchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://www.google.com/search?q=\(formattedName)"
        return URL(string: urlString) ?? URL(string: "https://www.google.com")!
    }
    
    var body: some View {
        NavigationView {
            WebSearchContainer(
                whiskey: whiskey,
                url: searchURL,
                onLinkSelected: { url in
                    selectedURL = url
                    isShowingWebReader = true
                }
            )
            .navigationTitle("Search Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $isShowingWebReader) {
                if let url = selectedURL {
                    WebReaderView(whiskey: whiskey, url: url)
                        .onDisappear {
                            // Check if we should dismiss to whiskey detail
                            if shouldDismissToWhiskeyDetail {
                                dismiss()
                            }
                        }
                }
            }
            .onChange(of: shouldDismissToWhiskeyDetail) { newValue in
                if newValue {
                    // Dismiss back to whiskey detail view
                    dismiss()
                }
            }
            .onAppear {
                // Set up notification observer for web content saved
                NotificationCenter.default.addObserver(
                    forName: NSNotification.Name("WebContentSavedForWhiskey"),
                    object: nil,
                    queue: .main
                ) { notification in
                    // Check if this notification is for this whiskey
                    if let userInfo = notification.userInfo,
                       let whiskeyID = userInfo["whiskeyID"] as? String,
                       let currentWhiskeyID = whiskey.id?.uuidString,
                       whiskeyID == currentWhiskeyID {
                        print("Received web content saved notification for this whiskey")
                        
                        // Set flag to dismiss to whiskey detail
                        shouldDismissToWhiskeyDetail = true
                    }
                }
            }
        }
    }
}

// Container for the WebView with search results
struct WebSearchContainer: UIViewRepresentable {
    let whiskey: Whiskey
    let url: URL
    let onLinkSelected: (URL) -> Void
    
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
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        // No updates needed
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebSearchContainer
        
        init(_ parent: WebSearchContainer) {
            self.parent = parent
        }
        
        // Intercept link clicks
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated {
                // Get the URL that was clicked
                if let url = navigationAction.request.url {
                    // Check if it's a Google search result (we want to allow those)
                    if url.host?.contains("google.com") == true && 
                       (url.path.contains("/search") || url.path.isEmpty) {
                        // Allow navigation within Google search
                        decisionHandler(.allow)
                        return
                    } else {
                        // It's an external link - open in the reader view
                        parent.onLinkSelected(url)
                        decisionHandler(.cancel)
                        return
                    }
                }
            }
            
            // Allow other navigation
            decisionHandler(.allow)
        }
    }
}

// Preview
struct WebSearchView_Previews: PreviewProvider {
    static var previews: some View {
        WebSearchView(whiskey: Whiskey())
    }
} 