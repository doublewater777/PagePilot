//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import AVFoundation
import SwiftUI

struct TTSSettingsView: View {
    @StateObject private var model = TTSSettingsModel()

    var body: some View {
        HStack {
            if UIDevice.current.userInterfaceIdiom == .pad {
                Spacer()
            }
            
            List {
                premiumPromptSection
                voiceSection
                speedPitchSection
                previewSection
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 600 : .infinity)
            
            if UIDevice.current.userInterfaceIdiom == .pad {
                Spacer()
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(NSLocalizedString("tts_settings_title", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.load() }
        .onDisappear { model.stopPreview() }
    }

    // MARK: - Premium Voice Prompt

    private var premiumPromptSection: some View {
        Group {
            if model.showPremiumPrompt {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.yellow)
                                .font(.title3.weight(.semibold))
                            Text(NSLocalizedString("tts_premium_prompt_title", comment: ""))
                                .font(.headline)
                        }

                        Text(NSLocalizedString("tts_premium_prompt_body", comment: ""))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(NSLocalizedString("tts_premium_prompt_steps", comment: ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)

                        Button {
                            model.dismissPremiumPrompt()
                        } label: {
                            Text(NSLocalizedString("tts_premium_prompt_dismiss", comment: ""))
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        Section {
            NavigationLink {
                VoicePickerView(model: model)
            } label: {
                HStack {
                    Text(NSLocalizedString("tts_settings_voice_label", comment: ""))
                    Spacer()
                    Text(model.selectedVoiceDisplayName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } header: {
            Text(NSLocalizedString("tts_settings_voice_section", comment: ""))
        } footer: {
            Text(NSLocalizedString("tts_settings_voice_footer", comment: ""))
        }
    }

    // MARK: - Speed & Pitch

    private var speedPitchSection: some View {
        Section {
            // Rate
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(NSLocalizedString("tts_settings_rate", comment: ""))
                        .font(.subheadline)
                    Spacer()
                    Text(model.rateDisplay)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Image(systemName: "tortoise.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Slider(
                        value: $model.rate,
                        in: Double(AVSpeechUtteranceMinimumSpeechRate)...Double(AVSpeechUtteranceMaximumSpeechRate),
                        onEditingChanged: { editing in
                            if !editing { model.persistRate() }
                        }
                    )
                    Image(systemName: "hare.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding(.vertical, 4)

            // Pitch
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(NSLocalizedString("tts_settings_pitch", comment: ""))
                        .font(.subheadline)
                    Spacer()
                    Text(model.pitchDisplay)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Slider(
                        value: $model.pitch,
                        in: 0.5...2.0,
                        onEditingChanged: { editing in
                            if !editing { model.persistPitch() }
                        }
                    )
                    Image(systemName: "arrow.up")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding(.vertical, 4)

            Button(role: .destructive) {
                model.resetRateAndPitch()
            } label: {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text(NSLocalizedString("tts_settings_reset", comment: ""))
                }
            }
        } header: {
            Text(NSLocalizedString("tts_settings_speed_section", comment: ""))
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        Section {
            Button(action: model.togglePreview) {
                HStack {
                    Image(systemName: model.isPreviewing ? "stop.fill" : "play.fill")
                    Text(model.isPreviewing
                         ? NSLocalizedString("tts_settings_preview_stop", comment: "")
                         : NSLocalizedString("tts_settings_preview", comment: ""))
                    Spacer()
                }
            }
            .foregroundStyle(model.isPreviewing ? Color.red : Color.accentColor)
        } footer: {
            Text(NSLocalizedString("tts_settings_preview_footer", comment: ""))
        }
    }
}

// MARK: - Voice Picker

private struct VoicePickerView: View {
    @ObservedObject var model: TTSSettingsModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            if UIDevice.current.userInterfaceIdiom == .pad {
                Spacer()
            }
            
            List {
                // System Default
                Section {
                    Button {
                        model.selectVoice(nil)
                    } label: {
                        HStack {
                            Text(NSLocalizedString("tts_default", comment: ""))
                                .foregroundStyle(.primary)
                            Spacer()
                            if model.selectedVoiceId == nil {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text(NSLocalizedString("tts_settings_default_voice_footer", comment: ""))
                }

                // Voices grouped by language
                ForEach(model.voiceLanguages, id: \.self) { language in
                    Section(language) {
                        ForEach(model.voices(for: language), id: \.identifier) { voice in
                            Button {
                                model.selectVoice(voice.identifier)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(voice.name)
                                            .foregroundStyle(.primary)
                                        if let badge = qualityBadge(voice.quality) {
                                            Text(badge)
                                                .font(.caption2.weight(.medium))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.accentColor.opacity(0.15))
                                                .foregroundStyle(Color.accentColor)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    Spacer()
                                    if model.selectedVoiceId == voice.identifier {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 600 : .infinity)
            
            if UIDevice.current.userInterfaceIdiom == .pad {
                Spacer()
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(NSLocalizedString("tts_settings_voice_section", comment: ""))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func qualityBadge(_ quality: AVSpeechSynthesisVoiceQuality) -> String? {
        if #available(iOS 16.0, *) {
            if quality == .premium {
                return NSLocalizedString("tts_quality_premium", comment: "")
            }
        }
        switch quality {
        case .enhanced: return NSLocalizedString("tts_quality_enhanced", comment: "")
        default: return nil
        }
    }
}

// MARK: - Model

@MainActor
final class TTSSettingsModel: ObservableObject {
    @Published var rate: Double
    @Published var pitch: Double
    @Published private(set) var selectedVoiceId: String?
    @Published private(set) var isPreviewing = false
    @Published private(set) var showPremiumPrompt: Bool

    private var allVoices: [AVSpeechSynthesisVoice] = []
    private let synthesizer = AVSpeechSynthesizer()
    private let synthesizerDelegate = PreviewDelegate()

    init() {
        let prefs = TTSPreferences()
        rate = Double(prefs.rate)
        pitch = Double(prefs.pitch)
        selectedVoiceId = prefs.voiceId
        showPremiumPrompt = TTSSettingsModel.shouldShowPremiumPrompt(voiceId: prefs.voiceId)

        synthesizer.delegate = synthesizerDelegate
        synthesizerDelegate.onFinish = { [weak self] in
            Task { @MainActor in self?.isPreviewing = false }
        }
    }

    func load() {
        guard allVoices.isEmpty else { return }
        allVoices = AVSpeechSynthesisVoice.speechVoices()
            .sorted {
                let l = displayLanguage(for: $0)
                let r = displayLanguage(for: $1)
                if l != r { return l < r }
                return $0.name < $1.name
            }
    }

    var voiceLanguages: [String] {
        Array(Set(allVoices.map(displayLanguage)))
            .sorted()
    }

    func voices(for language: String) -> [AVSpeechSynthesisVoice] {
        allVoices.filter { displayLanguage(for: $0) == language }
    }

    var selectedVoiceDisplayName: String {
        guard
            let id = selectedVoiceId,
            let voice = AVSpeechSynthesisVoice(identifier: id)
        else {
            return NSLocalizedString("tts_default", comment: "")
        }
        return voice.name
    }

    var rateDisplay: String {
        let pct = Int(((rate - Double(AVSpeechUtteranceMinimumSpeechRate)) /
                       (Double(AVSpeechUtteranceMaximumSpeechRate) - Double(AVSpeechUtteranceMinimumSpeechRate))) * 100)
        return "\(pct)%"
    }

    var pitchDisplay: String {
        String(format: "%.2f×", pitch)
    }

    // MARK: Persistence

    func persistRate() {
        var prefs = TTSPreferences()
        prefs.rate = Float(rate)
    }

    func persistPitch() {
        var prefs = TTSPreferences()
        prefs.pitch = Float(pitch)
    }

    func selectVoice(_ id: String?) {
        var prefs = TTSPreferences()
        prefs.voiceId = id
        selectedVoiceId = id
        showPremiumPrompt = TTSSettingsModel.shouldShowPremiumPrompt(voiceId: id)
    }

    func resetRateAndPitch() {
        rate = Double(AVSpeechUtteranceDefaultSpeechRate)
        pitch = 1.0
        persistRate()
        persistPitch()
    }

    // MARK: Premium Voice Prompt

    func dismissPremiumPrompt() {
        UserDefaults.standard.set(true, forKey: "tts_premium_prompt_dismissed")
        showPremiumPrompt = false
    }

    private static func shouldShowPremiumPrompt(voiceId: String?) -> Bool {
        guard UserDefaults.standard.bool(forKey: "tts_premium_prompt_dismissed") == false else {
            return false
        }
        let voice: AVSpeechSynthesisVoice?
        if let id = voiceId {
            voice = AVSpeechSynthesisVoice(identifier: id)
        } else {
            voice = AVSpeechSynthesisVoice(language: Locale.current.languageCode)
        }
        guard let v = voice else { return false }
        if #available(iOS 16.0, *) {
            if v.quality == .premium {
                return false
            }
        }
        return v.quality != .enhanced
    }

    // MARK: Preview

    func togglePreview() {
        if isPreviewing {
            stopPreview()
        } else {
            playPreview()
        }
    }

    func playPreview() {
        stopPreview()

        let utterance = AVSpeechUtterance(
            string: NSLocalizedString("tts_settings_preview_text", comment: "")
        )
        utterance.rate = Float(rate)
        utterance.pitchMultiplier = Float(pitch)

        if
            let id = selectedVoiceId,
            let voice = AVSpeechSynthesisVoice(identifier: id)
        {
            utterance.voice = voice
        }

        isPreviewing = true
        synthesizer.speak(utterance)
    }

    func stopPreview() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isPreviewing = false
    }

    // MARK: Helpers

    private func displayLanguage(for voice: AVSpeechSynthesisVoice) -> String {
        Locale.current.localizedString(forLanguageCode: voice.language) ?? voice.language
    }
}

// MARK: - Preview Delegate

private final class PreviewDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (() -> Void)?

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onFinish?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onFinish?()
    }
}

#Preview {
    NavigationView {
        TTSSettingsView()
    }
    .navigationViewStyle(.stack)
}
