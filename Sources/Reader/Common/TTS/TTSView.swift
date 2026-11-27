//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import AVFoundation
import Foundation
import ReadiumNavigator
import SwiftUI
import UIKit

private typealias Config = PublicationSpeechSynthesizer.Configuration

struct TTSControls: View {
    @ObservedObject var viewModel: TTSViewModel
    @State private var showSettings = false
    @State private var speedPresetIndex: Int = Self.nearestPresetIndex(for: TTSPreferences().rate)
    @Environment(\.colorScheme) private var colorScheme

    private struct SpeedPreset {
        let label: String
        let rate: Float
    }

    private static let presets: [SpeedPreset] = [
        SpeedPreset(label: "0.8×", rate: max(AVSpeechUtteranceMinimumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * 0.8)),
        SpeedPreset(label: "1.0×", rate: AVSpeechUtteranceDefaultSpeechRate),
        SpeedPreset(label: "1.2×", rate: min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * 1.15)),
        SpeedPreset(label: "1.5×", rate: min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * 1.3)),
        SpeedPreset(label: "1.8×", rate: min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * 1.45)),
    ]

    private static func nearestPresetIndex(for rate: Float) -> Int {
        presets.enumerated().min { abs($0.element.rate - rate) < abs($1.element.rate - rate) }?.offset ?? 1
    }

    private var currentPreset: SpeedPreset {
        Self.presets[min(max(speedPresetIndex, 0), Self.presets.count - 1)]
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                cycleSpeed()
            } label: {
                Text(currentPreset.label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppColors.accentBlue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppColors.accentBlue.opacity(colorScheme == .dark ? 0.22 : 0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(format: NSLocalizedString("tts_speed_a11y", comment: ""), currentPreset.label))

            Spacer(minLength: 4)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.previous()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.pauseOrResume()
            } label: {
                Image(systemName: viewModel.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(AppColors.accentGradient, in: Circle())
                    .shadow(color: AppColors.accentBlue.opacity(0.28), radius: 8, y: 3)
            }
            .buttonStyle(.plain)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.next()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 4)

            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSettings) {
                TTSSettings(viewModel: viewModel)
                    .frame(
                        minWidth: 320, idealWidth: 380, maxWidth: nil,
                        minHeight: 300, idealHeight: 320, maxHeight: nil,
                        alignment: .top
                    )
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                viewModel.stop()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 34)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 420)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(
                    colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08),
                    lineWidth: 0.75
                )
        )
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 18, y: 8)
    }

    private func cycleSpeed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        speedPresetIndex = (speedPresetIndex + 1) % Self.presets.count
        var prefs = TTSPreferences()
        prefs.rate = currentPreset.rate
    }
}

struct TTSSettings: View {
    @ObservedObject var viewModel: TTSViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let settings = viewModel.settings
        NavigationStack {
            Form {
                Section {
                    picker(
                        caption: NSLocalizedString("tts_language", comment: ""),
                        for: \.defaultLanguage,
                        choices: settings.availableLanguages,
                        choiceLabel: { $0?.localizedDescription() ?? NSLocalizedString("tts_default", comment: "") }
                    )

                    picker(
                        caption: NSLocalizedString("tts_voice", comment: ""),
                        for: \.voiceIdentifier,
                        choices: [nil] + settings.availableVoiceIds,
                        choiceLabel: { id in
                            id.flatMap { viewModel.voiceWithIdentifier($0)?.name } ?? NSLocalizedString("tts_default", comment: "")
                        }
                    )
                }
            }
            .navigationTitle(NSLocalizedString("tts_settings", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SheetCloseButton { dismiss() }
                }
            }
        }
    }

    private func picker<T: Hashable>(
        caption: String,
        for keyPath: WritableKeyPath<Config, T>,
        choices: [T],
        choiceLabel: @escaping (T) -> String
    ) -> some View {
        Picker(caption, selection: configBinding(for: keyPath)) {
            ForEach(choices, id: \.self) {
                Text(choiceLabel($0))
            }
        }
    }

    private func configBinding<T>(for keyPath: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(
            get: { viewModel.settings.config[keyPath: keyPath] },
            set: {
                var config = viewModel.settings.config
                config[keyPath: keyPath] = $0
                viewModel.setConfig(config)
            }
        )
    }
}

private extension Optional where Wrapped == TTSVoice {
    func localizedDescription() -> String {
        guard case let .some(voice) = self else {
            return NSLocalizedString("tts_default", comment: "")
        }
        var desc = voice.name
        if let region = voice.language.localizedRegion() {
            desc += " (\(region))"
        }
        return desc
    }
}
