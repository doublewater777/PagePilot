//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import AVFoundation
import Combine
import Foundation
import MediaPlayer
import ReadiumNavigator
import ReadiumShared

final class TTSViewModel: ObservableObject, Loggable {
    struct State: Equatable {
        /// Whether the TTS was enabled by the user.
        var showControls: Bool = false
        /// Whether the TTS is currently speaking.
        var isPlaying: Bool = false
    }

    struct Settings: Equatable {
        /// Currently selected user preferences.
        let config: PublicationSpeechSynthesizer.Configuration
        /// Languages supported by the synthesizer.
        let availableLanguages: [Language]
        /// Voices supported by the synthesizer, for the selected language.
        let availableVoiceIds: [String]

        init(config: PublicationSpeechSynthesizer.Configuration, availableLanguages: [Language] = [], availableVoiceIds: [String] = []) {
            self.config = config
            self.availableLanguages = availableLanguages
            self.availableVoiceIds = availableVoiceIds
        }

        init(synthesizer: PublicationSpeechSynthesizer) {
            let voicesByLanguage: [Language: [TTSVoice]] =
                Dictionary(grouping: synthesizer.availableVoices, by: \.language)

            config = synthesizer.config
            availableLanguages = voicesByLanguage.keys.sorted { $0.localizedDescription() < $1.localizedDescription() }
            availableVoiceIds = synthesizer.config.defaultLanguage
                .flatMap { voicesByLanguage[$0]?.map(\.identifier) }
                ?? []
        }
    }

    @Published private(set) var state: State = .init()
    @Published private(set) var settings: Settings

    private let publication: Publication
    private let navigator: Navigator
    private let synthesizer: PublicationSpeechSynthesizer
    private let engineDelegate: TTSEngineDelegate

    @Published private var playingUtterance: Locator?
    private let playingWordRangeSubject = PassthroughSubject<Locator, Never>()

    private var isMoving = false
    private var navigationGeneration = 0
    private var isNavigationSuspended = false
    private var navigationTask: Task<Void, Never>?

    private var subscriptions: Set<AnyCancellable> = []

    init?(navigator: Navigator, publication: Publication) {
        let prefs = TTSPreferences()

        // Build the engine and apply the user's rate/pitch on every utterance.
        let engineDelegate = TTSEngineDelegate()
        let engineFactory: () -> TTSEngine = {
            let engine = AVTTSEngine()
            engine.delegate = engineDelegate
            return engine
        }

        guard let synthesizer = PublicationSpeechSynthesizer(
            publication: publication,
            config: prefs.readiumConfig,
            engineFactory: engineFactory
        ) else {
            return nil
        }
        self.engineDelegate = engineDelegate
        self.synthesizer = synthesizer
        settings = Settings(config: prefs.readiumConfig)
        self.navigator = navigator
        self.publication = publication

        synthesizer.delegate = self

        // Asynchronously load available voices and languages to prevent blocking the main thread during init
        Task { [weak self] in
            guard let self = self else { return }
            let loadedSettings = await Task.detached(priority: .userInitiated) {
                let voices = synthesizer.availableVoices
                let config = synthesizer.config
                let voicesByLanguage = Dictionary(grouping: voices, by: \.language)
                let availableLanguages = voicesByLanguage.keys.sorted { $0.localizedDescription() < $1.localizedDescription() }
                let availableVoiceIds = config.defaultLanguage
                    .flatMap { voicesByLanguage[$0]?.map(\.identifier) }
                    ?? []
                return Settings(config: config, availableLanguages: availableLanguages, availableVoiceIds: availableVoiceIds)
            }.value

            await MainActor.run {
                self.settings = loadedSettings
            }
        }

        // Highlight the currently spoken utterance.
        if let navigator = navigator as? DecorableNavigator {
            $playingUtterance
                .removeDuplicates()
                .sink { locator in
                    var decorations: [Decoration] = []
                    if let locator = locator {
                        decorations.append(Decoration(
                            id: "tts-utterance",
                            locator: locator,
                            style: .highlight(tint: .red)
                        ))
                    }
                    navigator.apply(decorations: decorations, in: "tts")
                }
                .store(in: &subscriptions)
        }

        // Navigate to the currently spoken utterance word.
        // This will automatically turn pages when needed.
        playingWordRangeSubject
            .removeDuplicates()
            .map { [weak self] locator in
                (self?.navigationGeneration ?? 0, locator)
            }
            //  Improve performances by throttling the moves to maximum one per second.
            .throttle(for: 1, scheduler: RunLoop.main, latest: true)
            .filter { [weak self] _ in self?.isMoving == false }
            .sink { [weak self] generation, locator in
                guard let self = self else {
                    return
                }
                guard !isNavigationSuspended, generation == navigationGeneration else { return }

                isMoving = true
                navigationTask = Task { [weak self] in
                    await navigator.go(to: locator)
                    self?.isMoving = false
                    self?.navigationTask = nil
                }
            }
            .store(in: &subscriptions)
    }

    func setConfig(_ config: PublicationSpeechSynthesizer.Configuration) {
        synthesizer.config = config
        settings = Settings(synthesizer: synthesizer)
    }

    func voiceWithIdentifier(_ id: String) -> TTSVoice? {
        synthesizer.voiceWithIdentifier(id)
    }

    @objc func start() {
        activateAudioSession()

        if let navigator = navigator as? VisualNavigator {
            Task {
                // Gets the locator of the element at the top of the page.
                if let locator = await navigator.firstVisibleElementLocator() {
                    synthesizer.start(from: locator)
                }
            }
        } else {
            synthesizer.start(from: navigator.currentLocation)
        }

        setupNowPlaying()
    }

    func restart(from locator: Locator) {
        activateAudioSession()
        synthesizer.start(from: locator)
    }

    func suspendNavigation() async {
        navigationGeneration &+= 1
        isNavigationSuspended = true
        let task = navigationTask
        task?.cancel()
        await task?.value
        navigationTask = nil
        isMoving = false
    }

    func resumeNavigation() {
        navigationGeneration &+= 1
        isNavigationSuspended = false
    }

    @objc func stop() {
        synthesizer.stop()
    }

    @objc func pauseOrResume() {
        synthesizer.pauseOrResume()
    }

    @objc func pause() {
        synthesizer.pause()
    }

    @objc func previous() {
        synthesizer.previous()
    }

    @objc func next() {
        synthesizer.next()
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio)
        try? session.setActive(true)
    }

    // MARK: - Now Playing

    // This will display the publication in the Control Center and support
    // external controls.

    private func setupNowPlaying() {
        Task {
            NowPlayingInfo.shared.media = await .init(
                title: publication.metadata.title ?? "",
                artist: publication.metadata.authors.map(\.name).joined(separator: ", "),
                artwork: try? publication.cover().get()
            )
        }

        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.pauseOrResume()
            return .success
        }
    }

    private func clearNowPlaying() {
        NowPlayingInfo.shared.clear()
    }
}

extension TTSViewModel: PublicationSpeechSynthesizerDelegate {
    func publicationSpeechSynthesizer(_ synthesizer: PublicationSpeechSynthesizer, stateDidChange synthesizerState: PublicationSpeechSynthesizer.State) {
        switch synthesizerState {
        case .stopped:
            state.showControls = false
            state.isPlaying = false
            playingUtterance = nil
            clearNowPlaying()

        case let .playing(utterance, range: wordRange):
            state.showControls = true
            state.isPlaying = true
            playingUtterance = utterance.locator
            if let wordRange = wordRange {
                playingWordRangeSubject.send(wordRange)
            }

        case let .paused(utterance):
            state.showControls = true
            state.isPlaying = false
            playingUtterance = utterance.locator
        }
    }

    func publicationSpeechSynthesizer(_ synthesizer: PublicationSpeechSynthesizer, utterance: PublicationSpeechSynthesizer.Utterance, didFailWithError error: PublicationSpeechSynthesizer.Error) {
        // FIXME:
        log(.error, error)
    }
}


/// Bridge that applies user-selected rate and pitch to every utterance
/// produced by the Readium `AVTTSEngine`.
///
/// The Readium `PublicationSpeechSynthesizer.Configuration` only exposes
/// `defaultLanguage` and `voiceIdentifier`. Rate and pitch are configured
/// here at the AVFoundation layer.
final class TTSEngineDelegate: AVTTSEngineDelegate {
    func avTTSEngine(_ engine: AVTTSEngine, didCreateUtterance utterance: AVSpeechUtterance) {
        let prefs = TTSPreferences()
        utterance.rate = prefs.rate.clamped(
            to: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate
        )
        utterance.pitchMultiplier = prefs.pitch.clamped(to: 0.5...2.0)
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
