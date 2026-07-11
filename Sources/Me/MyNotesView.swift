import Combine
import ReadiumShared
import SwiftUI
import UIKit

// MARK: - My Notes (grouped by book)

struct MyNotesView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var notes: [TimelineNote] = []
    @State private var isLoading = true
    @State private var notePendingDeletion: TimelineNote?
    @State private var showDeleteConfirmation = false
    @State private var deleteErrorMessage: String?
    @State private var highlightCount = 0
    @ObservedObject private var proPurchase = ProPurchaseManager.shared
    @State private var showPaywall = false

    private let bookmarkRepo: BookmarkRepository
    private let highlightRepo: HighlightRepository
    private let bookRepo: BookRepository

    init() {
        let app = AppModule.shared
        bookmarkRepo = app!.bookmarkRepository
        highlightRepo = app!.highlightRepository
        bookRepo = app!.books
    }

    /// Only surface free-quota pressure near the limit — not on first few highlights.
    private var showQuotaBanner: Bool {
        !proPurchase.hasProAccess && highlightCount >= NotesQuota.warningThreshold
    }

    private var bookGroups: [BookNotesGroup] {
        let grouped = Dictionary(grouping: notes) { note -> Int64 in
            note.book.id?.rawValue ?? -1
        }
        return grouped.values
            .compactMap { BookNotesGroup(notes: $0) }
            .sorted { $0.latestDate > $1.latestDate }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(AppColors.accentBlue)
                    .scaleEffect(1.2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if notes.isEmpty {
                emptyState
                    .padding(.bottom, notesBottomClearance)
            } else {
                bookList
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(NSLocalizedString("my_notes_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await loadNotes() }
        .alert(
            NSLocalizedString("my_notes_delete_error_title", comment: ""),
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { if !$0 { deleteErrorMessage = nil } }
            )
        ) {
            Button(NSLocalizedString("ok_button", comment: ""), role: .cancel) {
                deleteErrorMessage = nil
            }
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    private var bookList: some View {
        List {
            Section {
                Text(NSLocalizedString("my_notes_subtitle", comment: ""))
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.secondaryText)
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 8, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            if showQuotaBanner {
                Section {
                    Button {
                        Analytics.shared.log(.paywallViewed(source: "notes_quota_banner"))
                        showPaywall = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "highlighter")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.orange)
                            Text(
                                String(
                                    format: NSLocalizedString("my_notes_quota_banner", comment: ""),
                                    highlightCount,
                                    ProPurchaseManager.freeHighlightLimit
                                )
                            )
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.primaryText)
                            .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.orange.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 8, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }

            Section {
                ForEach(bookGroups) { group in
                    NavigationLink {
                        BookNotesDetailView(
                            book: group.book,
                            allNotes: $notes,
                            onOpen: openReader,
                            onDelete: { note in
                                notePendingDeletion = note
                                showDeleteConfirmation = true
                            }
                        )
                    } label: {
                        BookNotesGroupRow(group: group)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, notesBottomClearance, for: .scrollContent)
        .padding(.top, 4)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .alert(
            NSLocalizedString("my_notes_delete_confirm_title", comment: ""),
            isPresented: $showDeleteConfirmation
        ) {
            Button(NSLocalizedString("delete_button", comment: ""), role: .destructive) {
                guard let note = notePendingDeletion else { return }
                notePendingDeletion = nil
                Task { await deleteNote(note) }
            }
            Button(NSLocalizedString("cancel_button", comment: ""), role: .cancel) {
                notePendingDeletion = nil
            }
        }
    }

    private var notesBottomClearance: CGFloat {
        UIDevice.current.userInterfaceIdiom == .pad ? 24 : 96
    }

    private func deleteNote(_ note: TimelineNote) async {
        do {
            switch note.item {
            case .bookmark(let bookmark):
                guard let id = bookmark.id else { return }
                try await bookmarkRepo.remove(id)
            case .highlight(let highlight):
                guard let id = highlight.id else { return }
                try await highlightRepo.remove(id)
            }

            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                notes.removeAll { $0.id == note.id }
            }
            if case .highlight = note.item {
                highlightCount = max(0, highlightCount - 1)
            }
        } catch {
            deleteErrorMessage = NSLocalizedString("my_notes_delete_error_message", comment: "")
        }
    }

    private func openReader(for note: TimelineNote) {
        guard let app = AppModule.shared, let bookId = note.book.id else { return }

        app.pendingNavigationTarget = (bookId, note.item.locator)

        // Close Home sheet first; from Me-tab NavigationLink this pops notes.
        // Defer open so the sheet/nav transition finishes (especially on iPad).
        dismiss()

        Task { @MainActor in
            // Allow sheet dismissal / pop animation to complete before presenting reader.
            try? await Task.sleep(nanoseconds: 350_000_000)

            let tabBar = app.tabBarController
            let nav = app.library.rootViewController
            tabBar?.selectedIndex = 1
            nav.popToRootViewController(animated: false)

            guard let pub = try? await app.library.openBook(note.book, sender: nav) else { return }
            app.reader.presentPublication(publication: pub, book: note.book, in: nav)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)

            Text(NSLocalizedString("my_notes_empty", comment: ""))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadNotes() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let bookmarkBookIds = try await bookmarkRepo.distinctBookIds()
            let highlightBookIds = try await highlightRepo.distinctBookIds()
            let allBookIds = Set(bookmarkBookIds + highlightBookIds)

            var timelineNotes: [TimelineNote] = []

            for bookId in allBookIds {
                guard let book = try await bookRepo.get(bookId) else { continue }

                let bookmarks = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[Bookmark], Error>) in
                    var cancellable: AnyCancellable?
                    cancellable = bookmarkRepo.all(for: bookId)
                        .sink(receiveCompletion: { completion in
                            if case .failure(let error) = completion {
                                cont.resume(throwing: error)
                            }
                            cancellable?.cancel()
                        }, receiveValue: { bookmarks in
                            cont.resume(returning: bookmarks)
                            cancellable?.cancel()
                        })
                }

                let highlights = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[Highlight], Error>) in
                    var cancellable: AnyCancellable?
                    cancellable = highlightRepo.all(for: bookId)
                        .sink(receiveCompletion: { completion in
                            if case .failure(let error) = completion {
                                cont.resume(throwing: error)
                            }
                            cancellable?.cancel()
                        }, receiveValue: { highlights in
                            cont.resume(returning: highlights)
                            cancellable?.cancel()
                        })
                }

                timelineNotes.append(contentsOf: bookmarks.map { TimelineNote(book: book, item: .bookmark($0)) })
                timelineNotes.append(contentsOf: highlights.map { TimelineNote(book: book, item: .highlight($0)) })
            }

            timelineNotes.sort { $0.date > $1.date }
            notes = timelineNotes
            highlightCount = timelineNotes.reduce(0) { partial, note in
                if case .highlight = note.item { return partial + 1 }
                return partial
            }
        } catch {
            print("MyNotesView: failed to load notes: \(error)")
            notes = []
            highlightCount = 0
        }
    }
}

// MARK: - Book group

private struct BookNotesGroup: Identifiable {
    let book: Book
    let notes: [TimelineNote]
    let latestDate: Date
    let highlightCount: Int
    let bookmarkCount: Int

    var id: Int64 { book.id?.rawValue ?? 0 }

    init?(notes: [TimelineNote]) {
        guard let first = notes.first else { return nil }
        book = first.book
        self.notes = notes.sorted { $0.date > $1.date }
        latestDate = self.notes.map(\.date).max() ?? first.date
        highlightCount = notes.filter {
            if case .highlight = $0.item { return true }
            return false
        }.count
        bookmarkCount = notes.filter {
            if case .bookmark = $0.item { return true }
            return false
        }.count
    }
}

private struct BookNotesGroupRow: View {
    let group: BookNotesGroup
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 14) {
            BookCoverThumbnail(book: group.book)
                .frame(width: 52, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 6) {
                Text(group.book.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(2)

                if let authors = group.book.authors, !authors.isEmpty {
                    Text(authors)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)
                }

                HStack(spacing: 10) {
                    Text(String(format: NSLocalizedString("my_notes_progress_format", comment: ""), Int(min(max(group.book.progression, 0), 1) * 100)))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.accentTeal)

                    Text("·")
                        .foregroundStyle(AppColors.tertiaryText)

                    Text(String(format: NSLocalizedString("my_notes_count_format", comment: ""), group.notes.count))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.secondaryText)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AppColors.cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppColors.cardCornerRadius, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04), lineWidth: 1)
        )
    }
}

// MARK: - Book detail

private struct BookNotesDetailView: View {
    let book: Book
    @Binding var allNotes: [TimelineNote]
    let onOpen: (TimelineNote) -> Void
    let onDelete: (TimelineNote) -> Void

    private var notes: [TimelineNote] {
        allNotes
            .filter { $0.book.id == book.id }
            .sorted { $0.date > $1.date }
    }

    private var highlightCount: Int {
        notes.filter { if case .highlight = $0.item { return true }; return false }.count
    }

    private var bookmarkCount: Int {
        notes.filter { if case .bookmark = $0.item { return true }; return false }.count
    }

    var body: some View {
        List {
            Section {
                bookHeader
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            Section {
                if notes.isEmpty {
                    Text(NSLocalizedString("my_notes_empty", comment: ""))
                        .font(.system(size: 15))
                        .foregroundStyle(AppColors.secondaryText)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(notes) { note in
                        // Use Button (not onTapGesture): List + swipeActions swallows taps on iPad.
                        Button {
                            onOpen(note)
                        } label: {
                            NoteContentRow(note: note)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                onDelete(note)
                            } label: {
                                Text(NSLocalizedString("delete_button", comment: ""))
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var bookHeader: some View {
        HStack(spacing: 14) {
            BookCoverThumbnail(book: book)
                .frame(width: 56, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                if let authors = book.authors, !authors.isEmpty {
                    Text(authors)
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.secondaryText)
                }

                Text(String(format: NSLocalizedString("my_notes_progress_format", comment: ""), Int(min(max(book.progression, 0), 1) * 100)))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.accentTeal)

                HStack(spacing: 12) {
                    labelCount(highlightCount, key: "my_notes_highlights_label")
                    labelCount(bookmarkCount, key: "my_notes_bookmarks_label")
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AppColors.cardCornerRadius, style: .continuous))
    }

    private func labelCount(_ count: Int, key: String) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppColors.primaryText)
            Text(NSLocalizedString(key, comment: ""))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColors.tertiaryText)
        }
        .frame(minWidth: 48)
    }
}

// MARK: - Note content row (no book cover — already in book context)

private struct NoteContentRow: View {
    let note: TimelineNote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Spacer()
                Text(formattedDate(note.date))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            switch note.item {
            case .bookmark(let bm):
                bookmarkContent(bm)
            case .highlight(let hl):
                highlightContent(hl)
            }
        }
    }

    private func bookmarkContent(_ bm: Bookmark) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.accentBlue)
                Text(NSLocalizedString("my_notes_bookmark_label", comment: ""))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColors.accentBlue)
                Spacer()
                if let position = bm.positionText {
                    Text(position)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }

            if let title = bm.locator.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            if let context = bookmarkContext(bm) {
                Text(context)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .lineSpacing(2)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.accentBlue.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func bookmarkContext(_ bm: Bookmark) -> String? {
        let text = bm.locator.text.sanitized()
        let before = text.before?.trimmingCharacters(in: .whitespacesAndNewlines)
        let after = text.after?.trimmingCharacters(in: .whitespacesAndNewlines)

        switch (before?.isEmpty, after?.isEmpty) {
        case (false?, false?):
            return "…\(before!) \(after!)…"
        case (false?, _):
            return "…\(before!)"
        case (_, false?):
            return "\(after!)…"
        default:
            return nil
        }
    }

    private func highlightContent(_ hl: Highlight) -> some View {
        let highlightColor = Color(hl.color.uiColor)
        return VStack(alignment: .leading, spacing: 0) {
            Text(hl.locator.text.sanitized().highlight ?? "")
                .font(.system(size: 14))
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(highlightColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let note = hl.note, !note.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "note.text")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(2)
                        .lineLimit(4)
                }
                .padding(.top, 10)
                .padding(.horizontal, 4)
            }

            if let title = hl.locator.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        NoteContentRow.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}

// MARK: - Models

private struct TimelineNote: Identifiable {
    let id: String
    let book: Book
    let item: NoteItem
    let date: Date

    init(book: Book, item: NoteItem) {
        self.book = book
        self.item = item
        self.id = item.id
        self.date = item.created
    }
}

private enum NoteItem {
    case bookmark(Bookmark)
    case highlight(Highlight)

    var id: String {
        switch self {
        case .bookmark(let bm): return "bm-\(bm.id?.rawValue ?? 0)"
        case .highlight(let hl): return "hl-\(hl.id?.rawValue ?? 0)"
        }
    }

    var locator: Locator {
        switch self {
        case .bookmark(let bm): return bm.locator
        case .highlight(let hl): return hl.locator
        }
    }

    var created: Date {
        switch self {
        case .bookmark(let bm): return bm.created
        case .highlight(let hl): return hl.created
        }
    }
}

// MARK: - Book Cover Thumbnail

private struct BookCoverThumbnail: View {
    let book: Book
    @State private var image: UIImage?
    private static let loader = CoverImageLoader()

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.system(size: 16, weight: .light))
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: book.cover?.url) {
            image = nil
            guard let bookId = book.id, let coverURL = book.cover?.url else { return }
            let loadedImage = await Self.loader.load(
                url: coverURL,
                bookId: bookId.rawValue,
                maxPixelSize: 160
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
        }
    }
}
