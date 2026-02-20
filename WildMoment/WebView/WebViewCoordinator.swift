
import Foundation
import Combine
import WebKit
#if canImport(UIKit)
import UIKit
#endif

final class WildMomentWebViewCoordinator: NSObject, ObservableObject {
    @Published var wildMomentCanGoBack = false
    @Published var wildMomentCanGoForward = false
    @Published var wildMomentIsLoading = false
    @Published var wildMomentCurrentURL: URL?
    @Published var wildMomentChildWebView: WKWebView?
    @Published var wildMomentPaymentWebView: WKWebView? // Второй WebView для платежных систем
    
    // ВАЖНО: Стек WebView для навигации между popup'ами
    private var wildMomentWebViewStack: [WKWebView] = []

    var wildMomentUserAgent: String = "Version/17.2 Mobile/15E148 Safari/604.1"
    weak var wildMomentHostWebView: WKWebView?

    func wildMomentUpdateState(from webView: WKWebView) {
        // Проверяем, что webView не nil и на главном потоке
        guard !Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.wildMomentUpdateState(from: webView)
            }
            return
        }
        
        wildMomentCanGoBack = webView.canGoBack
        wildMomentCanGoForward = webView.canGoForward
        wildMomentIsLoading = webView.isLoading
        wildMomentCurrentURL = webView.url
    }

    func wildMomentPushChild(with configuration: WKWebViewConfiguration) -> WKWebView {
        // НЕ очищаем старый дочерний WebView - пусть работают несколько окон
        print("📱 Creating new child WebView (keeping existing ones)")
        
        // ВАЖНО: Добавляем текущий WebView в стек если он есть
        if let currentChild = wildMomentChildWebView {
            wildMomentWebViewStack.append(currentChild)
            print("📚 Added current child WebView to stack, stack size: \(wildMomentWebViewStack.count)")
        } else if let hostWebView = wildMomentHostWebView {
            // ВАЖНО: Если нет дочернего, добавляем основной WebView в стек
            wildMomentWebViewStack.append(hostWebView)
            print("📚 Added host WebView to stack, stack size: \(wildMomentWebViewStack.count)")
        }
        
        // ВАЖНО: Создаем WebView с размером полного экрана
        let screenBounds = UIScreen.main.bounds
        print("🔍 Screen bounds: \(screenBounds)")
        let webView = WKWebView(frame: screenBounds, configuration: configuration)
        webView.customUserAgent = wildMomentUserAgent
        
        // ВАЖНО: Устанавливаем как текущий child WebView для отображения на главном потоке
        DispatchQueue.main.async {
            self.wildMomentChildWebView = webView
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
    
    func wildMomentPushPayment(with configuration: WKWebViewConfiguration) -> WKWebView {
        // Если уже есть платежный WebView, очищаем его перед созданием нового
        if let existing = wildMomentPaymentWebView {
            print("⚠️ Payment WebView already exists, cleaning up...")
            DispatchQueue.main.async {
                existing.stopLoading()
                existing.navigationDelegate = nil
                existing.uiDelegate = nil
            }
        }
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = wildMomentUserAgent
        
        // Устанавливаем синхронно, так как метод должен вернуть webView сразу
        wildMomentPaymentWebView = webView
        print("✅ Created new payment WebView")
        return webView
    }
    
    func wildMomentSetPaymentWebView(_ webView: WKWebView) {
        // Очищаем предыдущий платежный WebView если есть
        if let existing = wildMomentPaymentWebView {
            print("⚠️ Payment WebView already exists, cleaning up...")
            DispatchQueue.main.async {
                existing.stopLoading()
                existing.navigationDelegate = nil
                existing.uiDelegate = nil
            }
        }
        
        wildMomentPaymentWebView = webView
        print("✅ Set new payment WebView")
    }
    
    func wildMomentClosePaymentWebView() {
        guard let payment = wildMomentPaymentWebView else { 
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
            
            self.wildMomentPaymentWebView = nil
            print("✅ Payment WebView cleaned up")
        }
    }

    func wildMomentGoBackToPreviousWebView() -> Bool {
        print("🔙 Attempting to go back to previous WebView")
        print("📚 Current stack size: \(wildMomentWebViewStack.count)")
        
        guard !wildMomentWebViewStack.isEmpty else {
            print("❌ No previous WebView in stack")
            return false
        }
        
        let previousWebView = wildMomentWebViewStack.removeLast()
        print("🔙 Returning to previous WebView: \(previousWebView.hashValue)")
        
        DispatchQueue.main.async {
            self.wildMomentChildWebView = previousWebView
            self.objectWillChange.send()
            print("✅ Returned to previous WebView")
        }
        
        return true
    }
    
    func wildMomentCanGoBackToPreviousWebView() -> Bool {
        return !wildMomentWebViewStack.isEmpty
    }
    
    func wildMomentCloseChild() {
        guard let child = wildMomentChildWebView else { 
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
            
            self.wildMomentChildWebView = nil
            print("✅ Child WebView cleaned up")
        }
    }

    func wildMomentGoBack() {
        if let payment = wildMomentPaymentWebView, payment.canGoBack {
            payment.goBack()
        } else if let child = wildMomentChildWebView, child.canGoBack {
            child.goBack()
        } else if let host = wildMomentHostWebView, host.canGoBack {
            host.goBack()
        }
    }

    func wildMomentGoForward() {
        if let payment = wildMomentPaymentWebView, payment.canGoForward {
            payment.goForward()
        } else if let child = wildMomentChildWebView, child.canGoForward {
            child.goForward()
        } else if let host = wildMomentHostWebView, host.canGoForward {
            host.goForward()
        }
    }
}
