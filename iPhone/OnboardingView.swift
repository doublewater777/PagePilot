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
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showsIPadPaywall = false
    @State private var hasHandledInitialURL = false
    @State private var selectedPublication: OnboardingPublicationPresentation?
    @State private var isOpeningReader = false
    @State private var isReaderTransitionActive = false
    @State private var hasFinished = false
    @State private var workTask: Task<Void, Never>?
    @State private var readerOpenTask: Task<Void, Never>?

    let importPublication: (URL) async throws -> OnboardingPublicationPresentation
    let loadSamplePublication: () async -> OnboardingPublicationPresentation?
    let loadPublication: (Int64) async -> OnboardingPublicationPresentation?
    let onFlowChange: (OnboardingFlow) -> Void
    let onOpenPublication: (Int64, Bool) -> Void
    let onFinish: () -> Void
    let initialURL: URL?

    init(
        flow: OnboardingFlow,
        importPublication: @escaping (URL) async throws -> OnboardingPublicationPresentation,
        loadSamplePublication: @escaping () async -> OnboardingPublicationPresentation?,
        loadPublication: @escaping (Int64) async -> OnboardingPublicationPresentation?,
        onFlowChange: @escaping (OnboardingFlow) -> Void,
        onOpenPublication: @escaping (Int64, Bool) -> Void,
        onFinish: @escaping () -> Void,
        initialURL: URL? = nil
    ) {
        _flow = State(initialValue: flow)
        self.importPublication = importPublication
        self.loadSamplePublication = loadSamplePublication
        self.loadPublication = loadPublication
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

            Button(action: finish) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(.thinMaterial, in: Circle())
            }
            .accessibilityLabel(Text("onboarding_close_accessibility"))
            .padding(20)
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            importURL(url)
        }
        .sheet(isPresented: $showsIPadPaywall, onDismiss: finishIPadPurchaseIfNeeded) {
            PaywallView(context: .iPadWatchRelay)
        }
        .onReceive(NotificationCenter.default.publisher(for: .onboardingImportURLRequested)) { notification in
            guard let url = notification.object as? URL else { return }
            importURL(url)
        }
        .onAppear {
            resumeIfNeeded()
            if !hasHandledInitialURL,
               flow.step == .choosePublication,
               let initialURL {
                hasHandledInitialURL = true
                importURL(initialURL)
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
                    isImporterPresented = true
                }

                Button("onboarding_use_sample") {
                    useSamplePublication()
                }
                .font(.body.weight(.semibold))
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

    private func primaryButton(_ titleKey: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(titleKey, systemImage: systemImage)
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

    private func importURL(_ url: URL) {
        guard !hasFinished else { return }
        workTask?.cancel()
        isWorking = true
        errorMessage = nil
        workTask = Task {
            do {
                let publication = try await importPublication(url)
                guard !Task.isCancelled, !hasFinished else { return }
                selectedPublication = publication
                didChoosePublication(bookID: publication.bookID, source: .user)
            } catch {
                guard !Task.isCancelled, !hasFinished else { return }
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func useSamplePublication() {
        guard !hasFinished else { return }
        workTask?.cancel()
        isWorking = true
        errorMessage = nil
        workTask = Task {
            if let publication = await loadSamplePublication() {
                guard !Task.isCancelled, !hasFinished else { return }
                selectedPublication = publication
                didChoosePublication(bookID: publication.bookID, source: .sample)
            } else {
                guard !Task.isCancelled, !hasFinished else { return }
                errorMessage = NSLocalizedString("onboarding_sample_error", comment: "")
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
}

extension Notification.Name {
    static let onboardingImportURLRequested = Notification.Name("onboardingImportURLRequested")
}
