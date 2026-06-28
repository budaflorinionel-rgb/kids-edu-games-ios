import WebKit
import StoreKit

/// Bridge between the PWA WebView and StoreKit for In-App Purchase
/// The web app can communicate with native IAP via JavaScript message handlers:
/// - window.webkit.messageHandlers['iap-purchase'].postMessage('buy')  -> triggers purchase
/// - window.webkit.messageHandlers['iap-restore'].postMessage('restore') -> triggers restore
/// - window.webkit.messageHandlers['iap-status'].postMessage('check') -> checks unlock status
///
/// The native side injects JavaScript callbacks:
/// - window.iapPurchaseSuccess() -> called after successful purchase
/// - window.iapPurchaseFailed(reason) -> called after failed purchase
/// - window.iapStatusUpdate(isUnlocked) -> called with current unlock status

@available(iOS 15.0, *)
class IAPBridge {
    static let shared = IAPBridge()
    
    private init() {}
    
    /// Register IAP message handlers on the WKUserContentController
    func registerHandlers(on contentController: WKUserContentController, handler: WKScriptMessageHandler) {
        contentController.add(handler, name: "iap-purchase")
        contentController.add(handler, name: "iap-restore")
        contentController.add(handler, name: "iap-status")
    }
    
    /// Inject the IAP status JavaScript into the webview
    func injectIAPStatus(webView: WKWebView) {
        let isUnlocked = StoreKitManager.shared.isUnlocked
        let js = "window.isIOSApp = true; window.iapUnlocked = \(isUnlocked); if (window.iapStatusUpdate) { window.iapStatusUpdate(\(isUnlocked)); }"
        webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("[IAPBridge] Error injecting status: \(error)")
            }
        }
    }
    
    /// Handle IAP messages from the web view
    func handleMessage(name: String, webView: WKWebView) {
        switch name {
        case "iap-purchase":
            Task {
                let success = await StoreKitManager.shared.purchase()
                await MainActor.run {
                    if success {
                        let js = "if (window.iapPurchaseSuccess) { window.iapPurchaseSuccess(); } window.iapUnlocked = true;"
                        webView.evaluateJavaScript(js, completionHandler: nil)
                    } else {
                        let js = "if (window.iapPurchaseFailed) { window.iapPurchaseFailed('cancelled'); }"
                        webView.evaluateJavaScript(js, completionHandler: nil)
                    }
                }
            }
            
        case "iap-restore":
            Task {
                await StoreKitManager.shared.restorePurchases()
                await MainActor.run {
                    let isUnlocked = StoreKitManager.shared.isUnlocked
                    let js = "window.iapUnlocked = \(isUnlocked); if (window.iapStatusUpdate) { window.iapStatusUpdate(\(isUnlocked)); }"
                    webView.evaluateJavaScript(js, completionHandler: nil)
                }
            }
            
        case "iap-status":
            injectIAPStatus(webView: webView)
            
        default:
            break
        }
    }
}
