

import SwiftUI
import WebKit

struct RootView: View {
    @StateObject var viewModel: RootViewModel
    @EnvironmentObject private var webCoordinator: WebViewCoordinator

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
        }
        .onAppear { viewModel.start() }
    }

    private static func isPaymentUrlString(_ urlString: String) -> Bool {
        let lowercased = urlString.lowercased()
        return lowercased.contains("paymentiq") ||
            lowercased.contains("payment") ||
            lowercased.contains("checkout") ||
            lowercased.contains("cashier")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            LoadingStateView()
        case .stub:
            StubStateView(message: viewModel.errorMessage ?? "Nothing to show yet.", retry: viewModel.retry)
        case .web(let url):
            WebShellView(url: url)
        case .failed:
            StubStateView(message: "An error occurred. Please try again later.", retry: viewModel.retry)
        }
    }

    private struct LoadingStateView: View {
        var body: some View {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.09, green: 0.11, blue: 0.18),
                        Color(red: 0.05, green: 0.30, blue: 0.30),
                        Color(red: 0.06, green: 0.45, blue: 0.33)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.6)
                    .shadow(color: .white.opacity(0.2), radius: 8, x: 0, y: 0)
            }
        }
    }

    private struct StubStateView: View {
        let message: String
        let retry: () -> Void

        var body: some View {
            VStack(spacing: 24) {
                Text(message)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button(action: retry) {
                    Text("Try again")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                        .padding(.horizontal, 24)
                }
            }
        }
    }

    private struct WebShellView: View {
        @EnvironmentObject private var webCoordinator: WebViewCoordinator
        @State private var presentedChildWebView: WKWebView?
        @State private var presentedPaymentWebView: WKWebView?
        @State private var dragOffset: CGSize = .zero
        let url: URL

        var body: some View {
            let webShellView = WebViewContainer(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(x: dragOffset.width, y: 0)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Свайп слева направо для возврата
                            if value.translation.width > 0 && webCoordinator.canGoBack {
                                dragOffset = value.translation
                            }
                        }
                        .onEnded { value in
                            // Если свайп достаточно сильный слева направо и можно вернуться назад
                            if value.translation.width > 100 && webCoordinator.canGoBack {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    dragOffset = CGSize(width: -UIScreen.main.bounds.width, height: 0)
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    webCoordinator.goBack()
                                    withAnimation(.spring()) {
                                        dragOffset = .zero
                                    }
                                }
                            } else {
                                // Возвращаем на место если свайп недостаточно сильный
                                withAnimation(.spring()) {
                                    dragOffset = .zero
                                }
                            }
                        }
                )
            
            return ZStack {
                Color.black.ignoresSafeArea()
                
                webShellView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Удалены стрелки навигации по ТЗ - оставлен только свайп как основной метод
            }
            .onChange(of: webCoordinator.childWebView) { newValue in
                print("🔄 Child WebView changed: \(newValue?.url?.absoluteString ?? "nil")")
                print("🔄 Child WebView instance: \(newValue?.hashValue ?? 0)")
                print("🔄 Payment WebView exists: \(webCoordinator.paymentWebView != nil)")
                
                // Если есть платежный WebView, но открывается обычный дочерний — закрываем платежный
                if let paymentWebView = webCoordinator.paymentWebView, let newValue = newValue {
                    let childUrl = newValue.url?.absoluteString ?? ""
                    if !RootView.isPaymentUrlString(childUrl) {
                        print("⚠️ Payment WebView exists, closing to show child WebView")
                        webCoordinator.closePaymentWebView()
                    } else {
                        print("⚠️ Payment WebView exists, skipping child WebView presentation")
                        presentedChildWebView = nil
                        return
                    }
                }
                
                if let newValue = newValue, presentedChildWebView != newValue {
                    print("✅ Presenting new child WebView")
                } else if newValue == nil {
                    print("❌ Child WebView cleared")
                    presentedChildWebView = nil
                }
        }
        .onChange(of: webCoordinator.childWebView) { newValue in
            print("🔄 Child WebView changed: \(newValue?.url?.absoluteString ?? "nil")")
            print("🔄 Child WebView instance: \(newValue?.hashValue ?? 0)")
            print("🔄 Payment WebView exists: \(webCoordinator.paymentWebView != nil)")
            
            // Закрываем обычный дочерний WebView если открывается платежный
            if webCoordinator.paymentWebView != nil {
                print("⚠️ Payment WebView opening, closing child WebView")
                presentedChildWebView = nil
                webCoordinator.closeChild()
                return
            }
            
            if let newValue = newValue, presentedChildWebView != newValue {
                print("✅ Presenting new child WebView")
                presentedChildWebView = newValue
            } else if newValue == nil {
                print("❌ Child WebView cleared")
                presentedChildWebView = nil
            }
        }
            .fullScreenCover(item: Binding<ChildWebViewWrapper?>(
                get: { 
                    // Показываем только если нет платежного WebView
                    if webCoordinator.paymentWebView != nil {
                        print("⚠️ Payment WebView exists, hiding child fullScreenCover")
                        return nil
                    }
                    let wrapper = presentedChildWebView.map { ChildWebViewWrapper(webView: $0) }
                    print("📱 FullScreenCover get: \(wrapper != nil)")
                    if wrapper != nil {
                        print("📱 Showing child WebView: \(wrapper!.webView.url?.absoluteString ?? "unknown")")
                    }
                    return wrapper
                },
                set: { _ in
                    print("📱 FullScreenCover set: dismissing")
                    // НЕ сбрасываем presentedChildWebView - пусть остается видимым
                    // presentedChildWebView = nil
                    // webCoordinator.closeChild()
                }
            )) { wrapper in
            // ВАЖНО: Простая обертка для WebView с уникальным id для пересоздания
            ZStack {
                Color.black.ignoresSafeArea()  // ВАЖНО: Черный фон для safe area
                
                SimpleWebViewContainer(webView: wrapper.webView)
                    .id(wrapper.webView.hashValue)
            }
        }
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
            .fullScreenCover(item: Binding<PaymentWebViewWrapper?>(
                get: { 
                    let wrapper = presentedPaymentWebView.map { PaymentWebViewWrapper(webView: $0) }
                    print("💳 Payment FullScreenCover get: \(wrapper != nil)")
                    return wrapper
                },
                set: { _ in
                    print("💳 Payment FullScreenCover set: dismissing")
                    presentedPaymentWebView = nil
                    webCoordinator.closePaymentWebView()
                }
            )) { wrapper in
                PaymentWebViewContainer(webView: wrapper.webView)
            }
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        }
    }
    
    private struct ChildWebViewWrapper: Identifiable {
        let id: ObjectIdentifier
        let webView: WKWebView
        
        init(webView: WKWebView) {
            self.id = ObjectIdentifier(webView)
            self.webView = webView
        }
    }
    
    private struct ChildWebViewContainer: View {
        let webView: WKWebView
        @EnvironmentObject private var webCoordinator: WebViewCoordinator
        @Environment(\.dismiss) private var dismiss
        @State private var dragOffset: CGSize = .zero
        
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ChildWebViewRepresentable(webView: webView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: dragOffset.width, y: 0)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Свайп справа налево для закрытия дочернего окна
                                if value.translation.width < 0 {
                                    dragOffset = value.translation
                                }
                            }
                            .onEnded { value in
                                // Если свайп достаточно сильный справа налево, закрываем окно
                                if value.translation.width < -100 {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        dragOffset = CGSize(width: -UIScreen.main.bounds.width, height: 0)
                                    }
                                    
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        dismiss()
                                    }
                                } else {
                                    // Возвращаем на место если свайп недостаточно сильный
                                    withAnimation(.spring()) {
                                        dragOffset = .zero
                                    }
                                }
                            }
                    )
                
                // Удалены стрелки навигации по ТЗ - оставлен только свайп для закрытия дочернего окна
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: dragOffset as CGSize)
        }
    }
    
    private struct SimpleWebViewContainer: UIViewRepresentable {
        let webView: WKWebView
        @EnvironmentObject private var webCoordinator: WebViewCoordinator
        
        func makeUIView(context: Context) -> UIView {
            print("📱 Creating SimpleWebViewContainer")
            
            // Создаем контейнер и добавляем WebView
            let containerView = UIView()
            containerView.backgroundColor = UIColor.black  // ВАЖНО: Черный фон как в основном WebView
            
            webView.translatesAutoresizingMaskIntoConstraints = false
            containerView.addSubview(webView)
            
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: containerView.topAnchor),
                webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
            
            // ВАЖНО: Добавляем свайп для возврата к предыдущему WebView
            let swipeGesture = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipeBack))
            swipeGesture.direction = .right
            containerView.addGestureRecognizer(swipeGesture)
            
            print("✅ SimpleWebViewContainer created with WebView and swipe gesture")
            return containerView
        }
        
        func updateUIView(_ uiView: UIView, context: Context) {
            // Ничего не обновляем
        }
        
        func makeCoordinator() -> Coordinator {
            Coordinator(webView: webView, webCoordinator: webCoordinator)
        }
        
        class Coordinator: NSObject {
            let webView: WKWebView
            let webCoordinator: WebViewCoordinator
            
            init(webView: WKWebView, webCoordinator: WebViewCoordinator) {
                self.webView = webView
                self.webCoordinator = webCoordinator
            }
            
            @objc func handleSwipeBack() {
                print("👆 Swipe back gesture detected")
                if webCoordinator.canGoBackToPreviousWebView() {
                    webCoordinator.goBackToPreviousWebView()
                } else {
                    print("❌ Cannot go back - no previous WebView")
                }
            }
        }
    }
    
    private struct ChildWebViewRepresentable: UIViewRepresentable {
        let webView: WKWebView
        
        func makeUIView(context: Context) -> UIView {
            print("📱 Creating ChildWebViewRepresentable")
            webView.scrollView.contentInsetAdjustmentBehavior = .automatic
            webView.isUserInteractionEnabled = true
            webView.scrollView.keyboardDismissMode = .interactive
            
            // Создаем контейнер для WebView
            let containerView = UIView()
            containerView.backgroundColor = UIColor.black  // ВАЖНО: Черный фон как в основном WebView
            containerView.addSubview(webView)
            
            // Настраиваем constraints
            webView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: containerView.topAnchor),
                webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
            
            print("✅ ChildWebViewRepresentable created")
            return containerView
        }
        
        func updateUIView(_ uiView: UIView, context: Context) {
            // Обновление не требуется, так как мы используем существующий webView
        }
    }
    
    private struct PaymentWebViewWrapper: Identifiable {
        let id: ObjectIdentifier
        let webView: WKWebView
        
        init(webView: WKWebView) {
            self.id = ObjectIdentifier(webView)
            self.webView = webView
        }
    }
    
    private struct PaymentWebViewContainer: View {
        let webView: WKWebView
        @EnvironmentObject private var webCoordinator: WebViewCoordinator
        @Environment(\.dismiss) private var dismiss
        @State private var dragOffset: CGSize = .zero
        
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                
                PaymentWebViewRepresentable(webView: webView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: dragOffset.width, y: 0)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: dragOffset as CGSize)
        }
    }
    
    private struct PaymentWebViewRepresentable: UIViewRepresentable {
        let webView: WKWebView
        
        func makeUIView(context: Context) -> UIView {
            print("💳 Creating PaymentWebViewRepresentable")
            webView.scrollView.contentInsetAdjustmentBehavior = .automatic
            
            // ВАЖНО: Улучшаем конфигурацию для полей ввода
            webView.scrollView.isScrollEnabled = true
            webView.scrollView.bounces = true
            webView.scrollView.alwaysBounceVertical = true
            webView.scrollView.showsVerticalScrollIndicator = true
            webView.scrollView.showsHorizontalScrollIndicator = false
            
            // Создаем контейнер для WebView
            let containerView = UIView()
            containerView.backgroundColor = UIColor.black  // ВАЖНО: Черный фон как в основном WebView
            containerView.addSubview(webView)
            
            // Настраиваем constraints
            webView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: containerView.topAnchor),
                webView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                webView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
            
            print("✅ PaymentWebViewRepresentable created with enhanced input support")
            return containerView
        }
        
        func updateUIView(_ uiView: UIView, context: Context) {
            // Обновление не требуется, так как мы используем существующий webView
        }
    }
}
