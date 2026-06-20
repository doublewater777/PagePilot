import Combine
import ReadiumShared
import SwiftUI
import UIKit

// MARK: - My Notes (timeline)

struct MyNotesView: View {
    @State private var notes: [TimelineNote] = []
    @State private var isLoading = true
    @State private var filter: TimelineFilter = .all

    private let bookmarkRepo: BookmarkRepository
    private let highlightRepo: HighlightRepository
    private let bookRepo: BookRepository

    init() {
        let app = AppModule.shared
        bookmarkRepo = app!.bookmarkRepository
        highlightRepo = app!.highlightRepository
        bookRepo = app!.books
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(AppColors.accentBlue)
                    .scaleEffect(1.2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredNotes.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        filterBar
                        notesList
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
        }
        .background(AppColors.background)
        .navigationTitle(NSLocalizedString("my_notes_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadNotes() }
    }

    private var filteredNotes: [TimelineNote] {
        switch filter {
        case .all:
            return notes
        case .week:
            return notes.filter { $0.date > Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date() }
        case .month:
            return notes.filter { $0.date > Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(NSLocalizedString("my_notes_title", comment: ""))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColors.primaryText)
            Text(NSLocalizedString("my_notes_subtitle", comment: ""))
                .font(.system(size: 14))
                .foregroundStyle(AppColors.secondaryText)
        }
        .padding(.bottom, 18)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(TimelineFilter.allCases) { f in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        filter = f
                    }
                } label: {
                    Text(f.label)
                        .font(.system(size: 13, weight: filter == f ? .semibold : .medium))
                        .foregroundStyle(filter == f ? Color.white : AppColors.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background {
                            if filter == f {
                                AppColors.horizontalGradient
                            } else {
                                AppColors.cardBackground
                            }
                        }
                        .cornerRadius(999)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 24)
    }

    private var notesList: some View {
        LazyVStack(spacing: 16) {
            ForEach(filteredNotes) { note in
                TimelineRow(note: note)
                    .contentShape(Rectangle())
                    .onTapGesture { openReader(for: note) }
            }
        }
    }

    private func openReader(for note: TimelineNote) {
        guard let app = AppModule.shared, let bookId = note.book.id else { return }

        app.pendingNavigationTarget = (bookId, note.item.locator)
        app.didNavigateFromNotes = true

        let tabBar = app.tabBarController
        let nav = app.library.rootViewController
        tabBar?.selectedIndex = 1
        nav.popToRootViewController(animated: false)

        Task {
            guard let pub = try? await app.library.openBook(note.book, sender: nav) else { return }
            app.reader.presentPublication(publication: pub, book: note.book, in: nav)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.tertiary)

            Text(NSLocalizedString(filter == .all ? "my_notes_empty" : "my_notes_filtered_empty", comment: ""))
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
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
        } catch {
            print("MyNotesView: failed to load notes: \(error)")
        }
    }
}

// MARK: - Timeline Filter

private enum TimelineFilter: String, CaseIterable, Identifiable {
    case all
    case week
    case month

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            return NSLocalizedString("my_notes_filter_all", comment: "")
        case .week:
            return NSLocalizedString("my_notes_filter_week", comment: "")
        case .month:
            return NSLocalizedString("my_notes_filter_month", comment: "")
        }
    }
}

// MARK: - Timeline Note

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

// MARK: - Timeline Row

private struct TimelineRow: View {
    let note: TimelineNote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            bookCover
            content
        }
    }

    private var bookCover: some View {
        VStack(spacing: 0) {
            BookCoverThumbnail(book: note.book)
                .frame(width: 32, height: 43)
                .cornerRadius(4)
            Rectangle()
                .fill(AppColors.primaryText.opacity(0.06))
                .frame(width: 1.5)
                .padding(.top, 8)
        }
        .frame(width: 32)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(note.book.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
        .cornerRadius(12)
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
                .cornerRadius(12)

            if let title = hl.locator.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        TimelineRow.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}

// MARK: - Models

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

    var body: some View {
        Group {
            if let cover = book.cover, let image = UIImage(contentsOfFile: cover.path) {
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
        .cornerRadius(6)
    }
}
