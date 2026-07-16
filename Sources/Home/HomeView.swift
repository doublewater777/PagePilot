//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import ReadiumShared
import SwiftUI
import UIKit

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

    init(book: Book) {
        self.id = book.id!
        self.title = book.title
        self.authors = book.authors
        self.coverPath = book.coverPath
        self.progression = book.progression
    }
}

final class HomeViewModel: ObservableObject {
    @Published var lastReadBook: LastReadBook?
    @Published var isEmpty: Bool = true
    @Published var statsRefreshID = UUID()

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

    private let books: BookRepository
    private var latestBooks: [Book] = []
    private var cancellables = Set<AnyCancellable>()

    init(
        books: BookRepository,
        statsStore: ReadingStatsStore = .shared
    ) {
        self.books = books
        self.statsStore = statsStore

        loadLastReadBook()
    }

    private func loadLastReadBook() {
        books.all()
            .receive(on: DispatchQueue.main)
            .sink { _ in } receiveValue: { [weak self] books in
                self?.latestBooks = books
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
        let selected = ContinueReadingSelector.select(
            from: latestBooks,
            lastReadIds: LastReadBooks.orderedIds
        )
        lastReadBook = selected.map { LastReadBook(book: $0) }
        isEmpty = selected == nil
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

enum ReadingPreferences {
    enum Keys {
        static let dailyGoalMinutes = "reading_daily_goal_minutes"
        static let reminderEnabled = "reading_reminder_enabled"
        static let reminderHour = "reading_reminder_hour"
        static let reminderMinute = "reading_reminder_minute"
    }

    static let defaultDailyGoalMinutes = 30
    static let dailyGoalRange = 5...180
    static let defaultReminderEnabled = true
    static let defaultReminderHour = 21
    static let defaultReminderMinute = 0
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
}

// MARK: - Reusable Styles and Helpers

private struct PremiumButtonStyle: ButtonStyle {
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

// MARK: - Home View

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    weak var delegate: HomeModuleDelegate?
    @Environment(\.colorScheme) var colorScheme

    @State private var appeared = false
    @State private var progressAnimated = false
    @State private var localizationRefreshID = AppAppearancePreferences.language.rawValue
    @State private var showStats = false
    @State private var showNotes = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    greetingHeader
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                        .animation(.easeOut(duration: 0.5), value: appeared)

                    dailyReadingGoalCard
                        .id(viewModel.statsRefreshID)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 15)
                        .animation(.easeOut(duration: 0.5).delay(0.1), value: appeared)

                    if !viewModel.isEmpty {
                        continueReadingSection
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 15)
                            .animation(.easeOut(duration: 0.5).delay(0.2), value: appeared)
                    } else {
                        emptyStateView
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 15)
                            .animation(.easeOut(duration: 0.5).delay(0.2), value: appeared)
                    }

                    homeShortcuts
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 15)
                        .animation(.easeOut(duration: 0.5).delay(0.28), value: appeared)

                    Spacer(minLength: UIDevice.current.userInterfaceIdiom == .pad ? 24 : 100)
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
            }
        }
        .background(AppColors.background.ignoresSafeArea())
        .id(localizationRefreshID)
        .onAppear {
            appeared = true
            viewModel.refreshContinueReading()
            withAnimation(.easeOut(duration: 0.8).delay(0.3)) {
                progressAnimated = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AppAppearancePreferences.languageDidChange)) { _ in
            localizationRefreshID = AppAppearancePreferences.language.rawValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .readingStatsDidChange)) { _ in
            viewModel.statsRefreshID = UUID()
        }
        .sheet(isPresented: $showStats) {
            NavigationStack {
                ReadingStatsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            SheetCloseButton { showStats = false }
                        }
                    }
            }
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(.systemGroupedBackground))
        }
        .sheet(isPresented: $showNotes) {
            // NavigationView (.stack) instead of NavigationStack: NavigationStack
            // deadlocks in SwiftUI layout (_MovableLockLock) when pushing a
            // List-based destination from inside a sheet on iPad (iOS 17) - the
            // Home > My Notes > tap book flow hangs. NavigationView mirrors the
            // Me tab's working notes entry. See git history for the LLDB trace.
            NavigationView {
                MyNotesView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            SheetCloseButton { showNotes = false }
                        }
                    }
            }
            .navigationViewStyle(.stack)
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Shortcuts (stats / notes)

    private var homeShortcuts: some View {
        HStack(spacing: 12) {
            Button {
                showStats = true
            } label: {
                homeShortcutLabel(
                    icon: "chart.bar.xaxis",
                    title: NSLocalizedString("home_shortcut_stats", comment: ""),
                    subtitle: NSLocalizedString("home_shortcut_stats_subtitle", comment: "")
                )
            }
            .buttonStyle(PremiumButtonStyle())

            Button {
                showNotes = true
            } label: {
                homeShortcutLabel(
                    icon: "bookmark.fill",
                    title: NSLocalizedString("home_shortcut_notes", comment: ""),
                    subtitle: NSLocalizedString("home_shortcut_notes_subtitle", comment: "")
                )
            }
            .buttonStyle(PremiumButtonStyle())
        }
    }

    private func homeShortcutLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppColors.accentBlue)
                .frame(width: 36, height: 36)
                .background(AppColors.accentBlue.opacity(colorScheme == .dark ? 0.2 : 0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppColors.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.tertiaryText)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Greeting Header

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.greetingText)
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(AppColors.primaryText)

            Text(viewModel.dateText)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppColors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Daily Reading Goal Card

    private var dailyReadingGoalCard: some View {
        let todayStats = viewModel.stats(for: .day)

        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(NSLocalizedString("home_daily_goal", comment: ""))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        gradientText("\(viewModel.todayReadingMinutes)", font: .system(size: 46, weight: .bold))

                        Text(String(format: NSLocalizedString("home_daily_goal_of", comment: ""), viewModel.dailyReadingGoalMinutes))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(AppColors.tertiaryText)
                    }
                }

                Spacer()

                Text("\(Int(viewModel.dailyProgress * 100))%")
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                    .foregroundColor(AppColors.accentGradientStart)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.accentGradientStart.opacity(colorScheme == .dark ? 0.2 : 0.11))
                    .clipShape(Capsule())
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColors.progressTrack)

                    Capsule()
                        .fill(AppColors.horizontalGradient)
                        .frame(width: geometry.size.width * (progressAnimated ? viewModel.dailyProgress : 0))
                }
            }
            .frame(height: 8)

            HStack(spacing: 12) {
                compactMetric(
                    title: NSLocalizedString("stats_metric_sessions", comment: ""),
                    value: "\(todayStats.sessions)",
                    icon: "timer"
                )

                Button {
                    showStats = true
                } label: {
                    compactMetric(
                        title: NSLocalizedString("stats_metric_streak", comment: ""),
                        value: "\(viewModel.currentStreakDays)",
                        icon: viewModel.currentStreakDays > 0 ? "flame.fill" : "flame"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint(NSLocalizedString("home_streak_a11y_hint", comment: ""))
            }
        }
        .padding(22)
        .cardStyle()
    }

    // MARK: - Continue Reading Section

    private var continueReadingSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(NSLocalizedString("home_continue_reading", comment: ""))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(AppColors.secondaryText)

                Spacer()
            }
            .padding(.leading, 4)

            if let book = viewModel.lastReadBook {
                VStack(spacing: 0) {
                    HStack(spacing: 18) {
                        coverImage(for: book)
                            .frame(width: 85, height: 125)
                            .clipped()
                            .cornerRadius(8)
                            .overlay(
                                HStack {
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.white.opacity(0.25), Color.black.opacity(0.1)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: 4)
                                    Spacer()
                                }
                            )
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 10, x: -2, y: 4)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(book.title)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(2)

                            if let authors = book.authors {
                                Text(authors)
                                    .font(.system(size: 14))
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(1)
                                    .opacity(0.7)
                            }

                            Spacer()

                            if book.isFinished {
                                Text(NSLocalizedString("home_finished_label", comment: ""))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(AppColors.accentTeal)
                            }

                            HStack(spacing: 12) {
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(AppColors.progressTrack)
                                            .frame(height: 6)

                                        let progressWidth = geometry.size.width * book.displayProgression

                                        Capsule()
                                            .fill(AppColors.horizontalGradient)
                                            .frame(width: progressWidth, height: 6)

                                        Capsule()
                                            .fill(AppColors.horizontalGradient)
                                            .frame(width: progressWidth, height: 6)
                                            .blur(radius: 4)
                                            .opacity(0.4)
                                    }
                                }
                                .frame(height: 6)

                                Text("\(Int(book.displayProgression * 100))%")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(AppColors.accentGradientStart)
                            }
                        }
                    }
                    .padding(20)
                    .frame(height: 165)

                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 1)
                        .padding(.horizontal, 20)

                    Button(action: {
                        delegate?.homeDidSelectContinueReading(bookId: book.id)
                    }) {
                        HStack(spacing: 6) {
                            Text(NSLocalizedString(
                                book.isFinished ? "home_reread_button" : "home_continue_reading_button",
                                comment: ""
                            ))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.horizontalGradient)
                        .cornerRadius(14)
                    }
                    .buttonStyle(PremiumButtonStyle())
                    .padding(20)
                }
                .cardStyle()
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppColors.accentGradientStart.opacity(colorScheme == .dark ? 0.22 : 0.12))
                        .frame(width: 70, height: 70)

                    Image(systemName: "books.vertical")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(AppColors.accentGradientStart)
                }
                .padding(.bottom, 4)

                Text(NSLocalizedString("home_empty_title", comment: ""))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(AppColors.primaryText)

                Text(NSLocalizedString("home_empty_message", comment: ""))
                    .font(.system(size: 15))
                    .foregroundColor(AppColors.secondaryText)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 12)

            Button(action: {
                delegate?.homeDidSelectGoToLibrary()
            }) {
                HStack(spacing: 6) {
                    Text(NSLocalizedString("home_import_button", comment: ""))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppColors.horizontalGradient)
                .cornerRadius(14)
            }
            .buttonStyle(PremiumButtonStyle())
        }
        .padding(24)
        .cardStyle()
    }

    // MARK: - Helper Views and Methods

    private func gradientText(_ text: String, font: Font) -> some View {
        Text(text)
            .font(font)
            .overlay(
                AppColors.horizontalGradient
            )
            .mask(
                Text(text)
                    .font(font)
            )
    }

    private func compactMetric(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.accentGradientStart)
                .frame(width: 28, height: 28)
                .background(AppColors.accentGradientStart.opacity(colorScheme == .dark ? 0.18 : 0.09))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(AppColors.primaryText)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(AppColors.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.tertiarySystemGroupedBackground))
        .cornerRadius(14)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "0m"
        }
    }

    private func formattedDate(_ dateKey: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.calendar = Calendar(identifier: .gregorian)
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        inputFormatter.dateFormat = "yyyy-MM-dd"

        guard let date = inputFormatter.date(from: dateKey) else {
            return dateKey
        }

        let outputFormatter = DateFormatter()
        outputFormatter.locale = AppAppearancePreferences.locale
        outputFormatter.setLocalizedDateFormatFromTemplate("MMMd")
        return outputFormatter.string(from: date)
    }

    // MARK: - Cover Image

    @ViewBuilder
    private func coverImage(for book: LastReadBook) -> some View {
        if let coverPath = book.coverPath {
            let coverURL = Paths.covers.appendingPath(coverPath, isDirectory: false).url
            AsyncImage(url: coverURL) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    placeholderCover(for: book)
                }
            }
        } else {
            placeholderCover(for: book)
        }
    }

    private func placeholderCover(for book: LastReadBook) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.53, green: 0.74, blue: 0.83), Color(red: 0.45, green: 0.60, blue: 0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Text(String(book.title.prefix(1)))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}
