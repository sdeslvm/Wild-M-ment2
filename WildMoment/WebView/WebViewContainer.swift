
import SwiftUI
import WebKit
#if os(iOS)
import UIKit
import UniformTypeIdentifiers

struct WebViewContainer: UIViewRepresentable {
    @EnvironmentObject private var coordinator: WebViewCoordinator
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        
        // Улучшенная конфигурация для платежных систем
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.javaScriptEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        
        // Включаем DOM Storage для платежных систем
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        
        // НЕ добавляем скрипт сюда - только для платежных WebView
        
        let webView = CoordinatedWKWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent = coordinator.userAgent
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        
        // ВАЖНО: Устанавливаем черный фон для основного WebView
        webView.backgroundColor = UIColor.black
        webView.isOpaque = true
        webView.scrollView.backgroundColor = UIColor.black
        
        // ВАЖНО: Добавляем CSS для принудительного черного фона
        let blackBackgroundScript = WKUserScript(
            source: """
            (function() {
                var style = document.createElement('style');
                style.innerHTML = 'html, body { background-color: black !important; }';
                document.head.appendChild(style);
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        webView.configuration.userContentController.addUserScript(blackBackgroundScript)
        
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.appCoordinator = coordinator
        
        context.coordinator.attach(webView: webView, appCoordinator: coordinator)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        coordinator.updateState(from: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIDocumentPickerDelegate {
        private weak var webView: WKWebView?
        private weak var appCoordinator: WebViewCoordinator?
        private var pendingFileUploadCompletion: (([URL]?) -> Void)?

        func attach(webView: WKWebView, appCoordinator: WebViewCoordinator) {
            self.webView = webView
            self.appCoordinator = appCoordinator
            appCoordinator.hostWebView = webView
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            appCoordinator?.updateState(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("✅ WebView didFinish navigation for: \(webView.url?.absoluteString ?? "unknown")")
            print("✅ WebView instance: \(webView.hashValue)")
            
            if webView === appCoordinator?.paymentWebView {
                print("✅ Payment WebView finished loading")
            } else if webView === appCoordinator?.childWebView {
                print("✅ Child WebView finished loading")
            } else {
                print("✅ Main WebView finished loading")
            }
            
            appCoordinator?.updateState(from: webView)
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("❌ WebView navigation failed: \(error.localizedDescription)")
            print("❌ Error code: \((error as NSError).code)")
            print("❌ URL: \(webView.url?.absoluteString ?? "unknown")")
            
            // Сохраняем URL до обновления состояния
            let currentURL = webView.url
            
            // Обновляем состояние с защитой от nil
            if let coordinator = appCoordinator {
                coordinator.updateState(from: webView)
            }
            
            // Если это ошибка загрузки платежной системы, НЕ открываем в Safari, а просто логируем
            if let url = currentURL, isPaymentURL(url) {
                print("⚠️ Payment page failed to load, keeping WebView open: \(url)")
                print("⚠️ Error: \(error.localizedDescription)")
                return // НЕ закрываем WebView
            }
            
            // Для обычных сайтов можно открыть в Safari
            if let url = currentURL {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("❌ WebView provisional navigation failed: \(error.localizedDescription)")
            print("❌ Error code: \((error as NSError).code)")
            print("❌ URL: \(webView.url?.absoluteString ?? "unknown")")
            
            // Сохраняем URL до обновления состояния
            let currentURL = webView.url
            
            // Обновляем состояние с защитой от nil
            if let coordinator = appCoordinator {
                coordinator.updateState(from: webView)
            }
            
            // Если это ошибка загрузки платежной системы, НЕ открываем в Safari, а просто логируем
            if let url = currentURL, isPaymentURL(url) {
                print("⚠️ Payment page failed to load (provisional), keeping WebView open: \(url)")
                print("⚠️ Error: \(error.localizedDescription)")
                return // НЕ закрываем WebView
            }
            
            // Для обычных сайтов можно открыть в Safari
            if let url = currentURL {
                DispatchQueue.main.async {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            
            print("🔍 Navigation action to: \(url)")
            print("🔍 Current WebView: Payment=\(webView === appCoordinator?.paymentWebView), Child=\(webView === appCoordinator?.childWebView)")
            
            // Разрешаем все навигации внутри WebView
            print("📄 Allowing navigation: \(url)")
            decisionHandler(.allow)
        }

        // MARK: - WKUIDelegate

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            print("🚀 createWebViewWith called!")
            print("🔍 Parent WebView URL: \(webView.url?.absoluteString ?? "unknown")")
            print("🔍 Parent WebView instance: \(webView.hashValue)")
            print("🔍 Is parent child WebView: \(self.appCoordinator?.childWebView == webView)")
            print("🔍 Is parent payment WebView: \(self.appCoordinator?.paymentWebView == webView)")
            
            guard let url = navigationAction.request.url else {
                print("❌ No URL in navigation action")
                return nil
            }
            
            print("🔗 New window request for URL: \(url)")
            
            // Проверяем, является ли URL платежным
            let isPayment = isPaymentURL(url)
            print("💰 Is payment URL: \(isPayment)")
            
            // Блокируем создание WebView для /loading страниц
            if url.absoluteString.contains("/loading") {
                print("🚫 Refusing to create WebView for loading page: \(url)")
                return nil
            }
            
            // Создаем обычный child WebView для popup окон
            print("📱 Creating child WebView for popup: \(url)")
            
            guard let appCoordinator = self.appCoordinator else {
                print("❌ No appCoordinator available")
                return nil
            }
            
            // НИКАКИХ ОГРАНИЧЕНИЙ - как обычный браузер
            let child = appCoordinator.pushChild(with: configuration)
            child.navigationDelegate = self
            child.uiDelegate = self  // ВАЖНО: child WebView тоже должен уметь создавать popup!
            
            // ВАЖНО: Проверяем что у нового WebView свой coordinator
            print("🔍 New child WebView coordinator: \(child.hashValue)")
            print("🔍 New child WebView navigationDelegate: \(child.navigationDelegate != nil)")
            print("🔍 New child WebView uiDelegate: \(child.uiDelegate != nil)")
            
            // ВАЖНО: НЕ меняем размер - он уже установлен правильный в координаторе
            print("🔍 WebView frame from coordinator: \(child.frame)")
            child.backgroundColor = UIColor.black  // ВАЖНО: Черный фон как в основном WebView
            child.isOpaque = true
            child.scrollView.backgroundColor = UIColor.black  // ВАЖНО: Черный фон скролла
            
            // ВАЖНО: Добавляем CSS для принудительного черного фона
            let blackBackgroundScript = WKUserScript(
                source: """
                (function() {
                    var style = document.createElement('style');
                    style.innerHTML = 'html, body { background-color: black !important; }';
                    document.head.appendChild(style);
                })();
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            child.configuration.userContentController.addUserScript(blackBackgroundScript)
            
            // ВАЖНО: Включаем JavaScript для popup'ов
            child.configuration.preferences.javaScriptEnabled = true
            child.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
            
            print("🔍 Child WebView uiDelegate set: \(child.uiDelegate != nil)")
            print("🔍 Child WebView navigationDelegate set: \(child.navigationDelegate != nil)")
            
            child.load(URLRequest(url: url))
            
            print("✅ Returning new child WebView: \(child.hashValue)")
            return child
        }
        
        private func createPaymentWebView(for url: URL, with configuration: WKWebViewConfiguration, appCoordinator: WebViewCoordinator?) -> WKWebView? {
            print("💳 Creating ULTIMATE payment WebView for: \(url)")
            
            // Используем переданную конфигурацию, а не создаем новую
            let paymentConfig = configuration
            
            // ВАЖНО: Включаем JavaScript для платежных систем
            paymentConfig.preferences.javaScriptEnabled = true
            paymentConfig.preferences.javaScriptCanOpenWindowsAutomatically = true
            
            // ВАЖНО: Включаем поддержку форм для платежных систем
            if #available(iOS 14.0, *) {
                paymentConfig.limitsNavigationsToAppBoundDomains = false
            }
            
            paymentConfig.websiteDataStore = WKWebsiteDataStore.default()
            
            // ВАЖНО: Добавляем маскировку под Safari на уровне конфигурации
            let safariMaskScript = WKUserScript(
                source: """
                (function() {
                    console.log('🎭 Safari mask loaded');
                    
                    const safariUA = 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
                    const safariVendor = 'Apple Computer, Inc.';
                    const safariPlatform = 'iPhone';
                    const safariLanguages = ['it-IT', 'it', 'en-US', 'en'];

                    try {
                        Object.defineProperty(navigator, 'userAgent', {
                            get: function() { return safariUA; },
                            configurable: true
                        });

                        Object.defineProperty(navigator, 'appVersion', {
                            get: function() { return safariUA; },
                            configurable: true
                        });

                        Object.defineProperty(navigator, 'vendor', {
                            get: function() { return safariVendor; },
                            configurable: true
                        });

                        Object.defineProperty(navigator, 'platform', {
                            get: function() { return safariPlatform; },
                            configurable: true
                        });

                        Object.defineProperty(navigator, 'language', {
                            get: function() { return safariLanguages[0]; },
                            configurable: true
                        });

                        Object.defineProperty(navigator, 'languages', {
                            get: function() { return safariLanguages; },
                            configurable: true
                        });

                        Object.defineProperty(navigator, 'maxTouchPoints', {
                            get: function() { return 5; },
                            configurable: true
                        });

                        Object.defineProperty(navigator, 'standalone', {
                            get: function() { return false; },
                            configurable: true
                        });

                        Object.defineProperty(navigator, 'webdriver', {
                            get: function() { return false; },
                            configurable: true
                        });

                        // Маскировка под Safari - скрываем WebView признаки
                        Object.defineProperty(window, 'webkit', {
                            get: function() { return undefined; },
                            configurable: true
                        });

                        Object.defineProperty(navigator, 'webdriver', {
                            get: function() { return false; },
                            configurable: true
                        });

                        // Скрываем признаки мобильного WebView
                        if (window.chrome) {
                            Object.defineProperty(window, 'chrome', {
                                get: function() { return undefined; },
                                configurable: true
                            });
                        }

                        console.log('🎭 Safari mask applied successfully');
                    } catch (e) {
                        console.log('🎭 Safari mask error:', e);
                    }
                })();
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            
            // ВАЖНО: Добавляем CSS для полей ввода (минимально, без дублирования)
            let cssScript = WKUserScript(
                source: """
                (function() {
                    console.log('🎯 CSS for payment fields loaded');
                    
                    const style = document.createElement('style');
                    style.textContent = `
                        input, select, textarea {
                            display: block !important;
                            visibility: visible !important;
                            opacity: 1 !important;
                            pointer-events: auto !important;
                            -webkit-user-select: auto !important;
                            user-select: auto !important;
                            background: white !important;
                            border: 1px solid #ccc !important;
                            padding: 8px !important;
                            margin: 4px 0 !important;
                            border-radius: 4px !important;
                            font-size: 16px !important;
                            color: black !important;
                        }
                        
                        .overlay, .mask, [style*="position: fixed"], [style*="position: absolute"] {
                            pointer-events: none !important;
                        }
                        
                        iframe {
                            pointer-events: auto !important;
                            z-index: 1 !important;
                        }
                    `;
                    
                    if (document.head) {
                        document.head.appendChild(style);
                    } else {
                        document.addEventListener('DOMContentLoaded', function() {
                            document.head.appendChild(style);
                        });
                    }
                    
                    console.log('🎯 CSS for payment fields applied');
                })();
                """,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            
            paymentConfig.userContentController.addUserScript(safariMaskScript)
            paymentConfig.userContentController.addUserScript(cssScript)
            
            // Создаем платежное WebView с ПЕРЕДАННОЙ конфигурацией
            let paymentWebView = WKWebView(frame: UIScreen.main.bounds, configuration: paymentConfig)
            
            // ВАЖНО: Устанавливаем черный фон для платежного WebView
            paymentWebView.backgroundColor = UIColor.black
            paymentWebView.isOpaque = true
            paymentWebView.scrollView.backgroundColor = UIColor.black
            
            // ВАЖНО: Отключаем автоматическое появление клавиатуры для предотвращения конфликтов
            paymentWebView.scrollView.keyboardDismissMode = .onDrag
            
            // Используем настоящий Safari User Agent для полной маскировки
            let safariUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
            paymentWebView.customUserAgent = safariUserAgent
            paymentWebView.allowsBackForwardNavigationGestures = true
            paymentWebView.scrollView.contentInsetAdjustmentBehavior = .automatic
            
            // Включаем полную поддержку форм
            paymentWebView.scrollView.isScrollEnabled = true
            paymentWebView.scrollView.bounces = true
            paymentWebView.scrollView.alwaysBounceVertical = true
            paymentWebView.scrollView.showsVerticalScrollIndicator = true
            paymentWebView.scrollView.showsHorizontalScrollIndicator = false
            
            // Устанавливаем делегаты
            paymentWebView.navigationDelegate = self
            paymentWebView.uiDelegate = self
            
            // Сохраняем как платежный WebView через координатор
            appCoordinator?.setPaymentWebView(paymentWebView)
            
            // Загружаем URL
            let request = URLRequest(url: url)
            paymentWebView.load(request)
            
            print("✅ Payment WebView created and loading: \(url)")
            return paymentWebView
        }

        func webViewDidClose(_ webView: WKWebView) {
            print("🔒 webViewDidClose called for: \(webView.hashValue)")
            print("🔒 Is payment WebView: \(webView === appCoordinator?.paymentWebView)")
            print("🔒 Is child WebView: \(webView === appCoordinator?.childWebView)")
            print("🔒 WebView URL: \(webView.url?.absoluteString ?? "unknown")")
            
            // НЕ закрываем child WebView автоматически - даем пользователю решить
            if webView === appCoordinator?.childWebView {
                print("⚠️ Child WebView requested close, but keeping it open for user")
                return // НЕ закрываем child WebView
            }
            
            // Добавляем задержку чтобы избежать конфликтов с клавиатурой
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Закрываем ТОЛЬКО платежный WebView
                if webView === self.appCoordinator?.paymentWebView {
                    print("🔒 Closing payment WebView from webViewDidClose")
                    self.appCoordinator?.closePaymentWebView()
                    return
                }
            }
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            print("🚨 JavaScript Alert: \(message)")
            print("🚨 Frame URL: \(frame.request.url?.absoluteString ?? "unknown")")
            
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "Внимание", message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                    completionHandler(nil)
                }))
                
                if let topViewController = UIApplication.shared.keyWindow?.rootViewController {
                    topViewController.present(alert, animated: true)
                }
            }
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            presentConfirm(title: "Confirmation", message: message, completion: completionHandler)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            print("🚨 JavaScript Prompt: \(prompt)")
            print("🚨 Default text: \(defaultText ?? "none")")
            
            DispatchQueue.main.async {
                let alert = UIAlertController(title: "Ввод данных", message: prompt, preferredStyle: .alert)
                alert.addTextField { textField in
                    textField.text = defaultText
                }
                
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                    completionHandler(alert.textFields?.first?.text)
                }))
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel, handler: { _ in
                    completionHandler(nil)
                }))
                
                if let topViewController = UIApplication.shared.keyWindow?.rootViewController {
                    topViewController.present(alert, animated: true)
                }
            }
        }
        
        @objc func webView(_ webView: WKWebView, runOpenPanelWith parameters: Any, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            pendingFileUploadCompletion = completionHandler

            let alert = UIAlertController(title: "Upload file", message: nil, preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "Take photo/video", style: .default, handler: { [weak self] _ in
                self?.presentCamera()
            }))
            alert.addAction(UIAlertAction(title: "Choose from Files", style: .default, handler: { [weak self] _ in
                self?.presentDocumentPicker()
            }))
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { [weak self] _ in
                self?.pendingFileUploadCompletion?(nil)
                self?.pendingFileUploadCompletion = nil
            }))

            presentController(alert)
        }

        // MARK: - Presentation Helpers

        private func presentCamera() {
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                presentDocumentPicker()
                return
            }

            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.mediaTypes = ["public.image", "public.movie"]
            picker.delegate = self
            presentController(picker)
        }

        private func presentDocumentPicker() {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .image, .movie], asCopy: true)
            picker.delegate = self
            presentController(picker)
        }

        private func presentAlert(title: String, message: String, completion: @escaping () -> Void) {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in completion() }))
            presentController(alert)
        }

        private func presentConfirm(title: String, message: String, completion: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in completion(false) }))
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in completion(true) }))
            presentController(alert)
        }

        private func presentPrompt(title: String, defaultText: String?, completion: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
            alert.addTextField { textField in
                textField.text = defaultText
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { _ in completion(nil) }))
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak alert] _ in
                completion(alert?.textFields?.first?.text)
            }))
            presentController(alert)
        }

        private func presentController(_ controller: UIViewController) {
            DispatchQueue.main.async {
                guard let root = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .flatMap({ $0.windows })
                    .first(where: { $0.isKeyWindow })?.rootViewController else {
                        return
                    }
                root.present(controller, animated: true)
            }
        }

        // MARK: - UIDocumentPickerDelegate

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            pendingFileUploadCompletion?(nil)
            pendingFileUploadCompletion = nil
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            pendingFileUploadCompletion?(urls)
            pendingFileUploadCompletion = nil
        }

        // MARK: - UIImagePickerControllerDelegate

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            pendingFileUploadCompletion?(nil)
            pendingFileUploadCompletion = nil
            picker.dismiss(animated: true)
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            var tempURL: URL?
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.9) {
                tempURL = saveTemporary(data: data, fileExtension: "jpg")
            } else if let videoURL = info[.mediaURL] as? URL {
                tempURL = videoURL
            }

            if let tempURL {
                pendingFileUploadCompletion?([tempURL])
            } else {
                pendingFileUploadCompletion?(nil)
            }
            pendingFileUploadCompletion = nil
            picker.dismiss(animated: true)
        }

        private func saveTemporary(data: Data, fileExtension: String) -> URL? {
            let tempDir = FileManager.default.temporaryDirectory
            let fileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathExtension(fileExtension)
            do {
                try data.write(to: fileURL)
                return fileURL
            } catch {
                return nil
            }
        }
        
        // MARK: - Helper Methods
        
        private func isPaymentURL(_ url: URL) -> Bool {
            let host = url.host?.lowercased() ?? ""
            let path = url.path.lowercased()
            let absoluteString = url.absoluteString.lowercased()
            
            print("🔍 Checking URL: \(url)")
            print("🔍 Host: \(host), Path: \(path)")
            
            // Популярные платежные системы (без cashier.pgwsoft.com - это только шлюз)
            let paymentDomains = [
                "stripe.com", "paypal.com", "yoomoney.ru", "yandex.ru",
                "qiwi.com", "sberbank.ru", "tinkoff.ru", "alfabank.ru",
                "vtb.ru", "raiffeisen.ru", "cloudpayments.ru", "robokassa.ru",
                "unitpay.ru", "paymaster.ru", "interkassa.com", "fondy.eu",
                "wayforpay.com", "liqpay.ua", "portmone.com", "ipay.ua",
                "secure.payu.com", "authorizenet.com", "2checkout.com", "adyen.com",
                "braintreepayments.com", "squareup.com", "paddle.com", "fastspring.com",
                "neteller.com", "paysafe.com", "revolut.com", "paymentiq.io",
                "card-fields.paymentiq.io", "pay.skrill.com", "checkout.banklayer.org",
                "api.payment-gateway.io", "banklayer.org", "payment-gateway.io"
            ]
            
            // cashier.pgwsoft.com - это всегда обычный шлюз, не платежная система
            if host.contains("cashier.pgwsoft.com") {
                print("📄 Cashier gateway detected, not payment: \(url)")
                return false
            }
            
            // Проверяем домен
            if paymentDomains.contains(where: { host.contains($0) }) {
                print("✅ Payment domain detected: \(host)")
                return true
            }
            
            // Проверяем path на наличие платежных ключевых слов
            let paymentKeywords = ["payment", "pay", "checkout", "billing", "order", "purchase", "donate"]
            if paymentKeywords.contains(where: { path.contains($0) }) {
                print("✅ Payment keyword detected in path: \(path)")
                return true
            }
            
            // Дополнительные проверки по URL параметрам
            if absoluteString.contains("payment") || absoluteString.contains("checkout") || absoluteString.contains("billing") {
                print("✅ Payment keyword detected in URL: \(absoluteString)")
                return true
            }
            
            // Особые случаи для настоящих платежных страниц (только прямые платежные системы)
            if host.contains("paymentiq.io") {
                print("✅ PaymentIQ detected: \(url)")
                return true
            }
            
            print("❌ Not a payment URL")
            return false
        }
        
        // MARK: - JavaScript Alert Handler
        
        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            DispatchQueue.main.async {
                let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                    completionHandler()
                })
                
                if let topController = UIApplication.shared.topViewController() {
                    topController.present(alert, animated: true)
                } else {
                    completionHandler()
                }
            }
        }
    }
}
#endif
