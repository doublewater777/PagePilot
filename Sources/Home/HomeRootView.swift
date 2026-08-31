import SwiftUI
import UIKit

struct HomeRootView: View {
    @ObservedObject var viewModel: HomeViewModel
    weak var delegate: HomeModuleDelegate?

    var body: some View {
        HomeView(viewModel: viewModel, delegate: delegate)
    }
}

struct MicroReadingStartSheet: View {
    let bookTitle: String
    @Binding var selectedMinutes: Int
    let onStart: (Int) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(AppColors.accentTeal)
                        .frame(width: 52, height: 52)
                        .background(AppColors.accentTeal.opacity(colorScheme == .dark ? 0.18 : 0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Text(NSLocalizedString("micro_reading_title", comment: ""))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(AppColors.primaryText)

                    Text(bookTitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)

                    Text(NSLocalizedString("micro_reading_description", comment: ""))
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.secondaryText)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 10) {
                    ForEach(MicroReadingPolicy.supportedMinutes, id: \.self) { minutes in
                        Button {
                            selectedMinutes = minutes
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            Text(MicroReadingPolicy.localizedDuration(forMinutes: minutes))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(
                                    selectedMinutes == minutes ? Color.white : AppColors.primaryText
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    selectedMinutes == minutes
                                        ? AnyShapeStyle(AppColors.horizontalGradient)
                                        : AnyShapeStyle(AppColors.accentBlue.opacity(colorScheme == .dark ? 0.16 : 0.08))
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedMinutes == minutes ? .isSelected : [])
                    }
                }

                VStack(spacing: 12) {
                    Label(
                        NSLocalizedString("micro_reading_gentle_reminder", comment: ""),
                        systemImage: "bell.badge"
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.tertiaryText)

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onStart(selectedMinutes)
                    } label: {
                        Text(
                            String(
                                format: NSLocalizedString("micro_reading_start_format", comment: ""),
                                MicroReadingPolicy.localizedDuration(forMinutes: selectedMinutes)
                            )
                        )
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(AppColors.horizontalGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: horizontalSizeClass == .regular ? 560 : .infinity)
            .frame(maxWidth: .infinity)
            .padding(.top, horizontalSizeClass == .regular ? 32 : 24)
            .padding(.horizontal, horizontalSizeClass == .regular ? 32 : 24)
            .padding(.bottom, 24)
        }
        .background(AppColors.background)
    }
}
