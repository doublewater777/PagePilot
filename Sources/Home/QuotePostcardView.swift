//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Photos
import SwiftUI
import UIKit

/// Payload for rendering a single-quote editorial postcard from Reader or Journal.
struct QuotePostcardPayload: Identifiable, Equatable {
    let id: String
    let quote: String
    let note: String?
    let bookTitle: String
    let author: String?
    let chapterTitle: String?
    let date: Date

    init(
        id: String = UUID().uuidString,
        quote: String,
        note: String? = nil,
        bookTitle: String,
        author: String? = nil,
        chapterTitle: String? = nil,
        date: Date = Date()
    ) {
        self.id = id
        self.quote = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = (trimmedNote?.isEmpty == false) ? trimmedNote : nil
        self.bookTitle = bookTitle
        let trimmedAuthor = author?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.author = (trimmedAuthor?.isEmpty == false && trimmedAuthor?.lowercased() != "unknown") ? trimmedAuthor : nil
        let trimmedChapter = chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.chapterTitle = (trimmedChapter?.isEmpty == false) ? trimmedChapter : nil
        self.date = date
    }
}

struct QuotePostcardView: View {
    let payload: QuotePostcardPayload

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTheme: QuotePostcardTheme = .paper
    @State private var showMascotSeal = true
    @State private var isSaving = false
    @State private var toastMessage: String?
    @State private var showToast = false
    @State private var shareImage: UIImage?
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    // Curated style picker (Warm Paper / Midnight / Dawn)
                    HStack(spacing: 8) {
                        ForEach(QuotePostcardTheme.allCases) { theme in
                            let isSelected = selectedTheme == theme
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    selectedTheme = theme
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(theme.swatchFill)
                                        .frame(width: 14, height: 14)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.primary.opacity(0.16), lineWidth: 0.6)
                                        )
                                    Text(theme.title)
                                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                        .foregroundStyle(isSelected ? AppColors.accentBlue : AppColors.secondaryText)
                                }
                                .padding(.horizontal, 13)
                                .padding(.vertical, 8)
                                .background(
                                    isSelected
                                        ? AppColors.accentBlue.opacity(colorScheme == .dark ? 0.22 : 0.1)
                                        : AppColors.cardBackground,
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            isSelected ? AppColors.accentBlue : Color.primary.opacity(0.06),
                                            lineWidth: isSelected ? 1.4 : 0.75
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            showMascotSeal.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showMascotSeal ? "checkmark.seal.fill" : "seal")
                                .font(.system(size: 12, weight: .semibold))
                            Text(NSLocalizedString("quote_postcard_mascot_seal", comment: ""))
                                .font(.system(size: 12.5, weight: .medium))
                        }
                        .foregroundStyle(showMascotSeal ? AppColors.accentTeal : AppColors.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            showMascotSeal
                                ? AppColors.accentTeal.opacity(colorScheme == .dark ? 0.20 : 0.10)
                                : AppColors.cardBackground,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    showMascotSeal ? AppColors.accentTeal.opacity(0.6) : Color.primary.opacity(0.06),
                                    lineWidth: 0.85
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    // Editorial Postcard Canvas
                    postcardCanvas
                        .frame(width: 316)
                        .frame(minHeight: 380)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.06), lineWidth: 0.75)
                        )
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.44 : 0.14), radius: 22, x: 0, y: 12)

                    // Save & System Share row
                    HStack(spacing: 10) {
                        Button {
                            savePostcardToPhotos()
                        } label: {
                            HStack(spacing: 8) {
                                if isSaving {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "square.and.arrow.down.fill")
                                }
                                Text(NSLocalizedString("share_card_save", comment: ""))
                            }
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(AppColors.horizontalGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .disabled(isSaving)
                        .buttonStyle(PremiumButtonStyle())

                        Button {
                            presentSystemShare()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(AppColors.accentBlue)
                                .frame(width: 52, height: 48)
                                .background(
                                    AppColors.accentBlue.opacity(colorScheme == .dark ? 0.2 : 0.1),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                )
                        }
                        .disabled(isSaving)
                        .buttonStyle(PremiumButtonStyle())
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("quote_postcard_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton { dismiss() }
                }
            }
            .overlay(toastOverlay)
            .sheet(isPresented: $showShareSheet) {
                if let shareImage {
                    QuotePostcardActivityView(image: shareImage)
                }
            }
        }
    }

    // MARK: - Postcard Canvas

    private var postcardCanvas: some View {
        let style = selectedTheme
        let quoteFontSize: CGFloat = payload.quote.count > 160 ? 15.5 : (payload.quote.count > 90 ? 17.5 : 19.5)

        return ZStack {
            style.canvasBackground

            Circle()
                .fill(style.ambientGlow)
                .frame(width: 240, height: 240)
                .blur(radius: 56)
                .offset(x: 96, y: -120)

            VStack(alignment: .leading, spacing: 0) {
                // Header kicker
                HStack {
                    Text(NSLocalizedString("quote_postcard_kicker", comment: ""))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(1.3)
                        .foregroundStyle(style.accentText)
                    Spacer()
                    Text(formattedDate)
                        .font(.system(size: 10.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(style.mutedText)
                }
                .padding(.bottom, 22)

                // Large decorative quotation mark
                Text("“")
                    .font(.system(size: 46, weight: .bold, design: .serif))
                    .foregroundStyle(style.accentText.opacity(0.45))
                    .frame(height: 28, alignment: .topLeading)

                // Excerpt body
                Text(payload.quote)
                    .font(.system(size: quoteFontSize, weight: .medium, design: .serif))
                    .foregroundStyle(style.primaryText)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)

                // Optional reader note
                if let note = payload.note {
                    VStack(alignment: .leading, spacing: 6) {
                        Rectangle()
                            .fill(style.dividerColor)
                            .frame(height: 1)
                            .padding(.vertical, 14)

                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "pencil.line")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(style.accentText)
                                .padding(.top, 2)

                            Text(note)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(style.secondaryText)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Spacer(minLength: 28)

                // Footer attribution colophon
                HStack(alignment: .bottom, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("《\(payload.bookTitle)》")
                            .font(.system(size: 13.5, weight: .bold, design: .serif))
                            .foregroundStyle(style.primaryText)
                            .lineLimit(2)

                        if let subtitle = attributionSubtitle {
                            Text(subtitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(style.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    if showMascotSeal {
                        MascotPostcardSeal(
                            accentColor: style.accentText,
                            borderColor: style.dividerColor,
                            surfaceColor: style.dividerColor.opacity(0.45)
                        )
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(AppColors.accentGradient)
                                .frame(width: 24, height: 24)
                            Image(systemName: "book.pages.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.top, 14)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(style.dividerColor)
                        .frame(height: 0.75)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
    }

    private var attributionSubtitle: String? {
        let parts = [payload.author, payload.chapterTitle].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = AppAppearancePreferences.locale
        formatter.setLocalizedDateFormatFromTemplate("yyyyMMMd")
        return formatter.string(from: payload.date)
    }

    // MARK: - Export

    @MainActor
    private func renderImage() -> UIImage? {
        let renderer = ImageRenderer(
            content: postcardCanvas
                .frame(width: 360)
                .frame(minHeight: 432)
        )
        renderer.scale = 3.0
        return renderer.uiImage
    }

    private func presentSystemShare() {
        Task { @MainActor in
            if let image = renderImage() {
                shareImage = image
                showShareSheet = true
            }
        }
    }

    private func savePostcardToPhotos() {
        isSaving = true
        Task { @MainActor in
            guard let image = renderImage() else {
                displayToast(NSLocalizedString("share_card_saved_error", comment: ""))
                isSaving = false
                return
            }

            let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            switch status {
            case .authorized, .limited:
                persistToPhotoLibrary(image)
            case .notDetermined:
                let result = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                if result == .authorized || result == .limited {
                    persistToPhotoLibrary(image)
                } else {
                    displayToast(NSLocalizedString("share_card_saved_error", comment: ""))
                    isSaving = false
                }
            default:
                displayToast(NSLocalizedString("share_card_saved_error", comment: ""))
                isSaving = false
            }
        }
    }

    private func persistToPhotoLibrary(_ image: UIImage) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                self.isSaving = false
                if success {
                    self.displayToast(NSLocalizedString("share_card_saved_success", comment: ""))
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } else {
                    self.displayToast(error?.localizedDescription ?? NSLocalizedString("share_card_saved_error", comment: ""))
                }
            }
        }
    }

    private func displayToast(_ message: String) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.showToast = false
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if showToast, let toastMessage {
            VStack {
                Spacer()
                Text(toastMessage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.primaryText)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.6))
                    .shadow(color: Color.black.opacity(0.14), radius: 12, y: 5)
                    .padding(.bottom, 32)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showToast)
        }
    }
}

private enum QuotePostcardTheme: String, CaseIterable, Identifiable {
    case paper
    case midnight
    case dawn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: return NSLocalizedString("share_card_theme_paper", comment: "")
        case .midnight: return NSLocalizedString("share_card_theme_midnight", comment: "")
        case .dawn: return NSLocalizedString("share_card_theme_dawn", comment: "")
        }
    }

    var swatchFill: LinearGradient {
        switch self {
        case .paper:
            return LinearGradient(colors: [Color(red: 251 / 255, green: 247 / 255, blue: 239 / 255), Color(red: 242 / 255, green: 235 / 255, blue: 222 / 255)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .midnight:
            return LinearGradient(colors: [Color(red: 21 / 255, green: 27 / 255, blue: 40 / 255), Color(red: 13 / 255, green: 17 / 255, blue: 26 / 255)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .dawn:
            return LinearGradient(colors: [AppColors.accentBlue, AppColors.accentTeal], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var canvasBackground: LinearGradient {
        switch self {
        case .paper:
            return LinearGradient(
                colors: [Color(red: 252 / 255, green: 249 / 255, blue: 243 / 255), Color(red: 245 / 255, green: 240 / 255, blue: 231 / 255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .midnight:
            return LinearGradient(
                colors: [Color(red: 24 / 255, green: 30 / 255, blue: 44 / 255), Color(red: 14 / 255, green: 18 / 255, blue: 27 / 255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .dawn:
            return LinearGradient(
                colors: [Color(red: 28 / 255, green: 84 / 255, blue: 184 / 255), Color(red: 18 / 255, green: 132 / 255, blue: 126 / 255)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var ambientGlow: Color {
        switch self {
        case .paper: return Color.orange.opacity(0.12)
        case .midnight: return AppColors.accentTeal.opacity(0.24)
        case .dawn: return Color.white.opacity(0.22)
        }
    }

    var primaryText: Color {
        switch self {
        case .paper: return Color(red: 33 / 255, green: 31 / 255, blue: 28 / 255)
        case .midnight, .dawn: return .white
        }
    }

    var secondaryText: Color {
        switch self {
        case .paper: return Color(red: 105 / 255, green: 98 / 255, blue: 88 / 255)
        case .midnight: return Color.white.opacity(0.72)
        case .dawn: return Color.white.opacity(0.84)
        }
    }

    var mutedText: Color {
        switch self {
        case .paper: return Color(red: 142 / 255, green: 134 / 255, blue: 123 / 255)
        case .midnight: return Color.white.opacity(0.48)
        case .dawn: return Color.white.opacity(0.7)
        }
    }

    var accentText: Color {
        switch self {
        case .paper: return AppColors.accentBlue
        case .midnight: return AppColors.accentTeal
        case .dawn: return .white
        }
    }

    var dividerColor: Color {
        switch self {
        case .paper: return Color.black.opacity(0.1)
        case .midnight, .dawn: return Color.white.opacity(0.18)
        }
    }
}

private struct QuotePostcardActivityView: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
