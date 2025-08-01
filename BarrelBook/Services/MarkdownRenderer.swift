import SwiftUI
import WebKit

// Service for rendering markdown content
class MarkdownRenderer {
    
    // Singleton instance
    static let shared = MarkdownRenderer()
    
    // Private initializer for singleton
    private init() {}
    
    // Convert markdown to HTML
    func markdownToHTML(_ markdown: String) -> String {
        // Basic markdown to HTML conversion
        var html = markdown
        
        // Headers
        html = html.replacingOccurrences(of: "^# (.*?)$", with: "<h1>$1</h1>", options: .regularExpression, range: nil)
        html = html.replacingOccurrences(of: "^## (.*?)$", with: "<h2>$1</h2>", options: .regularExpression, range: nil)
        html = html.replacingOccurrences(of: "^### (.*?)$", with: "<h3>$1</h3>", options: .regularExpression, range: nil)
        html = html.replacingOccurrences(of: "^#### (.*?)$", with: "<h4>$1</h4>", options: .regularExpression, range: nil)
        html = html.replacingOccurrences(of: "^##### (.*?)$", with: "<h5>$1</h5>", options: .regularExpression, range: nil)
        html = html.replacingOccurrences(of: "^###### (.*?)$", with: "<h6>$1</h6>", options: .regularExpression, range: nil)
        
        // Bold
        html = html.replacingOccurrences(of: "\\*\\*(.*?)\\*\\*", with: "<strong>$1</strong>", options: .regularExpression, range: nil)
        html = html.replacingOccurrences(of: "__(.*?)__", with: "<strong>$1</strong>", options: .regularExpression, range: nil)
        
        // Italic
        html = html.replacingOccurrences(of: "\\*(.*?)\\*", with: "<em>$1</em>", options: .regularExpression, range: nil)
        html = html.replacingOccurrences(of: "_(.*?)_", with: "<em>$1</em>", options: .regularExpression, range: nil)
        
        // Links
        html = html.replacingOccurrences(of: "\\[(.*?)\\]\\((.*?)\\)", with: "<a href=\"$2\">$1</a>", options: .regularExpression, range: nil)
        
        // Images
        html = html.replacingOccurrences(of: "!\\[(.*?)\\]\\((.*?)\\)", with: "<img src=\"$2\" alt=\"$1\">", options: .regularExpression, range: nil)
        
        // Blockquotes
        html = html.replacingOccurrences(of: "^> (.*?)$", with: "<blockquote>$1</blockquote>", options: .regularExpression, range: nil)
        
        // Lists
        html = html.replacingOccurrences(of: "^\\- (.*?)$", with: "<li>$1</li>", options: .regularExpression, range: nil)
        html = html.replacingOccurrences(of: "^\\* (.*?)$", with: "<li>$1</li>", options: .regularExpression, range: nil)
        
        // Code blocks
        html = html.replacingOccurrences(of: "```(.*?)```", with: "<pre><code>$1</code></pre>", options: .regularExpression, range: nil)
        
        // Inline code
        html = html.replacingOccurrences(of: "`(.*?)`", with: "<code>$1</code>", options: .regularExpression, range: nil)
        
        // Paragraphs
        html = html.replacingOccurrences(of: "^([^<].*?)$", with: "<p>$1</p>", options: .regularExpression, range: nil)
        
        // Wrap in HTML document
        let fullHTML = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    line-height: 1.6;
                    color: #333;
                    max-width: 800px;
                    margin: 0 auto;
                    padding: 20px;
                }
                h1, h2, h3, h4, h5, h6 {
                    margin-top: 24px;
                    margin-bottom: 16px;
                    font-weight: 600;
                    line-height: 1.25;
                }
                h1 { font-size: 2em; }
                h2 { font-size: 1.5em; }
                h3 { font-size: 1.25em; }
                h4 { font-size: 1em; }
                h5 { font-size: 0.875em; }
                h6 { font-size: 0.85em; }
                p {
                    margin-top: 0;
                    margin-bottom: 16px;
                }
                a {
                    color: #0366d6;
                    text-decoration: none;
                }
                a:hover {
                    text-decoration: underline;
                }
                img {
                    max-width: 100%;
                    height: auto;
                }
                blockquote {
                    padding: 0 1em;
                    color: #6a737d;
                    border-left: 0.25em solid #dfe2e5;
                    margin: 0 0 16px 0;
                }
                code {
                    padding: 0.2em 0.4em;
                    margin: 0;
                    font-size: 85%;
                    background-color: rgba(27,31,35,0.05);
                    border-radius: 3px;
                    font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
                }
                pre {
                    padding: 16px;
                    overflow: auto;
                    font-size: 85%;
                    line-height: 1.45;
                    background-color: #f6f8fa;
                    border-radius: 3px;
                }
                pre code {
                    padding: 0;
                    margin: 0;
                    font-size: 100%;
                    word-break: normal;
                    white-space: pre;
                    background: transparent;
                    border: 0;
                }
                ul, ol {
                    padding-left: 2em;
                    margin-top: 0;
                    margin-bottom: 16px;
                }
                li {
                    margin-top: 0.25em;
                }
                table {
                    display: block;
                    width: 100%;
                    overflow: auto;
                    margin-top: 0;
                    margin-bottom: 16px;
                    border-spacing: 0;
                    border-collapse: collapse;
                }
                table th {
                    font-weight: 600;
                }
                table th, table td {
                    padding: 6px 13px;
                    border: 1px solid #dfe2e5;
                }
                table tr {
                    background-color: #fff;
                    border-top: 1px solid #c6cbd1;
                }
                table tr:nth-child(2n) {
                    background-color: #f6f8fa;
                }
            </style>
        </head>
        <body>
            \(html)
        </body>
        </html>
        """
        
        return fullHTML
    }
}

// SwiftUI view for rendering markdown
struct MarkdownView: UIViewRepresentable {
    let markdown: String
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .clear
        
        // Load the markdown content
        let html = MarkdownRenderer.shared.markdownToHTML(markdown)
        webView.loadHTMLString(html, baseURL: nil)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Update the content if markdown changes
        let html = MarkdownRenderer.shared.markdownToHTML(markdown)
        uiView.loadHTMLString(html, baseURL: nil)
    }
} 