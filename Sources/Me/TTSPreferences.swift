//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import AVFoundation
import Foundation
import ReadiumNavigator
import ReadiumShared

/// Single source of truth for user-selected TTS preferences.
///
/// Stored in `UserDefaults` so they persist across launches and are shared
/// between the global Me tab and every reader that uses TTS.
struct TTSPreferences {
    private enum Keys {
        static let voiceId = "tts_preferred_voice"
        static let rate = "tts_rate"
        static let pitch = "tts_pitch"
    }

    /// Apple voice identifier (e.g. "com.apple.voice.compact.zh-CN.Tingting").
    /// `nil` = use the system default for the publication's language.
    var voiceId: String? {
        get {
            let raw = UserDefaults.standard.string(forKey: Keys.voiceId)
            return (raw?.isEmpty == false) ? raw : nil
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.voiceId) }
    }

    /// Speech rate. Range: `AVSpeechUtteranceMinimumSpeechRate`...`AVSpeechUtteranceMaximumSpeechRate`.
    var rate: Float {
        get {
            let v = UserDefaults.standard.float(forKey: Keys.rate)
            return v == 0 ? AVSpeechUtteranceDefaultSpeechRate : v
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.rate) }
    }

    /// Pitch multiplier. 1.0 = normal, range 0.5...2.0.
    var pitch: Float {
        get {
            let v = UserDefaults.standard.float(forKey: Keys.pitch)
            return v == 0 ? 1.0 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.pitch) }
    }

    // MARK: - Bridge to Readium

    /// Builds an initial Readium `Configuration` from the saved voice preference.
    var readiumConfig: PublicationSpeechSynthesizer.Configuration {
        var config = PublicationSpeechSynthesizer.Configuration()
        if let id = voiceId {
            config.voiceIdentifier = id
            // Derive language from the voice so Readium can match a tokenizer.
            if let voice = AVSpeechSynthesisVoice(identifier: id) {
                config.defaultLanguage = Language(code: .bcp47(voice.language))
            }
        }
        return config
    }
}
