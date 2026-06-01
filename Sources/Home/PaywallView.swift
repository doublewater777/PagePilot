//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import StoreKit
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var isPurchasing = false
    @State private var purchaseError: Error?
    @State private var showError = false
    @State private var showSuccess = false
    @State private var products: [Product] = ProPurchaseManager.shared.products
    @State private var selectedProductID: String = ""
    @State private var isLoadingProducts = false
    @State private var productsLoadFailed = false
    @State private var isEligibleForTrial = true

    private let accentBlue = Color(red: 0.22, green: 0.43, blue: 0.95)
    private let accentTeal = Color(red: 0.16, green: 0.62, blue: 0.58)

    var body: some View {
        NavigationView {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    hero
                    optionList
                    purchasePanel
                    featureList
                    linksView
                }
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 42)
            }
            .scrollContentBackground(.hidden)
            .background(
                ZStack {
                    AppColors.background
                    
                    Circle()
                        .fill(accentBlue.opacity(0.12))
                        .frame(width: 300, height: 300)
                        .blur(radius: 60)
                        .offset(x: 150, y: -200)
                    
                    Circle()
                        .fill(accentTeal.opacity(0.12))
                        .frame(width: 300, height: 300)
                        .blur(radius: 60)
                        .offset(x: -150, y: 200)
                }
                .ignoresSafeArea()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("paywall_close", comment: "")) {
                        dismiss()
                    }
                    .disabled(isPurchasing)
                }
            }
            .onAppear {
                Analytics.shared.log(.paywallViewed(source: "paywall_sheet"))
                Task {
                    await loadProductsIfNeeded()
                }
            }
            .alert(NSLocalizedString("paywall_error_title", comment: ""), isPresented: $showError) {
                Button(NSLocalizedString("ok_button", comment: ""), role: .cancel) {}
            } message: {
                if let error = purchaseError as? ProPurchaseError {
                    Text(error.localizedDescription)
                } else {
                    Text(purchaseError?.localizedDescription ?? "")
                }
            }
            .overlay {
                if showSuccess {
                    successOverlay
                }
            }
            .onChange(of: selectedProductID) { oldValue, newValue in
                updateEligibility(for: newValue)
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Label(
                    NSLocalizedString("paywall_pro_badge", comment: ""),
                    systemImage: "crown.fill"
                )
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(accentBlue)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(accentBlue.opacity(colorScheme == .dark ? 0.22 : 0.10))
                .clipShape(Capsule())

                Spacer()
            }

            VStack(alignment: .leading, spacing: 9) {
                Text(NSLocalizedString("paywall_title", comment: ""))
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(AppColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text(NSLocalizedString("paywall_subtitle", comment: ""))
                    .font(.system(size: 15))
                    .foregroundColor(AppColors.secondaryText)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            readingChartPreview
        }
        .padding(22)
        .background(.ultraThinMaterial)
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.15 : 0.4),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.15 : 0.03),
            radius: 18,
            x: 0,
            y: 8
        )
    }

    private var readingChartPreview: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array([0.32, 0.48, 0.24, 0.72, 0.58, 0.86, 0.64].enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(index == 5 ? accentTeal : accentBlue.opacity(colorScheme == .dark ? 0.34 : 0.22))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34 + CGFloat(value * 58))
            }
        }
        .frame(height: 112)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }

    private var featureList: some View {
        VStack(spacing: 0) {
            featureRow(icon: "books.vertical.fill", iconColor: accentTeal, text: NSLocalizedString("paywall_feature_unlimited_books", comment: ""))
            Divider().padding(.leading, 54)
            featureRow(icon: "ipad.and.iphone", iconColor: .purple, text: NSLocalizedString("paywall_feature_ipad_page_turn", comment: ""))
            Divider().padding(.leading, 54)
            featureRow(icon: "chart.bar.fill", iconColor: accentBlue, text: NSLocalizedString("paywall_feature_stats", comment: ""))
            Divider().padding(.leading, 54)
            featureRow(icon: "flame.fill", iconColor: .orange, text: NSLocalizedString("paywall_feature_streak", comment: ""))
            Divider().padding(.leading, 54)
            featureRow(icon: "speaker.wave.2.fill", iconColor: .indigo, text: NSLocalizedString("paywall_feature_premium_tts", comment: ""))
            Divider().padding(.leading, 54)
            featureRow(icon: "rectangle.slash", iconColor: .green, text: NSLocalizedString("paywall_feature_ad_free", comment: ""))
        }
        .background(.thinMaterial)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.15 : 0.4),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Option Cards List

    private var optionList: some View {
        VStack(spacing: 12) {
            if productsLoadFailed {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text(NSLocalizedString("paywall_load_failed_title", comment: ""))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.primaryText)
                    Text(NSLocalizedString("paywall_load_failed_message", comment: ""))
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                    Button {
                        Task { await loadProductsIfNeeded() }
                    } label: {
                        Text(NSLocalizedString("paywall_retry_button", comment: ""))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(accentBlue)
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
                .padding(.vertical, 20)
            } else if isLoadingProducts || products.isEmpty {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    Text(NSLocalizedString("paywall_loading_price", comment: ""))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                }
                .padding(.vertical, 20)
            } else {
                ForEach(products, id: \.id) { product in
                    optionCard(for: product)
                }
            }
        }
    }

    @ViewBuilder
    private func optionCard(for product: Product) -> some View {
        let isSelected = selectedProductID == product.id
        let isMonthly = product.id.contains("monthly")
        let isYearly = product.id.contains("yearly")
        let isLifetime = product.id.contains("lifetime")
        
        let titleKey: String = {
            if isMonthly { return "paywall_option_monthly" }
            if isYearly { return "paywall_option_yearly" }
            return "paywall_option_lifetime"
        }()
        
        let priceSubtext: String = {
            if isMonthly {
                return NSLocalizedString("paywall_price_monthly_sub", comment: "")
            } else if isYearly {
                let monthlyPrice = product.price / 12
                let formattedMonthly = monthlyPrice.formatted(product.priceFormatStyle)
                let formatString = NSLocalizedString("paywall_price_yearly_sub", comment: "")
                return String(format: formatString, formattedMonthly)
            } else {
                return NSLocalizedString("paywall_price_lifetime_sub", comment: "")
            }
        }()
        
        let badgeText: String? = {
            if isYearly {
                return NSLocalizedString("paywall_recommended_badge", comment: "")
            } else {
                return isLifetime ? NSLocalizedString("paywall_limited_badge", comment: "") : nil
            }
        }()
        
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selectedProductID = product.id
            }
        }) {
            HStack(spacing: 16) {
                // Radio Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? accentBlue : Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    
                    if isSelected {
                        Circle()
                            .fill(accentBlue)
                            .frame(width: 12, height: 12)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(NSLocalizedString(titleKey, comment: ""))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                        
                        if let badgeText {
                            Text(badgeText)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    LinearGradient(
                                        colors: isLifetime 
                                            ? [Color.orange, Color.red] 
                                            : (isYearly ? [accentTeal, accentBlue] : [accentBlue, accentTeal]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(6)
                        }
                    }
                    
                    Text(priceSubtext)
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                Text(displayPrice(for: product))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppColors.primaryText)
                    .monospacedDigit()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(
                            colors: [accentBlue.opacity(colorScheme == .dark ? 0.20 : 0.08), accentTeal.opacity(colorScheme == .dark ? 0.10 : 0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            )
            .background(.thinMaterial)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected 
                            ? LinearGradient(colors: [accentBlue, accentTeal], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color.white.opacity(colorScheme == .dark ? 0.08 : 0.3), Color.white.opacity(0.0)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(
                color: Color.black.opacity(isSelected ? (colorScheme == .dark ? 0.12 : 0.03) : 0),
                radius: 8,
                x: 0,
                y: 4
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Purchase Panel

    private var buyButtonText: String {
        guard let selectedProduct = products.first(where: { $0.id == selectedProductID }) else {
            return NSLocalizedString("paywall_buy_button_ineligible", comment: "")
        }
        
        if selectedProduct.id.contains("lifetime") {
            return NSLocalizedString("paywall_buy_button_lifetime", comment: "")
        } else if isEligibleForTrial {
            return NSLocalizedString("paywall_buy_button_eligible", comment: "")
        } else {
            return NSLocalizedString("paywall_buy_button_ineligible", comment: "")
        }
    }

    private var purchasePanel: some View {
        VStack(spacing: 14) {
            Button(action: purchase) {
                HStack(spacing: 8) {
                    if isPurchasing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text(buyButtonText)
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(
                        colors: [accentBlue, accentTeal],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(16)
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(isPurchasing || selectedProductID.isEmpty)

            Button(NSLocalizedString("paywall_restore_button", comment: "")) {
                Task { await restore() }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(accentBlue)
            .disabled(isPurchasing)

            Text(NSLocalizedString("paywall_subscription_billing_note", comment: ""))
                .font(.system(size: 11))
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .cornerRadius(18)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.15 : 0.4),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    private var successOverlay: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            Text(NSLocalizedString("paywall_success_title", comment: ""))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(AppColors.primaryText)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(AppColors.cardBackground.opacity(0.96))
        )
        .shadow(radius: 20)
    }

    @MainActor
    private func loadProductsIfNeeded() async {
        guard !isLoadingProducts else { return }

        // Use already-loaded products if available
        if !ProPurchaseManager.shared.products.isEmpty {
            products = ProPurchaseManager.shared.products
            selectDefaultProduct()
            return
        }

        isLoadingProducts = true
        productsLoadFailed = false

        let loaded = await ProPurchaseManager.shared.loadProducts()
        isLoadingProducts = false

        if loaded.isEmpty {
            productsLoadFailed = true
        } else {
            products = loaded
            selectDefaultProduct()
        }
    }

    @MainActor
    private func selectDefaultProduct() {
        guard !products.isEmpty else { return }
        if let yearly = products.first(where: { $0.id == ProPurchaseManager.yearlyProductID }) {
            selectedProductID = yearly.id
        } else if let first = products.first {
            selectedProductID = first.id
        }
    }

    private func featureRow(icon: String, iconColor: Color, text: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(iconColor.opacity(colorScheme == .dark ? 0.22 : 0.12))

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            .frame(width: 40, height: 40)

            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var linksView: some View {
        HStack(spacing: 16) {
            Link(NSLocalizedString("paywall_terms_of_use", comment: ""), destination: URL(string: "https://doublewater777.github.io/PagePilot/terms.html")!)
            
            Text("•")
                .foregroundColor(AppColors.secondaryText)
            
            Link(NSLocalizedString("paywall_privacy_policy", comment: ""), destination: URL(string: "https://doublewater777.github.io/PagePilot/privacy.html")!)
        }
        .font(.system(size: 12))
        .foregroundColor(accentBlue)
        .padding(.top, 8)
    }

    private func displayPrice(for product: Product) -> String {
        return product.displayPrice
    }

    private func purchase() {
        guard let selectedProduct = products.first(where: { $0.id == selectedProductID }) else { return }
        isPurchasing = true
        Task {
            do {
                try await ProPurchaseManager.shared.purchase(selectedProduct)
                withAnimation(.easeOut(duration: 0.3)) {
                    showSuccess = true
                }
                try await Task.sleep(nanoseconds: 1_500_000_000)
                dismiss()
            } catch let error as ProPurchaseError where error == .userCancelled {
                Analytics.shared.log(.purchaseCancelled)
            } catch let error as ProPurchaseError {
                Analytics.shared.log(.purchaseFailed(error: String(describing: error)))
                purchaseError = error
                showError = true
            } catch {
                Analytics.shared.log(.purchaseFailed(error: error.localizedDescription))
                purchaseError = error
                showError = true
            }
            isPurchasing = false
        }
    }

    @MainActor
    private func updateEligibility(for productID: String) {
        guard let selectedProduct = products.first(where: { $0.id == productID }) else {
            isEligibleForTrial = false
            return
        }
        
        if selectedProduct.id.contains("lifetime") {
            isEligibleForTrial = false
            return
        }
        
        Task {
            if let subscription = selectedProduct.subscription {
                let eligible = await subscription.isEligibleForIntroOffer
                isEligibleForTrial = eligible
            } else {
                isEligibleForTrial = false
            }
        }
    }

    @MainActor
    private func restore() async {
        isPurchasing = true
        Analytics.shared.log(.purchaseRestored)
        await ProPurchaseManager.shared.restorePurchases()
        if ProPurchaseManager.shared.hasProAccess {
            withAnimation(.easeOut(duration: 0.3)) {
                showSuccess = true
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            dismiss()
        } else {
            isPurchasing = false
        }
    }
}

#Preview {
    PaywallView()
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
