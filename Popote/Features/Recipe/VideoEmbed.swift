import SwiftUI
import WebKit

/// Lets recipe steps jump the YouTube player to their timestamp.
@Observable
final class VideoController {
    fileprivate weak var webView: WKWebView?

    func seek(to seconds: Int) {
        webView?.evaluateJavaScript("seek(\(seconds))")
    }
}

/// Official embeds: YouTube iframe player, TikTok and Instagram embed pages.
struct VideoEmbed: UIViewRepresentable {
    let source: RecipeSource
    let videoID: String
    let controller: VideoController

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = source != .youtube
        controller.webView = webView

        switch source {
        case .youtube:
            // Loaded from an https origin with a referrer policy: YouTube refuses embeds without one (error 153).
            webView.loadHTMLString(youTubeHTML, baseURL: URL(string: "https://com.leobrunet.popote"))
        case .tiktok:
            webView.load(URLRequest(url: URL(string: "https://www.tiktok.com/player/v1/\(videoID)?music_info=0&description=0&rel=0")!))
        case .instagram:
            webView.load(URLRequest(url: URL(string: "https://www.instagram.com/p/\(videoID)/embed/")!))
        default:
            break
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private var youTubeHTML: String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;background:#000;height:100%}#player{position:absolute;inset:0;width:100%;height:100%}</style></head>
        <body><div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
        var player;
        function onYouTubeIframeAPIReady() {
          player = new YT.Player('player', {
            videoId: '\(videoID)', host: 'https://www.youtube-nocookie.com',
            playerVars: { playsinline: 1, rel: 0, modestbranding: 1, origin: 'https://com.leobrunet.popote' }
          });
        }
        function seek(t) { if (player && player.seekTo) { player.seekTo(t, true); player.playVideo(); } }
        </script></body></html>
        """
    }
}
