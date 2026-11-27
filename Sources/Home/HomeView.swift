//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import ReadiumShared
import SwiftUI
import UIKit

// MARK: - Desk Data Models

struct LastReadBook: Identifiable {
    let id: Book.Id
    let title: String
    let authors: String?
    let coverPath: String?
    let progression: Double

    /// Clamped 0...1 for progress UI.
    var displayProgression: Double {
        min(max(progression, 0), 1)
    }

    var isFinished: Bool {
        progression >= ContinueReadingSelector.finishedProgressThreshold
    }

    var cleanAuthors: String? {
        let trimmed = authors?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed.lowercased() != "unknown" else { return nil }
        return trimmed
    }

    init(book: Book) {
        self.id = book.id!
        self.title = book.title
        self.authors = book.authors
        self.coverPath = book.coverPath
        self.progression = book.progression
    }
}

enum DeskShelfFilter: String, CaseIterable, Identifiable {
    case all
    case reading
    case unread
    case finished

    var id: String { rawValue }

    var title: String {
        NSLocalizedString("library_filter_" + rawValue, comment: "Reading status")
    }

    func matches(_ book: Book) -> Bool {
        switch self {
        case .all:
            return true
        case .reading:
            return book.progression > 0 && book.progression < ContinueReadingSelector.finishedProgressThreshold
        case .unread:
            return book.progression <= 0
        case .finished:
            return book.progression >= ContinueReadingSelector.finishedProgressThreshold
        }
    }
}

enum DeskSortMode: String, CaseIterable, Identifiable {
    case recentRead
    case recentAdded
    case title
    case author

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentRead: return NSLocalizedString("library_sort_recent_read", comment: "")
        case .recentAdded: return NSLocalizedString("library_sort_recent_added", comment: "")
        case .title: return NSLocalizedString("library_sort_title", comment: "")
        case .author: return NSLocalizedString("library_sort_author", comment: "")
        }
    }

    var symbol: String {
        switch self {
        case .recentRead: return "book"
        case .recentAdded: return "clock"
        case .title: return "textformat"
        case .author: return "person"
        }
    }
}

enum DeskViewMode: String {
    case grid
    case list
}

// MARK: - Home / Desk ViewModel

final class HomeViewModel: ObservableObject {
    @Published var lastReadBook: LastReadBook?
    @Published var recentBooks: [LastReadBook] = []
    @Published var allBooks: [Book] = []
    @Published var isEmpty: Bool = true
    @Published var statsRefreshID = UUID()

    @Published var shelfFilter: DeskShelfFilter = .all
    @Published var searchQuery: String = ""
    @Published var sortMode: DeskSortMode {
        didSet {
            UserDefaults.standard.set(sortMode.rawValue, forKey: "LibrarySortMode")
        }
    }
    @Published var viewMode: DeskViewMode {
        didSet {
            UserDefaults.standard.set(viewMode.rawValue, forKey: "LibraryViewMode")
        }
    }

    private let statsStore: ReadingStatsStore

    /// Daily reading goal in minutes.
    var dailyReadingGoalMinutes: Int {
        ReadingPreferences.dailyGoalMinutes
    }

    /// Returns time-based greeting emoji
    var greetingEmoji: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "🌤️"
        case 12..<14: return "☀️"
        case 14..<18: return "🌤️"
        case 18..<22: return "🌙"
        default: return "🌙"
        }
    }

    /// Returns time-based greeting text
    var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return NSLocalizedString("home_greeting_morning", comment: "")
        case 12..<14: return NSLocalizedString("home_greeting_noon", comment: "")
        case 14..<18: return NSLocalizedString("home_greeting_afternoon", comment: "")
        case 18..<22: return NSLocalizedString("home_greeting_evening", comment: "")
        default: return NSLocalizedString("home_greeting_night", comment: "")
        }
    }

    /// Formatted current date and weekday, e.g. "5月28日 · 周三" or "May 28 · Wed"
    var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = AppAppearancePreferences.locale

        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        let dateStr = formatter.string(from: Date())

        formatter.setLocalizedDateFormatFromTemplate("EEE")
        let weekdayStr = formatter.string(from: Date())

        return "\(dateStr) · \(weekdayStr)"
    }

    var filteredBooks: [Book] {
        var result = allBooks.filter { shelfFilter.matches($0) }

        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            result = result.filter { book in
                book.title.localizedCaseInsensitiveContains(trimmed)
                    || (book.authors?.localizedCaseInsensitiveContains(trimmed) ?? false)
            }
        }

        switch sortMode {
        case .recentAdded:
            result.sort { $0.created > $1.created }
        case .recentRead:
            let orderedIds = LastReadBooks.orderedIds
            result.sort { b1, b2 in
                let i1 = b1.id.flatMap { orderedIds.firstIndex(of: $0.rawValue) }
                let i2 = b2.id.flatMap { orderedIds.firstIndex(of: $0.rawValue) }
                switch (i1, i2) {
                case let (a?, b?): return a < b
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return b1.created > b2.created
                }
            }
        case .title:
            result.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .author:
            result.sort { b1, b2 in
                let a1 = b1.authors ?? ""
                let a2 = b2.authors ?? ""
                if a1.isEmpty && !a2.isEmpty { return false }
                if !a1.isEmpty && a2.isEmpty { return true }
                return a1.localizedCompare(a2) == .orderedAscending
            }
        }

        return result
    }

    func count(for filter: DeskShelfFilter) -> Int {
        allBooks.filter { filter.matches($0) }.count
    }

    private let books: BookRepository
    private var latestBooks: [Book] = []
    private var cancellables = Set<AnyCancellable>()

    init(
        books: BookRepository,
        statsStore: ReadingStatsStore = .shared
    ) {
        self.books = books
        self.statsStore = statsStore
        self.sortMode = DeskSortMode(rawValue: UserDefaults.standard.string(forKey: "LibrarySortMode") ?? "") ?? .recentRead
        self.viewMode = DeskViewMode(rawValue: UserDefaults.standard.string(forKey: "LibraryViewMode") ?? "") ?? .grid

        loadLastReadBook()
    }

    private func loadLastReadBook() {
        books.all()
            .receive(on: DispatchQueue.main)
            .sink { _ in } receiveValue: { [weak self] books in
                self?.latestBooks = books
                self?.allBooks = books
                self?.applyContinueReadingSelection()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: LastReadBooks.didChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyContinueReadingSelection()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .readingStatsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.statsRefreshID = UUID()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: ReadingPreferences.dailyGoalDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.statsRefreshID = UUID()
            }
            .store(in: &cancellables)
    }

    /// Re-evaluate continue-reading using current books + MRU list.
    func refreshContinueReading() {
        applyContinueReadingSelection()
    }

    private func applyContinueReadingSelection() {
        let orderedIds = LastReadBooks.orderedIds
        let selected = ContinueReadingSelector.select(
            from: latestBooks,
            lastReadIds: orderedIds
        )
        lastReadBook = selected.map { LastReadBook(book: $0) }
        isEmpty = latestBooks.isEmpty

        let heroId = selected?.id
        let orderedOthers = latestBooks
            .filter { $0.id != nil && $0.id != heroId }
            .sorted { b1, b2 in
                let i1 = b1.id.flatMap { orderedIds.firstIndex(of: $0.rawValue) }
                let i2 = b2.id.flatMap { orderedIds.firstIndex(of: $0.rawValue) }
                switch (i1, i2) {
                case let (a?, b?): return a < b
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return b1.created > b2.created
                }
            }
        recentBooks = orderedOthers.prefix(8).map { LastReadBook(book: $0) }
    }

    /// Today's reading time in minutes
    var todayReadingMinutes: Int {
        statsStore.todayReadingSeconds() / 60
    }

    /// Progress towards daily goal (0.0 to 1.0+)
    var dailyProgress: Double {
        min(Double(todayReadingMinutes) / Double(dailyReadingGoalMinutes), 1.0)
    }

    /// Current reading streak in days (summary scope).
    var currentStreakDays: Int {
        statsStore.snapshot(for: .summary).currentStreakDays
    }

    /// Formatted reading time string
    var formattedReadingTime: String {
        String(format: NSLocalizedString("home_minutes", comment: ""), todayReadingMinutes)
    }

    func stats(for scope: ReadingStatsScope) -> ReadingStatsSnapshot {
        statsStore.snapshot(for: scope)
    }

    func canAccessStats(_ scope: ReadingStatsScope) -> Bool {
        !scope.requiresPro || ProPurchaseManager.shared.hasProAccess
    }
}

// MARK: - Reading Preferences

enum ReadingPreferences {
    enum Keys {
        static let dailyGoalMinutes = "reading_daily_goal_minutes"
        static let reminderEnabled = "reading_reminder_enabled"
        static let reminderHour = "reading_reminder_hour"
        static let reminderMinute = "reading_reminder_minute"
        static let launchDirectlyToReader = "reading_launch_directly_to_reader"
    }

    static let defaultDailyGoalMinutes = 30
    static let dailyGoalRange = 5...180
    static let defaultReminderEnabled = true
    static let defaultReminderHour = 21
    static let defaultReminderMinute = 0
    static let defaultLaunchDirectlyToReader = false
    static let dailyGoalDidChange = Notification.Name("ReadingPreferencesDailyGoalDidChange")

    static var dailyGoalMinutes: Int {
        get {
            let stored = UserDefaults.standard.integer(forKey: Keys.dailyGoalMinutes)
            guard stored > 0 else { return defaultDailyGoalMinutes }
            return min(max(stored, dailyGoalRange.lowerBound), dailyGoalRange.upperBound)
        }
        set {
            let clamped = min(max(newValue, dailyGoalRange.lowerBound), dailyGoalRange.upperBound)
            UserDefaults.standard.set(clamped, forKey: Keys.dailyGoalMinutes)
            NotificationCenter.default.post(name: dailyGoalDidChange, object: clamped)
        }
    }

    static var reminderEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: Keys.reminderEnabled) != nil else {
                return defaultReminderEnabled
            }
            return UserDefaults.standard.bool(forKey: Keys.reminderEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.reminderEnabled) }
    }

    static var reminderHour: Int {
        get {
            guard UserDefaults.standard.object(forKey: Keys.reminderHour) != nil else {
                return defaultReminderHour
            }
            let stored = UserDefaults.standard.integer(forKey: Keys.reminderHour)
            return (0...23).contains(stored) ? stored : defaultReminderHour
        }
        set { UserDefaults.standard.set(min(max(newValue, 0), 23), forKey: Keys.reminderHour) }
    }

    static var reminderMinute: Int {
        get {
            guard UserDefaults.standard.object(forKey: Keys.reminderMinute) != nil else {
                return defaultReminderMinute
            }
            let stored = UserDefaults.standard.integer(forKey: Keys.reminderMinute)
            return (0...59).contains(stored) ? stored : defaultReminderMinute
        }
        set { UserDefaults.standard.set(min(max(newValue, 0), 59), forKey: Keys.reminderMinute) }
    }

    /// Optional Scheme-B behavior: resume the last-read book automatically on cold launch.
    static var launchDirectlyToReader: Bool {
        get {
            guard UserDefaults.standard.object(forKey: Keys.launchDirectlyToReader) != nil else {
                return defaultLaunchDirectlyToReader
            }
            return UserDefaults.standard.bool(forKey: Keys.launchDirectlyToReader)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.launchDirectlyToReader)
        }
    }
}

// MARK: - Reusable Styles and Helpers

struct PremiumButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct CardStyleModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Self.Content) -> some View {
        let radius = AppColors.cardCornerRadius
        content
            .background(
                AppColors.cardBackground,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(
                        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0 : 0.04),
                radius: colorScheme == .dark ? 0 : 12,
                x: 0,
                y: colorScheme == .dark ? 0 : 6
            )
    }
}

extension View {
    func cardStyle() -> some View {
        self.modifier(CardStyleModifier())
    }
}

// MARK: - Unified Desk View (Hero Reading Desk + Editorial Bookshelf)

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    weak var delegate: HomeModuleDelegate?
    @ObservedObject private var watchService = WatchPageTurnService.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var appeared = false
    @State private var progressAnimated = false
    @State private var localizationRefreshID = AppAppearancePreferences.language.rawValue

    // Micro reading sheet
    @State private var selectedMicroReadingMinutes = 5
    @State private var pendingMicroReadingMinutes: Int?
    @State private var pendingMicroReadingBookId: Book.Id?
    @State private var microReadingBook: LastReadBook?

    // Shelf interaction state
    @State private var isSearchVisible = false
    @State private var isEditingShelf = false
    @State private var selectedBookIds: Set<Int64> = []
    @State private var booksPendingDeletion: [Book] = []
    @State private var showDeleteAlert = false
    @State private var showSettingsSheet = false

    var body: some View {
        GeometryReader { proxy in
            let containerWidth = proxy.size.width
            let isWideLayout = containerWidth >= 760
            let horizontalPadding: CGFloat = isWideLayout ? 32 : 18
            let maxContentWidth: CGFloat = isWideLayout ? 1040 : 640
            let effectiveGridWidth = min(containerWidth, maxContentWidth) - horizontalPadding * 2
            let columnCount = Self.gridColumnCount(for: effectiveGridWidth)

            ZStack(alignment: .bottom) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        deskHeader
                            .id(viewModel.statsRefreshID)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 6)
                            .animation(.easeOut(duration: 0.38), value: appeared)

                        if viewModel.isEmpty {
                            emptyStateView
                                .frame(maxWidth: 520)
                                .frame(maxWidth: .infinity)
                        } else {
                            if isWideLayout {
                                HStack(alignment: .top, spacing: 20) {
                                    if let heroBook = viewModel.lastReadBook {
                                        heroDeskCard(for: heroBook)
                                            .frame(maxWidth: .infinity)
                                    }
                                    compactRhythmCard
                                        .id(viewModel.statsRefreshID)
                                        .frame(width: min(350, max(296, containerWidth * 0.34)))
                                }
                            } else if let heroBook = viewModel.lastReadBook {
                                heroDeskCard(for: heroBook)
                                    .opacity(appeared ? 1 : 0)
                                    .offset(y: appeared ? 0 : 10)
                                    .animation(.easeOut(duration: 0.42).delay(0.06), value: appeared)
                            }

                            unifiedBookshelfSection(columnCount: columnCount)
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 12)
                                .animation(.easeOut(duration: 0.42).delay(0.12), value: appeared)
                        }

                        Spacer(minLength: isEditingShelf ? 108 : ((horizontalSizeClass == .regular || UIDevice.current.userInterfaceIdiom == .pad) ? 32 : 96))
                    }
                    .frame(maxWidth: maxContentWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 10)
                }

                if isEditingShelf {
                    editingDeleteBar
                        .padding(.horizontal, horizontalPadding)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .id(localizationRefreshID)
        .onAppear {
            appeared = true
            viewModel.refreshContinueReading()
            withAnimation(.easeOut(duration: 0.7).delay(0.2)) {
                progressAnimated = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppAppearancePreferences.languageDidChange)) { _ in
            localizationRefreshID = AppAppearancePreferences.language.rawValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .readingStatsDidChange)) { _ in
            viewModel.statsRefreshID = UUID()
        }
        .sheet(
            item: $microReadingBook,
            onDismiss: {
                guard let minutes = pendingMicroReadingMinutes,
                      let bookId = pendingMicroReadingBookId else { return }
                pendingMicroReadingMinutes = nil
                pendingMicroReadingBookId = nil
                delegate?.homeDidSelectMicroReading(bookId: bookId, minutes: minutes)
            }
        ) { book in
            MicroReadingStartSheet(
                bookTitle: book.title,
                selectedMinutes: $selectedMicroReadingMinutes,
                onStart: { minutes in
                    pendingMicroReadingMinutes = minutes
                    pendingMicroReadingBookId = book.id
                    microReadingBook = nil
                }
            )
            .appSheetStyle(.compact)
        }
        .sheet(isPresented: $showSettingsSheet) {
            NavigationStack {
                MeView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            SheetCloseButton { showSettingsSheet = false }
                        }
                    }
            }
            .appSheetStyle(.content)
        }
        .alert(
            NSLocalizedString("library_delete_confirm_title", comment: ""),
            isPresented: $showDeleteAlert
        ) {
            Button(NSLocalizedString("library_delete_button", comment: ""), role: .destructive) {
                let targets = booksPendingDeletion
                booksPendingDeletion = []
                Task {
                    await delegate?.homeDidRequestDeleteBooks(targets)
                    await MainActor.run {
                        selectedBookIds.removeAll()
                        isEditingShelf = false
                    }
                }
            }
            Button(NSLocalizedString("cancel_button", comment: ""), role: .cancel) {
                booksPendingDeletion = []
            }
        } message: {
            Text(String(format: NSLocalizedString("library_delete_confirm_message", comment: ""), booksPendingDeletion.count))
        }
    }

    private static func gridColumnCount(for availableWidth: CGFloat) -> Int {
        switch availableWidth {
        case ..<440:
            return 3
        case 440..<680:
            return 4
        case 680..<920:
            return 5
        default:
            return 6
        }
    }

    // MARK: - Editorial Desk Header

    private var deskHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(NSLocalizedString("desk_title", comment: ""))
                    .font(.system(size: 31, weight: .bold, design: .serif))
                    .foregroundStyle(AppColors.primaryText)

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    delegate?.homeDidRequestJournal()
                } label: {
                    HStack(spacing: 5) {
                        Text(viewModel.dateText)
                        Text("·")
                        Text(
                            String(
                                format: NSLocalizedString("desk_today_progress_format", comment: ""),
                                viewModel.todayReadingMinutes,
                                viewModel.dailyReadingGoalMinutes
                            )
                        )
                        .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9.5, weight: .bold))
                            .opacity(0.65)
                    }
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
                    .lineLimit(1)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if isWatchConnected {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        delegate?.homeDidRequestWatchSettings()
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(AppColors.accentTeal)
                                .frame(width: 6, height: 6)
                            Image(systemName: "applewatch")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text(NSLocalizedString("desk_watch_pill", comment: ""))
                                .font(.system(size: 11.5, weight: .bold))
                        }
                        .foregroundStyle(AppColors.accentTeal)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(
                            AppColors.accentTeal.opacity(colorScheme == .dark ? 0.18 : 0.11),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(PremiumButtonStyle())
                }

                Menu {
                    Button {
                        delegate?.homeDidRequestImportLocalFiles()
                    } label: {
                        Label(NSLocalizedString("library_import_local", comment: ""), systemImage: "folder")
                    }
                    Button {
                        delegate?.homeDidRequestWiFiTransfer()
                    } label: {
                        Label(NSLocalizedString("library_wifi_transfer", comment: ""), systemImage: "wifi")
                    }
                    Button {
                        delegate?.homeDidRequestDeviceTransfer(books: viewModel.allBooks)
                    } label: {
                        Label(NSLocalizedString("library_device_transfer", comment: ""), systemImage: "ipad.and.iphone")
                    }
                    Button {
                        delegate?.homeDidRequestOPDSFeeds()
                    } label: {
                        Label(NSLocalizedString("opds_add_feed", comment: ""), systemImage: "books.vertical")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.primaryText)
                        .frame(width: 34, height: 34)
                        .background(AppColors.cardBackground, in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.07), lineWidth: 0.75)
                        )
                }
                .accessibilityLabel(NSLocalizedString("library_import_local", comment: ""))

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showSettingsSheet = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.primaryText)
                        .frame(width: 34, height: 34)
                        .background(AppColors.cardBackground, in: Circle())
                        .overlay(
                            Circle()
                                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.1 : 0.07), lineWidth: 0.75)
                        )
                }
                .buttonStyle(PremiumButtonStyle())
                .accessibilityLabel(NSLocalizedString("settings_title", comment: ""))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isWatchConnected: Bool {
        if PagePilotReaderHost.isSupported {
            return watchService.peerHostState.connectedPeerCount > 0
        }
        return watchService.watchAvailability == .ready
    }

    // MARK: - Hero Desk Card ("此刻书桌")

    private func heroDeskCard(for book: LastReadBook) -> some View {
        let palette = GeneratedBookCover.palette(for: book.title)
        let pct = Int((book.displayProgression * 100).rounded())

        return VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    delegate?.homeDidSelectContinueReading(bookId: book.id)
                } label: {
                    Color.clear
                        .frame(width: 90, height: 132)
                        .overlay {
                            DeskBookCoverView(
                                bookId: book.id,
                                title: book.title,
                                author: book.cleanAuthors,
                                coverPath: book.coverPath,
                                maxPixelSize: 360
                            )
                        }
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            hardcoverSpineOverlay(cornerRadius: 10)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.6)
                        )
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.17), radius: 12, x: 0, y: 6)
                }
                .buttonStyle(PremiumButtonStyle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("desk_hero_kicker", comment: ""))
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(AppColors.accentTeal)

                    Text(book.title)
                        .font(.system(size: 19, weight: .bold, design: .serif))
                        .foregroundStyle(AppColors.primaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    if let authors = book.cleanAuthors {
                        Text(authors)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.secondaryText)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if book.isFinished {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text(NSLocalizedString("home_finished_label", comment: ""))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.accentTeal)
                    }

                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(AppColors.progressTrack)

                                let fillWidth = geo.size.width * book.displayProgression
                                if fillWidth > 0 {
                                    Capsule()
                                        .fill(AppColors.horizontalGradient)
                                        .frame(width: max(6, fillWidth))
                                }
                            }
                        }
                        .frame(height: 5)

                        Text("\(pct)%")
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(AppColors.accentBlue)
                    }
                }
                .frame(minHeight: 132)
            }

            HStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    delegate?.homeDidSelectContinueReading(bookId: book.id)
                } label: {
                    HStack(spacing: 7) {
                        Text(NSLocalizedString(
                            book.isFinished ? "home_reread_button" : "desk_open_continue_button",
                            comment: ""
                        ))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        colorScheme == .dark
                            ? Color(red: 244 / 255, green: 242 / 255, blue: 236 / 255)
                            : Color(red: 27 / 255, green: 28 / 255, blue: 30 / 255),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                }
                .buttonStyle(PremiumButtonStyle())

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    delegate?.homeDidSelectMicroReading(bookId: book.id, minutes: 5)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "timer")
                            .font(.system(size: 13.5, weight: .semibold))
                        Text(NSLocalizedString("desk_micro_5min_button", comment: ""))
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(AppColors.accentTeal)
                    .padding(.horizontal, 13)
                    .frame(height: 44)
                    .background(
                        AppColors.accentTeal.opacity(colorScheme == .dark ? 0.18 : 0.1),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(AppColors.accentTeal.opacity(0.24), lineWidth: 0.75)
                    )
                }
                .buttonStyle(PremiumButtonStyle())
                .contextMenu {
                    ForEach(MicroReadingPolicy.supportedMinutes, id: \.self) { minutes in
                        Button {
                            delegate?.homeDidSelectMicroReading(bookId: book.id, minutes: minutes)
                        } label: {
                            Label(
                                String(
                                    format: NSLocalizedString("micro_reading_start_format", comment: ""),
                                    MicroReadingPolicy.localizedDuration(forMinutes: minutes)
                                ),
                                systemImage: "timer"
                            )
                        }
                    }
                    Button {
                        selectedMicroReadingMinutes = 5
                        microReadingBook = book
                    } label: {
                        Label(NSLocalizedString("micro_reading_title", comment: ""), systemImage: "slider.horizontal.3")
                    }
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color(uiColor: palette.top).opacity(colorScheme == .dark ? 0.18 : 0.09),
                    Color.clear,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .background(
            AppColors.cardBackground,
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 14, x: 0, y: 7)
    }

    // MARK: - Compact Rhythm Card (iPad Wide Companion)

    private var compactRhythmCard: some View {
        let ringProgress = progressAnimated ? viewModel.dailyProgress : 0
        let todayStats = viewModel.stats(for: .day)

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            delegate?.homeDidRequestJournal()
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(NSLocalizedString("home_daily_goal", comment: ""))
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(AppColors.secondaryText)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.tertiaryText)
                }

                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(AppColors.progressTrack, lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: CGFloat(max(0, min(1, ringProgress))))
                            .stroke(AppColors.accentGradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: 1) {
                            Text("\(viewModel.todayReadingMinutes)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(AppColors.primaryText)
                            Text("\(Int((viewModel.dailyProgress * 100).rounded()))%")
                                .font(.system(size: 10, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(AppColors.accentBlue)
                        }
                    }
                    .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(viewModel.todayReadingMinutes)")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(AppColors.primaryText)
                            Text(String(format: NSLocalizedString("home_daily_goal_of", comment: ""), viewModel.dailyReadingGoalMinutes))
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundStyle(AppColors.secondaryText)
                        }

                        HStack(spacing: 10) {
                            Label("\(todayStats.sessions)", systemImage: "timer")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(AppColors.secondaryText)
                            Label("\(viewModel.currentStreakDays)", systemImage: viewModel.currentStreakDays > 0 ? "flame.fill" : "flame")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(viewModel.currentStreakDays > 0 ? .orange : AppColors.secondaryText)
                        }
                        .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 4)

                Text(NSLocalizedString("desk_open_journal_hint", comment: ""))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.accentBlue)
                    .padding(.top, 2)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 228, alignment: .topLeading)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0 : 0.05), radius: 14, x: 0, y: 7)
        }
        .buttonStyle(PremiumButtonStyle())
    }

    // MARK: - Unified Bookshelf ("精装书架")

    private func unifiedBookshelfSection(columnCount: Int) -> some View {
        let books = viewModel.filteredBooks

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(NSLocalizedString("desk_bookshelf_section", comment: ""))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.primaryText)

                Spacer(minLength: 8)

                if isEditingShelf {
                    Button(NSLocalizedString("cancel_button", comment: "")) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            isEditingShelf = false
                            selectedBookIds.removeAll()
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.accentBlue)
                } else {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                            isSearchVisible.toggle()
                            if !isSearchVisible {
                                viewModel.searchQuery = ""
                            }
                        }
                    } label: {
                        Image(systemName: isSearchVisible ? "xmark.circle.fill" : "magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSearchVisible ? AppColors.accentBlue : AppColors.secondaryText)
                            .frame(width: 30, height: 30)
                            .background(AppColors.cardBackground, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(NSLocalizedString("library_search_placeholder", comment: ""))

                    Menu {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                isEditingShelf = true
                                isSearchVisible = false
                                viewModel.searchQuery = ""
                                selectedBookIds.removeAll()
                            }
                        } label: {
                            Label(NSLocalizedString("library_select_books", comment: ""), systemImage: "checkmark.circle")
                        }

                        Menu {
                            Button {
                                viewModel.viewMode = .grid
                            } label: {
                                Label(
                                    NSLocalizedString("library_view_mode_grid", comment: ""),
                                    systemImage: viewModel.viewMode == .grid ? "checkmark" : "square.grid.2x2"
                                )
                            }
                            Button {
                                viewModel.viewMode = .list
                            } label: {
                                Label(
                                    NSLocalizedString("library_view_mode_list", comment: ""),
                                    systemImage: viewModel.viewMode == .list ? "checkmark" : "list.bullet"
                                )
                            }
                        } label: {
                            Label(NSLocalizedString("library_view_mode_title", comment: ""), systemImage: "square.grid.2x2")
                        }

                        Menu {
                            ForEach(DeskSortMode.allCases) { mode in
                                Button {
                                    viewModel.sortMode = mode
                                } label: {
                                    Label(
                                        mode.title,
                                        systemImage: viewModel.sortMode == mode ? "checkmark" : mode.symbol
                                    )
                                }
                            }
                        } label: {
                            Label(NSLocalizedString("library_sort_title_menu", comment: ""), systemImage: "arrow.up.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.secondaryText)
                            .frame(width: 30, height: 30)
                            .background(AppColors.cardBackground, in: Circle())
                    }
                }
            }

            if isSearchVisible {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.tertiaryText)
                    TextField(NSLocalizedString("library_search_placeholder", comment: ""), text: $viewModel.searchQuery)
                        .font(.system(size: 14.5))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !viewModel.searchQuery.isEmpty {
                        Button {
                            viewModel.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppColors.tertiaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06), lineWidth: 0.75)
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Status filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(DeskShelfFilter.allCases) { filter in
                        let isSelected = viewModel.shelfFilter == filter
                        let count = viewModel.count(for: filter)
                        let label = count > 0 ? "\(filter.title) \(count)" : filter.title

                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.easeOut(duration: 0.2)) {
                                viewModel.shelfFilter = filter
                            }
                        } label: {
                            Text(label)
                                .font(.system(size: 12.5, weight: isSelected ? .bold : .semibold))
                                .monospacedDigit()
                                .foregroundStyle(
                                    isSelected
                                        ? (colorScheme == .dark ? Color.black : Color.white)
                                        : AppColors.secondaryText
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    isSelected
                                        ? (colorScheme == .dark
                                            ? Color(red: 244 / 255, green: 242 / 255, blue: 236 / 255)
                                            : Color(red: 27 / 255, green: 28 / 255, blue: 30 / 255))
                                        : AppColors.cardBackground,
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            isSelected ? .clear : Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06),
                                            lineWidth: 0.75
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            // Books grid or list
            if books.isEmpty {
                filteredEmptyView
            } else if viewModel.viewMode == .list {
                LazyVStack(spacing: 10) {
                    ForEach(books, id: \.url) { book in
                        shelfBookListRow(book)
                    }
                }
            } else {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: columnCount)
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(books, id: \.url) { book in
                        shelfBookGridCell(book)
                    }
                }
            }
        }
    }

    private func shelfBookGridCell(_ book: Book) -> some View {
        let bookRawId = book.id?.rawValue ?? -1
        let isSelected = selectedBookIds.contains(bookRawId)
        let pct = Int((min(max(book.progression, 0), 1) * 100).rounded())
        let isFinished = book.progression >= ContinueReadingSelector.finishedProgressThreshold
        let cleanAuthor = cleanedAuthor(book.authors)

        return Button {
            handleBookTap(book)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                ZStack(alignment: .bottomLeading) {
                    Color.clear
                        .aspectRatio(2.0 / 3.0, contentMode: .fit)
                        .overlay {
                            DeskBookCoverView(
                                bookId: book.id,
                                title: book.title,
                                author: cleanAuthor,
                                coverPath: book.coverPath,
                                maxPixelSize: 320
                            )
                        }
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            hardcoverSpineOverlay(cornerRadius: 8)
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(
                                    isSelected ? AppColors.accentBlue : Color.primary.opacity(0.08),
                                    lineWidth: isSelected ? 2.5 : 0.5
                                )
                        )
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.38 : 0.14), radius: 8, x: 0, y: 4)

                    if book.progression > 0 && !isFinished {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle().fill(Color.black.opacity(0.32))
                                Rectangle()
                                    .fill(AppColors.accentTeal)
                                    .frame(width: max(4, geo.size.width * min(max(book.progression, 0), 1)))
                            }
                        }
                        .frame(height: 3)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    if isEditingShelf {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(isSelected ? AppColors.accentBlue : .white)
                            .shadow(color: .black.opacity(0.4), radius: 3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(6)
                    }
                }

                Text(book.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(AppColors.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(bookStatusCaption(progression: book.progression, pct: pct, isFinished: isFinished))
                    .font(.system(size: 10.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isFinished ? AppColors.accentTeal : AppColors.tertiaryText)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PremiumButtonStyle())
        .contextMenu {
            bookContextMenu(for: book)
        }
    }

    private func shelfBookListRow(_ book: Book) -> some View {
        let bookRawId = book.id?.rawValue ?? -1
        let isSelected = selectedBookIds.contains(bookRawId)
        let pct = Int((min(max(book.progression, 0), 1) * 100).rounded())
        let isFinished = book.progression >= ContinueReadingSelector.finishedProgressThreshold
        let cleanAuthor = cleanedAuthor(book.authors)

        return Button {
            handleBookTap(book)
        } label: {
            HStack(spacing: 14) {
                if isEditingShelf {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(isSelected ? AppColors.accentBlue : AppColors.tertiaryText)
                }

                Color.clear
                    .frame(width: 52, height: 76)
                    .overlay {
                        DeskBookCoverView(
                            bookId: book.id,
                            title: book.title,
                            author: cleanAuthor,
                            coverPath: book.coverPath,
                            maxPixelSize: 200
                        )
                    }
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        hardcoverSpineOverlay(cornerRadius: 7)
                    }
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 6, y: 3)

                VStack(alignment: .leading, spacing: 5) {
                    Text(book.title)
                        .font(.system(size: 15, weight: .bold, design: .serif))
                        .foregroundStyle(AppColors.primaryText)
                        .lineLimit(2)

                    if let cleanAuthor {
                        Text(cleanAuthor)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(AppColors.secondaryText)
                            .lineLimit(1)
                    }

                    Text(bookStatusCaption(progression: book.progression, pct: pct, isFinished: isFinished))
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isFinished ? AppColors.accentTeal : AppColors.accentBlue)
                }

                Spacer(minLength: 6)

                if !isEditingShelf {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.tertiaryText)
                }
            }
            .padding(12)
            .cardStyle()
            .contentShape(Rectangle())
        }
        .buttonStyle(PremiumButtonStyle())
        .contextMenu {
            bookContextMenu(for: book)
        }
    }

    @ViewBuilder
    private func bookContextMenu(for book: Book) -> some View {
        if let id = book.id {
            Button {
                delegate?.homeDidSelectContinueReading(bookId: id)
            } label: {
                Label(NSLocalizedString("home_continue_reading_button", comment: ""), systemImage: "book.pages")
            }

            Button {
                delegate?.homeDidSelectMicroReading(bookId: id, minutes: 5)
            } label: {
                Label(NSLocalizedString("desk_micro_5min_button", comment: ""), systemImage: "timer")
            }
        }

        Button {
            delegate?.homeDidRequestBookDetails(book: book)
        } label: {
            Label(NSLocalizedString("library_context_details", comment: ""), systemImage: "info.circle")
        }

        Button(role: .destructive) {
            booksPendingDeletion = [book]
            showDeleteAlert = true
        } label: {
            Label(NSLocalizedString("delete_button", comment: ""), systemImage: "trash")
        }
    }

    private func handleBookTap(_ book: Book) {
        if isEditingShelf {
            guard let id = book.id?.rawValue else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            if selectedBookIds.contains(id) {
                selectedBookIds.remove(id)
            } else {
                selectedBookIds.insert(id)
            }
            return
        }
        guard let id = book.id else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        delegate?.homeDidSelectContinueReading(bookId: id)
    }

    private var editingDeleteBar: some View {
        let count = selectedBookIds.count
        return HStack(spacing: 12) {
            Button {
                let targets = viewModel.allBooks.filter { book in
                    guard let id = book.id?.rawValue else { return false }
                    return selectedBookIds.contains(id)
                }
                guard !targets.isEmpty else { return }
                booksPendingDeletion = targets
                showDeleteAlert = true
            } label: {
                Text(
                    count > 0
                        ? String(format: NSLocalizedString("library_delete_selected_count", comment: ""), count)
                        : NSLocalizedString("library_delete_books", comment: "")
                )
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color.red.opacity(count > 0 ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(count == 0)
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: 520)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.75)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 18, y: 8)
    }

    private var filteredEmptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: viewModel.searchQuery.isEmpty ? "books.vertical" : "magnifyingglass")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AppColors.tertiaryText)
            Text(NSLocalizedString(
                viewModel.searchQuery.isEmpty ? "library_empty_filtered" : "library_empty_search",
                comment: ""
            ))
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(AppColors.secondaryText)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .cardStyle()
    }

    // MARK: - Empty State (Zero Books)

    private var emptyStateView: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                if UIImage(named: "EmptyLibraryArt") != nil {
                    Image("EmptyLibraryArt")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 210, height: 152)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06), lineWidth: 0.75)
                        )
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.08), radius: 14, y: 6)
                        .padding(.bottom, 4)
                        .accessibilityHidden(true)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(AppColors.accentGradientStart.opacity(colorScheme == .dark ? 0.22 : 0.12))
                            .frame(width: 68, height: 68)

                        Image(systemName: "books.vertical")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(AppColors.accentGradientStart)
                    }
                    .padding(.bottom, 4)
                }

                Text(NSLocalizedString("home_empty_title", comment: ""))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppColors.primaryText)

                Text(NSLocalizedString("home_empty_message", comment: ""))
                    .font(.system(size: 14.5))
                    .foregroundColor(AppColors.secondaryText)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            Menu {
                Button {
                    delegate?.homeDidRequestImportLocalFiles()
                } label: {
                    Label(NSLocalizedString("library_import_local", comment: ""), systemImage: "folder")
                }
                Button {
                    delegate?.homeDidRequestWiFiTransfer()
                } label: {
                    Label(NSLocalizedString("library_wifi_transfer", comment: ""), systemImage: "wifi")
                }
                Button {
                    delegate?.homeDidRequestOPDSFeeds()
                } label: {
                    Label(NSLocalizedString("opds_add_feed", comment: ""), systemImage: "books.vertical")
                }
            } label: {
                HStack(spacing: 6) {
                    Text(NSLocalizedString("home_import_button", comment: ""))
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColors.horizontalGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(24)
        .cardStyle()
    }

    // MARK: - Helpers

    private func hardcoverSpineOverlay(cornerRadius: CGFloat) -> some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [Color.black.opacity(0.2), Color.white.opacity(0.22), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 6)
            Spacer()
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
    }

    private func cleanedAuthor(_ authors: String?) -> String? {
        let trimmed = authors?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed.lowercased() != "unknown" else { return nil }
        return trimmed
    }

    private func bookStatusCaption(progression: Double, pct: Int, isFinished: Bool) -> String {
        if isFinished {
            return "✓ " + NSLocalizedString("home_finished_label", comment: "")
        }
        if progression > 0 {
            return "\(pct)%"
        }
        return NSLocalizedString("library_filter_unread", comment: "")
    }
}

// MARK: - Cached Async Hardcover Cover View

private struct DeskBookCoverView: View {
    let bookId: Book.Id?
    let title: String
    let author: String?
    let coverPath: String?
    let maxPixelSize: Int

    @State private var loadedImage: UIImage?
    private static let loader = CoverImageLoader()

    var body: some View {
        Group {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                GeneratedBookCoverView(title: title, author: author)
            }
        }
        .task(id: coverPath) {
            loadedImage = nil
            guard let coverPath, let bookId else { return }
            let url = Paths.covers.appendingPath(coverPath, isDirectory: false).url
            let image = await Self.loader.load(url: url, bookId: bookId.rawValue, maxPixelSize: maxPixelSize)
            guard !Task.isCancelled else { return }
            loadedImage = image
        }
    }
}
