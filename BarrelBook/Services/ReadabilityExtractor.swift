import Foundation
import WebKit

// Readability-based extractor for web content
class ReadabilityExtractor: NSObject, WKNavigationDelegate {
    private var webView: WKWebView!
    private var extractionCompletion: ((String, String, Error?) -> Void)?
    private var loadTimer: Timer?
    private static let timeoutInterval: TimeInterval = 30.0 // Increased timeout to 30 seconds
    private var retryCount = 0
    private static let maxRetries = 2
    
    // Initialize with a frame (can be zero for headless operation)
    override init() {
        super.init()
        // Create a WebView with a configuration
        let config = WKWebViewConfiguration()
        // Prevent media playback to avoid memory issues
        config.mediaTypesRequiringUserActionForPlayback = .all
        // Set smaller memory limits
        config.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        
        print("ReadabilityExtractor initialized")
    }
    
    deinit {
        invalidateTimer()
        print("ReadabilityExtractor deinitialized")
    }
    
    private func invalidateTimer() {
        loadTimer?.invalidate()
        loadTimer = nil
    }
    
    // Extract content from a URL
    func extractContent(from url: URL, completion: @escaping (String, String, Error?) -> Void) {
        print("Starting extraction from URL: \(url.absoluteString)")
        retryCount = 0
        extractionCompletion = completion
        
        // Set up timeout timer
        invalidateTimer()
        loadTimer = Timer.scheduledTimer(withTimeInterval: ReadabilityExtractor.timeoutInterval, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("⚠️ Extraction timed out after \(ReadabilityExtractor.timeoutInterval) seconds")
            self.extractionCompletion?("", "", NSError(domain: "ReadabilityExtractor", code: -100, userInfo: [NSLocalizedDescriptionKey: "Extraction timed out"]))
            self.invalidateTimer()
        }
        
        // Load the URL with a more aggressive timeout
        var request = URLRequest(url: url)
        request.timeoutInterval = 20.0 // Increased from 15.0
        print("Loading URL: \(url.absoluteString)")
        webView.load(request)
    }
    
    // Handle page load completion
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("✅ WebView finished loading page")
        
        // Cancel the timeout timer since page loaded
        invalidateTimer()
        
        // Give a small delay to ensure page is fully rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { // Increased from 0.5
            print("Starting content extraction now...")
            self.extractContent()
        }
    }
    
    private func extractContent() {
        // Use a more comprehensive extraction approach with better error handling
        let extractionJS = """
        try {
            // Enhanced function to get text from the main content
            function extractMainContent() {
                // Get the page title - try multiple approaches
                var pageTitle = document.title;
                
                // Try to find a better title if the document title is generic
                if (!pageTitle || pageTitle.length < 5 || pageTitle.includes('Home') || pageTitle.includes('Page')) {
                    // Look for heading elements
                    const headings = document.querySelectorAll('h1, h2');
                    for (const heading of headings) {
                        if (heading.textContent && heading.textContent.trim().length > 5) {
                            pageTitle = heading.textContent.trim();
                            break;
                        }
                    }
                }
                
                // Define selectors in priority order - more specific first, general later
                var selectors = [
                    // Whiskey-specific review containers
                    '.whiskey-review', '.whisky-review', '.review-content', '.tasting-notes',
                    '.whiskey-tasting', '.whisky-tasting', '.bottle-review',
                    // Common review containers
                    'article', '[role="article"]', '[itemtype*="Article"]',
                    '.post-content', '.post-body', '.entry-content', '.article-content', '.article-body',
                    '.review-content', '.product-review', '.review-body', 
                    // Review-specific attributes
                    '[itemprop="reviewBody"]', '[itemprop="articleBody"]',
                    // Common content containers
                    '.content', 'main', '#main-content', '#content', '.main',
                    // Very general fallbacks
                    '.container', '.page-content'
                ];
                
                var mainElement = null;
                var bestTextLength = 0;
                var bestParagraphCount = 0;
                
                // Find the element with the most substantial text content
                for (var i = 0; i < selectors.length; i++) {
                    var elements = document.querySelectorAll(selectors[i]);
                    for (var j = 0; j < elements.length; j++) {
                        var el = elements[j];
                        var textLength = el.textContent.trim().length;
                        var paragraphCount = el.querySelectorAll('p').length;
                        
                        // Skip if it's too small
                        if (textLength < 100) continue;
                        
                        // Prioritize elements with paragraphs
                        if (
                            // Either this is the first good candidate
                            !mainElement ||
                            // Or this one has significantly more paragraphs
                            (paragraphCount > 3 && paragraphCount > bestParagraphCount * 1.5) ||
                            // Or this one has more text and at least as many paragraphs
                            (textLength > bestTextLength * 1.25 && paragraphCount >= bestParagraphCount)
                        ) {
                            mainElement = el;
                            bestTextLength = textLength;
                            bestParagraphCount = paragraphCount;
                        }
                    }
                    
                    // If we found something good, stop early
                    if (mainElement && bestParagraphCount > 3 && bestTextLength > 1000) {
                        break;
                    }
                }
                
                // If nothing good found, try collecting paragraphs
                if (!mainElement || bestTextLength < 300) {
                    console.log("No main element found, collecting paragraphs directly");
                    // Try a direct paragraph search (commonly works on simple websites)
                    var allParagraphs = document.querySelectorAll('p');
                    var paragraphText = '';
                    var substantialParagraphs = 0;
                    
                    for (var i = 0; i < allParagraphs.length; i++) {
                        var p = allParagraphs[i];
                        var pText = p.textContent.trim();
                        
                        // Only include paragraphs with substantial content
                        if (pText.length > 40) {
                            paragraphText += pText + '\\n\\n';
                            substantialParagraphs++;
                        }
                    }
                    
                    // If we found enough good paragraphs, use them
                    if (substantialParagraphs >= 3 && paragraphText.length > 300) {
                        return {
                            title: pageTitle || "Web Content",
                            content: paragraphText
                        };
                    }
                    
                    // Last resort - look for any divs with substantial text
                    var contentDivs = [];
                    var allDivs = document.querySelectorAll('div');
                    
                    for (var i = 0; i < allDivs.length; i++) {
                        var div = allDivs[i];
                        if (div.textContent.trim().length > 200) {
                            contentDivs.push(div);
                        }
                    }
                    
                    // Sort by text length (descending)
                    contentDivs.sort((a, b) => b.textContent.length - a.textContent.length);
                    
                    // Take the top 3 content divs
                    var divContent = '';
                    for (var i = 0; i < Math.min(contentDivs.length, 3); i++) {
                        divContent += contentDivs[i].textContent.trim() + '\\n\\n';
                    }
                    
                    // If we have substantial content, use it
                    if (divContent.length > 300) {
                        return {
                            title: pageTitle || "Web Content",
                            content: divContent
                        };
                    }
                    
                    // Absolute last resort - just use the body
                    return {
                        title: pageTitle || "Web Content",
                        content: document.body.textContent
                            .replace(/\\s+/g, ' ')
                            .trim()
                    };
                }
                
                // Process the main element to extract formatted content
                var processedContent = '';
                var paragraphs = mainElement.querySelectorAll('p, h1, h2, h3, h4, h5, h6, blockquote, li');
                
                if (paragraphs.length > 0) {
                    // If the element has proper paragraph structure, use it
                    for (var i = 0; i < paragraphs.length; i++) {
                        var paragraph = paragraphs[i].textContent.trim();
                        if (paragraph.length > 0) {
                            processedContent += paragraph + '\\n\\n';
                        }
                    }
                } else {
                    // Otherwise just use the text content with some cleanup
                    processedContent = mainElement.textContent
                        .replace(/\\s+/g, ' ')
                        .trim();
                }
                
                return {
                    title: pageTitle || "Web Content",
                    content: processedContent
                };
            }
            
            var result = extractMainContent();
            JSON.stringify(result);
        } catch (e) {
            "ERROR: " + e.toString();
        }
        """
        
        print("Executing extraction script...")
        webView.evaluateJavaScript(extractionJS) { [weak self] (result, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Error running extraction script: \(error)")
                self.extractionCompletion?("", "", error)
                return
            }
            
            guard let resultString = result as? String else {
                print("❌ Failed to get result as string")
                self.extractionCompletion?("", "", NSError(domain: "ReadabilityExtractor", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to extract content"]))
                return
            }
            
            if resultString.hasPrefix("ERROR:") {
                print("❌ JavaScript error: \(resultString)")
                // Try a fallback extraction method
                self.extractFallbackContent()
                return
            }
            
            print("Got result string of length: \(resultString.count)")
            
            do {
                if let data = resultString.data(using: .utf8),
                   let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let title = json["title"] as? String,
                   let content = json["content"] as? String {
                    
                    print("✅ Successfully extracted content")
                    print("Title: \(title)")
                    print("Content length: \(content.count) characters")
                    
                    // Check if the extracted content appears valid
                    if content.count < 100 || !self.isValidReviewContent(content) {
                        print("⚠️ Extracted content too short or invalid, trying fallback method")
                        self.extractFallbackContent()
                        return
                    }
                    
                    // Format the content nicely
                    let formattedContent = self.formatContent(content)
                    
                    // Return the extracted content
                    self.extractionCompletion?(title, formattedContent, nil)
                } else {
                    print("❌ Failed to parse JSON result")
                    self.extractFallbackContent()
                }
            } catch {
                print("❌ Error parsing JSON: \(error)")
                self.extractFallbackContent()
            }
            
            // Clear the webview to free up memory
            self.webView.loadHTMLString("", baseURL: nil)
        }
    }
    
    // Fallback extraction method for difficult sites
    private func extractFallbackContent() {
        print("Using fallback extraction method...")
        
        let fallbackJS = """
        try {
            // Enhanced fallback extraction
            function extractWithFallback() {
                var allText = "";
                var title = document.title || "";
                
                // Function to clean text
                function cleanText(text) {
                    return text.replace(/\\s+/g, ' ').trim();
                }
                
                // Function to check if text is likely review content
                function isReviewContent(text) {
                    var reviewTerms = ['nose', 'palate', 'finish', 'taste', 'aroma', 'flavor',
                                     'whiskey', 'whisky', 'bourbon', 'rye', 'scotch',
                                     'rating', 'score', 'review', 'notes'];
                    var count = 0;
                    var lowerText = text.toLowerCase();
                    for (var i = 0; i < reviewTerms.length; i++) {
                        if (lowerText.includes(reviewTerms[i])) count++;
                    }
                    return count >= 2;
                }
                
                // Try multiple extraction strategies
                var strategies = [
                    // Strategy 1: Look for review-specific elements
                    function() {
                        var elements = document.querySelectorAll('.review, .tasting-notes, [itemprop="reviewBody"], .whiskey-review, .whisky-review');
                        var text = '';
                        for (var i = 0; i < elements.length; i++) {
                            text += cleanText(elements[i].textContent) + '\\n\\n';
                        }
                        return text;
                    },
                    // Strategy 2: Get all paragraphs with substantial content
                    function() {
                        var paragraphs = document.getElementsByTagName('p');
                        var text = '';
                        for (var i = 0; i < paragraphs.length; i++) {
                            var p = paragraphs[i];
                            var content = cleanText(p.textContent);
                            if (content.length > 40 && isReviewContent(content)) {
                                text += content + '\\n\\n';
                            }
                        }
                        return text;
                    },
                    // Strategy 3: Look for content in article-like elements
                    function() {
                        var elements = document.querySelectorAll('article, .article, .content, .post, main, #content, #main');
                        var text = '';
                        for (var i = 0; i < elements.length; i++) {
                            var content = cleanText(elements[i].textContent);
                            if (content.length > 200 && isReviewContent(content)) {
                                text += content + '\\n\\n';
                            }
                        }
                        return text;
                    }
                ];
                
                // Try each strategy until we get good content
                for (var i = 0; i < strategies.length; i++) {
                    var content = strategies[i]();
                    if (content.length > 300 && isReviewContent(content)) {
                        allText = content;
                        break;
                    }
                }
                
                // If still no good content, try getting the whole body
                if (allText.length < 300) {
                    allText = cleanText(document.body.textContent);
                }
                
                // Clean up the final text
                allText = allText
                    .replace(/\\n{3,}/g, '\\n\\n')  // Remove excessive line breaks
                    .replace(/ {2,}/g, ' ')         // Remove multiple spaces
                    .trim();
                
                return {
                    title: title,
                    content: allText
                };
            }
            
            var result = extractWithFallback();
            return JSON.stringify(result);
        } catch (e) {
            return "ERROR FALLBACK: " + e.toString();
        }
        """
        
        webView.evaluateJavaScript(fallbackJS) { [weak self] (result, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Error running fallback script: \(error)")
                self.extractionCompletion?("", "", error)
                return
            }
            
            guard let resultString = result as? String else {
                print("❌ Failed to get fallback result")
                self.extractionCompletion?("", "", NSError(domain: "ReadabilityExtractor", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to extract content with fallback method"]))
                return
            }
            
            if resultString.hasPrefix("ERROR FALLBACK:") {
                print("❌ JavaScript fallback error: \(resultString)")
                self.extractionCompletion?("", "", NSError(domain: "ReadabilityExtractor", code: -6, userInfo: [NSLocalizedDescriptionKey: resultString]))
                return
            }
            
            do {
                if let data = resultString.data(using: .utf8),
                   let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let title = json["title"] as? String,
                   let content = json["content"] as? String {
                    
                    print("✅ Successfully extracted content with fallback method")
                    print("Title: \(title)")
                    print("Content length: \(content.count) characters")
                    
                    // Format the content nicely
                    let formattedContent = self.formatContent(content)
                    
                    // Return the extracted content
                    self.extractionCompletion?(title, formattedContent, nil)
                } else {
                    print("❌ Failed to parse fallback JSON result")
                    self.extractionCompletion?("", "", NSError(domain: "ReadabilityExtractor", code: -7, userInfo: [NSLocalizedDescriptionKey: "Failed to parse fallback result"]))
                }
            } catch {
                print("❌ Error parsing fallback JSON: \(error)")
                self.extractionCompletion?("", "", error)
            }
            
            // Clear the webview to free up memory
            self.webView.loadHTMLString("", baseURL: nil)
        }
    }
    
    private func formatContent(_ content: String) -> String {
        // Remove excess whitespace and format paragraphs
        let lines = content.components(separatedBy: .newlines)
        let nonEmptyLines = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
        
        // Join with double newlines to create paragraph breaks
        let formatted = nonEmptyLines.joined(separator: "\n\n")
        
        // Clean up common issues
        return formatted
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression) // Remove excessive line breaks
            .replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression) // Remove multiple spaces
    }
    
    // Handle errors
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("❌ WebView failed to load page: \(error)")
        invalidateTimer()
        
        // Retry on certain types of errors
        if retryCount < ReadabilityExtractor.maxRetries {
            retryCount += 1
            print("🔄 Retrying extraction (attempt \(retryCount + 1) of \(ReadabilityExtractor.maxRetries + 1))")
            
            // Add a small delay before retrying
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                self.webView.load(URLRequest(url: self.webView.url!))
            }
        } else {
            extractionCompletion?("", "", error)
        }
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("❌ WebView failed provisional navigation: \(error)")
        invalidateTimer()
        
        // Retry on certain types of errors
        if retryCount < ReadabilityExtractor.maxRetries {
            retryCount += 1
            print("🔄 Retrying extraction (attempt \(retryCount + 1) of \(ReadabilityExtractor.maxRetries + 1))")
            
            // Add a small delay before retrying
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                self.webView.load(URLRequest(url: self.webView.url!))
            }
        } else {
            extractionCompletion?("", "", error)
        }
    }
    
    // Helper function to validate review content
    private func isValidReviewContent(_ content: String) -> Bool {
        // Check for common review indicators
        let reviewIndicators = [
            "nose", "palate", "finish", "taste", "aroma", "flavor",
            "whiskey", "whisky", "bourbon", "rye", "scotch",
            "rating", "score", "review", "notes"
        ]
        
        let lowercasedContent = content.lowercased()
        let indicatorCount = reviewIndicators.filter { lowercasedContent.contains($0) }.count
        
        // Content should contain at least 3 review-related terms
        return indicatorCount >= 3
    }
} 