import SwiftUI
import WebKit

/// Temporary SVG logo experiment. The original XMBWaveAnimation remains available.
struct AnimatedRibbonLogo: UIViewRepresentable {
    var slowlyRotates = false
    var resourceName = "nodavex-circular-ribbons-animated"

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "svg"),
           let svg = try? String(contentsOf: url, encoding: .utf8) {
            view.loadHTMLString("""
            <!doctype html><html><head>
            <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
            <style>
            html,body { margin:0; width:100%; height:100%; overflow:hidden; background:transparent; }
            body { display:flex; align-items:center; justify-content:center; }
            svg { display:block; width:100%; height:100%; transform-origin:50% 50%; }
            @keyframes ribbon-spin { from { transform:rotate(0deg); } to { transform:rotate(360deg); } }
            @media (prefers-reduced-motion: no-preference) {
                svg { animation: \(slowlyRotates ? "ribbon-spin 90s linear infinite" : "none"); }
            }
            </style></head><body>\(svg)</body></html>
            """, baseURL: Bundle.main.bundleURL)
        }
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Keep the SVG loaded so SwiftUI updates do not restart its animation.
    }
}
