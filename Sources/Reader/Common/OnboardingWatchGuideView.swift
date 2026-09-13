//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI

struct OnboardingWatchGuideView: View {
    @ObservedObject var service: WatchPageTurnService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    let onDismiss: () -> Void

    init(
        service: WatchPageTurnService,
        onDismiss: @escaping () -> Void
    ) {
        self.service = service
        self.onDismiss = onDismiss
    }

    var body: some View {
        expandedGuide
    }

    private var expandedGuide: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppColors.accentBlue)
                    .scaleEffect(isPulsing && !reduceMotion && service.watchAvailability == .ready ? 1.08 : 1)
                    .onAppear {
                        guard !reduceMotion else { return }
                        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                            isPulsing = true
                        }
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button("onboarding_watch_skip", action: onDismiss)
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppColors.accentBlue.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.1), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var statusIcon: String {
        switch service.watchAvailability {
        case .unsupported, .unpaired:
            return "applewatch.slash"
        case .appNotInstalled:
            return "square.and.arrow.down"
        case .unreachable:
            return "applewatch"
        case .ready:
            return "arrow.right.page.on.rectangle"
        }
    }

    private var statusTitle: LocalizedStringKey {
        switch service.watchAvailability {
        case .unsupported, .unpaired:
            return "onboarding_watch_unpaired_title"
        case .appNotInstalled:
            return "onboarding_watch_install_title"
        case .unreachable:
            return "onboarding_watch_open_title"
        case .ready:
            return "onboarding_watch_ready_title"
        }
    }

    private var statusDetail: LocalizedStringKey {
        switch service.watchAvailability {
        case .unsupported, .unpaired:
            return "onboarding_watch_unpaired_detail"
        case .appNotInstalled:
            return "onboarding_watch_install_detail"
        case .unreachable:
            return "onboarding_watch_open_detail"
        case .ready:
            return "onboarding_watch_ready_detail"
        }
    }
}

struct OnboardingIPadReaderHintView: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppColors.accentBlue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("onboarding_ipad_reader_hint_title")
                        .font(.headline)
                    Text("onboarding_ipad_reader_hint_detail")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Button("onboarding_handoff_done", action: onDismiss)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppColors.accentBlue.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.1), radius: 18, y: 8)
    }
}
