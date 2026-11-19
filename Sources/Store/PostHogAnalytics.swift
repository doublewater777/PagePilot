//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import os
import UIKit

/// Configuration for the PostHog telemetry/analytics client.
public struct PostHogConfiguration {
    public var apiKey: String?
    public var host: URL
    public var isEnabled: Bool
    public var debugLogging: Bool

    public static let defaultHost = URL(string: "https://us.i.posthog.com")!

    public init(
        apiKey: String? = nil,
        host: URL = defaultHost,
        isEnabled: Bool = true,
        debugLogging: Bool = true
    ) {
        self.apiKey = apiKey
        self.host = host
        self.isEnabled = isEnabled
        self.debugLogging = debugLogging
    }

    /// Resolves configuration from environment variables and Info.plist.
    public static func resolveFromEnvironment() -> PostHogConfiguration {
        let env = ProcessInfo.processInfo.environment
        let bundle = Bundle.main

        // 1. Resolve API Key: Environment variable takes precedence, then Info.plist
        let rawKey = env["POSTHOG_API_KEY"] ?? (bundle.object(forInfoDictionaryKey: "PostHogAPIKey") as? String)
        let trimmedKey = rawKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let validKey: String?
        if let key = trimmedKey, !key.isEmpty, !key.hasPrefix("$(") {
            validKey = key
        } else {
            validKey = nil
        }

        // 2. Resolve Host: Environment variable or Info.plist or default
        let rawHost = env["POSTHOG_HOST"] ?? (bundle.object(forInfoDictionaryKey: "PostHogHost") as? String)
        let hostUrl: URL
        if let rawHost = rawHost?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawHost.isEmpty,
           !rawHost.hasPrefix("$("),
           let parsed = URL(string: rawHost) {
            hostUrl = parsed
        } else {
            hostUrl = defaultHost
        }

        #if DEBUG
        let isDebug = true
        #else
        let isDebug = false
        #endif

        return PostHogConfiguration(
            apiKey: validKey,
            host: hostUrl,
            isEnabled: true,
            debugLogging: isDebug
        )
    }
}

/// Lightweight PostHog analytics and telemetry client.
/// Conforms to PostHog Capture API (https://posthog.com/docs/api/capture).
public final class PostHogAnalytics {
    public static let shared = PostHogAnalytics()
    private static let logger = Logger(subsystem: "com.panyang.PagePilot", category: "PostHog")

    public private(set) var configuration: PostHogConfiguration
    public var session: URLSession

    private var observer: NSObjectProtocol?
    private let queue = DispatchQueue(label: "com.panyang.pagepilot.posthog", qos: .utility)
    private let userDefaults: UserDefaults

    private static let distinctIdKey = "com.panyang.pagepilot.posthog.distinct_id"

    public init(
        configuration: PostHogConfiguration = .resolveFromEnvironment(),
        session: URLSession = .shared,
        userDefaults: UserDefaults = .standard
    ) {
        self.configuration = configuration
        self.session = session
        self.userDefaults = userDefaults
    }

    /// Convenience configure method for application launch.
    public static func configure(with config: PostHogConfiguration? = nil) {
        if let config = config {
            shared.configuration = config
        }
        shared.startObserving()

        #if DEBUG
        if shared.configuration.apiKey == nil {
            print("[PostHog] Initialized in simulated/debug mode (no API key configured). Events will be logged locally.")
            Self.logger.notice("[PostHog] Initialized in simulated/debug mode (no API key configured). Events will be logged locally.")
        } else {
            print("[PostHog] Initialized with host: \(shared.configuration.host.absoluteString)")
            Self.logger.notice("[PostHog] Initialized with host: \(shared.configuration.host.absoluteString, privacy: .public)")
        }
        #endif
    }

    /// Update configuration dynamically if needed.
    public func updateConfiguration(_ config: PostHogConfiguration) {
        self.configuration = config
    }

    /// Distinct ID identifying the anonymous or logged-in user.
    public var distinctId: String {
        if let existing = userDefaults.string(forKey: Self.distinctIdKey) {
            return existing
        }
        let generated = UUID().uuidString
        userDefaults.set(generated, forKey: Self.distinctIdKey)
        return generated
    }

    /// Set an explicit distinctId (e.g. on user login).
    public func identify(distinctId: String, userProperties: [String: Any]? = nil) {
        userDefaults.set(distinctId, forKey: Self.distinctIdKey)
        var props: [String: Any] = [:]
        if let userProperties = userProperties {
            props["$set"] = userProperties
        }
        capture("$identify", properties: props)
    }

    /// Reset distinct ID back to a fresh anonymous UUID.
    public func reset() {
        userDefaults.removeObject(forKey: Self.distinctIdKey)
    }

    /// Starts observing application analytics events from NotificationCenter.
    public func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .analyticsEventLogged,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let userInfo = notification.userInfo,
                  let eventName = userInfo["event_name"] as? String else {
                return
            }
            let parameters = userInfo["parameters"] as? [String: Any] ?? [:]
            self.capture(eventName, properties: parameters)
        }
    }

    /// Stops observing analytics events.
    public func stopObserving() {
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
            observer = nil
        }
    }

    /// Capture an analytics event and forward to PostHog.
    public func capture(_ event: String, properties: [String: Any]? = nil) {
        guard configuration.isEnabled else { return }

        queue.async { [weak self] in
            guard let self = self else { return }
            self.sendEvent(name: event, customProperties: properties ?? [:])
        }
    }

    /// Capture a screen view event.
    public func screen(_ title: String, properties: [String: Any]? = nil) {
        var props = properties ?? [:]
        props["$screen_name"] = title
        capture("$screen", properties: props)
    }

    /// Tracks posture / layout transition (e.g. fold / unfold on iPhone Duo).
    public func recordPostureChange(size: CGSize) {
        let isDuoUnfolded = (size.width == 669 && size.height == 951) || (size.width == 951 && size.height == 669)
        let isDuoFolded = (size.width == 466 && size.height == 678) || (size.width == 678 && size.height == 466)

        var properties: [String: Any] = [
            "width": size.width,
            "height": size.height,
            "aspect_ratio": size.height > 0 ? size.width / size.height : 0
        ]

        if isDuoUnfolded {
            properties["duo_state"] = "unfolded"
        } else if isDuoFolded {
            properties["duo_state"] = "folded"
        }

        capture("duo_posture_changed", properties: properties)
    }

    /// Sends a test event to verify PostHog telemetry.
    @discardableResult
    public func sendTestEvent(context: String = "manual_check") -> String {
        let testId = UUID().uuidString
        capture("posthog_test_event", properties: [
            "test_id": testId,
            "test_context": context,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ])
        return testId
    }

    // MARK: - Private Payload & Dispatch

    private func sendEvent(name: String, customProperties: [String: Any]) {
        var allProperties = defaultProperties()
        for (key, val) in customProperties {
            allProperties[key] = val
        }

        let isoDate = ISO8601DateFormatter().string(from: Date())
        let payload: [String: Any] = [
            "api_key": configuration.apiKey ?? "simulated_key",
            "event": name,
            "distinct_id": distinctId,
            "properties": allProperties,
            "timestamp": isoDate
        ]

        if configuration.debugLogging {
            let mode = configuration.apiKey != nil ? "Live" : "Simulated"
            let logMsg = "[\(mode)] Captured '\(name)' with \(allProperties.count) properties: \(allProperties)"
            print("[PostHog] \(logMsg)")
            Self.logger.notice("[PostHog] \(logMsg, privacy: .public)")
        }

        // If no real API key is configured, log locally and skip network call
        guard let apiKey = configuration.apiKey, !apiKey.isEmpty else {
            return
        }

        var captureUrl = configuration.host
        if !captureUrl.path.hasSuffix("/capture/") && !captureUrl.path.hasSuffix("/capture") {
            captureUrl = captureUrl.appendingPathComponent("capture/")
        }

        var request = URLRequest(url: captureUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            print("[PostHog] Error serializing payload for '\(name)': \(error)")
            return
        }

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("[PostHog] Network error capturing '\(name)': \(error.localizedDescription)")
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                print("[PostHog] HTTP \(http.statusCode) error capturing '\(name)': \(body)")
            } else {
                #if DEBUG
                print("[PostHog] Successfully dispatched '\(name)' to PostHog.")
                #endif
            }
        }
        task.resume()
    }

    private func defaultProperties() -> [String: Any] {
        var props: [String: Any] = [
            "$lib": "posthog-ios-light",
            "$lib_version": "1.0.0",
            "$os": "iOS",
            "$os_version": UIDevice.current.systemVersion,
            "$device_id": distinctId
        ]

        let bundle = Bundle.main
        if let appVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String {
            props["$app_version"] = appVersion
        }
        if let buildNumber = bundle.infoDictionary?["CFBundleVersion"] as? String {
            props["$app_build"] = buildNumber
        }

        props["$device_model"] = UIDevice.current.model

        let screen = UIScreen.main
        props["$screen_width"] = screen.bounds.width
        props["$screen_height"] = screen.bounds.height

        // Detect iPhone Duo features
        let deviceName = UIDevice.current.name
        let isDuo = deviceName.localizedCaseInsensitiveContains("Duo") ||
                    (screen.bounds.width == 669 && screen.bounds.height == 951) ||
                    (screen.bounds.width == 951 && screen.bounds.height == 669)
        props["is_duo"] = isDuo

        return props
    }
}
