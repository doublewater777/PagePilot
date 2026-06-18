//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SafariServices
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
    @State private var isEligibleForTrial = false
    @State private var safariURL: IdentifiableURL?

    private var selectedProduct: Product? {
        products.first(where: { $0.id == selectedProductID })
    }

    private var canStartFreeTrial: Bool {
        guard let selectedProduct else { return false }
        return freeTrialOffer(for: selectedProduct) != nil && isEligibleForTrial
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                closeRow
                hero
                featureList
                optionList
                purchasePanel
                linksView
            }
            .frame(maxWidth: 440)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .presentationDetents([.height(640)])
        .presentationDragIndicator(.hidden)
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
        .sheet(item: $safariURL) { identifiableURL in
            SafariView(url: identifiableURL.url)
        }
    }

    // MARK: - Hero

    private var closeRow: some View {
        HStack {
            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                    .frame(width: 30, height: 30)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("paywall_close", comment: ""))
            .disabled(isPurchasing)
        }
        .frame(height: 30)
    }

    private var hero: some View {
        VStack(spacing: 7) {
            Image(systemName: "crown.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.orange)
                .frame(width: 36, height: 36)
                .background(Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.12))
                .clipShape(Circle())

            Text(NSLocalizedString("paywall_title", comment: ""))
                .font(.system(size: 23, weight: .bold))
                .foregroundColor(AppColors.primaryText)
                .multilineTextAlignment(.center)

            Text(NSLocalizedString("paywall_subtitle", comment: ""))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
    }

    private var featureList: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 0) {
                miniFeature(
                    icon: "books.vertical.fill",
                    iconColor: AppColors.accentTeal,
                    title: NSLocalizedString("paywall_feature_unlimited_title", comment: ""),
                    subtitle: NSLocalizedString("paywall_feature_unlimited_subtitle", comment: "")
                )
                miniFeature(
                    icon: "applewatch.watchface",
                    iconColor: .purple,
                    title: NSLocalizedString("paywall_feature_watch_title", comment: ""),
                    subtitle: NSLocalizedString("paywall_feature_watch_subtitle", comment: "")
                )
                miniFeature(
                    icon: "chart.bar.xaxis",
                    iconColor: AppColors.accentBlue,
                    title: NSLocalizedString("paywall_feature_stats_title", comment: ""),
                    subtitle: NSLocalizedString("paywall_feature_stats_subtitle", comment: "")
                )
                miniFeature(
                    icon: "sparkles",
                    iconColor: .green,
                    title: NSLocalizedString("paywall_feature_clean_title", comment: ""),
                    subtitle: NSLocalizedString("paywall_feature_clean_subtitle", comment: "")
                )
            }

            Divider()
        }
        .padding(.top, 4)
    }

    // MARK: - Option Cards List

    private var optionList: some View {
        VStack(spacing: 8) {
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
                            .background(AppColors.accentBlue)
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
                // Fixed display order: yearly -> monthly -> lifetime
                let ordered = products.sorted { a, b in
                    let rank: (Product) -> Int = { p in
                        if p.id.contains("yearly") { return 0 }
                        if p.id.contains("monthly") { return 1 }
                        return 2
                    }
                    return rank(a) < rank(b)
                }
                ForEach(ordered, id: \.id) { product in
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
                return yearlyPriceSubtext(for: product)
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
            HStack(spacing: 12) {
                // Radio Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? AppColors.accentBlue : Color.secondary.opacity(0.3), lineWidth: 2)
                        .frame(width: 20, height: 20)
                    
                    if isSelected {
                        Circle()
                            .fill(AppColors.accentBlue)
                            .frame(width: 11, height: 11)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(NSLocalizedString(titleKey, comment: ""))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                            .lineLimit(1)
                        
                        if let badgeText {
                            Text(badgeText)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(
                                    LinearGradient(
                                        colors: isLifetime 
                                            ? [Color.orange, Color.red] 
                                            : (isYearly ? [AppColors.accentTeal, AppColors.accentBlue] : [AppColors.accentBlue, AppColors.accentTeal]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(6)
                        }
                    }
                    
                    Text(priceSubtext)
                        .font(.system(size: 11.5, weight: isYearly ? .semibold : .regular))
                        .foregroundColor(isYearly ? AppColors.accentTeal : AppColors.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                
                Spacer()
                
                Text(displayPrice(for: product))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(AppColors.primaryText)
                    .monospacedDigit()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Group {
                    if isSelected {
                        LinearGradient(
                            colors: [AppColors.accentBlue.opacity(colorScheme == .dark ? 0.20 : 0.08), AppColors.accentTeal.opacity(colorScheme == .dark ? 0.10 : 0.04)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            )
            .background(.thinMaterial)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected 
                            ? LinearGradient(colors: [AppColors.accentBlue, AppColors.accentTeal], startPoint: .leading, endPoint: .trailing)
                            : LinearGradient(colors: [Color.white.opacity(colorScheme == .dark ? 0.08 : 0.3), Color.white.opacity(0.0)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: isSelected ? 1.5 : 1
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
        guard let selectedProduct else {
            return NSLocalizedString("paywall_buy_button_ineligible", comment: "")
        }
        
        if selectedProduct.id.contains("lifetime") {
            return NSLocalizedString("paywall_buy_button_lifetime", comment: "")
        } else if canStartFreeTrial {
            return NSLocalizedString("paywall_buy_button_eligible", comment: "")
        } else {
            return NSLocalizedString("paywall_buy_button_ineligible", comment: "")
        }
    }

    private var purchasePanel: some View {
        VStack(spacing: 9) {
            HStack(spacing: 14) {
                if canStartFreeTrial {
                    assuranceItem(icon: "checkmark.seal.fill", text: NSLocalizedString("paywall_assurance_trial", comment: ""))
                }
                assuranceItem(icon: "xmark.seal.fill", text: NSLocalizedString("paywall_assurance_cancel", comment: ""))
            }

            Text(NSLocalizedString(canStartFreeTrial ? "paywall_trial_note" : "paywall_subscription_billing_note", comment: ""))
                .font(.system(size: 10.5))
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.9)

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
                .frame(height: 48)
                .background(
                    LinearGradient(
                        colors: [AppColors.accentBlue, AppColors.accentTeal],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(15)
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(isPurchasing || selectedProductID.isEmpty)

            Button(NSLocalizedString("paywall_restore_button", comment: "")) {
                Task { await restore() }
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(AppColors.secondaryText.opacity(0.65))
            .disabled(isPurchasing)
        }
        .padding(.top, 2)
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

    private func miniFeature(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(iconColor)
                .frame(width: 32, height: 32)
                .background(iconColor.opacity(colorScheme == .dark ? 0.20 : 0.11))
                .clipShape(Circle())

            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(AppColors.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(subtitle)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 70, alignment: .top)
    }

    private func assuranceItem(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.accentTeal)

            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    private var linksView: some View {
        HStack(spacing: 16) {
            Button {
                safariURL = IdentifiableURL(url: URL(string: "https://pagepilot.doublewaterapps.com/terms.html")!)
            } label: {
                Text(NSLocalizedString("paywall_terms_of_use", comment: ""))
            }

            Text("•")
                .foregroundColor(AppColors.secondaryText)

            Button {
                safariURL = IdentifiableURL(url: URL(string: "https://pagepilot.doublewaterapps.com/privacy.html")!)
            } label: {
                Text(NSLocalizedString("paywall_privacy_policy", comment: ""))
            }
        }
        .font(.system(size: 12))
        .foregroundColor(AppColors.accentBlue)
        .padding(.top, 0)
    }

    private func displayPrice(for product: Product) -> String {
        product.displayPrice
    }

    private func localizedMonthlyPrice(for product: Product) -> String {
        if product.id.contains("yearly") {
            let monthlyPrice = product.price / Decimal(12)
            return monthlyPrice.formatted(product.priceFormatStyle)
        } else if product.id.contains("monthly") {
            return product.displayPrice
        } else {
            return product.displayPrice
        }
    }

    private func yearlyPriceSubtext(for yearlyProduct: Product) -> String {
        let formattedMonthly = localizedMonthlyPrice(for: yearlyProduct)
        guard
            let monthlyProduct = products.first(where: { $0.id == ProPurchaseManager.monthlyProductID }),
            monthlyProduct.price > 0
        else {
            return String(format: NSLocalizedString("paywall_price_yearly_sub_no_savings", comment: ""), formattedMonthly)
        }

        let monthlyAnnualPrice = monthlyProduct.price * Decimal(12)
        guard monthlyAnnualPrice > yearlyProduct.price else {
            return String(format: NSLocalizedString("paywall_price_yearly_sub_no_savings", comment: ""), formattedMonthly)
        }

        let savingsRatio = (monthlyAnnualPrice - yearlyProduct.price) / monthlyAnnualPrice
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        let formattedSavings = formatter.string(from: NSDecimalNumber(decimal: savingsRatio)) ?? ""

        return String(format: NSLocalizedString("paywall_price_yearly_sub", comment: ""), formattedMonthly, formattedSavings)
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
            if let subscription = selectedProduct.subscription, freeTrialOffer(for: selectedProduct) != nil {
                let eligible = await subscription.isEligibleForIntroOffer
                isEligibleForTrial = eligible
            } else {
                isEligibleForTrial = false
            }
        }
    }

    private func freeTrialOffer(for product: Product) -> Product.SubscriptionOffer? {
        guard let offer = product.subscription?.introductoryOffer, offer.paymentMode == .freeTrial else {
            return nil
        }
        return offer
    }

    @MainActor
    private func restore() async {
        isPurchasing = true
        do {
            let hasProAccess = try await ProPurchaseManager.shared.restorePurchases()
            guard hasProAccess else {
                throw ProPurchaseError.noPurchasesToRestore
            }

            withAnimation(.easeOut(duration: 0.3)) {
                showSuccess = true
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            dismiss()
        } catch {
            purchaseError = error
            showError = true
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
