import Foundation
import WebKit
import Combine

// Service for extracting content from web pages and converting to markdown
class MarkdownExtractor: NSObject {
    
    // Singleton instance
    static let shared = MarkdownExtractor()
    
    // Private initializer for singleton
    private override init() {
        super.init()
    }
    
    // Extract content from a URL and convert to markdown
    func extractMarkdown(from url: URL, completion: @escaping (Result<ExtractedMarkdown, Error>) -> Void) {
        // Create a URL session task to fetch the HTML content
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data, let html = String(data: data, encoding: .utf8) else {
                DispatchQueue.main.async {
                    completion(.failure(ExtractionError.invalidContent))
                }
                return
            }
            
            // Extract title and content from HTML
            self.extractFromHTML(html, url: url, completion: completion)
        }
        
        task.resume()
    }
    
    // Extract content from HTML string
    private func extractFromHTML(_ html: String, url: URL, completion: @escaping (Result<ExtractedMarkdown, Error>) -> Void) {
        // Ensure we're on the main thread for UI operations
        DispatchQueue.main.async {
            // Create a temporary WebView to parse the HTML
            let webView = WKWebView()
            webView.navigationDelegate = self
            
            // Store the completion handler
            self.completionHandler = completion
            
            // Load the HTML content
            webView.loadHTMLString(html, baseURL: url)
        }
    }
    
    // Completion handler for extraction
    private var completionHandler: ((Result<ExtractedMarkdown, Error>) -> Void)?
    
    // JavaScript for extracting content and converting to markdown
    private let extractionScript = """
    (function() {
        // Helper to get the main content
        function findMainContent() {
            // First try to find article or main elements
            let article = document.querySelector('article');
            if (article) return article;
            
            let main = document.querySelector('main');
            if (main) return main;
            
            // If in reader mode, the content should be easily accessible
            let readerContent = document.querySelector('#reader-content');
            if (readerContent) return readerContent;
            
            // Look for common content containers
            for (let selector of ['.content', '.article-content', '.post-content', '.entry-content', '.review-content', '.post-body', '.article-body']) {
                let element = document.querySelector(selector);
                if (element) return element;
            }
            
            // Fallback to body
            return document.body;
        }
        
        // Get the main content
        let content = findMainContent();
        
        // Clean up the content
        function cleanContent(element) {
            // Create a clone to work with
            let clone = element.cloneNode(true);
            
            // Remove unwanted elements
            const unwanted = [
                'script', 'style', 'noscript', 'iframe',
                'nav', 'footer', 'header', 'aside',
                '.comments', '.ads', '.advertisement',
                '.social', '.sharing', '.related',
                'form', '.newsletter', '.subscription',
                '.cookie-notice', '.popup', '.modal',
                '.sidebar', '.navigation', '.menu'
            ];
            
            unwanted.forEach(selector => {
                let elements = clone.querySelectorAll(selector);
                elements.forEach(el => el.remove());
            });
            
            return clone;
        }
        
        // Convert HTML to Markdown
        function htmlToMarkdown(element) {
            let markdown = '';
            
            // Process headings
            for (let i = 1; i <= 6; i++) {
                let headings = element.querySelectorAll(`h${i}`);
                headings.forEach(heading => {
                    let text = heading.textContent.trim();
                    markdown += '#'.repeat(i) + ' ' + text + '\\n\\n';
                });
            }
            
            // Process paragraphs
            let paragraphs = element.querySelectorAll('p');
            paragraphs.forEach(p => {
                let text = p.textContent.trim();
                if (text) {
                    markdown += text + '\\n\\n';
                }
            });
            
            // Process lists
            let lists = element.querySelectorAll('ul, ol');
            lists.forEach(list => {
                let items = list.querySelectorAll('li');
                items.forEach(item => {
                    let text = item.textContent.trim();
                    if (text) {
                        markdown += '- ' + text + '\\n';
                    }
                });
                markdown += '\\n';
            });
            
            // Process blockquotes
            let quotes = element.querySelectorAll('blockquote');
            quotes.forEach(quote => {
                let text = quote.textContent.trim();
                if (text) {
                    markdown += '> ' + text.replace(/\\n/g, '\\n> ') + '\\n\\n';
                }
            });
            
            // Process links
            let links = element.querySelectorAll('a');
            links.forEach(link => {
                let text = link.textContent.trim();
                let href = link.getAttribute('href');
                if (text && href) {
                    markdown += `[${text}](${href})\\n\\n`;
                }
            });
            
            // Process images
            let images = element.querySelectorAll('img');
            images.forEach(img => {
                let alt = img.getAttribute('alt') || '';
                let src = img.getAttribute('src') || '';
                if (src) {
                    markdown += `![${alt}](${src})\\n\\n`;
                }
            });
            
            // Process code blocks
            let codeBlocks = element.querySelectorAll('pre code, pre');
            codeBlocks.forEach(code => {
                let text = code.textContent.trim();
                if (text) {
                    markdown += '```\\n' + text + '\\n```\\n\\n';
                }
            });
            
            return markdown;
        }
        
        // Get the title
        let title = document.title;
        
        // Clean and convert the content
        let cleanedContent = cleanContent(content);
        let markdown = htmlToMarkdown(cleanedContent);
        
        return {
            title: title,
            markdown: markdown,
            url: window.location.href
        };
    })();
    """
}

// MARK: - WKNavigationDelegate
extension MarkdownExtractor: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Extract content using JavaScript
        webView.evaluateJavaScript(extractionScript) { [weak self] (result, error) in
            guard let self = self else { return }
            
            if let error = error {
                self.completionHandler?(.failure(error))
                return
            }
            
            if let dict = result as? [String: Any],
               let title = dict["title"] as? String,
               let markdown = dict["markdown"] as? String,
               let url = dict["url"] as? String {
                
                let extracted = ExtractedMarkdown(
                    title: title,
                    markdown: markdown,
                    sourceURL: url
                )
                
                self.completionHandler?(.success(extracted))
            } else {
                self.completionHandler?(.failure(ExtractionError.extractionFailed))
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        completionHandler?(.failure(error))
    }
}

// Model for extracted markdown
struct ExtractedMarkdown {
    let title: String
    let markdown: String
    let sourceURL: String
}

// Custom errors
enum ExtractionError: Error {
    case invalidContent
    case extractionFailed
} 