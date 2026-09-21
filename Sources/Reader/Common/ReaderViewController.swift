//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import ReadiumNavigator
import ReadiumShared
import SafariServices
import SwiftUI
import UIKit

struct ReaderSessionLifecycle {
    struct ActiveSession {
        let bookId: Book.Id
        let startedAt: Date
        let startProgression: Double
        var watchPageTurns: Int = 0
    }

    struct FinishedSession {
        let bookId: Book.Id
        let startedAt: Date
        let endedAt: Date
        let startProgression: Double
        let watchPageTurns: Int
    }

    private let bookId: Book.Id
    private(set) var isReaderVisible = false
    private var activeSession: ActiveSession?

    init(bookId: Book.Id) {
        self.bookId = bookId
    }

    mutating func readerDidAppear(
        at startedAt: Date,
        progression: Double,
        applicationIsActive: Bool
    ) -> ActiveSession? {
        isReaderVisible = true
        return startIfNeeded(
            at: startedAt,
            progression: progression,
            applicationIsActive: applicationIsActive
        )
    }

    mutating func readerWillDisappear(at endedAt: Date) -> FinishedSession? {
        isReaderVisible = false
        return finishIfNeeded(at: endedAt)
    }

    mutating func applicationDidEnterBackground(at endedAt: Date) -> FinishedSession? {
        finishIfNeeded(at: endedAt)
    }

    mutating func applicationDidBecomeActive(
        at startedAt: Date,
        progression: Double
    ) -> ActiveSession? {
        startIfNeeded(
            at: startedAt,
            progression: progression,
            applicationIsActive: true
        )
    }

    mutating func recordSuccessfulWatchPageTurn(origin: WatchPageTurnOrigin) {
        guard var session = activeSession else { return }
        session.watchPageTurns += 1
        activeSession = session
    }

    private mutating func startIfNeeded(
        at startedAt: Date,
        progression: Double,
        applicationIsActive: Bool
    ) -> ActiveSession? {
        guard isReaderVisible,
              applicationIsActive,
              activeSession == nil else {
            return nil
        }

        let session = ActiveSession(
            bookId: bookId,
            startedAt: startedAt,
            startProgression: progression
        )
        activeSession = session
        return session
    }

    private mutating func finishIfNeeded(at endedAt: Date) -> FinishedSession? {
        guard let session = activeSession else { return nil }
        activeSession = nil

        return FinishedSession(
            bookId: session.bookId,
            startedAt: session.startedAt,
            endedAt: endedAt,
            startProgression: session.startProgression,
            watchPageTurns: session.watchPageTurns
        )
    }
}

struct ReadingSessionSummary: Equatable {
    enum DailyGoalFeedback: Equatable {
        case remaining(minutes: Int)
        case complete
    }

    let durationSeconds: Int
    let startProgression: Double
    let endProgression: Double
    let progressDelta: Double
    let watchPageTurns: Int
    let dailyGoalFeedback: DailyGoalFeedback?
}

enum ReadingSessionSummaryPolicy {
    static let minimumDurationSeconds = 2 * 60
    static let minimumForwardProgress = 0.01
    static let minimumWatchPageTurns = 5
    private static let progressComparisonTolerance = 1e-9

    static func makeSummary(
        for session: ReadingSession,
        todaySeconds: Int,
        goalMinutes: Int,
        suppressGoalCompletion: Bool
    ) -> ReadingSessionSummary? {
        let isMeaningful =
            session.durationSeconds >= minimumDurationSeconds
            || session.progressDelta >= minimumForwardProgress - progressComparisonTolerance
            || session.watchPageTurns >= minimumWatchPageTurns

        guard isMeaningful else { return nil }

        let dailyGoalFeedback: ReadingSessionSummary.DailyGoalFeedback?
        if goalMinutes <= 0 {
            dailyGoalFeedback = nil
        } else {
            let goalSeconds = goalMinutes * 60
            if todaySeconds >= goalSeconds {
                dailyGoalFeedback = suppressGoalCompletion ? nil : .complete
            } else {
                let remainingSeconds = max(0, goalSeconds - todaySeconds)
                let remainingMinutes = max(1, (remainingSeconds + 59) / 60)
                dailyGoalFeedback = .remaining(minutes: remainingMinutes)
            }
        }

        return ReadingSessionSummary(
            durationSeconds: session.durationSeconds,
            startProgression: session.startProgression,
            endProgression: session.endProgression,
            progressDelta: session.progressDelta,
            watchPageTurns: session.watchPageTurns,
            dailyGoalFeedback: dailyGoalFeedback
        )
    }
}

enum ReadingSessionSummaryLayoutPolicy {
    static let horizontalInset: CGFloat = 24
    static let maximumContentWidth: CGFloat = 480

    static func contentWidth(for containerWidth: CGFloat) -> CGFloat {
        max(0, min(maximumContentWidth, containerWidth - horizontalInset * 2))
    }
}

private enum SummaryColors {
    static let accentBlue = UIColor(red: 56 / 255, green: 110 / 255, blue: 242 / 255, alpha: 1)
    static let accentTeal = UIColor(red: 41 / 255, green: 158 / 255, blue: 148 / 255, alpha: 1)
    static let background = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 15 / 255, green: 16 / 255, blue: 19 / 255, alpha: 1)
            : UIColor(red: 246 / 255, green: 248 / 255, blue: 252 / 255, alpha: 1)
    }
    static let cardBackground = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 26 / 255, green: 28 / 255, blue: 32 / 255, alpha: 1)
            : .white
    }
    static let cardBorder = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.06)
            : UIColor.black.withAlphaComponent(0.04)
    }
}

private final class SummaryCardView: UIView {
    init() {
        super.init(frame: .zero)
        backgroundColor = SummaryColors.cardBackground
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = SummaryColors.cardBorder.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.04
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        layer.borderColor = SummaryColors.cardBorder.cgColor
    }
}

private final class SummaryActionRowButton: UIButton {
    init(title: String, iconName: String, tintColor: UIColor) {
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
        backgroundColor = SummaryColors.cardBackground
        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = SummaryColors.cardBorder.cgColor

        let iconContainer = UIView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.backgroundColor = tintColor.withAlphaComponent(0.12)
        iconContainer.layer.cornerRadius = 10
        iconContainer.layer.cornerCurve = .continuous
        iconContainer.isUserInteractionEnabled = false
        addSubview(iconContainer)

        let iconImageView = UIImageView(image: UIImage(
            systemName: iconName,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        ))
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        iconImageView.tintColor = tintColor
        iconImageView.contentMode = .scaleAspectFit
        iconImageView.isUserInteractionEnabled = false
        iconContainer.addSubview(iconImageView)

        let titleLabelView = UILabel()
        titleLabelView.translatesAutoresizingMaskIntoConstraints = false
        titleLabelView.text = title
        titleLabelView.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabelView.textColor = .label
        titleLabelView.isUserInteractionEnabled = false
        addSubview(titleLabelView)

        let chevron = UIImageView(image: UIImage(
            systemName: "chevron.right",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        ))
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.tintColor = .tertiaryLabel
        chevron.contentMode = .scaleAspectFit
        chevron.isUserInteractionEnabled = false
        addSubview(chevron)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 48),

            iconContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            iconContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 30),
            iconContainer.heightAnchor.constraint(equalToConstant: 30),

            iconImageView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),

            titleLabelView.leadingAnchor.constraint(equalTo: iconContainer.trailingAnchor, constant: 12),
            titleLabelView.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabelView.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -8),

            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        layer.borderColor = SummaryColors.cardBorder.cgColor
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.alpha = self.isHighlighted ? 0.65 : 1.0
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
            }
        }
    }
}

private final class SummaryBrandButton: UIButton {
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        gradientLayer.colors = [
            SummaryColors.accentBlue.cgColor,
            SummaryColors.accentTeal.cgColor,
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        gradientLayer.cornerRadius = 14
        layer.insertSublayer(gradientLayer, at: 0)

        layer.cornerRadius = 14
        layer.cornerCurve = .continuous
        clipsToBounds = true

        setTitleColor(.white, for: .normal)
        titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientLayer.frame = bounds
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.1) {
                self.alpha = self.isHighlighted ? 0.85 : 1.0
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.98, y: 0.98) : .identity
            }
        }
    }
}

final class ReadingSessionSummaryViewController: UIViewController {

    let summary: ReadingSessionSummary
    var onHistoryRequested: (() -> Void)?
    var onPredictionRequested: (() -> Void)?
    private(set) var contentStack = UIStackView()
    private(set) var historyButton = UIButton(type: .custom)
    private(set) var predictionButton = UIButton(type: .custom)
    private(set) var dismissButton = UIButton(type: .custom)

    init(summary: ReadingSessionSummary) {
        self.summary = summary
        super.init(nibName: nil, bundle: nil)
        if UIDevice.current.userInterfaceIdiom == .pad {
            modalPresentationStyle = .formSheet
        } else {
            modalPresentationStyle = .pageSheet
        }
        isModalInPresentation = false
        preferredContentSize = CGSize(
            width: ReadingSessionSummaryLayoutPolicy.maximumContentWidth,
            height: 420
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = SummaryColors.background
        view.accessibilityViewIsModal = true

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = false
        view.addSubview(scrollView)

        contentStack.axis = .vertical
        contentStack.alignment = .fill
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.accessibilityIdentifier = "readingSessionSummary.content"
        scrollView.addSubview(contentStack)

        let titleLabel = makeLabel(
            text: NSLocalizedString("reader_session_summary_title", comment: ""),
            textStyle: .title2
        )
        titleLabel.font = UIFontMetrics(forTextStyle: .title2)
            .scaledFont(for: UIFont.systemFont(ofSize: 20, weight: .bold))
        titleLabel.accessibilityTraits.insert(.header)
        titleLabel.accessibilityIdentifier = "readingSessionSummary.title"
        contentStack.addArrangedSubview(titleLabel)

        // Core metric card
        let metricCard = SummaryCardView()
        metricCard.translatesAutoresizingMaskIntoConstraints = false

        let cardStack = UIStackView()
        cardStack.axis = .vertical
        cardStack.alignment = .fill
        cardStack.spacing = 14
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        metricCard.addSubview(cardStack)

        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: metricCard.topAnchor, constant: 16),
            cardStack.bottomAnchor.constraint(equalTo: metricCard.bottomAnchor, constant: -16),
            cardStack.leadingAnchor.constraint(equalTo: metricCard.leadingAnchor, constant: 16),
            cardStack.trailingAnchor.constraint(equalTo: metricCard.trailingAnchor, constant: -16),
        ])

        // Duration row
        let durationRow = UIStackView()
        durationRow.axis = .horizontal
        durationRow.alignment = .center
        durationRow.spacing = 12

        let timerIconContainer = UIView()
        timerIconContainer.translatesAutoresizingMaskIntoConstraints = false
        timerIconContainer.backgroundColor = SummaryColors.accentBlue.withAlphaComponent(0.12)
        timerIconContainer.layer.cornerRadius = 18
        timerIconContainer.layer.cornerCurve = .continuous
        let timerIcon = UIImageView(image: UIImage(
            systemName: "timer",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        ))
        timerIcon.tintColor = SummaryColors.accentBlue
        timerIcon.translatesAutoresizingMaskIntoConstraints = false
        timerIconContainer.addSubview(timerIcon)

        NSLayoutConstraint.activate([
            timerIconContainer.widthAnchor.constraint(equalToConstant: 36),
            timerIconContainer.heightAnchor.constraint(equalToConstant: 36),
            timerIcon.centerXAnchor.constraint(equalTo: timerIconContainer.centerXAnchor),
            timerIcon.centerYAnchor.constraint(equalTo: timerIconContainer.centerYAnchor),
        ])
        durationRow.addArrangedSubview(timerIconContainer)

        let durationTextStack = UIStackView()
        durationTextStack.axis = .vertical
        durationTextStack.alignment = .leading
        durationTextStack.spacing = 1

        let durationCaption = UILabel()
        durationCaption.text = NSLocalizedString("stats_metric_time", comment: "")
        durationCaption.font = .systemFont(ofSize: 11, weight: .medium)
        durationCaption.textColor = .secondaryLabel
        durationTextStack.addArrangedSubview(durationCaption)

        let durationLabel = makeLabel(
            text: Self.durationText(seconds: summary.durationSeconds),
            textStyle: .title1
        )
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 26, weight: .bold)
        durationLabel.accessibilityIdentifier = "readingSessionSummary.duration"
        durationTextStack.addArrangedSubview(durationLabel)

        durationRow.addArrangedSubview(durationTextStack)
        cardStack.addArrangedSubview(durationRow)

        // Progress row
        let progressStack = UIStackView()
        progressStack.axis = .vertical
        progressStack.alignment = .fill
        progressStack.spacing = 6

        let progressLabel = makeLabel(
            text: progressText(),
            textStyle: .body
        )
        progressLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        progressLabel.textColor = .secondaryLabel
        progressLabel.accessibilityIdentifier = "readingSessionSummary.progress"
        progressStack.addArrangedSubview(progressLabel)

        let progressTrack = UIView()
        progressTrack.translatesAutoresizingMaskIntoConstraints = false
        progressTrack.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.08)
                : UIColor.black.withAlphaComponent(0.06)
        }
        progressTrack.layer.cornerRadius = 3
        progressTrack.clipsToBounds = true

        let progressFill = UIView()
        progressFill.translatesAutoresizingMaskIntoConstraints = false
        progressFill.backgroundColor = SummaryColors.accentTeal
        progressFill.layer.cornerRadius = 3
        progressTrack.addSubview(progressFill)

        let progressMultiplier = CGFloat(min(max(summary.endProgression, 0.03), 1.0))
        NSLayoutConstraint.activate([
            progressTrack.heightAnchor.constraint(equalToConstant: 6),
            progressFill.leadingAnchor.constraint(equalTo: progressTrack.leadingAnchor),
            progressFill.topAnchor.constraint(equalTo: progressTrack.topAnchor),
            progressFill.bottomAnchor.constraint(equalTo: progressTrack.bottomAnchor),
            progressFill.widthAnchor.constraint(equalTo: progressTrack.widthAnchor, multiplier: progressMultiplier),
        ])
        progressStack.addArrangedSubview(progressTrack)
        cardStack.addArrangedSubview(progressStack)

        if summary.watchPageTurns > 0 {
            let watchRow = UIStackView()
            watchRow.axis = .horizontal
            watchRow.alignment = .center
            watchRow.spacing = 6

            let watchIcon = UIImageView(image: UIImage(
                systemName: "applewatch",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            ))
            watchIcon.tintColor = SummaryColors.accentBlue
            watchIcon.contentMode = .scaleAspectFit
            watchRow.addArrangedSubview(watchIcon)

            let format = NSLocalizedString("reader_session_summary_watch_turns_format", comment: "")
            let watchLabel = makeLabel(
                text: String(format: format, summary.watchPageTurns),
                textStyle: .body
            )
            watchLabel.font = .systemFont(ofSize: 12, weight: .medium)
            watchLabel.textColor = .secondaryLabel
            watchLabel.accessibilityIdentifier = "readingSessionSummary.watchTurns"
            watchRow.addArrangedSubview(watchLabel)

            cardStack.addArrangedSubview(watchRow)
        }

        if let dailyGoalFeedback = summary.dailyGoalFeedback {
            let divider = UIView()
            divider.translatesAutoresizingMaskIntoConstraints = false
            divider.backgroundColor = UIColor { traits in
                traits.userInterfaceStyle == .dark
                    ? UIColor.white.withAlphaComponent(0.06)
                    : UIColor.black.withAlphaComponent(0.05)
            }
            NSLayoutConstraint.activate([
                divider.heightAnchor.constraint(equalToConstant: 1),
            ])
            cardStack.addArrangedSubview(divider)

            let goalRow = UIStackView()
            goalRow.axis = .horizontal
            goalRow.alignment = .center
            goalRow.spacing = 6

            let isComplete: Bool
            let goalText: String
            switch dailyGoalFeedback {
            case let .remaining(minutes):
                isComplete = false
                goalText = String(
                    format: NSLocalizedString("stats_goal_remaining_message", comment: ""),
                    minutes
                )
            case .complete:
                isComplete = true
                goalText = NSLocalizedString("stats_goal_complete_message", comment: "")
            }

            let goalIcon = UIImageView(image: UIImage(
                systemName: isComplete ? "checkmark.circle.fill" : "target",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
            ))
            goalIcon.tintColor = isComplete ? SummaryColors.accentTeal : SummaryColors.accentBlue
            goalIcon.contentMode = .scaleAspectFit
            goalRow.addArrangedSubview(goalIcon)

            let goalLabel = makeLabel(text: goalText, textStyle: .subheadline)
            goalLabel.font = .systemFont(ofSize: 12, weight: .medium)
            goalLabel.textColor = .secondaryLabel
            goalLabel.accessibilityIdentifier = "readingSessionSummary.dailyGoal"
            goalRow.addArrangedSubview(goalLabel)

            cardStack.addArrangedSubview(goalRow)
        }

        contentStack.addArrangedSubview(metricCard)

        // Action row buttons
        historyButton = SummaryActionRowButton(
            title: NSLocalizedString("reader_session_summary_history_action", comment: ""),
            iconName: "chart.bar.xaxis",
            tintColor: SummaryColors.accentBlue
        )
        historyButton.addTarget(self, action: #selector(openHistory), for: .touchUpInside)
        historyButton.accessibilityIdentifier = "readingSessionSummary.history"
        contentStack.addArrangedSubview(historyButton)

        predictionButton = SummaryActionRowButton(
            title: NSLocalizedString("reader_session_summary_prediction_action", comment: ""),
            iconName: "speedometer",
            tintColor: SummaryColors.accentTeal
        )
        predictionButton.addTarget(self, action: #selector(openPrediction), for: .touchUpInside)
        predictionButton.accessibilityIdentifier = "readingSessionSummary.prediction"
        contentStack.addArrangedSubview(predictionButton)

        let brandDoneButton = SummaryBrandButton()
        brandDoneButton.translatesAutoresizingMaskIntoConstraints = false
        brandDoneButton.setTitle(NSLocalizedString("reader_session_summary_done", comment: ""), for: .normal)
        brandDoneButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        dismissButton = brandDoneButton
        dismissButton.addTarget(self, action: #selector(dismissSummary), for: .touchUpInside)
        dismissButton.accessibilityIdentifier = "readingSessionSummary.dismiss"
        contentStack.addArrangedSubview(dismissButton)

        let safeArea = view.safeAreaLayoutGuide
        let fillWidth = contentStack.widthAnchor.constraint(
            equalTo: scrollView.frameLayoutGuide.widthAnchor,
            constant: -(ReadingSessionSummaryLayoutPolicy.horizontalInset * 2)
        )
        fillWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: safeArea.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            contentStack.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            contentStack.widthAnchor.constraint(
                lessThanOrEqualToConstant: ReadingSessionSummaryLayoutPolicy.maximumContentWidth
            ),
            fillWidth,
        ])
    }

    private func makeInsightButton(
        title: String,
        action: Selector,
        accessibilityIdentifier: String
    ) -> UIButton {
        let button = SummaryActionRowButton(
            title: title,
            iconName: "chart.bar.xaxis",
            tintColor: SummaryColors.accentBlue
        )
        button.addTarget(self, action: action, for: .touchUpInside)
        button.accessibilityIdentifier = accessibilityIdentifier
        return button
    }

    private func makeLabel(text: String, textStyle: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = UIFont.preferredFont(forTextStyle: textStyle)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textColor = .label
        return label
    }

    private func progressText() -> String {
        let start = Self.percentText(summary.startProgression)
        let end = Self.percentText(summary.endProgression)

        guard summary.progressDelta > 0 else {
            return "\(start) → \(end)"
        }

        let delta = Self.percentText(summary.progressDelta)
        return String(
            format: NSLocalizedString("reader_session_summary_progress_format", comment: ""),
            start,
            end,
            delta
        )
    }

    private static func durationText(seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = seconds >= 3600
            ? [.hour, .minute]
            : (seconds >= 60 ? [.minute] : [.second])

        return formatter.string(from: TimeInterval(max(0, seconds)))
            ?? "\(max(0, seconds))s"
    }

    private static func percentText(_ progression: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0

        return formatter.string(from: NSNumber(value: progression))
            ?? "\(Int((progression * 100).rounded()))%"
    }

    @objc private func openHistory() {
        onHistoryRequested?()
    }

    @objc private func openPrediction() {
        onPredictionRequested?()
    }

    @objc private func dismissSummary() {
        dismiss(animated: true)
    }
}

private struct ReadingSessionInsightSheet: View {
    @Environment(\.dismiss) private var dismiss

    let book: Book?

    var body: some View {
        NavigationStack {
            readingHistoryDestination(book: book)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        SheetCloseButton { dismiss() }
                    }
                }
        }
    }
}

enum ReadingSessionSummaryPresenter {
    static func present(
        _ summary: ReadingSessionSummary,
        bookId: Book.Id,
        after reader: UIViewController
    ) {
        guard let navigationController = reader.navigationController else { return }

        // A completed pop can release the Reader before this deferred block
        // runs. Keep only its identity so presentation does not depend on the
        // popped Reader still being alive.
        let readerIdentifier = ObjectIdentifier(reader)
        let presentationBlock: () -> Void = { [weak navigationController] in
            guard let navigationController,
                  let host = navigationController.topViewController,
                  ObjectIdentifier(host) != readerIdentifier,
                  host.presentedViewController == nil else {
                return
            }

            let summaryViewController = ReadingSessionSummaryViewController(summary: summary)
            summaryViewController.onHistoryRequested = { [weak summaryViewController, weak host] in
                Analytics.shared.log(.readingSessionInsightIntent(
                    destination: .history,
                    source: .sessionSummary
                ))
                summaryViewController?.dismiss(animated: true) { [weak host] in
                    guard let host else { return }
                    presentInsight(book: nil, from: host)
                }
            }
            summaryViewController.onPredictionRequested = { [weak summaryViewController, weak host] in
                Analytics.shared.log(.readingSessionInsightIntent(
                    destination: .prediction,
                    source: .sessionSummary
                ))
                summaryViewController?.dismiss(animated: true) { [weak host] in
                    guard let host,
                          let books = AppModule.shared?.books else {
                        return
                    }
                    Task { @MainActor in
                        guard let book = try? await books.get(bookId) else { return }
                        presentInsight(book: book, from: host)
                    }
                }
            }

            if let sheet = summaryViewController.sheetPresentationController {
                if #available(iOS 16.0, *) {
                    let compactDetent = UISheetPresentationController.Detent.custom(identifier: .init("compactSummary")) { _ in
                        420
                    }
                    sheet.detents = [compactDetent, .medium()]
                } else {
                    sheet.detents = [.medium()]
                }
                sheet.prefersGrabberVisible = true
            }
            host.present(summaryViewController, animated: true)
        }

        if let transitionCoordinator = reader.transitionCoordinator {
            transitionCoordinator.animate(alongsideTransition: nil) { context in
                guard !context.isCancelled else { return }
                DispatchQueue.main.async(execute: presentationBlock)
            }
        } else {
            DispatchQueue.main.async(execute: presentationBlock)
        }
    }

    @MainActor
    private static func presentInsight(book: Book?, from host: UIViewController) {
        guard host.presentedViewController == nil else { return }

        let viewController = UIHostingController(
            rootView: ReadingSessionInsightSheet(book: book)
        )
        viewController.modalPresentationStyle = .pageSheet
        if let sheet = viewController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        host.present(viewController, animated: true)
    }
}

/// Base class for all reader view controllers.
class ReaderViewController<N: Navigator>: UIViewController,
    NavigatorDelegate, UIPopoverPresentationControllerDelegate, Loggable
{
    weak var moduleDelegate: ReaderFormatModuleDelegate?

    let navigator: N
    let publication: Publication
    let bookId: Book.Id
    private let books: BookRepository
    private let bookmarks: BookmarkRepository
    private var readingSessionLifecycle: ReaderSessionLifecycle

    var supportsDetailedReadingSessions: Bool { false }
    private var suppressedReadingProgress: Locator?
    private(set) var isReadingProgressPersistenceSuppressed = false

    var subscriptions = Set<AnyCancellable>()

    private(set) var searchViewModel: SearchViewModel?
    private var searchViewController: UIHostingController<SearchView>?

    init(
        navigator: N,
        publication: Publication,
        bookId: Book.Id,
        books: BookRepository,
        bookmarks: BookmarkRepository
    ) {
        self.navigator = navigator
        self.publication = publication
        self.bookId = bookId
        self.books = books
        self.bookmarks = bookmarks
        self.readingSessionLifecycle = ReaderSessionLifecycle(bookId: bookId)

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItems = makeNavigationBarButtons()
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(watchPageTurnDidSucceed(_:)), name: .watchPageTurnDidSucceed, object: nil)

        LastReadBooks.record(id: bookId.rawValue)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        setMainTabBarHidden(true, animated: animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        beginReadingSession(
            readingSessionLifecycle.readerDidAppear(
                at: Date(),
                progression: currentReadingProgression,
                applicationIsActive: UIApplication.shared.applicationState == .active
            )
        )
        MicroReadingSessionPresenter.readerDidAppear(self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        let isReaderExit =
            isMovingFromParent
            || isBeingDismissed
            || navigationController?.isBeingDismissed == true

        MicroReadingSessionPresenter.readerWillDisappear(self)
        finishReadingSession(
            readingSessionLifecycle.readerWillDisappear(at: Date()),
            isVisibleReaderExit: isReaderExit
        )
        setMainTabBarHidden(false, animated: animated)
        if isReaderExit,
           UIApplication.shared.applicationState == .active {
            ReviewPromptManager.shared.tryPromptReview()
        }
    }

    private func setMainTabBarHidden(_ hidden: Bool, animated: Bool) {
        guard let tabBarController else { return }

        if #available(iOS 18.0, *) {
            tabBarController.setTabBarHidden(hidden, animated: animated)
        } else {
            tabBarController.tabBar.isHidden = hidden
        }
    }

    private var currentReadingProgression: Double {
        navigator.currentLocation?.locations.totalProgression
            ?? WatchPageTurnService.shared.currentBookProgress
    }

    private func beginReadingSession(_ session: ReaderSessionLifecycle.ActiveSession?) {
        guard let session else { return }

        WatchReadingSessionContext.begin(
            at: session.startedAt,
            progression: session.startProgression
        )
    }

    private func finishReadingSession(
        _ finishedSession: ReaderSessionLifecycle.FinishedSession?,
        isVisibleReaderExit: Bool
    ) {
        guard let finishedSession else { return }

        WatchReadingSessionContext.end()

        ReadingStatsStore.shared.recordReadingSession(
            startDate: finishedSession.startedAt,
            endDate: finishedSession.endedAt,
            bookId: finishedSession.bookId
        )

        var detailedSession: ReadingSession?
        if supportsDetailedReadingSessions {
            let endProgression = navigator.currentLocation?.locations.totalProgression
                ?? finishedSession.startProgression
            let session = ReadingSession(
                bookId: finishedSession.bookId,
                startedAt: finishedSession.startedAt,
                endedAt: finishedSession.endedAt,
                startProgression: finishedSession.startProgression,
                endProgression: endProgression,
                watchPageTurns: finishedSession.watchPageTurns
            )
            detailedSession = session

            if session.durationSeconds > 0 {
                Task {
                    do {
                        try await AppModule.shared?.readingSessions.add(session)
                    } catch {
                        print("ReaderViewController: failed to save reading session: \(error)")
                    }
                }
            }
        }

        let todaySeconds = ReadingStatsStore.shared.todayReadingSeconds()
        let goalMinutes = ReadingPreferences.dailyGoalMinutes
        let goalReached = ReadingGoalPolicy.goalReached(
            todaySeconds: todaySeconds,
            goalMinutes: goalMinutes
        )
        let shouldCelebrateGoal =
            isVisibleReaderExit
            && goalReached
            && !ReadingGoalCelebration.alreadyCelebratedToday()

        let summary: ReadingSessionSummary?
        if isVisibleReaderExit, let detailedSession {
            summary = ReadingSessionSummaryPolicy.makeSummary(
                for: detailedSession,
                todaySeconds: todaySeconds,
                goalMinutes: goalMinutes,
                suppressGoalCompletion: shouldCelebrateGoal
            )
        } else {
            summary = nil
        }

        if shouldCelebrateGoal {
            ReadingGoalCelebration.markCelebratedToday()
            toast(NSLocalizedString("reader_goal_reached", comment: ""), on: view, duration: 2)
        }

        if let summary {
            ReadingSessionSummaryPresenter.present(
                summary,
                bookId: finishedSession.bookId,
                after: self
            )
        }
    }

    @objc private func appDidEnterBackground() {
        // Backgrounding ends the active interval without changing visibility,
        // so didBecomeActive can start a fresh interval only if this Reader
        // is still on screen.
        finishReadingSession(
            readingSessionLifecycle.applicationDidEnterBackground(at: Date()),
            isVisibleReaderExit: false
        )
    }

    /// The Watch Live Activity requires applicationState == .active;
    /// willEnterForeground fires while the app is still .inactive, so the
    /// restart must wait for didBecomeActive.
    @objc private func appDidBecomeActive() {
        beginReadingSession(
            readingSessionLifecycle.applicationDidBecomeActive(
                at: Date(),
                progression: currentReadingProgression
            )
        )
    }

    @objc private func watchPageTurnDidSucceed(_ notification: Notification) {
        guard let origin = notification.object as? WatchPageTurnOrigin else { return }
        readingSessionLifecycle.recordSuccessfulWatchPageTurn(origin: origin)
    }

    // MARK: - Navigation bar

    func makeNavigationBarButtons() -> [UIBarButtonItem] {
        var buttons: [UIBarButtonItem] = []
        // Table of Contents
        buttons.append(UIBarButtonItem(image: #imageLiteral(resourceName: "menuIcon"), style: .plain, target: self, action: #selector(presentOutline)))

        // User preferences
        buttons.append(UIBarButtonItem(image: UIImage(systemName: "gearshape"), style: .plain, target: self, action: #selector(presentUserPreferences)))

        // DRM management
        if publication.isProtected {
            buttons.append(UIBarButtonItem(image: #imageLiteral(resourceName: "drm"), style: .plain, target: self, action: #selector(presentDRMManagement)))
        }
        // Bookmarks
        buttons.append(UIBarButtonItem(image: #imageLiteral(resourceName: "bookmark"), style: .plain, target: self, action: #selector(bookmarkCurrentPosition)))
        // Search
        if publication.isSearchable {
            buttons.append(UIBarButtonItem(image: UIImage(systemName: "magnifyingglass"), style: .plain, target: self, action: #selector(showSearchUI)))
        }

        return buttons
    }

    // MARK: - NavigatorDelegate

    func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
        guard !isReadingProgressPersistenceSuppressed else {
            suppressedReadingProgress = locator
            return
        }
        persistReadingProgress(locator)
    }

    func beginSuppressingReadingProgressPersistence() {
        isReadingProgressPersistenceSuppressed = true
        suppressedReadingProgress = nil
    }

    func endSuppressingReadingProgressPersistence(commit: Bool) {
        let locator = suppressedReadingProgress
        suppressedReadingProgress = nil
        isReadingProgressPersistenceSuppressed = false
        if commit, let locator {
            persistReadingProgress(locator)
        }
    }

    private func persistReadingProgress(_ locator: Locator) {
        Task {
            do {
                try await books.saveProgress(for: bookId, locator: locator)

                // Keep MRU order warm while the user reads.
                LastReadBooks.record(id: bookId.rawValue)
            } catch {
                moduleDelegate?.presentError(UserError(error), from: self)
            }
        }
    }

    func navigator(_ navigator: Navigator, presentExternalURL url: URL) {
        // SFSafariViewController crashes when given an URL without an HTTP scheme.
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return
        }
        present(SFSafariViewController(url: url), animated: true)
    }

    func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
        moduleDelegate?.presentError(UserError(error), from: self)
    }

    func navigator(_ navigator: any Navigator, didFailToLoadResourceAt href: RelativeURL, withError error: ReadError) {
        log(.error, "Failed to load resource at \(href): \(error)")
    }

    // MARK: - Locations

    var currentBookmark: Bookmark? {
        guard let locator = navigator.currentLocation else {
            return nil
        }

        return Bookmark(bookId: bookId, locator: locator)
    }

    // MARK: - Outlines

    @objc func presentOutline() {
        guard let locatorPublisher = moduleDelegate?.presentOutline(of: publication, bookId: bookId, from: self) else {
            return
        }

        locatorPublisher
            .sink(receiveValue: { [weak self] locator in
                Task {
                    await self?.navigator.go(to: locator, options: NavigatorGoOptions(animated: false))
                    self?.dismiss(animated: true)
                }
            })
            .store(in: &subscriptions)
    }

    // MARK: - User Preferences

    @objc func presentUserPreferences() {}

    // MARK: - Bookmarks

    @objc func bookmarkCurrentPosition() {
        guard let bookmark = currentBookmark else {
            return
        }

        Task {
            do {
                try await bookmarks.add(bookmark)
                toast(NSLocalizedString("reader_bookmark_success_message", comment: "Success message when adding a bookmark"), on: self.view, duration: 1)
            } catch {
                print(error)
                toast(NSLocalizedString("reader_bookmark_failure_message", comment: "Error message when adding a new bookmark failed"), on: self.view, duration: 2)
            }
        }
    }

    // MARK: - Search

    @objc func showSearchUI() {
        if searchViewModel == nil {
            searchViewModel = SearchViewModel(publication: publication)
            searchViewModel?.$selectedLocator.sink { [weak self] locator in
                guard let self else { return }

                self.searchViewController?.dismiss(animated: true, completion: nil)
                if let locator = locator {
                    Task {
                        await self.navigator.go(
                            to: locator,
                            options: NavigatorGoOptions(animated: true)
                        )
                    }
                }

                if let decorator = self.navigator as? DecorableNavigator {
                    var decorations: [Decoration] = []
                    if let locator = locator {
                        decorations.append(Decoration(
                            id: "selectedSearchResult",
                            locator: locator,
                            style: .highlight(tint: .yellow, isActive: false)
                        ))
                    }
                    decorator.apply(decorations: decorations, in: "search")
                }
            }
            .store(in: &subscriptions)
        }

        let searchView = SearchView(viewModel: searchViewModel!)
        let vc = UIHostingController(rootView: searchView)
        vc.modalPresentationStyle = .pageSheet
        present(vc, animated: true, completion: nil)
        searchViewController = vc
    }

    // MARK: - DRM

    @objc func presentDRMManagement() {
        guard publication.isProtected else {
            return
        }
        moduleDelegate?.presentDRM(for: publication, from: self)
    }

    // MARK: - UIPopoverPresentationControllerDelegate

    /// Prevent the popOver to be presented fullscreen on iPhones.
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        .none
    }
}
