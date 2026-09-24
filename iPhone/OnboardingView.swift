//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI
import UniformTypeIdentifiers

struct OnboardingPublicationPresentation {
    let bookID: Int64
    let title: String
    let coverURL: URL?
}

struct OnboardingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var flow: OnboardingFlow
    @State private var isImporterPresented = false
    @State private var showsImportSources = false
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showsIPadPaywall = false
    @State private var tourPage = 0
    @State private var hasHandledInitialURL = false
    @State private var selectedPublication: OnboardingPublicationPresentation?
    @State private var isOpeningReader = false
    @State private var isReaderTransitionActive = false
    @State private var hasFinished = false
    @State private var didLogOnboardingView = false
    @State private var didLogReaderOpened = false
    @State private var workTask: Task<Void, Never>?
    @State private var readerOpenTask: Task<Void, Never>?

    private enum ImportEntryPoint: String {
        case files
        case externalFile
        case wifi
        case opds
        case sample
    }

    let importPublication: (URL) async throws -> OnboardingPublicationPresentation
    let loadPublication: (Int64) async -> OnboardingPublicationPresentation?
    let presentWiFiTransfer: (@escaping (OnboardingPublicationPresentation) -> Void) -> Void
    let presentOPDS: (@escaping (OnboardingPublicationPresentation) -> Void) -> Void
    let onFlowChange: (OnboardingFlow) -> Void
    let onOpenPublication: (Int64, Bool) -> Void
    let onFinish: () -> Void
    let initialURL: URL?

    init(
        flow: OnboardingFlow,
        importPublication: @escaping (URL) async throws -> OnboardingPublicationPresentation,
        loadPublication: @escaping (Int64) async -> OnboardingPublicationPresentation?,
        presentWiFiTransfer: @escaping (@escaping (OnboardingPublicationPresentation) -> Void) -> Void,
        presentOPDS: @escaping (@escaping (OnboardingPublicationPresentation) -> Void) -> Void,
        onFlowChange: @escaping (OnboardingFlow) -> Void,
        onOpenPublication: @escaping (Int64, Bool) -> Void,
        onFinish: @escaping () -> Void,
        initialURL: URL? = nil
    ) {
        _flow = State(initialValue: flow)
        self.importPublication = importPublication
        self.loadPublication = loadPublication
        self.presentWiFiTransfer = presentWiFiTransfer
        self.presentOPDS = presentOPDS
        self.onFlowChange = onFlowChange
        self.onOpenPublication = onOpenPublication
        self.onFinish = onFinish
        self.initialURL = initialURL
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            AppColors.background.ignoresSafeArea()

            Group {
                switch flow.step {
                case .choosePublication:
                    publicationScreen
                case .chooseControlTarget:
                    controlTargetScreen
                case .watchIntro:
                    watchIntroScreen
                case .iPadHandoff:
                    iPadHandoffScreen
                case .reader:
                    readerTransitionScreen
                case .completed:
                    EmptyView()
                }
            }
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: handleSkip) {
                Text("onboarding_tour_skip")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(Text("onboarding_tour_skip"))
            .padding(20)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            importURL(url, entryPoint: .files)
        }
        .confirmationDialog(
            "onboarding_import_source_title",
            isPresented: $showsImportSources,
            titleVisibility: .visible
        ) {
            Button("onboarding_import_source_files") {
                isImporterPresented = true
            }
            Button("onboarding_import_source_wifi") {
                Analytics.shared.log(.onboardingImportStarted(source: ImportEntryPoint.wifi.rawValue))
                presentWiFiTransfer { publication in
                    didImportFromAlternativeSource(publication, entryPoint: .wifi)
                }
            }
            Button("onboarding_import_source_opds") {
                Analytics.shared.log(.onboardingImportStarted(source: ImportEntryPoint.opds.rawValue))
                presentOPDS { publication in
                    didImportFromAlternativeSource(publication, entryPoint: .opds)
                }
            }
            Button("cancel_button", role: .cancel) {}
        }
        .sheet(isPresented: $showsIPadPaywall, onDismiss: finishIPadPurchaseIfNeeded) {
            PaywallView(context: .iPadWatchRelay)
        }
        .onReceive(NotificationCenter.default.publisher(for: .onboardingImportURLRequested)) { notification in
            guard let url = notification.object as? URL else { return }
            importURL(url, entryPoint: .externalFile)
        }
        .onAppear {
            if !didLogOnboardingView {
                didLogOnboardingView = true
                Analytics.shared.log(.onboardingViewed(platform: analyticsPlatformName))
            }
            if !hasHandledInitialURL, let initialURL {
                hasHandledInitialURL = true
                importURL(initialURL, entryPoint: .externalFile)
            } else {
                resumeIfNeeded()
            }
            if ProcessInfo.processInfo.arguments.contains("-AutoDismissOnboarding") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    finish()
                }
            }
        }
    }

    private var publicationScreen: some View {
        scrollingScreen {
            VStack(spacing: 28) {
            Spacer(minLength: 72)

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppColors.accentGradient)
                    .frame(width: 112, height: 146)
                    .shadow(color: AppColors.accentBlue.opacity(0.22), radius: 24, y: 12)
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("onboarding_activation_title")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("onboarding_activation_subtitle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Spacer()

            VStack(spacing: 12) {
                primaryButton("onboarding_import_one_book", systemImage: "square.and.arrow.down") {
                    showsImportSources = true
                }

                Button(action: importSample) {
                    Label(
                        NSLocalizedString(
                            "onboarding_use_sample_book",
                            tableName: "Onboarding",
                            comment: "Onboarding sample book button"
                        ),
                        systemImage: "book.closed"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                }
                .buttonStyle(.bordered)
                .tint(AppColors.accentBlue)
                .disabled(isWorking)

                Text("onboarding_supported_formats")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 36)
            .overlay {
                if isWorking {
                    ProgressView()
                        .controlSize(.large)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
    }

    private var watchIntroScreen: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 44)

            TabView(selection: $tourPage) {
                tourPage1.tag(0)
                tourPage2.tag(1)
                tourPage3.tag(2)
                tourPage4.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    ForEach(0..<4) { idx in
                        Capsule()
                            .fill(tourPage == idx ? AppColors.accentBlue : Color.primary.opacity(0.18))
                            .frame(width: tourPage == idx ? 22 : 7, height: 7)
                            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: tourPage)
                    }
                }
                .padding(.bottom, 2)

                if tourPage < 3 {
                    primaryButton("onboarding_tour_next") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            tourPage += 1
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        primaryButton("onboarding_import_one_book", systemImage: "square.and.arrow.down") {
                            showsImportSources = true
                        }

                        Button(action: importSample) {
                            Label(
                                NSLocalizedString(
                                    "onboarding_use_sample_book",
                                    tableName: "Onboarding",
                                    comment: "Onboarding sample book button"
                                ),
                                systemImage: "book.closed"
                            )
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppColors.accentBlue)
                        .disabled(isWorking)

                        Text("onboarding_supported_formats")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
        .overlay {
            if isWorking {
                ProgressView()
                    .controlSize(.large)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private var tourPage1: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 20)

            ZStack {
                Circle()
                    .fill(AppColors.accentBlue.opacity(0.1))
                    .frame(width: 140, height: 140)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppColors.accentGradient)
                    .frame(width: 104, height: 104)
                    .shadow(color: AppColors.accentBlue.opacity(0.35), radius: 24, y: 12)

                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("onboarding_tour_page1_title")
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("onboarding_tour_page1_tagline")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.accentTeal)
            }

            Text("onboarding_tour_page1_desc")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 12)

            HStack(spacing: 8) {
                tourPill(icon: "digitalcrown.horizontal.press.fill", text: "onboarding_tour_page1_chip1")
                tourPill(icon: "hand.tap.fill", text: "onboarding_tour_page1_chip2")
                tourPill(icon: "waveform", text: "onboarding_tour_page1_chip3")
            }

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 20)
    }

    private var tourPage2: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 20)

            ZStack {
                Circle()
                    .fill(AppColors.accentTeal.opacity(0.1))
                    .frame(width: 140, height: 140)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(
                        colors: [AppColors.accentTeal, AppColors.accentBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 104, height: 104)
                    .shadow(color: AppColors.accentTeal.opacity(0.35), radius: 24, y: 12)

                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 46, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("onboarding_tour_page2_title")
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("onboarding_tour_page2_tagline")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.accentTeal)
            }

            Text("onboarding_tour_page2_desc")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 12)

            HStack(spacing: 8) {
                tourPill(icon: "doc.text.fill", text: "onboarding_tour_page2_chip1")
                tourPill(icon: "wifi", text: "onboarding_tour_page2_chip2")
                tourPill(icon: "ipad.and.iphone", text: "onboarding_tour_page2_chip3")
            }

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 20)
    }

    private var tourPage3: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 20)

            ZStack {
                Circle()
                    .fill(AppColors.accentBlue.opacity(0.1))
                    .frame(width: 140, height: 140)

                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 46 / 255, green: 130 / 255, blue: 245 / 255), AppColors.accentTeal],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 104, height: 104)
                    .shadow(color: AppColors.accentBlue.opacity(0.35), radius: 24, y: 12)

                Image(systemName: "icloud.fill")
                    .font(.system(size: 50, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("onboarding_tour_page3_title")
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("onboarding_tour_page3_tagline")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.accentTeal)
            }

            Text("onboarding_tour_page3_desc")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 12)

            HStack(spacing: 8) {
                tourPill(icon: "arrow.triangle.2.circlepath", text: "onboarding_tour_page3_chip1")
                tourPill(icon: "ipad.and.iphone", text: "onboarding_tour_page3_chip2")
                tourPill(icon: "lock.shield.fill", text: "onboarding_tour_page3_chip3")
            }

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 20)
    }

    private var tourPage4: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 20)

            ZStack {
                Circle()
                    .fill(AppColors.accentBlue.opacity(0.1))
                    .frame(width: 140, height: 140)

                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppColors.accentGradient)
                    .frame(width: 96, height: 124)
                    .shadow(color: AppColors.accentBlue.opacity(0.32), radius: 24, y: 12)

                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("onboarding_activation_title")
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)

                Text("onboarding_activation_subtitle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.horizontal, 12)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 20)
    }

    private func tourPill(icon: String, text: LocalizedStringKey) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.accentBlue)
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(AppColors.cardBackground, in: Capsule())
        .overlay {
            Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var controlTargetScreen: some View {
        scrollingScreen {
            VStack(spacing: 24) {
            Spacer(minLength: 72)

            selectedPublicationCover

            VStack(spacing: 10) {
                Text("onboarding_target_title")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("onboarding_target_subtitle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 14) {
                targetCard(
                    title: "onboarding_target_this_iphone",
                    detail: "onboarding_target_iphone_detail",
                    systemImage: "iphone",
                    badge: nil
                ) {
                    chooseTarget(.iPhone)
                }

                targetCard(
                    title: "onboarding_target_nearby_ipad",
                    detail: "onboarding_target_ipad_detail",
                    systemImage: "ipad",
                    badge: "PRO"
                ) {
                    chooseTarget(.iPad)
                }
            }

            Spacer()

            Button("onboarding_skip_watch") {
                flow.skipControlTarget()
                persistAndOpenReader()
            }
            .font(.body.weight(.semibold))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
    }

    private var iPadHandoffScreen: some View {
        scrollingScreen {
            VStack(spacing: 26) {
            Spacer(minLength: 64)

            Image(systemName: "applewatch.and.arrow.forward")
                .font(.system(size: 54, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppColors.accentBlue)
                .accessibilityHidden(true)

            VStack(spacing: 10) {
                Text("onboarding_ipad_handoff_title")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text("onboarding_ipad_handoff_subtitle")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 18) {
                handoffStep(1, "onboarding_ipad_handoff_step1")
                handoffStep(2, "onboarding_ipad_handoff_step2")
                handoffStep(3, "onboarding_ipad_handoff_step3")
            }
            .padding(22)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Spacer()

            primaryButton("onboarding_handoff_done", systemImage: "checkmark") {
                finish()
            }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 36)
        }
    }

    private func scrollingScreen<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
        GeometryReader { proxy in
            ScrollView {
                content()
                    .frame(minHeight: proxy.size.height)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var readerTransitionScreen: some View {
        selectedPublicationCover
            .scaleEffect(isReaderTransitionActive && !reduceMotion ? 1.16 : 1)
            .offset(y: isReaderTransitionActive && !reduceMotion ? -24 : 0)
            .opacity(isReaderTransitionActive ? 0 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }

    private func primaryButton(_ titleKey: LocalizedStringKey, systemImage: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(titleKey, systemImage: systemImage)
                } else {
                    Text(titleKey)
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColors.accentBlue)
        .disabled(isWorking)
    }

    private func targetCard(
        title: LocalizedStringKey,
        detail: LocalizedStringKey,
        systemImage: String,
        badge: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(AppColors.accentBlue)
                    .frame(width: 48, height: 48)
                    .background(AppColors.accentBlue.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title).font(.headline)
                        if let badge {
                            Text(badge)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(AppColors.accentGradient, in: Capsule())
                        }
                    }
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.bold())
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func handoffStep(_ number: Int, _ textKey: LocalizedStringKey) -> some View {
        HStack(spacing: 14) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(AppColors.accentBlue, in: Circle())
            Text(textKey)
                .font(.body)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var selectedPublicationCover: some View {
        if let publication = selectedPublication {
            AsyncImage(url: publication.coverURL) { phase in
                if case let .success(image) = phase {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(AppColors.accentGradient)
                        .overlay {
                            Image(systemName: "book.closed.fill")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(.white)
                        }
                }
            }
            .frame(width: 88, height: 116)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: AppColors.accentBlue.opacity(0.2), radius: 18, y: 9)
            .accessibilityLabel(publication.title)
        } else {
            Image(systemName: "applewatch.side.right")
                .font(.system(size: 58, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(AppColors.accentBlue)
                .accessibilityHidden(true)
        }
    }

    private func importSample() {
        guard !hasFinished, !isOpeningReader else { return }
        workTask?.cancel()
        isWorking = true
        errorMessage = nil
        Analytics.shared.log(.onboardingImportStarted(source: ImportEntryPoint.sample.rawValue))
        workTask = Task {
            do {
                let url = try await OnboardingSamplePublication.makeURL()
                let publication = try await importPublication(url)
                guard !Task.isCancelled, !hasFinished, !isOpeningReader else { return }
                Analytics.shared.log(.onboardingImportSucceeded(source: ImportEntryPoint.sample.rawValue))
                selectedPublication = publication
                didChoosePublication(bookID: publication.bookID, source: .sample)
            } catch {
                guard !Task.isCancelled, !hasFinished else { return }
                Analytics.shared.log(
                    .onboardingImportFailed(
                        source: ImportEntryPoint.sample.rawValue,
                        error: String(describing: type(of: error))
                    )
                )
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func importURL(
        _ url: URL,
        source: OnboardingFlow.PublicationSource = .user,
        entryPoint: ImportEntryPoint = .files
    ) {
        guard !hasFinished, !isOpeningReader else { return }
        workTask?.cancel()
        isWorking = true
        errorMessage = nil
        Analytics.shared.log(.onboardingImportStarted(source: entryPoint.rawValue))
        workTask = Task {
            do {
                let publication = try await importPublication(url)
                guard !Task.isCancelled, !hasFinished, !isOpeningReader else { return }
                Analytics.shared.log(.onboardingImportSucceeded(source: entryPoint.rawValue))
                selectedPublication = publication
                didChoosePublication(bookID: publication.bookID, source: source)
            } catch {
                guard !Task.isCancelled, !hasFinished else { return }
                Analytics.shared.log(
                    .onboardingImportFailed(
                        source: entryPoint.rawValue,
                        error: String(describing: type(of: error))
                    )
                )
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func didChoosePublication(bookID: Int64, source: OnboardingFlow.PublicationSource) {
        guard !hasFinished else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
            flow.didChoosePublication(bookID: bookID, source: source)
        }
        onFlowChange(flow)
        if flow.step == .reader {
            persistAndOpenReader()
        }
    }

    private func handleSkip() {
        if flow.step == .watchIntro {
            Analytics.shared.log(.onboardingTourSkipped(page: tourPage))
        }
        if flow.platform == .iPhone, flow.step == .watchIntro, tourPage < 3 {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                tourPage = 3
            }
        } else {
            Analytics.shared.log(.onboardingDismissed(step: analyticsStepName))
            finish()
        }
    }

    private func continueFromWatchIntro() {
        guard !hasFinished else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) {
            flow.didFinishWatchIntro()
        }
        onFlowChange(flow)
    }

    private func didImportFromAlternativeSource(
        _ publication: OnboardingPublicationPresentation,
        entryPoint: ImportEntryPoint
    ) {
        guard !hasFinished, !isOpeningReader else { return }
        Analytics.shared.log(.onboardingImportSucceeded(source: entryPoint.rawValue))
        selectedPublication = publication
        didChoosePublication(bookID: publication.bookID, source: .user)
    }

    private func chooseTarget(_ target: OnboardingFlow.ControlTarget) {
        guard !hasFinished else { return }
        let effect = flow.didChooseControlTarget(
            target,
            hasProAccess: ProPurchaseManager.shared.hasProAccess
        )
        if effect == .showIPadPaywall {
            showsIPadPaywall = true
            return
        }
        var settings = WatchPageTurnSettings()
        settings.controlTarget = target == .iPad ? .iPad : .iPhone
        settings.syncToWatch()
        if target == .iPad {
            WatchPageTurnService.shared.prepareIPadRelay()
        }
        onFlowChange(flow)
        if flow.step == .reader {
            persistAndOpenReader()
        }
    }

    private func finishIPadPurchaseIfNeeded() {
        guard ProPurchaseManager.shared.hasProAccess else { return }
        chooseTarget(.iPad)
    }

    private func persistAndOpenReader() {
        onFlowChange(flow)
        guard let selection = flow.publication else {
            finish()
            return
        }
        guard !isOpeningReader else { return }
        isOpeningReader = true
        if !didLogReaderOpened {
            didLogReaderOpened = true
            Analytics.shared.log(.onboardingReaderOpened(source: selection.source.analyticsValue))
        }
        if reduceMotion {
            hasFinished = true
            onOpenPublication(selection.bookID, flow.shouldShowWatchGuide)
            return
        }
        readerOpenTask = Task {
            await Task.yield()
            guard !Task.isCancelled, !hasFinished else { return }
            withAnimation(.easeInOut(duration: 0.28)) {
                isReaderTransitionActive = true
            }
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled, !hasFinished else { return }
            hasFinished = true
            onOpenPublication(selection.bookID, flow.shouldShowWatchGuide)
        }
    }

    private func resumeIfNeeded() {
        guard !hasFinished else { return }
        if flow.step == .reader,
           selectedPublication == nil,
           let bookID = flow.publication?.bookID {
            workTask = Task {
                selectedPublication = await loadPublication(bookID)
                guard !Task.isCancelled, !hasFinished else { return }
                persistAndOpenReader()
            }
            return
        }
        switch flow.step {
        case .reader:
            persistAndOpenReader()
        case .completed:
            onFinish()
        default:
            break
        }
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        workTask?.cancel()
        readerOpenTask?.cancel()
        flow.finish()
        onFlowChange(flow)
        onFinish()
    }

    private var analyticsPlatformName: String {
        switch flow.platform {
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        }
    }

    private var analyticsStepName: String {
        switch flow.step {
        case .choosePublication: return "choose_publication"
        case .chooseControlTarget: return "choose_control_target"
        case .watchIntro: return "watch_intro"
        case .reader: return "reader"
        case .iPadHandoff: return "ipad_handoff"
        case .completed: return "completed"
        }
    }
}

extension Notification.Name {
    static let onboardingImportURLRequested = Notification.Name("onboardingImportURLRequested")
}
