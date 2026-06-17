//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI
import Photos

struct ReadingShareCardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    let todaySeconds: Int
    let streakDays: Int
    let books: [Book]
    
    @State private var selectedBook: Book?
    @State private var isSaving = false
    @State private var saveMessage: String?
    @State private var showToast = false
    
    private let accentBlue = Color(red: 0.22, green: 0.43, blue: 0.95)
    private let accentTeal = Color(red: 0.16, green: 0.62, blue: 0.58)
    
    init(todaySeconds: Int, streakDays: Int, books: [Book]) {
        self.todaySeconds = todaySeconds
        self.streakDays = streakDays
        self.books = books
        _selectedBook = State(initialValue: books.first)
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Book selector if there are multiple books
                if books.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(books, id: \.url) { book in
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        selectedBook = book
                                    }
                                } label: {
                                    Text(book.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(selectedBook?.url == book.url ? .white : AppColors.primaryText)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(selectedBook?.url == book.url ? accentBlue : Color(.secondarySystemGroupedBackground))
                                        .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .frame(height: 38)
                }
                
                // Poster Preview Card (Aspect Ratio ~ 4:5)
                posterCanvas
                    .frame(width: 300, height: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 15, x: 0, y: 8)
                
                Spacer()
                
                // Save Button
                Button {
                    savePosterToPhotos()
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
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        LinearGradient(
                            colors: [accentBlue, accentTeal],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                    .padding(.horizontal, 24)
                }
                .disabled(isSaving)
                .buttonStyle(.plain)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("share_card_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("close_button", comment: "")) {
                        dismiss()
                    }
                }
            }
            .overlay(toastOverlay)
        }
    }
    
    // MARK: - Poster Canvas View
    private var posterCanvas: some View {
        VStack(spacing: 0) {
            // Header: Cover Background and Title
            ZStack {
                LinearGradient(
                    colors: [accentBlue.opacity(0.85), accentTeal.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                
                VStack(spacing: 14) {
                    // Book Icon or cover placeholder
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 72, height: 96)
                        
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white)
                    }
                    
                    VStack(spacing: 4) {
                        Text(selectedBook?.title ?? "PagePilot Reader")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .padding(.horizontal, 20)
                        
                        Text(selectedBook?.authors ?? "")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 20)
            }
            .frame(height: 200)
            
            // Statistics Content
            VStack(spacing: 20) {
                HStack(spacing: 0) {
                    // Today duration
                    VStack(spacing: 6) {
                        Text(NSLocalizedString("share_card_reading_today", comment: ""))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                        
                        Text(formattedTodayTime)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Divider
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 1, height: 32)
                    
                    // Streak
                    VStack(spacing: 6) {
                        Text(NSLocalizedString("share_card_streak", comment: ""))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                        
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text("\(streakDays)")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.orange)
                            Text(NSLocalizedString("share_card_days", comment: ""))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 16)
                
                Divider()
                    .padding(.horizontal, 20)
                
                // Quote Section
                VStack(spacing: 6) {
                    Text(NSLocalizedString("share_card_quote", comment: ""))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppColors.primaryText)
                        .italic()
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .padding(.horizontal, 20)
                }
                .frame(maxHeight: .infinity)
                
                // Branding footer
                HStack {
                    Image("icon") // Safe fallback if icon exists, otherwise SF symbol
                        .resizable()
                        .frame(width: 20, height: 20)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .onDevelopmentFallback {
                            Image(systemName: "crown.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                        }
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text("PagePilot")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                        
                        Text(NSLocalizedString("share_card_subtitle", comment: ""))
                            .font(.system(size: 8))
                            .foregroundColor(AppColors.secondaryText)
                    }
                    
                    Spacer()
                    
                    // Simulated QR code representation (a modern dot-grid mockup)
                    HStack(spacing: 2) {
                        ForEach(0..<4) { _ in
                            VStack(spacing: 2) {
                                ForEach(0..<4) { _ in
                                    Circle()
                                        .fill(accentBlue.opacity(Double.random(in: 0.4...1.0)))
                                        .frame(width: 3, height: 3)
                                }
                            }
                        }
                    }
                    .padding(6)
                    .background(Color.white)
                    .cornerRadius(6)
                    .shadow(color: Color.black.opacity(0.05), radius: 2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .background(Color(.secondarySystemGroupedBackground))
        }
    }
    
    // MARK: - Time Formatter
    private var formattedTodayTime: String {
        let hours = todaySeconds / 3600
        let minutes = (todaySeconds % 3600) / 60
        if hours > 0 {
            return String(format: NSLocalizedString("stats_hours_minutes", comment: ""), hours, minutes)
        } else {
            let mins = max(minutes, todaySeconds > 0 ? 1 : 0)
            return String(format: NSLocalizedString("stats_minutes", comment: ""), mins)
        }
    }
    
    // MARK: - Save Poster Handler
    private func savePosterToPhotos() {
        isSaving = true
        
        // Render view on main actor
        Task { @MainActor in
            let renderer = ImageRenderer(content: posterCanvas.frame(width: 375, height: 500))
            renderer.scale = 3.0 // High quality scale
            
            guard let image = renderer.uiImage else {
                showToast(message: NSLocalizedString("share_card_saved_error", comment: ""))
                isSaving = false
                return
            }
            
            // Check Photos Permission
            let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            switch status {
            case .authorized, .limited:
                saveImage(image)
            case .notDetermined:
                let result = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                if result == .authorized || result == .limited {
                    saveImage(image)
                } else {
                    showToast(message: NSLocalizedString("share_card_saved_error", comment: ""))
                    isSaving = false
                }
            default:
                showToast(message: NSLocalizedString("share_card_saved_error", comment: ""))
                isSaving = false
            }
        }
    }
    
    private func saveImage(_ image: UIImage) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        } completionHandler: { success, error in
            DispatchQueue.main.async {
                self.isSaving = false
                if success {
                    self.showToast(message: NSLocalizedString("share_card_saved_success", comment: ""))
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } else {
                    self.showToast(message: error?.localizedDescription ?? NSLocalizedString("share_card_saved_error", comment: ""))
                }
            }
        }
    }
    
    private func showToast(message: String) {
        saveMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.showToast = false
        }
    }
    
    // MARK: - Toast Overlay
    @ViewBuilder
    private var toastOverlay: some View {
        if showToast, let message = saveMessage {
            VStack {
                Spacer()
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.8))
                    .clipShape(Capsule())
                    .padding(.bottom, 40)
            }
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.spring(), value: showToast)
        }
    }
}

// Helper view extension to gracefully handle asset or fallback loading
extension View {
    func onDevelopmentFallback(fallback: @escaping () -> some View) -> some View {
        modifier(DevelopmentFallbackModifier(fallback: fallback))
    }
}

struct DevelopmentFallbackModifier<Fallback: View>: ViewModifier {
    let fallback: () -> Fallback
    
    func body(content: Content) -> some View {
        if UIImage(named: "icon") != nil {
            content
        } else {
            fallback()
        }
    }
}
