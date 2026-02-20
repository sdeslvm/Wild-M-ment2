

import SwiftUI
import WebKit

struct WildMomentRootView: View {
    @StateObject var wildMomentViewModel: WildMomentRootViewModel
    @EnvironmentObject private var wildMomentWebCoordinator: WildMomentWebViewCoordinator

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            wildMomentContent
        }
        .onAppear { wildMomentViewModel.wildMomentStart() }
    }

    private static func wildMomentIsPaymentUrlString(_ urlString: String) -> Bool {
        let lowercased = urlString.lowercased()
        return lowercased.contains("paymentiq") ||
            lowercased.contains("payment") ||
            lowercased.contains("checkout") ||
            lowercased.contains("cashier")
    }

    @ViewBuilder
    private var wildMomentContent: some View {
        switch wildMomentViewModel.wildMomentState {
        case .loading:
            WildMomentLoadingStateView()
        case .stub:
            WildMomentStubStateView(message: wildMomentViewModel.wildMomentErrorMessage ?? "Nothing to show yet.", retry: wildMomentViewModel.wildMomentRetry)
        case .web(let url):
            WildMomentWebShellView(wildMomentUrl: url)
        case .failed:
            WildMomentStubStateView(message: "An error occurred. Please try again later.", retry: wildMomentViewModel.wildMomentRetry)
        }
    }

    private struct WildMomentLoadingStateView: View {
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

    private struct WildMomentStubStateView: View {
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

    private struct WildMomentWebShellView: View {
        @EnvironmentObject private var wildMomentWebCoordinator: WildMomentWebViewCoordinator
        @State private var wildMomentPresentedChildWebView: WKWebView?
        @State private var wildMomentPresentedPaymentWebView: WKWebView?
        @State private var wildMomentDragOffset: CGSize = .zero
        let wildMomentUrl: URL

        private func wildMomentHandleChildWebViewChange(_ newValue: WKWebView?) {
            print("🔄 Child WebView changed: \(newValue?.url?.absoluteString ?? "nil")")
            print("🔄 Child WebView instance: \(newValue?.hashValue ?? 0)")
            print("🔄 Payment WebView exists: \(wildMomentWebCoordinator.wildMomentPaymentWebView != nil)")
            
            // Если есть платежный WebView, но открывается обычный дочерний — закрываем платежный
            if let paymentWebView = wildMomentWebCoordinator.wildMomentPaymentWebView, let newValue = newValue {
                let childUrl = newValue.url?.absoluteString ?? ""
                if !WildMomentRootView.wildMomentIsPaymentUrlString(childUrl) {
                    print("⚠️ Payment WebView exists, closing to show child WebView")
                    wildMomentWebCoordinator.wildMomentClosePaymentWebView()
                } else {
                    print("⚠️ Payment WebView exists, skipping child WebView presentation")
                    wildMomentPresentedChildWebView = nil
                    return
                }
            }
            
            // Закрываем обычный дочерний WebView если открывается платежный
            if wildMomentWebCoordinator.wildMomentPaymentWebView != nil {
                print("⚠️ Payment WebView opening, closing child WebView")
                wildMomentPresentedChildWebView = nil
                wildMomentWebCoordinator.wildMomentCloseChild()
                return
            }
            
            if let newValue = newValue, wildMomentPresentedChildWebView != newValue {
                print("✅ Presenting new child WebView")
                wildMomentPresentedChildWebView = newValue
            } else if newValue == nil {
                print("❌ Child WebView cleared")
                wildMomentPresentedChildWebView = nil
            }
        }

        var body: some View {
            let wildMomentWebShellView = WildMomentWebViewContainer(wildMomentUrl: wildMomentUrl)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(x: wildMomentDragOffset.width, y: 0)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Свайп слева направо для возврата
                            if value.translation.width > 0 && wildMomentWebCoordinator.wildMomentCanGoBack {
                                wildMomentDragOffset = value.translation
                            }
                        }
                        .onEnded { value in
                            // Если свайп достаточно сильный слева направо и можно вернуться назад
                            if value.translation.width > 100 && wildMomentWebCoordinator.wildMomentCanGoBack {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    wildMomentDragOffset = CGSize(width: -UIScreen.main.bounds.width, height: 0)
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    wildMomentWebCoordinator.wildMomentGoBack()
                                    withAnimation(.spring()) {
                                        wildMomentDragOffset = .zero
                                    }
                                }
                            } else {
                                // Возвращаем на место если свайп недостаточно сильный
                                withAnimation(.spring()) {
                                    wildMomentDragOffset = .zero
                                }
                            }
                        }
                )
            
            return ZStack {
                Color.black.ignoresSafeArea()
                
                wildMomentWebShellView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Удалены стрелки навигации по ТЗ - оставлен только свайп как основной метод
            }
        .onChange(of: wildMomentWebCoordinator.wildMomentChildWebView) { newValue in
            wildMomentHandleChildWebViewChange(newValue)
        }
            .fullScreenCover(item: Binding<WildMomentChildWebViewWrapper?>(
                get: { 
                    // Показываем только если нет платежного WebView
                    if wildMomentWebCoordinator.wildMomentPaymentWebView != nil {
                        print("⚠️ Payment WebView exists, hiding child fullScreenCover")
                        return nil
                    }
                    let wrapper = wildMomentPresentedChildWebView.map { WildMomentChildWebViewWrapper(webView: $0) }
                    print("📱 FullScreenCover get: \(wrapper != nil)")
                    if wrapper != nil {
                        print("📱 Showing child WebView: \(wrapper!.webView.url?.absoluteString ?? "unknown")")
                    }
                    return wrapper
                },
                set: { _ in
                    print("📱 FullScreenCover set: dismissing")
                    // НЕ сбрасываем presentedChildWebView - пусть остается видимым
                    // wildMomentPresentedChildWebView = nil
                    // wildMomentWebCoordinator.wildMomentCloseChild()
                }
            )) { wrapper in
            // ВАЖНО: Простая обертка для WebView с уникальным id для пересоздания
            ZStack {
                Color.black.ignoresSafeArea()  // ВАЖНО: Черный фон для safe area
                
                WildMomentSimpleWebViewContainer(webView: wrapper.webView)
                    .id(wrapper.webView.hashValue)
            }
        }
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
            .fullScreenCover(item: Binding<WildMomentPaymentWebViewWrapper?>(
                get: { 
                    let wrapper = wildMomentPresentedPaymentWebView.map { WildMomentPaymentWebViewWrapper(webView: $0) }
                    print("💳 Payment FullScreenCover get: \(wrapper != nil)")
                    return wrapper
                },
                set: { _ in
                    print("💳 Payment FullScreenCover set: dismissing")
                    wildMomentPresentedPaymentWebView = nil
                    wildMomentWebCoordinator.wildMomentClosePaymentWebView()
                }
            )) { wrapper in
                WildMomentPaymentWebViewContainer(webView: wrapper.webView)
            }
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
        }
    }
    
    private struct WildMomentChildWebViewWrapper: Identifiable {
        let id: ObjectIdentifier
        let webView: WKWebView
        
        init(webView: WKWebView) {
            self.id = ObjectIdentifier(webView)
            self.webView = webView
        }
    }
    
    private struct WildMomentChildWebViewContainer: View {
        let webView: WKWebView
        @EnvironmentObject private var wildMomentWebCoordinator: WildMomentWebViewCoordinator
        @Environment(\.dismiss) private var dismiss
        @State private var wildMomentDragOffset: CGSize = .zero
        
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                
                WildMomentChildWebViewRepresentable(webView: webView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: wildMomentDragOffset.width, y: 0)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                // Свайп справа налево для закрытия дочернего окна
                                if value.translation.width < 0 {
                                    wildMomentDragOffset = value.translation
                                }
                            }
                            .onEnded { value in
                                // Если свайп достаточно сильный справа налево, закрываем окно
                                if value.translation.width < -100 {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        wildMomentDragOffset = CGSize(width: -UIScreen.main.bounds.width, height: 0)
                                    }
                                    
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        dismiss()
                                    }
                                } else {
                                    // Возвращаем на место если свайп недостаточно сильный
                                    withAnimation(.spring()) {
                                        wildMomentDragOffset = .zero
                                    }
                                }
                            }
                    )
                
                // Удалены стрелки навигации по ТЗ - оставлен только свайп для закрытия дочернего окна
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: wildMomentDragOffset as CGSize)
        }
    }
    
    private struct WildMomentSimpleWebViewContainer: UIViewRepresentable {
        let webView: WKWebView
        @EnvironmentObject private var wildMomentWebCoordinator: WildMomentWebViewCoordinator
        
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
            let swipeGesture = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(WildMomentCoordinator.wildMomentHandleSwipeBack))
            swipeGesture.direction = .right
            containerView.addGestureRecognizer(swipeGesture)
            
            print("✅ SimpleWebViewContainer created with WebView and swipe gesture")
            return containerView
        }
        
        func updateUIView(_ uiView: UIView, context: Context) {
            // Ничего не обновляем
        }
        
        func makeCoordinator() -> WildMomentCoordinator {
            WildMomentCoordinator(webView: webView, webCoordinator: wildMomentWebCoordinator)
        }
        
        class WildMomentCoordinator: NSObject {
            let webView: WKWebView
            let webCoordinator: WildMomentWebViewCoordinator
            
            init(webView: WKWebView, webCoordinator: WildMomentWebViewCoordinator) {
                self.webView = webView
                self.webCoordinator = webCoordinator
            }
            
            @objc func wildMomentHandleSwipeBack() {
                print("👆 Swipe back gesture detected")
                if webCoordinator.wildMomentCanGoBackToPreviousWebView() {
                    webCoordinator.wildMomentGoBackToPreviousWebView()
                } else {
                    print("❌ Cannot go back - no previous WebView")
                }
            }
        }
    }
    
    private struct WildMomentChildWebViewRepresentable: UIViewRepresentable {
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
    
    private struct WildMomentPaymentWebViewWrapper: Identifiable {
        let id: ObjectIdentifier
        let webView: WKWebView
        
        init(webView: WKWebView) {
            self.id = ObjectIdentifier(webView)
            self.webView = webView
        }
    }
    
    private struct WildMomentPaymentWebViewContainer: View {
        let webView: WKWebView
        @EnvironmentObject private var wildMomentWebCoordinator: WildMomentWebViewCoordinator
        @Environment(\.dismiss) private var dismiss
        @State private var wildMomentDragOffset: CGSize = .zero
        
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                
                WildMomentPaymentWebViewRepresentable(webView: webView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(x: wildMomentDragOffset.width, y: 0)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: wildMomentDragOffset as CGSize)
        }
    }
    
    private struct WildMomentPaymentWebViewRepresentable: UIViewRepresentable {
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
