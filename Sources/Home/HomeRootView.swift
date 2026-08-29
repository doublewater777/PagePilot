import SwiftUI

/// Composes Home with lightweight actions that should stay outside the main
/// Home layout. This keeps the existing dashboard stable while making short
/// reading sessions immediately available above the tab bar.
struct HomeRootView: View {
    @ObservedObject var viewModel: HomeViewModel
    weak var delegate: HomeModuleDelegate?

    var body: some View {
        HomeView(viewModel: viewModel, delegate: delegate)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let book = viewModel.lastReadBook {
                    MicroReadingQuickStartBar { minutes in
                        delegate?.homeDidSelectMicroReading(
                            bookId: book.id,
                            minutes: minutes
                        )
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(
                .spring(response: 0.35, dampingFraction: 0.8),
                value: viewModel.lastReadBook?.id
            )
    }
}

private struct MicroReadingQuickStartBar: View {
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.accentTeal)
                .accessibilityHidden(true)

            ForEach(MicroReadingPolicy.supportedMinutes, id: \.self) { minutes in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onSelect(minutes)
                } label: {
                    Text(MicroReadingPolicy.localizedDuration(forMinutes: minutes))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(AppColors.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(AppColors.accentBlue.opacity(0.09))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text(MicroReadingPolicy.localizedDuration(forMinutes: minutes))
                )
            }
        }
        .padding(10)
        .background(AppColors.cardBackground)
        .clipShape(
            RoundedRectangle(
                cornerRadius: AppColors.cardCornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: AppColors.cardCornerRadius,
                style: .continuous
            )
            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 12, y: 6)
        .accessibilityElement(children: .contain)
    }
}
