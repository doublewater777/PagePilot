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

    let readingTimeManager: ReadingTimeManager

    /// Daily reading goal in minutes (default 30 min)
    let dailyReadingGoalMinutes: Int = 30

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

    private let books: BookRepository
    private var cancellables = Set<AnyCancellable>()

    init(books: BookRepository, readingTimeManager: ReadingTimeManager) {
        self.books = books
        self.readingTimeManager = readingTimeManager

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
    }

    /// Today's reading time in minutes
    var todayReadingMinutes: Int {
        readingTimeManager.todayReadingTimeSeconds / 60
    }

    /// Progress towards daily goal (0.0 to 1.0+)
    var dailyProgress: Double {
        min(Double(todayReadingMinutes) / Double(dailyReadingGoalMinutes), 1.0)
    }

    /// Formatted reading time string
    var formattedReadingTime: String {
        String(format: NSLocalizedString("home_minutes", comment: ""), todayReadingMinutes)
    }
}

// MARK: - Adaptive Colors

private struct AppColors {
    // Background colors
    static let background = Color(.systemGroupedBackground)
    static let cardBackground = Color(.systemBackground)

    // Text colors
    static let primaryText = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    static let tertiaryText = Color(.tertiaryLabel)

    // Accent gradient colors
    static let accentGradientStart = Color(red: 0.4, green: 0.6, blue: 0.98)
    static let accentGradientEnd = Color(red: 0.55, green: 0.45, blue: 0.95)

    // Progress track
    static let progressTrack = Color.gray.opacity(0.15)
}

struct HomeView: View {
    @ObservedObject var viewModel: HomeViewModel
    weak var delegate: HomeModuleDelegate?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                // Greeting Header
                greetingHeader

                // Daily Reading Goal Card
                dailyReadingGoalCard

                // Continue Reading Section
                if !viewModel.isEmpty {
                    continueReadingSection
                } else {
                    emptyStateView
                }

                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .background(AppColors.background)
    }

    // MARK: - Greeting Header

    private var greetingHeader: some View {
        HStack(spacing: 6) {
            Text(viewModel.greetingEmoji)
                .font(.system(size: 24))

            Text(viewModel.greetingText)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(AppColors.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: - Daily Reading Goal Card

    private var dailyReadingGoalCard: some View {
        HStack(spacing: 20) {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(AppColors.progressTrack, lineWidth: 8)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: viewModel.dailyProgress)
                    .stroke(
                        LinearGradient(
                            colors: [AppColors.accentGradientStart, AppColors.accentGradientEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))

                Text("\(Int(viewModel.dailyProgress * 100))%")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("home_daily_goal", comment: ""))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)

                Text(viewModel.formattedReadingTime)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(AppColors.primaryText)

                Text(String(format: NSLocalizedString("home_daily_goal_of", comment: ""), viewModel.dailyReadingGoalMinutes))
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.tertiaryText)
            }

            Spacer()
        }
        .padding(20)
        .background(AppColors.cardBackground)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 12, y: 4)
    }

    // MARK: - Continue Reading Section

    private var continueReadingSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text(NSLocalizedString("home_continue_reading", comment: ""))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)

                Spacer()
            }

            if let book = viewModel.lastReadBook {
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        // Book cover
                        coverImage(for: book)
                            .frame(width: 75, height: 110)
                            .cornerRadius(10)
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.2 : 0.08), radius: 8, y: 2)

                        // Book details
                        VStack(alignment: .leading, spacing: 6) {
                            Text(book.title)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(2)

                            if let authors = book.authors {
                                Text(authors)
                                    .font(.system(size: 13))
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(1)
                            }

                            Spacer()

                            // Progress bar
                            HStack(spacing: 10) {
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(AppColors.progressTrack)
                                            .frame(height: 5)

                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(
                                                LinearGradient(
                                                    colors: [AppColors.accentGradientStart, AppColors.accentGradientEnd],
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                            .frame(width: geometry.size.width * book.progression, height: 5)
                                    }
                                }
                                .frame(height: 5)

                                Text("\(Int(book.progression * 100))%")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(AppColors.accentGradientStart)
                            }
                        }

                        Spacer()
                    }
                    .padding(20)

                    // Continue reading button
                    Button(action: {
                        delegate?.homeDidSelectContinueReading(bookId: book.id)
                    }) {
                        Text(NSLocalizedString("home_continue_reading_button", comment: ""))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: [AppColors.accentGradientStart, AppColors.accentGradientEnd],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                    }
                }
                .background(AppColors.cardBackground)
                .cornerRadius(20)
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 12, y: 4)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Text("📚")
                    .font(.system(size: 48))

                Text(NSLocalizedString("home_empty_title", comment: ""))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppColors.primaryText)

                Text(NSLocalizedString("home_empty_message", comment: ""))
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 32)

            Button(action: {
                delegate?.homeDidSelectGoToLibrary()
            }) {
                Text(NSLocalizedString("home_import_button", comment: ""))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [AppColors.accentGradientStart, AppColors.accentGradientEnd],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
            }
        }
        .padding(24)
        .background(AppColors.cardBackground)
        .cornerRadius(20)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.05), radius: 12, y: 4)
    }

    // MARK: - Cover Image

    @ViewBuilder
    private func coverImage(for book: LastReadBook) -> some View {
        if let coverPath = book.coverPath {
            let coverURL = Paths.covers.appendingPath(coverPath, isDirectory: false).url
            if let data = try? Data(contentsOf: coverURL),
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderCover(for: book)
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
