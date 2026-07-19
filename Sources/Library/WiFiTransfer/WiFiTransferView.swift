//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI

/// A view that starts a local HTTP server and displays the URL for the user
/// to open on their computer to upload files via WiFi.
struct WiFiTransferView: View {
    @StateObject private var viewModel: WiFiTransferViewModel
    @Environment(\.dismiss) private var dismiss

    init(library: LibraryService, onPublicationImported: ((Book) -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: WiFiTransferViewModel(
            library: library,
            onPublicationImported: onPublicationImported
        ))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if viewModel.isRunning {
                    runningContent
                } else if let error = viewModel.error {
                    errorContent(error)
                } else {
                    startingContent
                }
            }
            .padding(24)
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
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "wifi")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)

            Text(NSLocalizedString("wifi_transfer_instruction", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let url = viewModel.serverURL {
                VStack(spacing: 8) {
                    Text(url)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contextMenu {
                            Button {
                                UIPasteboard.general.string = url
                            } label: {
                                Label(
                                    NSLocalizedString("wifi_transfer_copy", comment: ""),
                                    systemImage: "doc.on.doc"
                                )
                            }
                        }

                    Text(NSLocalizedString("wifi_transfer_copy_hint", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            if viewModel.uploadedCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(String(
                        format: NSLocalizedString("wifi_transfer_uploaded_count", comment: ""),
                        viewModel.uploadedCount
                    ))
                    .font(.subheadline.weight(.medium))
                }
                .padding(.top, 8)
            }

            Spacer()

            tipView
        }
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
                .foregroundStyle(.yellow)
                .font(.subheadline)
            Text(NSLocalizedString("wifi_transfer_tip", comment: ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            let url = try server.start()
            serverURL = url
            isRunning = true

            server.onFileUploaded = { [weak self] fileURL in
                guard let self else { return }
                self.uploadedCount += 1
                self.importToLibrary(fileURL: fileURL)
            }
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
    private func importToLibrary(fileURL: URL) {
        guard let absoluteURL = fileURL.anyURL.absoluteURL else { return }

        Task { @MainActor in
            do {
                let book = try await library.importPublication(
                    from: absoluteURL,
                    sender: UIApplication.shared.firstKeyWindow?.rootViewController ?? UIViewController(),
                    progress: { _ in }
                )
                if !didNotifyFirstImport {
                    didNotifyFirstImport = true
                    onPublicationImported?(book)
                }
            } catch {
                print("WiFiTransfer: failed to import \(fileURL.lastPathComponent) to library: \(error)")
            }
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
