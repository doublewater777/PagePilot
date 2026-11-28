//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import ReadiumShared
import SwiftUI
import UIKit

// MARK: - Journal Root Navigation Controller

final class JournalNavigationController: UINavigationController {
    private var didBecomeActiveObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.enforceHiddenNavigationBar()
        }
        enforceHiddenNavigationBar()
    }

    deinit {
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enforceHiddenNavigationBar()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        enforceHiddenNavigationBar()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        enforceHiddenNavigationBar()
    }

    private func enforceHiddenNavigationBar() {
        guard topViewController === viewControllers.first else { return }
        guard !isNavigationBarHidden else { return }
        setNavigationBarHidden(true, animated: false)
    }
}

// MARK: - Unified Journal View ("印记" = Rhythm + Quote Card Box)

struct JournalView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject private var proPurchase = ProPurchaseManager.shared
    @ObservedObject private var intelligenceEngine = ReadingIntelligenceEngine.shared

    @State private var entries: [JournalEntry] = []
    @State private var isLoading = true
    @State private var filter: JournalFilter = .all
    @State private var highlightCount = 0
    @State private var statsRefreshID = UUID()
    @State private var localizationRefreshID = AppAppearancePreferences.language.rawValue

    @State private var showFullStats = false
    @State private var showSettingsSheet = false
    @State private var showPaywall = false
    @State private var showQuoteInsights = false
    @State private var postcardPayload: QuotePostcardPayload?
    @State private var entryPendingDeletion: JournalEntry?
    @State private var showDeleteConfirmation = false
    @State private var deleteErrorMessage: String?

    private let statsStore = ReadingStatsStore.shared

    private enum JournalFilter: String, CaseIterable, Identifiable {
        case all
        case highlights
        case bookmarks

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return NSLocalizedString("my_notes_filter_all", comment: "")
            case .highlights: return NSLocalizedString("my_notes_highlights_label", comment: "")
            case .bookmarks: return NSLocalizedString("my_notes_bookmarks_label", comment: "")
            }
        }
    }

    private var filteredEntries: [JournalEntry] {
        switch filter {
        case .all:
            return entries
        case .highlights:
            return entries.filter { if case .highlight = $0.kind { return true }; return false }
        case .bookmarks:
            return entries.filter { if case .bookmark = $0.kind { return true }; return false }
        }
    }

    private var bookmarkCount: Int {
        entries.reduce(0) { count, entry in
            if case .bookmark = entry.kind { return count + 1 }
            return count
        }
    }

    private var showQuotaBanner: Bool {
        !proPurchase.hasProAccess && highlightCount >= NotesQuota.warningThreshold
    }

    var body: some View {
        GeometryReader { proxy in
            let containerWidth = proxy.size.width
            let isWideLayout = containerWidth >= 760
            let horizontalPadding: CGFloat = isWideLayout ? 32 : 18

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    journalHeader

                    if isWideLayout {
                        HStack(alignment: .top, spacing: 22) {
                            VStack(alignment: .leading, spacing: 14) {
                                rhythmSummaryCards
                                fourWeekHeatmapCard
                            }
                            .id(statsRefreshID)
                            .frame(width: min(370, max(310, containerWidth * 0.38)))

                            quoteBoxSection
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            rhythmSummaryCards
                            fourWeekHeatmapCard
                        }
                        .id(statsRefreshID)

                        quoteBoxSection
                    }

                    Spacer(minLength: (horizontalSizeClass == .regular || UIDevice.current.userInterfaceIdiom == .pad) ? 32 : 96)
                }
                .frame(maxWidth: isWideLayout ? 1040 : 620)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 10)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .id(localizationRefreshID)
        .task { await reloadJournal() }
        .onAppear {
            statsRefreshID = UUID()
            Task { await reloadJournal(showSpinner: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readingStatsDidChange)) { _ in
            statsRefreshID = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppAppearancePreferences.languageDidChange)) { _ in
            localizationRefreshID = AppAppearancePreferences.language.rawValue
        }
        .sheet(isPresented: $showFullStats) {
            NavigationStack {
                ReadingStatsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            SheetCloseButton { showFullStats = false }
                        }
                    }
            }
            .appSheetStyle(.content)
        }
        .sheet(item: $postcardPayload) { payload in
            QuotePostcardView(payload: payload)
                .appSheetStyle(.content)
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
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showQuoteInsights) {
            ReadingIntelligenceSheet(task: .quoteInsights(quotes: quoteSamplesForInsights))
                .appSheetStyle(.content)
        }
        .alert(
            NSLocalizedString("my_notes_delete_confirm_title", comment: ""),
            isPresented: $showDeleteConfirmation
        ) {
            Button(NSLocalizedString("delete_button", comment: ""), role: .destructive) {
                guard let target = entryPendingDeletion else { return }
                entryPendingDeletion = nil
                Task { await deleteEntry(target) }
            }
            Button(NSLocalizedString("cancel_button", comment: ""), role: .cancel) {
                entryPendingDeletion = nil
            }
        }
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

    // MARK: - Header

    private var journalHeader: some View {
        let todaySeconds = statsStore.todayReadingSeconds()
        let goalMinutes = ReadingPreferences.dailyGoalMinutes
        let streakDays = statsStore.snapshot(for: .summary).currentStreakDays
        let mascotMood = MascotMoodPolicy.resolve(
            todaySeconds: todaySeconds,
            dailyGoalMinutes: goalMinutes,
            streakDays: streakDays,
            hour: MascotMoodPolicy.currentHour(),
            hasBooks: true
        )

        return HStack(alignment: .center, spacing: 10) {
            PilotOwlMascotView(mood: mascotMood, size: 46, animated: true, showSoftGlow: true)

            VStack(alignment: .leading, spacing: 3) {
                Text(NSLocalizedString("journal_title", comment: ""))
                    .font(.system(size: 31, weight: .bold, design: .serif))
                    .foregroundStyle(AppColors.primaryText)

                Text(NSLocalizedString("journal_subtitle", comment: ""))
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(AppColors.secondaryText)
            }

            Spacer(minLength: 8)

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

    // MARK: - Rhythm Summary & 4-Week Heatmap

    private var rhythmSummaryCards: some View {
        let todayMinutes = statsStore.todayReadingSeconds() / 60
        let goalMinutes = ReadingPreferences.dailyGoalMinutes
        let streakDays = statsStore.snapshot(for: .summary).currentStreakDays

        return HStack(spacing: 12) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showFullStats = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(todayMinutes)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(AppColors.primaryText)
                        Text(NSLocalizedString("stats_minutes_unit", comment: ""))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    Text(String(format: NSLocalizedString("journal_today_goal_format", comment: ""), goalMinutes))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .cardStyle()
            }
            .buttonStyle(PremiumButtonStyle())

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showFullStats = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(streakDays)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(streakDays > 0 ? Color.orange : AppColors.primaryText)
                        Text(NSLocalizedString("share_card_days", comment: ""))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    Text(String(format: NSLocalizedString("journal_streak_quotes_format", comment: ""), highlightCount))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .cardStyle()
            }
            .buttonStyle(PremiumButtonStyle())
        }
    }

    private var fourWeekHeatmapCard: some View {
        let cells = makeRecent28DayHeatmap()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 14)

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showFullStats = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(NSLocalizedString("journal_heatmap_title", comment: ""))
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(AppColors.primaryText)
                    Spacer()
                    HStack(spacing: 4) {
                        Text(NSLocalizedString("journal_view_full_stats", comment: ""))
                            .font(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(AppColors.accentBlue)
                }

                LazyVGrid(columns: columns, spacing: 5) {
                    ForEach(cells) { cell in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(heatmapColor(for: cell.level))
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            }
            .padding(16)
            .cardStyle()
        }
        .buttonStyle(PremiumButtonStyle())
    }

    private struct HeatmapDayCell: Identifiable {
        let id: String
        let level: Int
    }

    private func makeRecent28DayHeatmap() -> [HeatmapDayCell] {
        let snapshot = statsStore.snapshot(for: .summary)
        let secondsByKey = Dictionary(uniqueKeysWithValues: snapshot.dailyStats.map { ($0.dateKey, $0.seconds) })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let goalSeconds = max(60, ReadingPreferences.dailyGoalMinutes * 60)

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        return (0..<28).reversed().map { offset in
            let date = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            let key = formatter.string(from: date)
            let secs = secondsByKey[key] ?? 0
            let level: Int
            if secs <= 0 {
                level = 0
            } else if secs < goalSeconds / 2 {
                level = 1
            } else if secs < goalSeconds {
                level = 2
            } else {
                level = 3
            }
            return HeatmapDayCell(id: key, level: level)
        }
    }

    private func heatmapColor(for level: Int) -> Color {
        switch level {
        case 1:
            return AppColors.accentBlue.opacity(colorScheme == .dark ? 0.35 : 0.25)
        case 2:
            return AppColors.accentBlue.opacity(colorScheme == .dark ? 0.65 : 0.55)
        case 3:
            return AppColors.accentTeal
        default:
            return Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06)
        }
    }

    // MARK: - Quote Card Box ("书摘卡片盒")

    private var quoteSamplesForInsights: [ReadingQuoteSample] {
        entries.compactMap { entry in
            guard case let .highlight(hl) = entry.kind else { return nil }
            let raw = hl.locator.text.sanitized().highlight ?? hl.locator.text.highlight ?? ""
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return ReadingQuoteSample(
                text: trimmed,
                note: hl.note,
                bookTitle: entry.book.title,
                chapterTitle: hl.locator.title
            )
        }
    }

    private var quoteBoxSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(NSLocalizedString("journal_quote_box_title", comment: ""))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.primaryText)
                Spacer()
                if intelligenceEngine.isFeatureAvailable && !quoteSamplesForInsights.isEmpty {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showQuoteInsights = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                            Text(NSLocalizedString("ai_quote_insights_button", comment: ""))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.accentTeal)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColors.accentTeal.opacity(colorScheme == .dark ? 0.18 : 0.11), in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(NSLocalizedString("journal_quote_box_hint", comment: ""))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(AppColors.tertiaryText)
                }
            }

            if showQuotaBanner {
                Button {
                    Analytics.shared.log(.paywallViewed(source: "notes_quota_banner"))
                    showPaywall = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "highlighter")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.orange)
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
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            // Filter pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(JournalFilter.allCases) { item in
                        let isSelected = filter == item
                        let count: Int = {
                            switch item {
                            case .all: return entries.count
                            case .highlights: return highlightCount
                            case .bookmarks: return bookmarkCount
                            }
                        }()
                        let title = count > 0 ? "\(item.title) \(count)" : item.title

                        Button {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.easeOut(duration: 0.2)) {
                                filter = item
                            }
                        } label: {
                            Text(title)
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

            if isLoading {
                ProgressView()
                    .tint(AppColors.accentBlue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
            } else if filteredEntries.isEmpty {
                emptyQuotesCard
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredEntries) { entry in
                        journalEntryCard(entry)
                    }
                }
            }
        }
    }

    private func journalEntryCard(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch entry.kind {
            case .highlight(let highlight):
                let quote = highlight.locator.text.sanitized().highlight ?? ""
                let barColor = Color(highlight.color.uiColor)

                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(barColor)
                        .frame(width: 3)

                    Text(quote)
                        .font(.system(size: 14.5, weight: .regular, design: .serif))
                        .foregroundStyle(AppColors.primaryText)
                        .lineSpacing(5)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let note = highlight.note, !note.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "pencil.line")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColors.accentTeal)
                            .padding(.top, 2)
                        Text(note)
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.secondaryText)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                HStack(spacing: 8) {
                    Text("\(entry.book.title) · \(Self.shortDateFormatter.string(from: entry.date))")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(AppColors.tertiaryText)
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    if !quote.isEmpty {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            postcardPayload = QuotePostcardPayload(
                                id: entry.id,
                                quote: quote,
                                note: highlight.note,
                                bookTitle: entry.book.title,
                                author: entry.book.authors,
                                chapterTitle: highlight.locator.title,
                                date: entry.date
                            )
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10.5, weight: .bold))
                                Text(NSLocalizedString("quote_postcard_action_short", comment: ""))
                                    .font(.system(size: 11.5, weight: .bold))
                            }
                            .foregroundStyle(AppColors.accentBlue)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(AppColors.accentBlue.opacity(colorScheme == .dark ? 0.2 : 0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

            case .bookmark(let bookmark):
                HStack(spacing: 6) {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColors.accentBlue)
                    Text(bookmark.locator.title?.isEmpty == false ? bookmark.locator.title! : NSLocalizedString("my_notes_bookmark_label", comment: ""))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.primaryText)
                        .lineLimit(1)
                    Spacer()
                    if let pos = bookmark.positionText {
                        Text(pos)
                            .font(.system(size: 11.5, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(AppColors.tertiaryText)
                    }
                }

                if let context = bookmarkExcerpt(bookmark) {
                    Text(context)
                        .font(.system(size: 13.5, design: .serif))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(2)
                        .lineSpacing(3)
                }

                Text("\(entry.book.title) · \(Self.shortDateFormatter.string(from: entry.date))")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppColors.tertiaryText)
                    .lineLimit(1)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .contentShape(Rectangle())
        .onTapGesture {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            AppModule.shared?.openBook(entry.book, locator: entry.locator)
        }
        .contextMenu {
            Button {
                AppModule.shared?.openBook(entry.book, locator: entry.locator)
            } label: {
                Label(NSLocalizedString("home_continue_reading_button", comment: ""), systemImage: "book.pages")
            }

            if case .highlight(let highlight) = entry.kind,
               let quote = highlight.locator.text.sanitized().highlight,
               !quote.isEmpty {
                Button {
                    postcardPayload = QuotePostcardPayload(
                        id: entry.id,
                        quote: quote,
                        note: highlight.note,
                        bookTitle: entry.book.title,
                        author: entry.book.authors,
                        chapterTitle: highlight.locator.title,
                        date: entry.date
                    )
                } label: {
                    Label(NSLocalizedString("quote_postcard_title", comment: ""), systemImage: "sparkles")
                }

                Button {
                    UIPasteboard.general.string = quote
                } label: {
                    Label(NSLocalizedString("reader_copy", comment: ""), systemImage: "doc.on.doc")
                }
            }

            Button(role: .destructive) {
                entryPendingDeletion = entry
                showDeleteConfirmation = true
            } label: {
                Label(NSLocalizedString("delete_button", comment: ""), systemImage: "trash")
            }
        }
    }

    private var emptyQuotesCard: some View {
        VStack(spacing: 12) {
            PilotOwlMascotView(mood: .reading, size: 112, animated: true, showSoftGlow: true)
            Text(NSLocalizedString("my_notes_empty", comment: ""))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .cardStyle()
    }

    // MARK: - Data Loading & Mutation

    private func reloadJournal(showSpinner: Bool = true) async {
        guard let app = AppModule.shared else {
            isLoading = false
            return
        }
        if showSpinner {
            isLoading = true
        }
        defer { isLoading = false }

        do {
            let booksList = (try? await app.books.allOnce()) ?? []
            let booksById = Dictionary(uniqueKeysWithValues: booksList.compactMap { b -> (Book.Id, Book)? in
                guard let id = b.id else { return nil }
                return (id, b)
            })

            let bookmarkBookIds = try await app.bookmarkRepository.distinctBookIds()
            let highlightBookIds = try await app.highlightRepository.distinctBookIds()
            let targetIds = Set(bookmarkBookIds + highlightBookIds)

            var collected: [JournalEntry] = []

            for bookId in targetIds {
                let resolvedBook: Book?
                if let cached = booksById[bookId] {
                    resolvedBook = cached
                } else {
                    resolvedBook = try await app.books.get(bookId)
                }
                guard let book = resolvedBook else { continue }

                let bookmarks = try await fetchOnce(app.bookmarkRepository.all(for: bookId))
                let highlights = try await fetchOnce(app.highlightRepository.all(for: bookId))

                collected.append(contentsOf: bookmarks.map { JournalEntry(book: book, kind: .bookmark($0)) })
                collected.append(contentsOf: highlights.map { JournalEntry(book: book, kind: .highlight($0)) })
            }

            collected.sort { $0.date > $1.date }
            entries = collected
            highlightCount = collected.reduce(0) { partial, entry in
                if case .highlight = entry.kind { return partial + 1 }
                return partial
            }
        } catch {
            entries = []
            highlightCount = 0
        }
    }

    private func fetchOnce<T>(_ publisher: AnyPublisher<T, Error>) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            var cancellable: AnyCancellable?
            cancellable = publisher.sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        cont.resume(throwing: error)
                    }
                    cancellable?.cancel()
                },
                receiveValue: { value in
                    cont.resume(returning: value)
                    cancellable?.cancel()
                }
            )
        }
    }

    private func deleteEntry(_ entry: JournalEntry) async {
        guard let app = AppModule.shared else { return }
        do {
            switch entry.kind {
            case .bookmark(let bm):
                guard let id = bm.id else { return }
                try await app.bookmarkRepository.remove(id)
            case .highlight(let hl):
                guard let id = hl.id else { return }
                try await app.highlightRepository.remove(id)
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                entries.removeAll { $0.id == entry.id }
            }
            if case .highlight = entry.kind {
                highlightCount = max(0, highlightCount - 1)
            }
        } catch {
            deleteErrorMessage = NSLocalizedString("my_notes_delete_error_message", comment: "")
        }
    }

    private func bookmarkExcerpt(_ bm: Bookmark) -> String? {
        let text = bm.locator.text.sanitized()
        let before = text.before?.trimmingCharacters(in: .whitespacesAndNewlines)
        let after = text.after?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (before?.isEmpty, after?.isEmpty) {
        case (false?, false?): return "…\(before!) \(after!)…"
        case (false?, _): return "…\(before!)"
        case (_, false?): return "\(after!)…"
        default: return nil
        }
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}

// MARK: - Journal Entry Model

private struct JournalEntry: Identifiable {
    enum Kind {
        case bookmark(Bookmark)
        case highlight(Highlight)
    }

    let id: String
    let book: Book
    let kind: Kind
    let date: Date
    let locator: Locator

    init(book: Book, kind: Kind) {
        self.book = book
        self.kind = kind
        switch kind {
        case .bookmark(let bm):
            self.id = "bm-\(bm.id?.rawValue ?? 0)"
            self.date = bm.created
            self.locator = bm.locator
        case .highlight(let hl):
            self.id = "hl-\(hl.id?.rawValue ?? 0)"
            self.date = hl.created
            self.locator = hl.locator
        }
    }
}
