
import Foundation
import Combine
import WebKit
#if canImport(UIKit)
import UIKit
#endif

final class WebViewCoordinator: NSObject, ObservableObject {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var currentURL: URL?
    @Published var childWebView: WKWebView?
    @Published var paymentWebView: WKWebView? // Второй WebView для платежных систем
    
    // ВАЖНО: Стек WebView для навигации между popup'ами
    private var webViewStack: [WKWebView] = []

    var userAgent: String = "Version/17.2 Mobile/15E148 Safari/604.1"
    weak var hostWebView: WKWebView?

    func updateState(from webView: WKWebView) {
        // Проверяем, что webView не nil и на главном потоке
        guard !Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateState(from: webView)
            }
            return
        }
        
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        currentURL = webView.url
    }

    func pushChild(with configuration: WKWebViewConfiguration) -> WKWebView {
        // НЕ очищаем старый дочерний WebView - пусть работают несколько окон
        print("📱 Creating new child WebView (keeping existing ones)")
        
        // ВАЖНО: Добавляем текущий WebView в стек если он есть
        if let currentChild = childWebView {
            webViewStack.append(currentChild)
            print("📚 Added current child WebView to stack, stack size: \(webViewStack.count)")
        } else if let hostWebView = hostWebView {
            // ВАЖНО: Если нет дочернего, добавляем основной WebView в стек
            webViewStack.append(hostWebView)
            print("📚 Added host WebView to stack, stack size: \(webViewStack.count)")
        }
        
        // ВАЖНО: Создаем WebView с размером полного экрана
        let screenBounds = UIScreen.main.bounds
        print("🔍 Screen bounds: \(screenBounds)")
        let webView = WKWebView(frame: screenBounds, configuration: configuration)
        webView.customUserAgent = userAgent
        
        // ВАЖНО: Устанавливаем как текущий child WebView для отображения на главном потоке
        DispatchQueue.main.async {
            self.childWebView = webView
            print("✅ Created new child WebView and set as current on main thread")
            print("🔍 Final WebView frame: \(webView.frame)")
            
            // ВАЖНО: Принудительно обновляем UI чтобы fullScreenCover сразу показал новый WebView
            DispatchQueue.main.async {
                self.objectWillChange.send()
                print("🔄 Forced UI update for new WebView")
            }
        }
        
        return webView
    }
    
    func pushPayment(with configuration: WKWebViewConfiguration) -> WKWebView {
        // Если уже есть платежный WebView, очищаем его перед созданием нового
        if let existing = paymentWebView {
            print("⚠️ Payment WebView already exists, cleaning up...")
            DispatchQueue.main.async {
                existing.stopLoading()
                existing.navigationDelegate = nil
                existing.uiDelegate = nil
            }
        }
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = userAgent
        
        // Устанавливаем синхронно, так как метод должен вернуть webView сразу
        paymentWebView = webView
        print("✅ Created new payment WebView")
        return webView
    }
    
    func setPaymentWebView(_ webView: WKWebView) {
        // Очищаем предыдущий платежный WebView если есть
        if let existing = paymentWebView {
            print("⚠️ Payment WebView already exists, cleaning up...")
            DispatchQueue.main.async {
                existing.stopLoading()
                existing.navigationDelegate = nil
                existing.uiDelegate = nil
            }
        }
        
        paymentWebView = webView
        print("✅ Set new payment WebView")
    }
    
    func closePaymentWebView() {
        guard let payment = paymentWebView else { 
            print("⚠️ No payment WebView to close")
            return 
        }
        
        print("🔄 Closing payment WebView")
        
        // Очищаем платежный WebView на главном потоке
        DispatchQueue.main.async { [weak self, weak payment] in
            guard let self = self, let payment = payment else { return }
            
            payment.stopLoading()
            payment.navigationDelegate = nil
            payment.uiDelegate = nil
            
            self.paymentWebView = nil
            print("✅ Payment WebView cleaned up")
        }
    }

    func goBackToPreviousWebView() -> Bool {
        print("🔙 Attempting to go back to previous WebView")
        print("📚 Current stack size: \(webViewStack.count)")
        
        guard !webViewStack.isEmpty else {
            print("❌ No previous WebView in stack")
            return false
        }
        
        let previousWebView = webViewStack.removeLast()
        print("🔙 Returning to previous WebView: \(previousWebView.hashValue)")
        
        DispatchQueue.main.async {
            self.childWebView = previousWebView
            self.objectWillChange.send()
            print("✅ Returned to previous WebView")
        }
        
        return true
    }
    
    func canGoBackToPreviousWebView() -> Bool {
        return !webViewStack.isEmpty
    }
    
    func closeChild() {
        guard let child = childWebView else { 
            print("⚠️ No child WebView to close")
            return 
        }
        
        print("🔄 Closing child WebView")
        
        // Очищаем дочерний WebView на главном потоке
        DispatchQueue.main.async { [weak self, weak child] in
            guard let self = self, let child = child else { return }
            
            child.stopLoading()
            child.navigationDelegate = nil
            child.uiDelegate = nil
            
            self.childWebView = nil
            print("✅ Child WebView cleaned up")
        }
    }

    func goBack() {
        if let payment = paymentWebView, payment.canGoBack {
            payment.goBack()
        } else if let child = childWebView, child.canGoBack {
            child.goBack()
        } else if let host = hostWebView, host.canGoBack {
            host.goBack()
        }
    }

    func goForward() {
        if let payment = paymentWebView, payment.canGoForward {
            payment.goForward()
        } else if let child = childWebView, child.canGoForward {
            child.goForward()
        } else if let host = hostWebView, host.canGoForward {
            host.goForward()
        }
    }
}
