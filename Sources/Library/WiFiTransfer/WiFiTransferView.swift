//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import CoreImage.CIFilterBuiltins
import SwiftUI

/// A view that starts a local HTTP server and displays the URL for the user
/// to open on their computer to upload files via WiFi.
struct WiFiTransferView: View {
    @StateObject private var viewModel: WiFiTransferViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var copiedFeedback = false

    init(library: LibraryService, onPublicationImported: ((Book) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: WiFiTransferViewModel(
            library: library,
            onPublicationImported: onPublicationImported
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 20) {
                    if viewModel.isRunning {
                        runningContent
                    } else if let error = viewModel.error {
                        errorContent(error)
                    } else {
                        startingContent
                    }
                }
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
                .padding(24)
            }
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("wifi_transfer_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton(
                        accessibilityLabel: NSLocalizedString("wifi_transfer_done", comment: "")
                    ) {
                        viewModel.stop()
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.start()
            }
            .onDisappear {
                viewModel.stop()
            }
        }
    }

    // MARK: - Running state

    private var runningContent: some View {
        VStack(spacing: 18) {
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppColors.accentBlue.opacity(colorScheme == .dark ? 0.2 : 0.1))
                        .frame(width: 60, height: 60)
                    Image(systemName: "wifi")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(AppColors.accentBlue)
                }

                Text(NSLocalizedString("wifi_transfer_instruction", comment: ""))
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)

                if let url = viewModel.serverURL {
                    // URL pill + one-tap copy button
                    HStack(spacing: 10) {
                        Text(url)
                            .font(.system(size: 17, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppColors.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Spacer(minLength: 4)

                        Button {
                            UIPasteboard.general.string = url
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                copiedFeedback = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { copiedFeedback = false }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: copiedFeedback ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(NSLocalizedString(copiedFeedback ? "wifi_transfer_copied" : "wifi_transfer_copy", comment: ""))
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .foregroundStyle(copiedFeedback ? .white : AppColors.accentBlue)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(
                                copiedFeedback
                                    ? AnyShapeStyle(AppColors.accentTeal)
                                    : AnyShapeStyle(AppColors.accentBlue.opacity(colorScheme == .dark ? 0.22 : 0.1)),
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.04), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                    // Real scannable QR code
                    if let qrImage = Self.makeQRCode(from: url) {
                        VStack(spacing: 8) {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 148, height: 148)
                                .padding(12)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.black.opacity(0.06), lineWidth: 0.75)
                                )

                            Text(NSLocalizedString("wifi_transfer_scan_qr", comment: ""))
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.tertiaryText)
                        }
                        .padding(.top, 4)
                    }
                }

                if let error = viewModel.error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                if viewModel.uploadedCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppColors.accentTeal)
                        Text(String(
                            format: NSLocalizedString("wifi_transfer_uploaded_count", comment: ""),
                            viewModel.uploadedCount
                        ))
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(AppColors.accentTeal)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(AppColors.accentTeal.opacity(colorScheme == .dark ? 0.2 : 0.1), in: Capsule())
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .cardStyle()

            tipView
        }
    }

    private static func makeQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Error state

    private func errorContent(_ error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.red)

            Text(error)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(NSLocalizedString("wifi_transfer_retry", comment: "")) {
                viewModel.start()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
    }

    // MARK: - Starting state

    private var startingContent: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text(NSLocalizedString("wifi_transfer_starting", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Tip

    private var tipView: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)
            Text(NSLocalizedString("wifi_transfer_tip", comment: ""))
                .font(.caption)
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .cardStyle()
    }
}

// MARK: - ViewModel

@MainActor
final class WiFiTransferViewModel: ObservableObject {
    @Published var isRunning = false
    @Published var serverURL: String?
    @Published var error: String?
    @Published var uploadedCount = 0

    private let server = WiFiTransferServer()
    private let library: LibraryService
    private let onPublicationImported: ((Book) -> Void)?
    private var didNotifyFirstImport = false

    init(library: LibraryService, onPublicationImported: ((Book) -> Void)? = nil) {
        self.library = library
        self.onPublicationImported = onPublicationImported
    }

    func start() {
        error = nil

        guard WiFiTransferServer.wifiIPAddress() != nil else {
            error = NSLocalizedString("wifi_transfer_no_wifi", comment: "")
            return
        }

        do {
            server.onFileUploaded = { [weak self] fileURL in
                guard let self else { throw CancellationError() }
                do {
                    try await self.importToLibrary(fileURL: fileURL)
                    self.uploadedCount += 1
                } catch {
                    self.error = UserError(error).message
                    throw error
                }
            }
            let url = try server.start()
            serverURL = url
            isRunning = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stop() {
        server.stop()
        isRunning = false
    }

    /// Imports the uploaded file into the app's library (book database),
    /// so it appears on the bookshelf automatically.
    private func importToLibrary(fileURL: URL) async throws {
        guard let absoluteURL = fileURL.anyURL.absoluteURL else {
            throw LibraryError.publicationIsNotValid
        }
        let book = try await library.importPublication(
            from: absoluteURL,
            sender: UIApplication.shared.firstKeyWindow?.rootViewController ?? UIViewController(),
            progress: { _ in }
        )
        if !didNotifyFirstImport {
            didNotifyFirstImport = true
            onPublicationImported?(book)
        }
    }

}

private extension UIApplication {
    var firstKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}
