//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import GRDB

struct ReadingSession: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "readingSession"

    struct Id: EntityId { let rawValue: Int64 }

    let id: Id?
    let sessionID: String
    let bookId: Book.Id
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: Int
    let startProgression: Double
    let endProgression: Double
    let watchPageTurns: Int

    var progressDelta: Double {
        max(0, endProgression - startProgression)
    }

    init(
        id: Id? = nil,
        sessionID: String = UUID().uuidString.lowercased(),
        bookId: Book.Id,
        startedAt: Date,
        endedAt: Date,
        startProgression: Double,
        endProgression: Double,
        watchPageTurns: Int
    ) {
        self.id = id
        self.sessionID = sessionID
        self.bookId = bookId
        self.startedAt = startedAt
        self.endedAt = endedAt
        durationSeconds = max(0, Int(endedAt.timeIntervalSince(startedAt).rounded()))
        self.startProgression = Self.clampProgress(startProgression)
        self.endProgression = Self.clampProgress(endProgression)
        self.watchPageTurns = max(0, watchPageTurns)
    }

    private static func clampProgress(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    enum Columns: String, ColumnExpression {
        case id
        case sessionID
        case bookId
        case startedAt
        case endedAt
        case durationSeconds
        case startProgression
        case endProgression
        case watchPageTurns
    }
}


struct ReadingPaceEstimate {
    let progressPerActiveMinute: Double
    let remainingActiveMinutes: Double
    let approximateFinishDate: Date?
}

enum ReadingPaceEstimateResult {
    case insufficientData
    case estimate(ReadingPaceEstimate)
}

enum ReadingPaceCalculator {
    static let minimumSessionCount = 3
    static let minimumActiveSeconds = 20 * 60
    static let minimumForwardProgress = 0.05
    static let recentSessionLimit = 20
    static let recentPositiveSessionLimit = 10
    static let recentDailyWindowDays = 7
    static let minimumRecentActiveDaysForFinishDate = 3

    static func estimate(
        sessions: [ReadingSession],
        currentProgression: Double,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ReadingPaceEstimateResult {
        let orderedSessions = sessions
            .filter { $0.durationSeconds > 0 }
            .sorted {
                if $0.startedAt == $1.startedAt {
                    return $0.sessionID > $1.sessionID
                }
                return $0.startedAt > $1.startedAt
            }

        let recentSessions = Array(orderedSessions.prefix(recentSessionLimit))
        let activeSeconds = recentSessions.reduce(0) { $0 + $1.durationSeconds }
        let forwardProgress = recentSessions.reduce(0.0) { $0 + $1.progressDelta }

        guard recentSessions.count >= minimumSessionCount,
              activeSeconds >= minimumActiveSeconds,
              forwardProgress + 0.000_000_1 >= minimumForwardProgress
        else {
            return .insufficientData
        }

        // Select recent positive-progress sessions independently so backward/no-progress
        // sessions never displace a forward sample or inflate its velocity.
        let positiveSessions = orderedSessions
            .filter { $0.progressDelta > 0.000_1 }
            .prefix(recentPositiveSessionLimit)
        let positiveActiveSeconds = positiveSessions.reduce(0) { $0 + $1.durationSeconds }
        let positiveProgress = positiveSessions.reduce(0.0) { $0 + $1.progressDelta }

        guard positiveActiveSeconds > 0, positiveProgress > 0 else {
            return .insufficientData
        }

        let progressPerActiveMinute = positiveProgress / (Double(positiveActiveSeconds) / 60.0)
        guard progressPerActiveMinute.isFinite, progressPerActiveMinute > 0 else {
            return .insufficientData
        }

        let clampedProgression = min(max(currentProgression, 0), 1)
        let remainingActiveMinutes = (1 - clampedProgression) / progressPerActiveMinute
        let finishDate = approximateFinishDate(
            sessions: orderedSessions,
            remainingActiveMinutes: remainingActiveMinutes,
            now: now,
            calendar: calendar
        )

        return .estimate(
            ReadingPaceEstimate(
                progressPerActiveMinute: progressPerActiveMinute,
                remainingActiveMinutes: remainingActiveMinutes,
                approximateFinishDate: finishDate
            )
        )
    }

    private static func approximateFinishDate(
        sessions: [ReadingSession],
        remainingActiveMinutes: Double,
        now: Date,
        calendar: Calendar
    ) -> Date? {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(
            byAdding: .day,
            value: -(recentDailyWindowDays - 1),
            to: today
        ),
        let windowEnd = calendar.date(byAdding: .day, value: 1, to: today)
        else {
            return nil
        }

        let recentDailySessions = sessions.filter {
            $0.startedAt >= windowStart && $0.startedAt < windowEnd
        }
        let activeDays = Set(recentDailySessions.map { calendar.startOfDay(for: $0.startedAt) })
        guard activeDays.count >= minimumRecentActiveDaysForFinishDate else {
            return nil
        }

        let recentActiveMinutes = Double(
            recentDailySessions.reduce(0) { $0 + $1.durationSeconds }
        ) / 60.0
        let averageActiveMinutesPerDay = recentActiveMinutes / Double(recentDailyWindowDays)
        guard averageActiveMinutesPerDay > 0 else {
            return nil
        }

        let calendarDaysRemaining = remainingActiveMinutes / averageActiveMinutesPerDay
        guard calendarDaysRemaining.isFinite else {
            return nil
        }
        return now.addingTimeInterval(max(0, calendarDaysRemaining) * 24 * 60 * 60)
    }
}

final class ReadingSessionRepository {
    private let db: Database

    init(db: Database) {
        self.db = db
    }

    @discardableResult
    func add(_ session: ReadingSession) async throws -> ReadingSession.Id? {
        guard session.durationSeconds > 0 else { return nil }

        return try await db.write { db in
            var session = session
            try session.insert(db)
            return ReadingSession.Id(rawValue: db.lastInsertedRowID)
        }
    }

    func recent(limit: Int = 20) async throws -> [ReadingSession] {
        let limit = max(1, limit)
        return try await db.read { db in
            try ReadingSession
                .order(ReadingSession.Columns.startedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func recent(for bookId: Book.Id, limit: Int = 20) async throws -> [ReadingSession] {
        let limit = max(1, limit)
        return try await db.read { db in
            try ReadingSession
                .filter(ReadingSession.Columns.bookId == bookId)
                .order(ReadingSession.Columns.startedAt.desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func count() async throws -> Int {
        try await db.read { db in
            try ReadingSession.fetchCount(db)
        }
    }
}
