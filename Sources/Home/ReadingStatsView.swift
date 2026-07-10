//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI
import Charts

struct ReadingStatsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(ReadingPreferences.Keys.dailyGoalMinutes) private var dailyGoalMinutes = ReadingPreferences.defaultDailyGoalMinutes
    
    @State private var selectedStatsScope: ReadingStatsScope = .day
    @State private var currentReferenceDate = Date()
    @State private var showPaywall = false
    @State private var showShareCard = false
    @State private var statsRefreshID = UUID()
    @State private var streakScale: CGFloat = 1.0
    @State private var booksMap: [String: Book] = [:]
    @State private var selectedChartDate: Date? = nil
    @State private var expandedWeeks: Set<Int> = [4]

    private let statsStore = ReadingStatsStore.shared
    @ObservedObject private var proPurchase = ProPurchaseManager.shared

    private var canAccessSelectedScope: Bool {
        !selectedStatsScope.requiresPro || proPurchase.hasProAccess
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                scopeSelector
                periodNavigator

                if canAccessSelectedScope {
                    // Show dashboard immediately — avoid loading spinner swap that feels like a flashy enter animation.
                    statsDashboard(statsStore.snapshot(for: selectedStatsScope, referenceDate: currentReferenceDate))
                        .id(statsRefreshID)
                } else {
                    lockedStatsView
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, UIDevice.current.userInterfaceIdiom == .pad ? 24 : 96)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(NSLocalizedString("stats_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color(.systemGroupedBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showShareCard) {
            ReadingShareCardView(
                todaySeconds: statsStore.todayReadingSeconds(),
                streakDays: statsStore.snapshot(for: .summary).currentStreakDays,
                books: Array(booksMap.values)
            )
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showShareCard = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundColor(AppColors.primaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readingStatsDidChange)) { _ in
            statsRefreshID = UUID()
        }
        .onAppear {
            loadBooksData()
        }
        .onChange(of: selectedStatsScope) { _, _ in
            // Scope changes can show a subtle streak pulse; skip on first appear.
            updateStreakAnimation()
        }
        .onChange(of: currentReferenceDate) { _, _ in
            updateStreakAnimation()
        }
        .onChange(of: selectedChartDate) { oldDate, newDate in
            if newDate != nil && oldDate == nil {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } else if let old = oldDate, let new = newDate, !Calendar.current.isDate(old, inSameDayAs: new) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(NSLocalizedString("stats_title", comment: ""))
                .font(.system(size: 30, weight: .bold))
                .foregroundColor(AppColors.primaryText)

            Text(NSLocalizedString("stats_subtitle", comment: ""))
                .font(.system(size: 15))
                .foregroundColor(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var scopeSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ReadingStatsScope.allCases) { scope in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selectedStatsScope = scope
                            currentReferenceDate = Date()
                            selectedChartDate = nil
                        }
                        if scope.requiresPro {
                            Analytics.shared.log(.statsScopeChanged(to: scope.rawValue))
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(scope.title)
                            if scope.requiresPro && !proPurchase.hasProAccess {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(selectedStatsScope == scope ? .white : AppColors.primaryText)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(scopeBackground(for: scope))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func scopeBackground(for scope: ReadingStatsScope) -> some View {
        if selectedStatsScope == scope {
            LinearGradient(
                colors: [AppColors.accentBlue, AppColors.accentTeal],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color(.secondarySystemGroupedBackground)
        }
    }

    private var isCurrentPeriod: Bool {
        let now = Date()
        let calendar = Calendar.current
        switch selectedStatsScope {
        case .summary:
            return true
        case .day:
            return calendar.isDate(currentReferenceDate, inSameDayAs: now)
        case .week:
            return calendar.isDate(currentReferenceDate, equalTo: now, toGranularity: .weekOfYear)
        case .month:
            return calendar.isDate(currentReferenceDate, equalTo: now, toGranularity: .month)
        case .year:
            return calendar.isDate(currentReferenceDate, equalTo: now, toGranularity: .year)
        }
    }

    private var periodNavigator: some View {
        Group {
            if selectedStatsScope != .summary {
                HStack {
                    Button(action: { navigatePeriod(by: -1) }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                            .frame(width: 36, height: 36)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    VStack(spacing: 4) {
                        Text(formattedPeriodTitle)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                        
                        if !isCurrentPeriod {
                            Button(action: {
                                let feedback = UIImpactFeedbackGenerator(style: .medium)
                                feedback.impactOccurred()
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                    currentReferenceDate = Date()
                                    selectedChartDate = nil
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .font(.system(size: 9, weight: .bold))
                                    Text(NSLocalizedString("stats_quick_return", comment: ""))
                                }
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(LinearGradient(
                                    colors: [AppColors.accentBlue, AppColors.accentTeal],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                .clipShape(Capsule())
                            }
                            .transition(.scale.combined(with: .opacity))
                        }
                    }

                    Spacer()

                    Button(action: { navigatePeriod(by: 1) }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                            .frame(width: 36, height: 36)
                            .background(Color(.secondarySystemGroupedBackground))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isFutureLimitReached)
                    .opacity(isFutureLimitReached ? 0.3 : 1.0)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var isFutureLimitReached: Bool {
        let now = Date()
        let calendar = Calendar.current
        switch selectedStatsScope {
        case .summary:
            return true
        case .day:
            return calendar.isDate(currentReferenceDate, inSameDayAs: now) || currentReferenceDate > now
        case .week:
            return calendar.isDate(currentReferenceDate, equalTo: now, toGranularity: .weekOfYear) || currentReferenceDate > now
        case .month:
            return calendar.isDate(currentReferenceDate, equalTo: now, toGranularity: .month) || currentReferenceDate > now
        case .year:
            return calendar.isDate(currentReferenceDate, equalTo: now, toGranularity: .year) || currentReferenceDate > now
        }
    }

    private func navigatePeriod(by value: Int) {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.impactOccurred()
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedChartDate = nil
            switch selectedStatsScope {
            case .summary:
                break
            case .day:
                currentReferenceDate = Calendar.current.date(byAdding: .day, value: value, to: currentReferenceDate) ?? currentReferenceDate
            case .week:
                currentReferenceDate = Calendar.current.date(byAdding: .weekOfYear, value: value, to: currentReferenceDate) ?? currentReferenceDate
            case .month:
                currentReferenceDate = Calendar.current.date(byAdding: .month, value: value, to: currentReferenceDate) ?? currentReferenceDate
            case .year:
                currentReferenceDate = Calendar.current.date(byAdding: .year, value: value, to: currentReferenceDate) ?? currentReferenceDate
            }
        }
    }

    private var formattedPeriodTitle: String {
        let calendar = Calendar.current
        let locale = AppAppearancePreferences.locale
        
        switch selectedStatsScope {
        case .summary:
            return NSLocalizedString("stats_summary_all_time", comment: "")
        case .day:
            if calendar.isDateInToday(currentReferenceDate) {
                return NSLocalizedString("stats_nav_today", comment: "")
            }
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            return formatter.string(from: currentReferenceDate)
        case .week:
            guard let weekRange = calendar.dateInterval(of: .weekOfYear, for: currentReferenceDate) else { return "" }
            let endOfWeek = calendar.date(byAdding: .second, value: -1, to: weekRange.end) ?? weekRange.end
            
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            let startStr = formatter.string(from: weekRange.start)
            let endStr = formatter.string(from: endOfWeek)
            
            let weekOfYear = calendar.component(.weekOfYear, from: currentReferenceDate)
            let weekName = String(format: NSLocalizedString("stats_timeline_grouped_week", comment: ""), weekOfYear)
            return "\(weekName) (\(startStr) - \(endStr))"
        case .month:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "yyyy MMMM"
            return formatter.string(from: currentReferenceDate)
        case .year:
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "yyyy"
            return formatter.string(from: currentReferenceDate)
        }
    }

    private func statsDashboard(_ stats: ReadingStatsSnapshot) -> some View {
        VStack(spacing: 14) {
            summaryCard(stats)
            insightGrid(stats)
            chartCard(stats)
            if selectedStatsScope == .month {
                heatmapGrid(stats)
            }
            if selectedStatsScope == .summary {
                badgesSection(stats)
            }
            groupedTimelineCard(stats)
        }
    }

    private func summaryCard(_ stats: ReadingStatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(selectedStatsScope.summaryTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)

                    Text(formattedDuration(stats.totalSeconds))
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(AppColors.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                }

                Spacer(minLength: 12)

                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppColors.accentTeal.opacity(colorScheme == .dark ? 0.24 : 0.13))

                    Image(systemName: selectedStatsScope.symbolName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(AppColors.accentTeal)
                }
                .frame(width: 52, height: 52)
            }

            HStack(spacing: 10) {
                compactMetric(
                    title: NSLocalizedString("stats_metric_sessions", comment: ""),
                    value: "\(stats.sessions)"
                )
                
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: NSLocalizedString("stats_days_value", comment: ""), stats.currentStreakDays))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Text(NSLocalizedString("stats_metric_streak", comment: ""))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppColors.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer()
                    Image(systemName: stats.currentStreakDays > 0 ? "flame.fill" : "flame")
                        .font(.system(size: 20))
                        .foregroundColor(stats.currentStreakDays > 0 ? .orange : AppColors.tertiaryText)
                        .scaleEffect(stats.currentStreakDays > 0 ? streakScale : 1.0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
        }
        .padding(20)
        .cardStyle()
    }

    private func compactMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(AppColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private func insightGrid(_ stats: ReadingStatsSnapshot) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            insightTile(
                icon: "calendar",
                iconColor: .blue,
                title: selectedStatsScope == .day ? NSLocalizedString("stats_metric_today", comment: "") : NSLocalizedString("stats_metric_days", comment: ""),
                value: selectedStatsScope == .day ? todayState(for: stats) : "\(stats.activeDays)"
            )
            insightTile(
                icon: "book.closed",
                iconColor: .indigo,
                title: NSLocalizedString("stats_metric_books", comment: ""),
                value: "\(stats.distinctBooks)"
            )
            insightTile(
                icon: "chart.line.uptrend.xyaxis",
                iconColor: .teal,
                title: NSLocalizedString("stats_metric_average", comment: ""),
                value: formattedDuration(stats.averageSecondsPerActiveDay)
            )
            insightTile(
                icon: "sparkles",
                iconColor: .orange,
                title: NSLocalizedString("stats_metric_best_day", comment: ""),
                value: formattedDuration(stats.bestDaySeconds)
            )
        }
    }

    private func insightTile(icon: String, iconColor: Color, title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(iconColor.opacity(colorScheme == .dark ? 0.22 : 0.12))

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(value)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppColors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(AppColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.cardBackground)
        .cornerRadius(16)
    }

    private func chartCard(_ stats: ReadingStatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            // 动态信息面板与标题
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    if let selectedDate = selectedChartDate {
                        let formattedDateStr = infoPanelDateString(for: selectedDate)
                        let value = infoPanelValue(for: selectedDate, stats: stats)
                        
                        Text(formattedDateStr)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(AppColors.accentTeal)
                        
                        Text(formattedDuration(Int(value * 60)))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                            .monospacedDigit()
                    } else {
                        Text(selectedStatsScope.summaryTitle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(AppColors.secondaryText)
                        
                        let avgText = formattedDuration(stats.averageSecondsPerActiveDay)
                        let averageLabel = String(format: NSLocalizedString("stats_chart_average_label", comment: ""), avgText)
                        Text(selectedStatsScope == .summary ? formattedDuration(stats.totalSeconds) : averageLabel)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(AppColors.primaryText)
                            .monospacedDigit()
                    }
                }
                .frame(height: 44, alignment: .leading) // Fixed height to prevent vertical layout shifts
                
                Spacer()
                
                if selectedStatsScope != .summary && selectedStatsScope != .day {
                    Text("min")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: selectedChartDate)

            if stats.dailyStats.isEmpty {
                emptyActivity
            } else {
                switch selectedStatsScope {
                case .day:
                    dayActivityRing(totalSeconds: stats.totalSeconds)
                case .week:
                    weekChart(makeWeekChartData(from: stats.dailyStats))
                case .month:
                    monthChart(makeMonthChartData(from: stats.dailyStats))
                case .year:
                    yearChart(makeYearChartData(from: stats.dailyStats))
                case .summary:
                    summaryBookChart(makeBookChartData(from: stats.dailyStats))
                }
            }
        }
        .padding(18)
        .cardStyle()
    }

    private func dayActivityRing(totalSeconds: Int) -> some View {
        let minutes = Double(totalSeconds) / 60.0
        let goal = Double(dailyGoalMinutes)
        let percentage = goal > 0 ? min(minutes / goal, 1.0) : 0.0
        
        return HStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(AppColors.progressTrack.opacity(0.8), lineWidth: 16)
                
                Circle()
                    .trim(from: 0.0, to: CGFloat(percentage))
                    .stroke(
                        LinearGradient(
                            colors: [AppColors.accentBlue, AppColors.accentTeal],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: percentage)
                    .shadow(color: AppColors.accentBlue.opacity(percentage > 0.8 ? 0.3 : 0), radius: 6, x: 0, y: 3)
                
                VStack {
                    Text(String(format: "%.0f%%", percentage * 100))
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(AppColors.primaryText)
                    
                    Text(NSLocalizedString("stats_active", comment: ""))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppColors.secondaryText)
                }
            }
            .frame(width: 110, height: 110)
            .padding(.vertical, 8)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(formattedDuration(totalSeconds))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AppColors.primaryText)
                
                Text(String(format: NSLocalizedString("stats_chart_goal_line_val", comment: ""), dailyGoalMinutes))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
                
                if minutes >= goal {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(NSLocalizedString("stats_chart_goal_reached", comment: ""))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(6)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 10)
    }

    private func weekChart(_ data: [ChartDataItem]) -> some View {
        let goalMinutes = Double(dailyGoalMinutes)
        
        return Chart {
            ForEach(data) { item in
                BarMark(
                    x: .value("Day", item.date, unit: .day),
                    y: .value("Minutes", item.value),
                    width: .fixed(16)
                )
                .foregroundStyle(
                    item.value >= goalMinutes ?
                    LinearGradient(
                        colors: [AppColors.accentTeal, Color(red: 0.22, green: 0.65, blue: 0.43)],
                        startPoint: .bottom,
                        endPoint: .top
                    ) :
                    LinearGradient(
                        colors: [AppColors.accentBlue, AppColors.accentTeal],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .cornerRadius(6)
            }
            
            RuleMark(
                y: .value("Goal", goalMinutes)
            )
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            .foregroundStyle(.orange)
            
            if let selectedDate = selectedChartDate {
                RuleMark(
                    x: .value("Selected", selectedDate, unit: .day)
                )
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                .foregroundStyle(AppColors.accentTeal)
                
                if let matchedItem = data.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
                    PointMark(
                        x: .value("SelectedX", matchedItem.date, unit: .day),
                        y: .value("SelectedY", matchedItem.value)
                    )
                    .foregroundStyle(AppColors.accentTeal)
                    .symbolSize(100)
                }
            }
        }
        .frame(height: 180)
        .chartXSelection(value: $selectedChartDate)
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }

    private func monthChart(_ data: [ChartDataItem]) -> some View {
        Chart {
            ForEach(data) { item in
                AreaMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Minutes", item.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.accentBlue.opacity(0.4), AppColors.accentBlue.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
                
                LineMark(
                    x: .value("Date", item.date, unit: .day),
                    y: .value("Minutes", item.value)
                )
                .lineStyle(StrokeStyle(lineWidth: 3))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.accentBlue, AppColors.accentTeal],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .interpolationMethod(.catmullRom)
            }
            
            if let selectedDate = selectedChartDate {
                RuleMark(
                    x: .value("Selected", selectedDate, unit: .day)
                )
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                .foregroundStyle(AppColors.accentTeal)
                
                if let matchedItem = data.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDate) }) {
                    PointMark(
                        x: .value("SelectedX", matchedItem.date, unit: .day),
                        y: .value("SelectedY", matchedItem.value)
                    )
                    .foregroundStyle(AppColors.accentTeal)
                    .symbolSize(100)
                }
            }
        }
        .frame(height: 180)
        .chartXSelection(value: $selectedChartDate)
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }

    private func yearChart(_ data: [ChartDataItem]) -> some View {
        Chart {
            ForEach(data) { item in
                BarMark(
                    x: .value("Month", item.date, unit: .month),
                    y: .value("Minutes", item.value),
                    width: .fixed(12)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.accentBlue, AppColors.accentTeal],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .cornerRadius(4)
            }
            
            if let selectedDate = selectedChartDate {
                RuleMark(
                    x: .value("Selected", selectedDate, unit: .month)
                )
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                .foregroundStyle(AppColors.accentTeal)
                
                if let matchedItem = data.first(where: { Calendar.current.isDate($0.date, equalTo: selectedDate, toGranularity: .month) }) {
                    PointMark(
                        x: .value("SelectedX", matchedItem.date, unit: .month),
                        y: .value("SelectedY", matchedItem.value)
                    )
                    .foregroundStyle(AppColors.accentTeal)
                    .symbolSize(100)
                }
            }
        }
        .frame(height: 180)
        .chartXSelection(value: $selectedChartDate)
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }

    private func summaryBookChart(_ data: [BookChartItem]) -> some View {
        let topData = Array(data.prefix(5))
        let otherSum = data.dropFirst(5).reduce(0.0) { $0 + $1.value }
        
        var displayData = topData
        if otherSum > 0 {
            displayData.append(BookChartItem(bookId: "other", title: NSLocalizedString("stats_unknown_book", comment: ""), value: otherSum))
        }
        
        let totalMinutes = displayData.reduce(0.0) { $0 + $1.value }
        
        return HStack(spacing: 16) {
            if totalMinutes > 0 {
                Chart(displayData) { item in
                    SectorMark(
                        angle: .value("Value", item.value),
                        innerRadius: .ratio(0.65),
                        outerRadius: .ratio(1.0),
                        angularInset: 1.5
                    )
                    .cornerRadius(4)
                    .foregroundStyle(by: .value("Book", item.title))
                }
                .chartLegend(.hidden)
                .frame(width: 120, height: 120)
                
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(displayData.prefix(4)) { item in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(bookColor(for: item.title))
                                .frame(width: 8, height: 8)
                            
                            Text(item.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(String(format: "%.0f%%", totalMinutes > 0 ? (item.value / totalMinutes) * 100 : 0))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppColors.secondaryText)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            } else {
                emptyActivity
            }
        }
        .padding(.vertical, 8)
    }

    private func bookColor(for title: String) -> Color {
        let hash = abs(title.hashValue)
        let colors: [Color] = [.blue, .indigo, .purple, .teal, .orange, .pink, .green]
        return colors[hash % colors.count]
    }

    private func infoPanelDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppAppearancePreferences.locale
        switch selectedStatsScope {
        case .day, .week, .month:
            formatter.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
            return formatter.string(from: date)
        case .year:
            formatter.dateFormat = "yyyy MMMM"
            return formatter.string(from: date)
        case .summary:
            return ""
        }
    }

    private func infoPanelValue(for date: Date, stats: ReadingStatsSnapshot) -> Double {
        let key = dateFormatter.string(from: date)
        switch selectedStatsScope {
        case .day, .week, .month:
            let seconds = stats.dailyStats.first(where: { $0.dateKey == key })?.seconds ?? 0
            return Double(seconds) / 60.0
        case .year:
            let calendar = Calendar.current
            guard let monthRange = calendar.dateInterval(of: .month, for: date) else { return 0 }
            let sumSeconds = stats.dailyStats.filter { stat in
                if let statDate = dateFormatter.date(from: stat.dateKey) {
                    return statDate >= monthRange.start && statDate < monthRange.end
                }
                return false
            }.reduce(0) { $0 + $1.seconds }
            return Double(sumSeconds) / 60.0
        case .summary:
            return 0
        }
    }

    struct HeatmapItem: Identifiable {
        let stableId: String
        let date: Date?
        let seconds: Int

        var id: String { stableId }
    }

    private func heatmapGrid(_ stats: ReadingStatsSnapshot) -> some View {
        let calendar = Calendar.current
        guard let monthRange = calendar.dateInterval(of: .month, for: currentReferenceDate) else { return AnyView(EmptyView()) }
        let numberOfDays = calendar.range(of: .day, in: .month, for: currentReferenceDate)?.count ?? 30
        
        let components = calendar.dateComponents([.year, .month], from: monthRange.start)
        guard let firstDayOfMonth = calendar.date(from: components) else { return AnyView(EmptyView()) }
        let weekday = calendar.component(.weekday, from: firstDayOfMonth)
        
        // alignment offset for calendar days
        let leadingSpaces = (weekday + 5) % 7
        
        var gridItems: [HeatmapItem] = []
        
        for index in 0..<leadingSpaces {
            gridItems.append(HeatmapItem(stableId: "pad-\(index)", date: nil, seconds: 0))
        }
        
        for i in 0..<numberOfDays {
            if let date = calendar.date(byAdding: .day, value: i, to: monthRange.start) {
                let key = dateFormatter.string(from: date)
                let seconds = stats.dailyStats.first(where: { $0.dateKey == key })?.seconds ?? 0
                gridItems.append(HeatmapItem(stableId: key, date: date, seconds: seconds))
            }
        }
        
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                Text(NSLocalizedString("settings_stats_section", comment: ""))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(AppColors.primaryText)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(gridItems) { item in
                        if let date = item.date {
                            let color = heatmapColor(for: item.seconds)
                            let isSelected = selectedChartDate != nil && calendar.isDate(selectedChartDate!, inSameDayAs: date)
                            
                            RoundedRectangle(cornerRadius: 4)
                                .fill(color)
                                .aspectRatio(1.0, contentMode: .fit)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(AppColors.accentTeal, lineWidth: isSelected ? 2 : 0)
                                )
                                .onTapGesture {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    withAnimation(.spring()) {
                                        if isSelected {
                                            selectedChartDate = nil
                                        } else {
                                            selectedChartDate = date
                                        }
                                    }
                                }
                        } else {
                            Color.clear
                                .aspectRatio(1.0, contentMode: .fit)
                        }
                    }
                }
                .padding(12)
                .background(AppColors.cardBackground)
                .cornerRadius(16)
            }
        )
    }

    private func heatmapColor(for seconds: Int) -> Color {
        let minutes = seconds / 60
        if minutes <= 0 {
            return colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
        } else if minutes < 10 {
            return AppColors.accentBlue.opacity(0.2)
        } else if minutes < 30 {
            return AppColors.accentBlue.opacity(0.5)
        } else {
            return AppColors.accentTeal
        }
    }

    private func groupedTimelineCard(_ stats: ReadingStatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(timelineTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppColors.primaryText)
            
            if stats.dailyStats.isEmpty {
                emptyActivity
            } else {
                switch selectedStatsScope {
                case .summary:
                    summaryLeaderboardList(makeBookChartData(from: stats.dailyStats))
                case .year:
                    yearGroupedList(stats.dailyStats)
                case .month:
                    monthActiveDaysList(stats.dailyStats)
                case .week:
                    weekDaysList(makeWeekChartData(from: stats.dailyStats))
                case .day:
                    daySessionsList(stats.dailyStats)
                }
            }
        }
        .padding(18)
        .cardStyle()
    }
    
    private var timelineTitle: String {
        switch selectedStatsScope {
        case .summary:
            return NSLocalizedString("stats_book_ranking", comment: "")
        default:
            return NSLocalizedString("stats_activity_title", comment: "")
        }
    }

    struct MonthlyWeekGroup: Identifiable {
        let id = UUID()
        let weekNumber: Int
        let dateRangeString: String
        let stats: [DailyReadingStat]
    }
    
    private func makeMonthlyWeekGroups(from stats: [DailyReadingStat]) -> [MonthlyWeekGroup] {
        let calendar = Calendar.current
        let activeStats = stats.filter { $0.seconds > 0 }
        
        var week1: [DailyReadingStat] = []
        var week2: [DailyReadingStat] = []
        var week3: [DailyReadingStat] = []
        var week4: [DailyReadingStat] = []
        
        for stat in activeStats {
            guard let date = dateFormatter.date(from: stat.dateKey) else { continue }
            let day = calendar.component(.day, from: date)
            if day <= 7 {
                week1.append(stat)
            } else if day <= 14 {
                week2.append(stat)
            } else if day <= 21 {
                week3.append(stat)
            } else {
                week4.append(stat)
            }
        }
        
        var groups: [MonthlyWeekGroup] = []
        
        if !week1.isEmpty {
            groups.append(MonthlyWeekGroup(weekNumber: 1, dateRangeString: "1-7", stats: week1))
        }
        if !week2.isEmpty {
            groups.append(MonthlyWeekGroup(weekNumber: 2, dateRangeString: "8-14", stats: week2))
        }
        if !week3.isEmpty {
            groups.append(MonthlyWeekGroup(weekNumber: 3, dateRangeString: "15-21", stats: week3))
        }
        if !week4.isEmpty {
            groups.append(MonthlyWeekGroup(weekNumber: 4, dateRangeString: "22+", stats: week4))
        }
        
        return groups
    }

    private func summaryLeaderboardList(_ data: [BookChartItem]) -> some View {
        let totalMinutes = data.reduce(0.0) { $0 + $1.value }
        let topThreeColors: [Color] = [
            Color(red: 0.98, green: 0.76, blue: 0.03), // Gold
            Color(red: 0.72, green: 0.72, blue: 0.72), // Silver
            Color(red: 0.80, green: 0.49, blue: 0.19)  // Bronze
        ]
        
        return VStack(spacing: 16) {
            ForEach(Array(data.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 14) {
                    ZStack(alignment: .topLeading) {
                        if let book = booksMap[item.bookId],
                           let coverURL = book.cover?.url {
                            AsyncImage(url: coverURL) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color(.secondarySystemBackground)
                            }
                            .frame(width: 36, height: 50)
                            .cornerRadius(6)
                            .clipped()
                        } else {
                            ZStack {
                                Color(.secondarySystemBackground)
                                Image(systemName: "book.closed")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .frame(width: 36, height: 50)
                            .cornerRadius(6)
                        }
                        
                        if index < 3 {
                            Image(systemName: "crown.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(topThreeColors[index])
                                .clipShape(Circle())
                                .offset(x: -6, y: -6)
                                .shadow(radius: 2)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(item.title)
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(AppColors.primaryText)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(formattedDuration(Int(item.value * 60)))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AppColors.primaryText)
                                .monospacedDigit()
                        }
                        
                        HStack {
                            if let author = booksMap[item.bookId]?.authors {
                                Text(author)
                                    .font(.system(size: 12))
                                    .foregroundColor(AppColors.secondaryText)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Text(String(format: "%.0f%%", totalMinutes > 0 ? (item.value / totalMinutes) * 100 : 0))
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppColors.secondaryText)
                        }
                        
                        GeometryReader { geo in
                            let ratio = totalMinutes > 0 ? CGFloat(item.value / totalMinutes) : 0
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(AppColors.progressTrack.opacity(0.5))
                                    .frame(height: 4)
                                
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(LinearGradient(
                                        colors: [AppColors.accentBlue, AppColors.accentTeal],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ))
                                    .frame(width: geo.size.width * ratio, height: 4)
                            }
                        }
                        .frame(height: 4)
                        .padding(.top, 2)
                    }
                }
                
                if item.id != data.last?.id {
                    Divider()
                }
            }
        }
    }

    private func yearGroupedList(_ stats: [DailyReadingStat]) -> some View {
        let items = makeYearChartData(from: stats)
            .filter { $0.value > 0 }
        
        return VStack(spacing: 12) {
            ForEach(items) { item in
                Button(action: {
                    let feedback = UIImpactFeedbackGenerator(style: .medium)
                    feedback.impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        currentReferenceDate = item.date
                        selectedStatsScope = .month
                    }
                }) {
                    HStack {
                        Text(item.label)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppColors.primaryText)
                        
                        Spacer()
                        
                        HStack(spacing: 6) {
                            Text(formattedDuration(Int(item.value * 60)))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(AppColors.primaryText)
                                .monospacedDigit()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(AppColors.tertiaryText)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                if item.id != items.last?.id {
                    Divider()
                }
            }
        }
    }

    private func monthActiveDaysList(_ stats: [DailyReadingStat]) -> some View {
        let groups = makeMonthlyWeekGroups(from: stats)
        
        if groups.isEmpty {
            return AnyView(emptyActivity)
        }
        
        return AnyView(
            VStack(spacing: 12) {
                ForEach(groups) { group in
                    let isExpanded = expandedWeeks.contains(group.weekNumber)
                    let totalSeconds = group.stats.reduce(0) { $0 + $1.seconds }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                if isExpanded {
                                    expandedWeeks.remove(group.weekNumber)
                                } else {
                                    expandedWeeks.insert(group.weekNumber)
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: "chevron.right")
                                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(AppColors.secondaryText)
                                
                                Text(String(format: NSLocalizedString("stats_week_group", comment: ""), group.weekNumber, group.dateRangeString))
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(AppColors.primaryText)
                                
                                Spacer()
                                
                                Text(formattedDuration(totalSeconds))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppColors.secondaryText)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        if isExpanded {
                            VStack(spacing: 10) {
                                ForEach(group.stats) { stat in
                                    HStack {
                                        Text(formattedDate(stat.dateKey))
                                            .font(.system(size: 13))
                                            .foregroundColor(AppColors.primaryText)
                                            .padding(.leading, 20)
                                        
                                        Spacer()
                                        
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(formattedDuration(stat.seconds))
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(AppColors.primaryText)
                                                .monospacedDigit()
                                            
                                            Text(String(format: NSLocalizedString("stats_sessions_value", comment: ""), stat.sessions))
                                                .font(.system(size: 10))
                                                .foregroundColor(AppColors.secondaryText)
                                        }
                                    }
                                    if stat.id != group.stats.last?.id {
                                        Divider().padding(.leading, 20)
                                    }
                                }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .padding(.top, 4)
                        }
                    }
                    if group.weekNumber != groups.last?.weekNumber {
                        Divider()
                    }
                }
            }
        )
    }

  private func weekDaysList(_ data: [ChartDataItem]) -> some View {
      let goalMinutes = Double(dailyGoalMinutes)
      
      return VStack(spacing: 12) {
          ForEach(data) { item in
              HStack {
                  Text(item.label)
                      .font(.system(size: 14, weight: .semibold))
                      .foregroundColor(AppColors.primaryText)
                  
                  Spacer()
                  
                  HStack(spacing: 10) {
                      Text(formattedDuration(Int(item.value * 60)))
                          .font(.system(size: 13, weight: .bold))
                          .foregroundColor(AppColors.primaryText)
                          .monospacedDigit()
                      
                      if item.value >= goalMinutes {
                          Image(systemName: "checkmark.circle.fill")
                              .foregroundColor(.green)
                              .font(.system(size: 14))
                      } else if item.value > 0 {
                          Image(systemName: "circle.dotted")
                              .foregroundColor(.orange)
                              .font(.system(size: 14))
                      } else {
                          Image(systemName: "circle")
                              .foregroundColor(AppColors.tertiaryText)
                              .font(.system(size: 14))
                      }
                  }
              }
              if item.id != data.last?.id {
                  Divider()
              }
          }
      }
  }

  private func daySessionsList(_ stats: [DailyReadingStat]) -> some View {
      guard let todayStat = stats.first else { return AnyView(emptyActivity) }
      
      let bookItems: [BookChartItem] = {
          if let bookSeconds = todayStat.bookSeconds {
              return bookSeconds.map { (bookId, sec) in
                  let title = booksMap[bookId]?.title ?? NSLocalizedString("stats_unknown_book", comment: "")
                  return BookChartItem(bookId: bookId, title: title, value: Double(sec) / 60.0)
              }
              .sorted { $0.value > $1.value }
          } else {
              let count = todayStat.bookIds.count
              guard count > 0 else { return [] }
              let avgSec = todayStat.seconds / count
              return todayStat.bookIds.map { bId in
                  let title = booksMap[bId]?.title ?? NSLocalizedString("stats_unknown_book", comment: "")
                  return BookChartItem(bookId: bId, title: title, value: Double(avgSec) / 60.0)
              }
          }
      }()
      
      return AnyView(
          VStack(spacing: 12) {
              ForEach(bookItems) { item in
                  HStack {
                      VStack(alignment: .leading, spacing: 4) {
                          Text(item.title)
                              .font(.system(size: 14, weight: .semibold))
                              .foregroundColor(AppColors.primaryText)
                              .lineLimit(1)
                          
                          if let author = booksMap[item.bookId]?.authors {
                              Text(author)
                                  .font(.system(size: 12))
                                  .foregroundColor(AppColors.secondaryText)
                                  .lineLimit(1)
                          }
                      }
                      
                      Spacer()
                      
                      Text(formattedDuration(Int(item.value * 60)))
                          .font(.system(size: 13, weight: .bold))
                          .foregroundColor(AppColors.primaryText)
                          .monospacedDigit()
                  }
                  if item.id != bookItems.last?.id {
                      Divider()
                  }
              }
          }
      )
  }

    private var emptyActivity: some View {
        VStack(spacing: 10) {
            Image(systemName: "book")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(AppColors.tertiaryText)

            Text(NSLocalizedString("stats_empty", comment: ""))
                .font(.system(size: 14))
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var lockedStatsView: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(
                            colors: [
                                AppColors.accentBlue.opacity(colorScheme == .dark ? 0.28 : 0.14),
                                AppColors.accentTeal.opacity(colorScheme == .dark ? 0.24 : 0.12)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))

                    Image(systemName: "lock.open.rotation")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(AppColors.accentBlue)
                }
                .frame(width: 64, height: 64)

                Text(NSLocalizedString("stats_pro_locked_title", comment: ""))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(AppColors.primaryText)

                Text(NSLocalizedString("stats_pro_locked_body", comment: ""))
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            VStack(spacing: 0) {
                lockedFeature(icon: "chart.bar.fill", text: NSLocalizedString("paywall_feature_stats", comment: ""))
                Divider().padding(.leading, 42)
                lockedFeature(icon: "flame.fill", text: NSLocalizedString("paywall_feature_streak", comment: ""))
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(16)

            Button(action: {
                Analytics.shared.log(.paywallViewed(source: "stats_locked_view"))
                showPaywall = true
            }) {
                Text(NSLocalizedString("stats_upgrade_pro", comment: ""))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(LinearGradient(
                        colors: [AppColors.accentBlue, AppColors.accentTeal],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .cornerRadius(14)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .cardStyle()
    }

    private func lockedFeature(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(AppColors.accentBlue)
                .frame(width: 30, height: 30)

            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(AppColors.primaryText)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func todayState(for stats: ReadingStatsSnapshot) -> String {
        stats.totalSeconds > 0 ? NSLocalizedString("stats_active", comment: "") : NSLocalizedString("stats_inactive", comment: "")
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return String(format: NSLocalizedString("stats_hours_minutes", comment: ""), hours, minutes)
        } else {
            return String(format: NSLocalizedString("stats_minutes", comment: ""), minutes)
        }
    }

    private func formattedDate(_ dateKey: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = AppAppearancePreferences.locale
        guard let date = formatter.date(from: dateKey) else { return dateKey }

        let displayFormatter = DateFormatter()
        displayFormatter.locale = AppAppearancePreferences.locale
        displayFormatter.setLocalizedDateFormatFromTemplate("MMMd")
        return displayFormatter.string(from: date)
    }

    // Chart Data Helpers
    
    struct ChartDataItem: Identifiable {
        let label: String
        let date: Date
        let value: Double

        var id: TimeInterval { date.timeIntervalSinceReferenceDate }
    }
    
    struct BookChartItem: Identifiable {
        let bookId: String
        let title: String
        let value: Double

        var id: String { bookId }
    }

    private func makeWeekChartData(from stats: [DailyReadingStat]) -> [ChartDataItem] {
        let calendar = Calendar.current
        guard let weekRange = calendar.dateInterval(of: .weekOfYear, for: currentReferenceDate) else { return [] }
        
        var items: [ChartDataItem] = []
        let formatter = DateFormatter()
        formatter.locale = AppAppearancePreferences.locale
        formatter.setLocalizedDateFormatFromTemplate("E")
        
        for i in 0..<7 {
            if let date = calendar.date(byAdding: .day, value: i, to: weekRange.start) {
                let key = dateFormatter.string(from: date)
                let seconds = stats.first(where: { $0.dateKey == key })?.seconds ?? 0
                let label = formatter.string(from: date)
                items.append(ChartDataItem(label: label, date: date, value: Double(seconds) / 60.0))
            }
        }
        return items
    }

    private func makeMonthChartData(from stats: [DailyReadingStat]) -> [ChartDataItem] {
        let calendar = Calendar.current
        guard let monthRange = calendar.dateInterval(of: .month, for: currentReferenceDate) else { return [] }
        let numberOfDays = calendar.range(of: .day, in: .month, for: currentReferenceDate)?.count ?? 30
        
        var items: [ChartDataItem] = []
        let formatter = DateFormatter()
        formatter.locale = AppAppearancePreferences.locale
        formatter.dateFormat = "d"
        
        for i in 0..<numberOfDays {
            if let date = calendar.date(byAdding: .day, value: i, to: monthRange.start) {
                let key = dateFormatter.string(from: date)
                let seconds = stats.first(where: { $0.dateKey == key })?.seconds ?? 0
                let label = formatter.string(from: date)
                items.append(ChartDataItem(label: label, date: date, value: Double(seconds) / 60.0))
            }
        }
        return items
    }

    private func makeYearChartData(from stats: [DailyReadingStat]) -> [ChartDataItem] {
        let calendar = Calendar.current
        guard let yearRange = calendar.dateInterval(of: .year, for: currentReferenceDate) else { return [] }
        
        var items: [ChartDataItem] = []
        let formatter = DateFormatter()
        formatter.locale = AppAppearancePreferences.locale
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        
        for i in 0..<12 {
            if let monthStartDate = calendar.date(byAdding: .month, value: i, to: yearRange.start),
               let monthRange = calendar.dateInterval(of: .month, for: monthStartDate) {
                let monthlySeconds = stats.filter { stat in
                    if let statDate = dateFormatter.date(from: stat.dateKey) {
                        return statDate >= monthRange.start && statDate < monthRange.end
                    }
                    return false
                }.reduce(0) { $0 + $1.seconds }
                
                let label = formatter.string(from: monthStartDate)
                items.append(ChartDataItem(label: label, date: monthStartDate, value: Double(monthlySeconds) / 60.0))
            }
        }
        return items
    }

    private func makeBookChartData(from stats: [DailyReadingStat]) -> [BookChartItem] {
        var totals: [String: Int] = [:]
        for stat in stats {
            if let bookSeconds = stat.bookSeconds {
                for (bId, sec) in bookSeconds {
                    totals[bId] = (totals[bId] ?? 0) + sec
                }
            } else {
                let bookCount = stat.bookIds.count
                if bookCount > 0 {
                    let averageSeconds = stat.seconds / bookCount
                    for bId in stat.bookIds {
                        totals[bId] = (totals[bId] ?? 0) + averageSeconds
                    }
                }
            }
        }
        
        return totals.map { (bookId, seconds) in
            let title = booksMap[bookId]?.title ?? "\(NSLocalizedString("stats_unknown_book", comment: "")) (\(bookId))"
            return BookChartItem(bookId: bookId, title: title, value: Double(seconds) / 60.0)
        }
        .sorted { $0.value > $1.value }
    }

    private func updateStreakAnimation() {
        let streakDays = statsStore.snapshot(
            for: selectedStatsScope,
            referenceDate: currentReferenceDate
        ).currentStreakDays

        if streakDays > 0 {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                streakScale = 1.12
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                    streakScale = 1.0
                }
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                streakScale = 1.0
            }
        }
    }

    private func badgesSection(_ stats: ReadingStatsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("badge_section_title", comment: ""))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(AppColors.primaryText)
                .padding(.top, 8)
                .padding(.leading, 4)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(stats.badges) { badge in
                    badgeCard(badge)
                }
            }
        }
        .padding(.bottom, 8)
    }
    
    private func badgeCard(_ badge: ReadingBadge) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(badge.isUnlocked ? 
                          AnyShapeStyle(LinearGradient(
                              colors: [AppColors.accentBlue, AppColors.accentTeal],
                              startPoint: .topLeading,
                              endPoint: .bottomTrailing
                          )) :
                          AnyShapeStyle(Color(.tertiarySystemGroupedBackground)))
                    .frame(width: 44, height: 44)
                
                Image(systemName: badge.iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(badge.isUnlocked ? .white : AppColors.secondaryText)
            }
            .padding(.top, 12)
            
            Text(NSLocalizedString(badge.titleKey, comment: ""))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(AppColors.primaryText)
                .lineLimit(1)
            
            Text(NSLocalizedString(badge.descKey, comment: ""))
                .font(.system(size: 10))
                .foregroundColor(AppColors.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 28)
                .padding(.horizontal, 8)
            
            // Progress text and bar
            VStack(spacing: 4) {
                ProgressView(value: badge.progress)
                    .tint(badge.isUnlocked ? AppColors.accentBlue : AppColors.secondaryText)
                    .scaleEffect(x: 1, y: 0.5, anchor: .center)
                    .padding(.horizontal, 16)
                
                Text(badgeProgressText(badge))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(AppColors.secondaryText)
            }
            .padding(.bottom, 12)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(badge.isUnlocked ? AppColors.accentBlue.opacity(0.15) : Color.clear, lineWidth: 1)
        )
    }
    
    private func badgeProgressText(_ badge: ReadingBadge) -> String {
        if badge.isUnlocked {
            return NSLocalizedString("stats_progress_done", comment: "")
        }
        
        if badge.id == "deep_reader" {
            return String(format: NSLocalizedString("stats_minutes", comment: ""), badge.currentValue) + " / " + String(format: NSLocalizedString("stats_minutes", comment: ""), badge.targetValue)
        }
        
        switch badge.id {
        case "early_bird", "night_owl", "super_streak":
            let format = NSLocalizedString("stats_days_value", comment: "")
            return "\(badge.currentValue) / \(String(format: format, badge.targetValue))"
        case "book_collector":
            return "\(badge.currentValue) / \(badge.targetValue)"
        case "watch_pilot":
            return "\(badge.currentValue) / \(badge.targetValue)"
        default:
            return "\(badge.currentValue)/\(badge.targetValue)"
        }
    }

    private func loadBooksData() {
        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return
        }
        Task {
            do {
                let books = try await appDelegate.app.db.read { db in
                    try Book.fetchAll(db)
                }
                await MainActor.run {
                    var map: [String: Book] = [:]
                    for book in books {
                        if let id = book.id {
                            map[id.string] = book
                        }
                    }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        self.booksMap = map
                    }
                }
            } catch {
                print("Failed to load books for stats: \(error)")
            }
        }
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private extension ReadingStatsScope {
    var symbolName: String {
        switch self {
        case .summary:
            return "chart.pie.fill"
        case .day:
            return "sun.max.fill"
        case .week:
            return "calendar.badge.clock"
        case .month:
            return "calendar"
        case .year:
            return "chart.bar.fill"
        }
    }

    var summaryTitle: String {
        switch self {
        case .summary:
            return NSLocalizedString("stats_summary_all_time", comment: "")
        case .day:
            return NSLocalizedString("stats_summary_today", comment: "")
        case .week:
            return NSLocalizedString("stats_summary_week", comment: "")
        case .month:
            return NSLocalizedString("stats_summary_month", comment: "")
        case .year:
            return NSLocalizedString("stats_summary_year", comment: "")
        }
    }
}

#Preview {
    NavigationView {
        ReadingStatsView()
    }
}
