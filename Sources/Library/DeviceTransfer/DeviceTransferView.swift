//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ReadiumShared
import SwiftUI

// MARK: - Root View (tab between Send / Receive)

struct DeviceTransferView: View {
    let books: [Book]
    let library: LibraryService
    @State private var selectedTab = 0

    var body: some View {
        NavigationView {
            TabView(selection: $selectedTab) {
                SendBooksView(books: books)
                    .tabItem { Label(NSLocalizedString("transfer_tab_send", comment: ""), systemImage: "arrow.up.circle") }
                    .tag(0)

                ReceiveBooksView(library: library)
                    .tabItem { Label(NSLocalizedString("transfer_tab_receive", comment: ""), systemImage: "arrow.down.circle") }
                    .tag(1)
            }
            .navigationTitle(NSLocalizedString("transfer_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Send Tab

private struct SendBooksView: View {
    let books: [Book]

    @ObservedObject private var service = DeviceTransferService.shared
    @State private var selectedBooks: Set<Book.Id> = []
    @State private var isSending = false
    @State private var sendProgress: [Book.Id: SendState] = [:]
    @State private var errorMessage: String?
    /// Resolved cover images, populated asynchronously so scrolling stays smooth.
    @State private var coverImages: [Book.Id: UIImage] = [:]
    private let coverLoader = CoverImageLoader()

    private enum SendState {
        case sending, done, failed
    }

    var body: some View {
        VStack(spacing: 0) {
            // Peer discovery status
            peerStatusBar

            if books.isEmpty {
                emptyLibraryView
            } else {
                bookList
            }

            // Send button
            if !selectedBooks.isEmpty {
                sendBar
            }
        }
        .onAppear { service.startDiscovery() }
        .onDisappear { service.stopDiscovery() }
    }

    // MARK: Peer status

    private var peerStatusBar: some View {
        HStack(spacing: 8) {
            if service.discoveredPeers.isEmpty {
                ProgressView().controlSize(.small)
                Text(NSLocalizedString("transfer_searching", comment: ""))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(String(format: NSLocalizedString("transfer_peers_found", comment: ""), service.discoveredPeers.count))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: Book list

    private var bookList: some View {
        List(books, id: \.id) { book in
            let bookId = book.id!
            let state = sendProgress[bookId]
            HStack(spacing: 14) {
                // Selection checkbox
                Image(systemName: selectedBooks.contains(bookId) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedBooks.contains(bookId) ? .blue : .secondary)
                    .font(.title3)

                // Cover thumbnail — loaded asynchronously via CoverImageLoader
                coverThumbnail(for: book)
                    .frame(width: 36, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .task(id: bookId) {
                        guard let coverURL = book.cover?.url else { return }
                        let image = await coverLoader.load(url: coverURL, bookId: bookId.rawValue)
                        if let image {
                            coverImages[bookId] = image
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(2)
                    if let authors = book.authors {
                        Text(authors)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Send state indicator
                if let state {
                    switch state {
                    case .sending:
                        ProgressView().controlSize(.small)
                    case .done:
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    case .failed:
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard state == nil else { return }
                if selectedBooks.contains(bookId) {
                    selectedBooks.remove(bookId)
                } else {
                    selectedBooks.insert(bookId)
                }
            }
        }
        .listStyle(.plain)
    }

    // MARK: Send bar

    private var sendBar: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 8) {
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                if service.discoveredPeers.isEmpty {
                    Text(NSLocalizedString("transfer_no_peers_hint", comment: ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    // If multiple peers, show a picker; otherwise send to the only one
                    ForEach(service.discoveredPeers) { peer in
                        Button {
                            sendSelected(to: peer)
                        } label: {
                            HStack {
                                Image(systemName: "ipad.and.iphone")
                                Text(String(format: NSLocalizedString("transfer_send_to", comment: ""), peer.name))
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.blue)
                            .foregroundStyle(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isSending)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: Empty

    private var emptyLibraryView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(NSLocalizedString("transfer_empty_library", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Actions

    private func sendSelected(to peer: TransferPeer) {
        guard !isSending else { return }
        isSending = true
        errorMessage = nil

        let booksToSend = books.filter { selectedBooks.contains($0.id!) }

        Task { @MainActor in
            defer { isSending = false }
            for book in booksToSend {
                guard let bookId = book.id else { continue }
                sendProgress[bookId] = .sending

                do {
                    guard let fileURL = try? book.absoluteFileURL() else {
                        sendProgress[bookId] = .failed
                        continue
                    }
                    try await DeviceTransferService.shared.sendBook(at: fileURL, to: peer) { _ in }
                    sendProgress[bookId] = .done
                } catch {
                    sendProgress[bookId] = .failed
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: Cover thumbnail

    @ViewBuilder
    private func coverThumbnail(for book: Book) -> some View {
        if let bookId = book.id, let image = coverImages[bookId] {
            // Cached/loaded image — no disk I/O on the main thread
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.teal.opacity(0.3)
                Text(String(book.title.prefix(1)))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.teal)
            }
        }
    }
}

// MARK: - Receive Tab

private struct ReceiveBooksView: View {
    let library: LibraryService
    @ObservedObject private var service = DeviceTransferService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: service.isReceiving ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(service.isReceiving ? .blue : .secondary)
                .symbolEffect(.pulse, isActive: service.isReceiving)

            VStack(spacing: 8) {
                Text(service.isReceiving
                     ? NSLocalizedString("transfer_receiving_active", comment: "")
                     : NSLocalizedString("transfer_receiving_idle", comment: ""))
                    .font(.headline)

                Text(NSLocalizedString("transfer_receiving_hint", comment: ""))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            if service.receivedCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(String(format: NSLocalizedString("transfer_received_count", comment: ""), service.receivedCount))
                        .font(.subheadline.weight(.medium))
                }
            }

            Spacer()

            Button {
                if service.isReceiving {
                    service.stopReceiving()
                } else {
                    service.startReceiving()
                }
            } label: {
                Text(service.isReceiving
                     ? NSLocalizedString("transfer_stop_receiving", comment: "")
                     : NSLocalizedString("transfer_start_receiving", comment: ""))
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(service.isReceiving ? Color.red.opacity(0.12) : Color.blue)
                    .foregroundStyle(service.isReceiving ? .red : .white)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .onAppear {
            service.startReceiving()
            service.onFileReceived = { fileURL in
                importToLibrary(fileURL: fileURL)
            }
        }
        .onDisappear {
            service.stopReceiving()
        }
    }

    private func importToLibrary(fileURL: URL) {
        guard let absoluteURL = fileURL.anyURL.absoluteURL else { return }
        Task { @MainActor in
            do {
                try await library.importPublication(
                    from: absoluteURL,
                    sender: UIApplication.shared.connectedScenes
                        .compactMap { $0 as? UIWindowScene }
                        .flatMap(\.windows)
                        .first(where: \.isKeyWindow)?
                        .rootViewController ?? UIViewController(),
                    progress: { _ in }
                )
            } catch {
                print("DeviceTransfer: import failed: \(error)")
            }
        }
    }
}
