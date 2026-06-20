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
    private let statsAccess: ReadingStatsAccess

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
    private var cancellables = Set<AnyCancellable>()

    init(
        books: BookRepository,
        statsStore: ReadingStatsStore = .shared,
        statsAccess: ReadingStatsAccess = .shared
    ) {
        self.books = books
        self.statsStore = statsStore
        self.statsAccess = statsAccess

        loadLastReadBook()
    }

    private func loadLastReadBook() {
        books.all()
            .map { books -> LastReadBook? in
                books.last { $0.progression > 0 && $0.progression < 1 }
                    .map { LastReadBook(book: $0) }
            }
            .receive(on: DispatchQueue.main)
            .sink { _ in } receiveValue: { [weak self] book in
                self?.lastReadBook = book
                self?.isEmpty = book == nil
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

    /// Today's reading time in minutes
    var todayReadingMinutes: Int {
        statsStore.todayReadingSeconds() / 60
    }

    /// Progress towards daily goal (0.0 to 1.0+)
    var dailyProgress: Double {
        min(Double(todayReadingMinutes) / Double(dailyReadingGoalMinutes), 1.0)
    }

    /// Formatted reading time string
    var formattedReadingTime: String {
        String(format: NSLocalizedString("home_minutes", comment: ""), todayReadingMinutes)
    }

    func stats(for scope: ReadingStatsScope) -> ReadingStatsSnapshot {
        statsStore.snapshot(for: scope)
    }

    func canAccessStats(_ scope: ReadingStatsScope) -> Bool {
        !scope.requiresPro || statsAccess.hasProAccess
    }
}

enum ReadingPreferences {
    enum Keys {
        static let dailyGoalMinutes = "reading_daily_goal_minutes"
    }

    static let defaultDailyGoalMinutes = 30
    static let dailyGoalRange = 5...180
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
        content
            .background(AppColors.cardBackground)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.7), lineWidth: 1)
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.25 : 0.04),
                radius: 16,
                x: 0,
                y: 6
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

                    Spacer(minLength: UIDevice.current.userInterfaceIdiom == .pad ? 24 : 100)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)
            }
        }
        .background(AppColors.background)
        .id(localizationRefreshID)
        .onAppear {
            appeared = true
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
    }

    // MARK: - Greeting Header

    private var greetingHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(AppColors.accentGradientStart.opacity(colorScheme == .dark ? 0.22 : 0.12))
                    .frame(width: 44, height: 44)

                Image(systemName: "book.closed")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColors.accentGradientStart)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.greetingText)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(AppColors.primaryText)

                Text(viewModel.dateText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
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

                compactMetric(
                    title: NSLocalizedString("home_daily_goal", comment: ""),
                    value: "\(viewModel.dailyReadingGoalMinutes)",
                    icon: "target"
                )
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

                            HStack(spacing: 12) {
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(AppColors.progressTrack)
                                            .frame(height: 6)

                                        let progressWidth = geometry.size.width * book.progression

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

                                Text("\(Int(book.progression * 100))%")
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
                            Text(NSLocalizedString("home_continue_reading_button", comment: ""))
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
