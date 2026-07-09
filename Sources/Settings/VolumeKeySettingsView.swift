//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI
import UIKit

struct VolumeKeySettingsView: View {
    @AppStorage(VolumeKeyService.volumeKeyEnabledKey) private var volumeKeyEnabled = false
    @AppStorage(VolumeKeyService.volumeKeyMappingKey) private var volumeKeyMapping = VolumeKeyService.defaultVolumeKeyMapping.rawValue
    @AppStorage(Self.educationSeenKey) private var educationSeen = false

    @State private var showEducation = false

    private static let educationSeenKey = "volume_key_education_seen"

    var body: some View {
        List {
            toggleSection
            explanationSection
            mappingSection
        }
        .listStyle(.insetGrouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(NSLocalizedString("settings_volume_key_turn_page", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEducation) {
            VolumeKeyEducationView {
                educationSeen = true
                volumeKeyEnabled = true
                showEducation = false
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private var toggleSection: some View {
        Section {
            Toggle(isOn: volumeKeyEnabledBinding) {
                Text(NSLocalizedString("settings_volume_key_turn_page", comment: ""))
            }
        }
    }

    private var volumeKeyEnabledBinding: Binding<Bool> {
        Binding(
            get: { volumeKeyEnabled },
            set: { newValue in
                if newValue, !educationSeen {
                    showEducation = true
                    return
                }
                volumeKeyEnabled = newValue
            }
        )
    }

    private var explanationSection: some View {
        Section {
            Text(NSLocalizedString("settings_volume_key_explanation", comment: ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
        }
    }

    private var mappingSection: some View {
        Section {
            Picker(selection: volumeKeyMappingBinding) {
                ForEach(VolumeKeyMapping.allCases) { mapping in
                    Text(mapping.localizedName).tag(mapping)
                }
            } label: {
                Text(NSLocalizedString("settings_volume_key_mapping_title", comment: ""))
            }
            .pickerStyle(.menu)
            .disabled(!volumeKeyEnabled)
        }
    }

    private var volumeKeyMappingBinding: Binding<VolumeKeyMapping> {
        Binding(
            get: {
                VolumeKeyMapping(rawValue: volumeKeyMapping) ?? .downForwardUpBackward
            },
            set: { newValue in
                volumeKeyMapping = newValue.rawValue
            }
        )
    }
}

// MARK: - First-enable education

private struct VolumeKeyEducationView: View {
    let onConfirm: () -> Void

    private let points: [(icon: String, key: String)] = [
        ("book.fill", "volume_key_edu_point_reading"),
        ("speaker.wave.2.fill", "volume_key_edu_point_tts"),
        ("speaker.slash.fill", "volume_key_edu_point_hud"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // No cancel button — dismiss by swipe down.
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 12)

            Text(NSLocalizedString("volume_key_edu_title", comment: ""))
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(AppColors.primaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            VStack(spacing: 10) {
                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: point.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColors.accentBlue)
                            .frame(width: 24, height: 24)
                            .background(AppColors.accentBlue.opacity(0.12))
                            .clipShape(Circle())

                        Text(NSLocalizedString(point.key, comment: ""))
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(
                        AppColors.cardBackground,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
            }
            .padding(.horizontal, 20)

            Spacer(minLength: 12)

            Button(action: onConfirm) {
                Text(NSLocalizedString("volume_key_edu_confirm", comment: ""))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(AppColors.horizontalGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(VolumeKeyEduPressStyle())
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .background(Color(.systemGroupedBackground))
        .presentationDetents([.height(420), .medium])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Color(.systemGroupedBackground))
    }
}

private struct VolumeKeyEduPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    NavigationView {
        VolumeKeySettingsView()
    }
    .navigationViewStyle(.stack)
}
