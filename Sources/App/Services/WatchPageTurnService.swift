import Foundation
import Darwin
import ReadiumNavigator
import ReadiumShared
import UIKit
import WatchConnectivity
import ReadiumGCDWebServer

private enum WatchPageTurnRoute {
    static let direct = "direct"
    static let iPhoneRelay = "iPhoneRelay"
}

private enum WatchPageTurnErrorCode {
    static let iPadNotFound = "IPAD_NOT_FOUND"
    static let relayTimeout = "RELAY_TIMEOUT"
    static let navigatorNotReady = "NAVIGATOR_NOT_READY"
    static let invalidCommand = "INVALID_COMMAND"
    static let proRequired = "PRO_REQUIRED"
}

enum WatchAvailability {
    case unsupported
    case unpaired
    case appNotInstalled
    case unreachable
    case ready
}

enum WatchReaderAvailabilityPolicy {
    static func isReady(hasNavigator: Bool, applicationIsActive: Bool) -> Bool {
        hasNavigator && applicationIsActive
    }
}

enum PagePilotLANRecoveryAction: Equatable {
    case reresolveKnownServices
    case startBrowsing
    case continueBrowsing
}

enum PagePilotLANRecoveryPolicy {
    static func action(knownServiceCount: Int, isBrowsing: Bool) -> PagePilotLANRecoveryAction {
        if knownServiceCount > 0 {
            return .reresolveKnownServices
        }
        return isBrowsing ? .continueBrowsing : .startBrowsing
    }
}

enum PagePilotLANResolveRetryPolicy {
    static let maxImmediateRetries = 2

    static func shouldRetry(afterFailureCount failureCount: Int) -> Bool {
        failureCount <= maxImmediateRetries
    }
}

enum PagePilotLANResolveLifecycleAction: Equatable {
    case start
    case wait
    case stopThenRestart
}

enum PagePilotLANResolveLifecyclePolicy {
    static func action(
        isResolving: Bool,
        forceRestart: Bool
    ) -> PagePilotLANResolveLifecycleAction {
        guard isResolving else { return .start }
        return forceRestart ? .stopThenRestart : .wait
    }
}

enum PagePilotLANFallbackPolicy {
    static func shouldUseFallback(
        knownServiceCount: Int,
        fallbackWasInvalidated: Bool
    ) -> Bool {
        knownServiceCount == 0 && !fallbackWasInvalidated
    }
}

enum PagePilotLANEndpointSource: Equatable {
    case fallback
    case bonjour(ObjectIdentifier)
}

struct PagePilotLANEndpointCandidate: Equatable {
    let url: URL
    let generation: UInt64
    let source: PagePilotLANEndpointSource
}

enum PagePilotLANEndpointCandidatePolicy {
    static func isCurrent(
        _ candidate: PagePilotLANEndpointCandidate,
        currentGeneration: UInt64,
        knownServiceIDs: Set<ObjectIdentifier>,
        knownServiceCount: Int,
        fallbackWasInvalidated: Bool
    ) -> Bool {
        guard candidate.generation == currentGeneration else { return false }

        switch candidate.source {
        case .fallback:
            return knownServiceCount == 0 && !fallbackWasInvalidated
        case .bonjour(let serviceID):
            return knownServiceIDs.contains(serviceID)
        }
    }
}

struct PagePilotLANLookupCycleState: Equatable {
    private(set) var activeID: UInt64?
    private var nextID: UInt64 = 0

    mutating func beginOrJoin() -> (id: UInt64, isNew: Bool) {
        if let activeID {
            return (activeID, false)
        }

        nextID &+= 1
        activeID = nextID
        return (nextID, true)
    }

    func isActive(_ id: UInt64) -> Bool {
        activeID == id
    }

    @discardableResult
    mutating func finish(_ id: UInt64? = nil) -> Bool {
        guard let activeID else { return false }
        if let id, activeID != id {
            return false
        }
        self.activeID = nil
        return true
    }

    mutating func cancel() {
        activeID = nil
    }
}

enum PagePilotLANBrowserCallbackPolicy {
    static func isCurrent(
        callbackBrowser: NetServiceBrowser,
        currentBrowser: NetServiceBrowser
    ) -> Bool {
        callbackBrowser === currentBrowser
    }
}

private final class PagePilotLANBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    static let shared = PagePilotLANBrowser()

    private let serviceType = "_pagepilot._tcp."
    private let serviceDomain = "local."
    private let fallbackEndpoint = URL(string: "http://iPad.local:61482")
    private var browser: NetServiceBrowser
    private var services: [NetService] = []
    private var resolvingServices: Set<ObjectIdentifier> = []
    private var pendingReresolveServices: Set<ObjectIdentifier> = []
    private var resolveFailureCounts: [ObjectIdentifier: Int] = [:]
    private var pendingCompletions: [(PagePilotLANEndpointCandidate?) -> Void] = []
    private var lookupCycleState = PagePilotLANLookupCycleState()
    private var isBrowsing = false
    private var fallbackWasInvalidated = false
    private var discoveryGeneration: UInt64 = 0
    private var lastKnownCandidate: PagePilotLANEndpointCandidate?

    private var lastKnownEndpoint: URL? {
        lastKnownCandidate?.url
    }

    private var knownServiceIDs: Set<ObjectIdentifier> {
        Set(services.map(ObjectIdentifier.init))
    }

    private override init() {
        browser = NetServiceBrowser()
        super.init()
        browser.delegate = self
    }

    func warmUp() {
        DispatchQueue.main.async {
            self.startBrowsingIfNeeded()
        }
    }

    func stopAndClear() {
        DispatchQueue.main.async {
            self.discoveryGeneration &+= 1

            // Retire the browser object itself before stopping it. Any didStop,
            // didNotSearch, didFind, or didRemove callback already queued by the
            // previous search will carry the retired object and be ignored by
            // the delegate identity guards below. Re-granting Pro can therefore
            // start a new search immediately without sharing callback lifetime
            // with the stopped generation.
            let retiredBrowser = self.browser
            let replacementBrowser = NetServiceBrowser()
            replacementBrowser.delegate = self
            self.browser = replacementBrowser
            self.isBrowsing = false
            retiredBrowser.stop()

            let oldServices = self.services
            self.services.removeAll()
            self.resolvingServices.removeAll()
            self.pendingReresolveServices.removeAll()
            self.resolveFailureCounts.removeAll()
            self.lastKnownCandidate = nil
            self.fallbackWasInvalidated = false
            self.cancelPendingLookups()

            for service in oldServices {
                service.delegate = nil
                service.stop()
            }
        }
    }

    func endpoint(completion: @escaping (PagePilotLANEndpointCandidate?) -> Void) {
        DispatchQueue.main.async {
            if let candidate = self.lastKnownCandidate,
               self.isCurrent(candidate) {
                completion(candidate)
                return
            }
            self.lastKnownCandidate = nil

            let lookup = self.lookupCycleState.beginOrJoin()
            self.pendingCompletions.append(completion)

            self.startBrowsingIfNeeded()
            if !self.services.isEmpty {
                // A previous resolve may have timed out while the browser still
                // knows the service is present. Every fresh endpoint request is
                // therefore another opportunity to resolve that same service.
                self.resolveKnownServices()
            }

            // Concurrent endpoint callers share one lookup cycle and therefore
            // one set of fallback/timeout timers.
            guard lookup.isNew else { return }

            let cycleID = lookup.id
            let cycleGeneration = self.discoveryGeneration

            // Prefer Bonjour (works for localized device names and dynamic
            // ports). The fixed fallback is valid only when there is no known
            // Bonjour service to resolve.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self,
                      self.lookupCycleState.isActive(cycleID),
                      self.discoveryGeneration == cycleGeneration
                else {
                    return
                }
                guard self.lastKnownEndpoint == nil else { return }
                guard !self.pendingCompletions.isEmpty else {
                    _ = self.lookupCycleState.finish(cycleID)
                    return
                }
                guard PagePilotLANFallbackPolicy.shouldUseFallback(
                    knownServiceCount: self.services.count,
                    fallbackWasInvalidated: self.fallbackWasInvalidated
                ), let fallbackEndpoint = self.fallbackEndpoint else {
                    return
                }

                let candidate = PagePilotLANEndpointCandidate(
                    url: fallbackEndpoint,
                    generation: cycleGeneration,
                    source: .fallback
                )
                print("PagePilotLANBrowser: Bonjour slow, trying fallback \(fallbackEndpoint.absoluteString)")
                // Finish only the cycle that scheduled this timer. A later
                // lookup cannot be flushed by an older cycle's callback.
                self.flushPendingIfNeeded(with: candidate, cycleID: cycleID)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self,
                      self.lookupCycleState.isActive(cycleID),
                      self.discoveryGeneration == cycleGeneration
                else {
                    return
                }
                guard !self.pendingCompletions.isEmpty else {
                    _ = self.lookupCycleState.finish(cycleID)
                    return
                }

                if let candidate = self.lastKnownCandidate,
                   self.isCurrent(candidate) {
                    self.flushPendingIfNeeded(with: candidate, cycleID: cycleID)
                } else {
                    print("PagePilotLANBrowser: Bonjour timed out")
                    self.flushPendingIfNeeded(with: nil, cycleID: cycleID)
                }
            }
        }
    }

    func remember(_ candidate: PagePilotLANEndpointCandidate) {
        DispatchQueue.main.async {
            guard self.isCurrent(candidate) else {
                print("PagePilotLANBrowser: ignoring stale endpoint remember \(candidate.url.absoluteString)")
                return
            }
            self.lastKnownCandidate = candidate
        }
    }

    func invalidate(
        _ candidate: PagePilotLANEndpointCandidate,
        completion: (() -> Void)? = nil
    ) {
        DispatchQueue.main.async {
            guard candidate.generation == self.discoveryGeneration else {
                completion?()
                return
            }

            if candidate.source == .fallback {
                self.fallbackWasInvalidated = true
            }
            if self.lastKnownCandidate == candidate {
                print("PagePilotLANBrowser: invalidating endpoint \(candidate.url.absoluteString)")
                self.lastKnownCandidate = nil
            }

            self.recoverAfterInvalidation()
            completion?()
        }
    }

    private func isCurrent(_ candidate: PagePilotLANEndpointCandidate) -> Bool {
        PagePilotLANEndpointCandidatePolicy.isCurrent(
            candidate,
            currentGeneration: discoveryGeneration,
            knownServiceIDs: knownServiceIDs,
            knownServiceCount: services.count,
            fallbackWasInvalidated: fallbackWasInvalidated
        )
    }

    private func recoverAfterInvalidation() {
        switch PagePilotLANRecoveryPolicy.action(
            knownServiceCount: services.count,
            isBrowsing: isBrowsing
        ) {
        case .reresolveKnownServices:
            print("PagePilotLANBrowser: re-resolving \(services.count) known service(s)")
            resolveKnownServices(forceRestart: true)

        case .startBrowsing:
            startBrowsingIfNeeded()

        case .continueBrowsing:
            break
        }
    }

    private func resolveKnownServices(forceRestart: Bool = false) {
        for service in services {
            resolve(service, forceRestart: forceRestart)
        }
    }

    private func resolve(_ service: NetService, forceRestart: Bool = false) {
        guard services.contains(where: { $0 === service }) else { return }
        let serviceID = ObjectIdentifier(service)

        switch PagePilotLANResolveLifecyclePolicy.action(
            isResolving: resolvingServices.contains(serviceID),
            forceRestart: forceRestart
        ) {
        case .wait:
            return

        case .stopThenRestart:
            // NetService resolution continues after a resolved-address callback
            // until it is explicitly stopped. Queue the restart and let
            // netServiceDidStop mark the old lifecycle complete first.
            pendingReresolveServices.insert(serviceID)
            service.stop()
            return

        case .start:
            resolvingServices.insert(serviceID)
            service.delegate = self
            service.resolve(withTimeout: 2.0)
        }
    }

    private func handleResolveFailure(
        for service: NetService,
        reason: String,
        resolutionIsActive: Bool
    ) {
        let serviceID = ObjectIdentifier(service)
        guard services.contains(where: { $0 === service }) else { return }

        if lastKnownCandidate?.source == .bonjour(serviceID) {
            lastKnownCandidate = nil
        }

        let failureCount = (resolveFailureCounts[serviceID] ?? 0) + 1
        resolveFailureCounts[serviceID] = failureCount
        print("PagePilotLANBrowser: resolve failure for \(service.name) #\(failureCount): \(reason)")

        let shouldRetry = PagePilotLANResolveRetryPolicy.shouldRetry(
            afterFailureCount: failureCount
        )

        if resolutionIsActive {
            if shouldRetry {
                pendingReresolveServices.insert(serviceID)
            } else {
                pendingReresolveServices.remove(serviceID)
            }
            service.stop()
            return
        }

        resolvingServices.remove(serviceID)
        pendingReresolveServices.remove(serviceID)

        guard shouldRetry else {
            // Keep the service in the known set. A future endpoint() call can
            // try resolving it again without waiting for another didFind event.
            return
        }

        let delay = 0.25 * Double(failureCount)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  self.services.contains(where: { $0 === service })
            else {
                return
            }
            self.resolve(service)
        }
    }

    private func startBrowsingIfNeeded() {
        guard !isBrowsing else { return }
        isBrowsing = true
        print("PagePilotLANBrowser: browsing \(serviceType) in \(serviceDomain)")
        browser.searchForServices(ofType: serviceType, inDomain: serviceDomain)
    }

    private func flushPendingIfNeeded(
        with candidate: PagePilotLANEndpointCandidate?,
        cycleID: UInt64? = nil
    ) {
        guard !pendingCompletions.isEmpty else { return }
        guard lookupCycleState.finish(cycleID) else { return }

        let completions = pendingCompletions
        pendingCompletions = []
        completions.forEach { $0(candidate) }
    }

    private func cancelPendingLookups() {
        lookupCycleState.cancel()
        guard !pendingCompletions.isEmpty else { return }

        let completions = pendingCompletions
        pendingCompletions = []
        completions.forEach { $0(nil) }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard PagePilotLANBrowserCallbackPolicy.isCurrent(
            callbackBrowser: browser,
            currentBrowser: self.browser
        ) else { return }
        guard service.name.hasPrefix("PagePilot-iPad") else { return }
        print("PagePilotLANBrowser: found service \(service.name)")

        // Replace only older objects representing the same advertised service.
        // Late callbacks from those objects must not be able to overwrite the
        // newly discovered service's endpoint.
        let replaced = services.filter { $0 !== service && $0.name == service.name }
        for oldService in replaced {
            let oldID = ObjectIdentifier(oldService)
            resolvingServices.remove(oldID)
            pendingReresolveServices.remove(oldID)
            resolveFailureCounts.removeValue(forKey: oldID)
            if lastKnownCandidate?.source == .bonjour(oldID) {
                lastKnownCandidate = nil
            }
            oldService.stop()
        }
        services.removeAll { existing in
            replaced.contains(where: { $0 === existing })
        }
        if !services.contains(where: { $0 === service }) {
            services.append(service)
        }
        resolve(service)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let serviceID = ObjectIdentifier(sender)

        // didRemove (or a same-name replacement) can race a resolve callback.
        // Only a service object that is still in the browser's known set may
        // publish an endpoint.
        guard services.contains(where: { $0 === sender }) else {
            print("PagePilotLANBrowser: ignoring late resolve for removed service \(sender.name)")
            sender.stop()
            return
        }

        guard let endpoint = endpointURL(for: sender) else {
            handleResolveFailure(
                for: sender,
                reason: "resolved without a usable endpoint",
                resolutionIsActive: true
            )
            return
        }

        resolveFailureCounts.removeValue(forKey: serviceID)
        let candidate = PagePilotLANEndpointCandidate(
            url: endpoint,
            generation: discoveryGeneration,
            source: .bonjour(serviceID)
        )
        print("PagePilotLANBrowser: resolved \(sender.name) -> \(endpoint.absoluteString)")
        lastKnownCandidate = candidate
        flushPendingIfNeeded(with: candidate)

        // We only need one usable endpoint. Explicitly stop resolution and wait
        // for netServiceDidStop before considering this service idle again.
        sender.stop()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        handleResolveFailure(
            for: sender,
            reason: String(describing: errorDict),
            resolutionIsActive: false
        )
    }

    func netServiceDidStop(_ sender: NetService) {
        let serviceID = ObjectIdentifier(sender)
        resolvingServices.remove(serviceID)

        guard services.contains(where: { $0 === sender }) else {
            pendingReresolveServices.remove(serviceID)
            return
        }

        guard pendingReresolveServices.remove(serviceID) != nil else { return }

        // Restart on the next main-queue turn so the prior NetService resolve
        // lifecycle has fully completed before calling resolve again.
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.services.contains(where: { $0 === sender })
            else {
                return
            }
            self.resolve(sender)
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        guard PagePilotLANBrowserCallbackPolicy.isCurrent(
            callbackBrowser: browser,
            currentBrowser: self.browser
        ) else { return }
        print("PagePilotLANBrowser: failed to browse: \(errorDict)")
        isBrowsing = false

        if PagePilotLANFallbackPolicy.shouldUseFallback(
            knownServiceCount: services.count,
            fallbackWasInvalidated: fallbackWasInvalidated
        ), let fallbackEndpoint {
            flushPendingIfNeeded(with: PagePilotLANEndpointCandidate(
                url: fallbackEndpoint,
                generation: discoveryGeneration,
                source: .fallback
            ))
        } else if services.isEmpty {
            // No known service and the fallback was already proven stale.
            flushPendingIfNeeded(with: nil)
        } else {
            // A known custom-named/dynamic-port service is still authoritative.
            // Keep pending requests alive for its resolve callback or the common
            // endpoint timeout instead of racing them to iPad.local:61482.
            resolveKnownServices()
        }
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        guard PagePilotLANBrowserCallbackPolicy.isCurrent(
            callbackBrowser: browser,
            currentBrowser: self.browser
        ) else { return }
        isBrowsing = false
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        guard PagePilotLANBrowserCallbackPolicy.isCurrent(
            callbackBrowser: browser,
            currentBrowser: self.browser
        ) else { return }
        guard services.contains(where: { $0 === service }) else { return }
        let serviceID = ObjectIdentifier(service)
        services.removeAll { $0 === service }
        resolvingServices.remove(serviceID)
        pendingReresolveServices.remove(serviceID)
        resolveFailureCounts.removeValue(forKey: serviceID)
        service.stop()

        if lastKnownCandidate?.source == .bonjour(serviceID) {
            lastKnownCandidate = nil
        }
    }

    private func endpointURL(for service: NetService) -> URL? {
        if let url = numericIPv4EndpointURL(for: service) {
            return url
        }

        guard service.port > 0 else { return nil }
        let rawHost = service.hostName ?? "\(service.name).local"
        let host = rawHost.hasSuffix(".") ? String(rawHost.dropLast()) : rawHost
        if let url = URL(string: "http://\(urlHost(host)):\(service.port)") {
            return url
        }

        return numericIPv6EndpointURL(for: service)
    }

    private func numericIPv4EndpointURL(for service: NetService) -> URL? {
        guard let addresses = service.addresses else { return nil }

        for address in addresses {
            guard let endpoint = numericEndpointURL(from: address, family: sa_family_t(AF_INET)) else {
                continue
            }
            return endpoint
        }

        return nil
    }

    private func numericIPv6EndpointURL(for service: NetService) -> URL? {
        guard let addresses = service.addresses else { return nil }

        for address in addresses {
            guard let endpoint = numericEndpointURL(from: address, family: sa_family_t(AF_INET6)) else {
                continue
            }
            return endpoint
        }

        return nil
    }

    private func numericEndpointURL(from address: Data, family: sa_family_t) -> URL? {
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        var portBuffer = [CChar](repeating: 0, count: Int(NI_MAXSERV))

        let result = address.withUnsafeBytes { rawBuffer -> Int32 in
            guard let sockaddrPointer = rawBuffer.baseAddress?.assumingMemoryBound(to: sockaddr.self),
                  sockaddrPointer.pointee.sa_family == family else {
                return EAI_FAIL
            }

            return getnameinfo(
                sockaddrPointer,
                socklen_t(address.count),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                &portBuffer,
                socklen_t(portBuffer.count),
                NI_NUMERICHOST | NI_NUMERICSERV
            )
        }

        guard result == 0,
              let port = Int(String(cString: portBuffer)) else {
            return nil
        }

        let host = String(cString: hostBuffer)
        return URL(string: "http://\(urlHost(host)):\(port)")
    }

    private func urlHost(_ host: String) -> String {
        host.contains(":") ? "[\(host)]" : host
    }
}

/// Handles Watch session and page turn commands from Apple Watch
final class WatchPageTurnService: NSObject, ObservableObject {
    static let shared = WatchPageTurnService()

    /// URL of the iPhone Watch app, used to guide users who need to install PagePilot on a paired Watch.
    static let watchAppURL = URL(string: "bridge://")!

    @Published var isWatchConnected: Bool = false
    @Published var isLANWatchConnected: Bool = false

    /// iPad LAN diagnostics (surfaced in the Me tab on iPad).
    @Published private(set) var lanServerRunning = false
    @Published private(set) var lanServerPort: UInt = 0
    @Published private(set) var lanBonjourName: String = ""
    @Published private(set) var lastLANClientAddress: String = ""
    @Published private(set) var lastLANHitAt: Date?
    /// Last non-loopback client hit (real iPhone / LAN peer, not self-test).
    @Published private(set) var lastRemoteLANHitAt: Date?

    /// Weak reference to the currently active VisualNavigator
    weak var activeNavigator: VisualNavigator?
    private var pageTurnSuppressionToken: UUID?
    private var isPageTurnSuppressed: Bool { pageTurnSuppressionToken != nil }

    @Published var currentBookTitle: String = ""
    @Published var currentBookProgress: Double = 0.0

    var isReaderReady: Bool {
        WatchReaderAvailabilityPolicy.isReady(
            hasNavigator: activeNavigator != nil,
            applicationIsActive: UIApplication.shared.applicationState == .active
        )
    }

    private var session: WCSession?
    private var lanServer: ReadiumGCDWebServer?
    private var lanResetTimer: Timer?
    private let preferredLANPort: UInt = 61482
    private let ipadRelayEnabledKey = "ipad_watch_relay_enabled"
    private let commandDedupWindow: TimeInterval = 8.0
    private var recentLANCommandIDs: [String: Date] = [:]

    var watchAvailability: WatchAvailability {
        guard WCSession.isSupported() else { return .unsupported }
        let session = WCSession.default
        guard session.isPaired else { return .unpaired }
        guard session.isWatchAppInstalled else { return .appNotInstalled }
        guard session.isReachable else { return .unreachable }
        return .ready
    }

    private override init() {
        super.init()
    }

    func activate() {
        if WCSession.isSupported() {
            session = WCSession.default
            session?.delegate = self
            session?.activate()
        }
        // Automatic routing has no selected target. Pro iPads advertise the LAN
        // service, while Pro iPhones prewarm Bonjour discovery immediately.
        if UIDevice.current.userInterfaceIdiom == .pad {
            enableIPadRelay()
        } else if UIDevice.current.userInterfaceIdiom == .phone,
                  ProPurchaseManager.shared.hasProAccess {
            PagePilotLANBrowser.shared.warmUp()
        }
    }

    /// Starts the iPad LAN page-turn server when this device is an iPad with Pro.
    /// Safe to call repeatedly; no-ops on iPhone or without Pro Access.
    func enableIPadRelay() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        guard ProPurchaseManager.shared.hasProAccess else {
            disableIPadRelay()
            return
        }
        UserDefaults.standard.set(true, forKey: ipadRelayEnabledKey)
        startLANServer()
    }

    /// Stops iPad LAN advertising when Pro access is no longer valid.
    func disableIPadRelay() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        UserDefaults.standard.set(false, forKey: ipadRelayEnabledKey)
        recentLANCommandIDs.removeAll()
        stopLANServer()
    }

    /// Stops iPhone-side nearby-iPad discovery and invalidates all outstanding
    /// endpoint candidates. Safe to call on entitlement revoke.
    func stopIPadRelayDiscovery() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        PagePilotLANBrowser.shared.stopAndClear()
    }

    /// Keeps automatic nearby-iPad discovery warm on a Pro iPhone.
    func prepareIPadRelay() {
        guard UIDevice.current.userInterfaceIdiom == .phone,
              ProPurchaseManager.shared.hasProAccess
        else {
            return
        }
        PagePilotLANBrowser.shared.warmUp()
    }

    /// Actively hit the local LAN status endpoint (self-test). Returns whether the server answered.
    @MainActor
    func runLocalStatusProbe() async -> Bool {
        if UIDevice.current.userInterfaceIdiom == .pad {
            enableIPadRelay()
        }
        guard lanServerRunning, lanServerPort > 0 else { return false }

        guard let url = URL(string: "http://127.0.0.1:\(lanServerPort)/status") else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.0

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            print("WatchPageTurnService: local status probe failed: \(error)")
            return false
        }
    }

    /// iPhone: actively try to reach an iPad page-turn server once (for diagnostics).
    func probeIPadRelayNow(completion: ((Bool) -> Void)? = nil) {
        guard UIDevice.current.userInterfaceIdiom == .phone,
              ProPurchaseManager.shared.hasProAccess else {
            completion?(false)
            return
        }
        PagePilotLANBrowser.shared.warmUp()
        relayRequestToLAN(path: "status", method: "GET", body: nil) { payload in
            let ok = (payload["ok"] as? Bool) == true
            completion?(ok)
        }
    }

    /// Call this from VisualReaderViewController when it appears/loads.
    func registerNavigator(_ navigator: VisualNavigator, publication: Publication) {
        self.activeNavigator = navigator
        let title = publication.metadata.title ?? ""
        let progress = navigator.currentLocation?.locations.totalProgression ?? 0.0
        self.currentBookTitle = title
        self.currentBookProgress = progress
        updateProgress(title: title, progression: progress)

        // Defensive: start LAN when a Pro iPad opens a book, even if Pro was
        // granted after the initial activate() call.
        if UIDevice.current.userInterfaceIdiom == .pad {
            enableIPadRelay()
        }
    }

    /// Call this from VisualReaderViewController when it disappears.
    func unregisterNavigator() {
        self.activeNavigator = nil
        pageTurnSuppressionToken = nil
        var context = WatchPageTurnSettings().watchContext
        context["currentBookTitle"] = ""
        context["currentBookProgress"] = 0.0
        updateApplicationContextSafely(context)
        // Keep the LAN server running so discovery stays warm. The /command
        // handler will return NAVIGATOR_NOT_READY until another Reader opens.
    }

    func beginPageTurnSuppression() -> UUID {
        let token = UUID()
        pageTurnSuppressionToken = token
        return token
    }

    func endPageTurnSuppression(_ token: UUID) {
        guard pageTurnSuppressionToken == token else { return }
        pageTurnSuppressionToken = nil
    }

    /// Update reading progress on the watch
    func updateProgress(title: String, progression: Double?) {
        self.currentBookTitle = title
        self.currentBookProgress = progression ?? 0.0

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled
        else { return }

        var context = WatchPageTurnSettings().watchContext
        context["currentBookTitle"] = title
        context["currentBookProgress"] = progression ?? 0.0

        updateApplicationContextSafely(context)
    }

    private func updateApplicationContextSafely(_ context: [String: Any]) {
        do {
            try WCSession.default.updateApplicationContext(context)
        } catch let error as WCError where error.code == .watchAppNotInstalled {
            // Expected when the Watch app is not installed; no need to log.
        } catch {
            print("WatchPageTurnService: Failed to update application context: \(error)")
        }
    }

    private func handleCommand(_ command: PageCommand, completion: (([String: Any]) -> Void)? = nil) {
        Task { @MainActor in
            guard !self.isPageTurnSuppressed else {
                var payload = self.localStatusPayload(route: WatchPageTurnRoute.direct)
                payload["pageDirection"] = command.rawValue
                payload["didTurnPage"] = false
                completion?(payload)
                return
            }
            guard let navigator = self.activeNavigator,
                  WatchReaderAvailabilityPolicy.isReady(
                      hasNavigator: true,
                      applicationIsActive: UIApplication.shared.applicationState == .active
                  ) else {
                completion?(self.errorPayload(
                    route: WatchPageTurnRoute.direct,
                    code: WatchPageTurnErrorCode.navigatorNotReady,
                    message: "reader is not ready"
                ))
                return
            }
            let succeeded: Bool
            switch command {
            case .next:
                succeeded = await navigator.goForward(options: NavigatorGoOptions(animated: false))
            case .prev:
                succeeded = await navigator.goBackward(options: NavigatorGoOptions(animated: false))
            }

            if succeeded {
                ReviewPromptManager.shared.recordWatchPageTurn()
                NotificationCenter.default.post(name: .watchPageTurnDidSucceed, object: nil)
            }

            var payload = self.localStatusPayload(route: WatchPageTurnRoute.direct)
            payload["pageDirection"] = command.rawValue
            payload["didTurnPage"] = succeeded
            completion?(payload)
        }
    }

    private func relayCommandToLAN(
        _ command: PageCommand,
        requestID: String?,
        replyHandler: (([String: Any]) -> Void)? = nil
    ) {
        relayRequestToLAN(
            path: "command",
            method: "POST",
            body: [
                "action": command.rawValue,
                "source": "watch",
                "requestId": requestID ?? UUID().uuidString,
                "timestamp": Date().timeIntervalSince1970
            ],
            replyHandler: replyHandler
        )
    }

    private func relayStatusToLAN(replyHandler: (([String: Any]) -> Void)? = nil) {
        relayRequestToLAN(path: "status", method: "GET", body: nil, replyHandler: replyHandler)
    }

    private func relayRequestToLAN(
        path: String,
        method: String,
        body: [String: Any]?,
        retryAfterInvalidation: Bool = true,
        replyHandler: (([String: Any]) -> Void)? = nil
    ) {
        guard ProPurchaseManager.shared.hasProAccess else {
            replyHandler?(errorPayload(
                route: WatchPageTurnRoute.iPhoneRelay,
                code: WatchPageTurnErrorCode.proRequired,
                message: "pro is required for iPad page turn"
            ))
            return
        }

        PagePilotLANBrowser.shared.endpoint { candidate in
            // Entitlement may have changed while Bonjour discovery was pending.
            // Re-check immediately before creating/sending any HTTP request.
            guard ProPurchaseManager.shared.hasProAccess else {
                replyHandler?(self.errorPayload(
                    route: WatchPageTurnRoute.iPhoneRelay,
                    code: WatchPageTurnErrorCode.proRequired,
                    message: "pro is required for iPad page turn"
                ))
                return
            }

            guard let candidate else {
                replyHandler?(self.errorPayload(
                    route: WatchPageTurnRoute.iPhoneRelay,
                    code: WatchPageTurnErrorCode.iPadNotFound,
                    message: "iPhone could not find PagePilot on iPad"
                ))
                return
            }

            let endpoint = candidate.url
            let url = endpoint.appendingPathComponent(path)
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.timeoutInterval = 2.5
            if let body {
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    if retryAfterInvalidation {
                        PagePilotLANBrowser.shared.invalidate(candidate) {
                            // relayRequestToLAN re-checks entitlement before the
                            // retry performs any new discovery or HTTP request.
                            self.relayRequestToLAN(
                                path: path,
                                method: method,
                                body: body,
                                retryAfterInvalidation: false,
                                replyHandler: replyHandler
                            )
                        }
                        return
                    }

                    PagePilotLANBrowser.shared.invalidate(candidate)
                    replyHandler?(self.errorPayload(
                        route: WatchPageTurnRoute.iPhoneRelay,
                        code: WatchPageTurnErrorCode.relayTimeout,
                        message: "\(error.localizedDescription) (\(url.absoluteString))"
                    ))
                    return
                }

                var payload: [String: Any] = [
                    "status": "ok",
                    "ok": true,
                    "route": WatchPageTurnRoute.iPhoneRelay,
                    "endpoint": endpoint.absoluteString
                ]
                if let data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    payload.merge(json) { _, new in new }
                    payload["route"] = WatchPageTurnRoute.iPhoneRelay
                }

                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    // 409 = reader not ready still means the candidate answered.
                    if http.statusCode != 409 {
                        PagePilotLANBrowser.shared.invalidate(candidate)
                    } else {
                        PagePilotLANBrowser.shared.remember(candidate)
                    }
                    if payload["error"] == nil {
                        payload = self.errorPayload(
                            route: WatchPageTurnRoute.iPhoneRelay,
                            code: http.statusCode == 409
                                ? WatchPageTurnErrorCode.navigatorNotReady
                                : WatchPageTurnErrorCode.relayTimeout,
                            message: "iPad HTTP \(http.statusCode)"
                        )
                    } else {
                        payload["status"] = "error"
                        payload["ok"] = false
                    }
                } else {
                    PagePilotLANBrowser.shared.remember(candidate)
                }
                replyHandler?(payload)
            }.resume()
        }
    }

    private func localStatusPayload(route: String) -> [String: Any] {
        [
            "status": "ok",
            "ok": true,
            "route": route,
            "target": UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone",
            "readerReady": isReaderReady,
            "bookTitle": currentBookTitle,
            "bookProgress": currentBookProgress,
            "crownSensitivity": WatchPageTurnSettings().crownSensitivity
        ]
    }

    private func errorPayload(route: String, code: String, message: String) -> [String: Any] {
        [
            "status": "error",
            "ok": false,
            "route": route,
            "errorCode": code,
            "error": message
        ]
    }

    private func jsonResponse(_ object: [String: Any], statusCode: Int = 200) -> ReadiumGCDWebServerDataResponse? {
        guard let response = ReadiumGCDWebServerDataResponse(jsonObject: object) else { return nil }
        response.statusCode = statusCode
        return response
    }

    private func shouldProcessLANCommand(requestID: String?) -> Bool {
        guard let requestID, !requestID.isEmpty else { return true }
        let now = Date()
        recentLANCommandIDs = recentLANCommandIDs.filter {
            now.timeIntervalSince($0.value) < commandDedupWindow
        }
        if recentLANCommandIDs[requestID] != nil {
            return false
        }
        recentLANCommandIDs[requestID] = now
        return true
    }

    // MARK: - LAN Server

    func markLANWatchConnected(remoteAddress: String? = nil) {
        lastLANHitAt = Date()
        let host = LocalNetworkInfo.hostOnly(remoteAddress ?? "")
        let isLoopback = host.isEmpty
            || host == "127.0.0.1"
            || host == "::1"
            || host.hasPrefix("127.")
            || host == "localhost"

        if let remoteAddress, !remoteAddress.isEmpty {
            lastLANClientAddress = remoteAddress
        }

        // Self-test (localhost) must not count as "iPhone connected".
        guard !isLoopback else { return }

        lastRemoteLANHitAt = Date()
        isLANWatchConnected = true
        lanResetTimer?.invalidate()
        lanResetTimer = Timer.scheduledTimer(withTimeInterval: 8.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.isLANWatchConnected = false
            }
        }
    }

    private func startLANServer() {
        guard lanServer == nil else { return }

        let webServer = ReadiumGCDWebServer()
        let deviceName = UIDevice.current.name.replacingOccurrences(of: " ", with: "-")
        let bonjourName = "PagePilot-iPad-\(deviceName)"

        // GET /status
        webServer.addHandler(
            forMethod: "GET",
            path: "/status",
            request: ReadiumGCDWebServerRequest.self,
            asyncProcessBlock: { request, completionBlock in
                let remote = request.remoteAddressString
                DispatchQueue.main.async {
                    let title = WatchPageTurnService.shared.currentBookTitle
                    let progress = WatchPageTurnService.shared.currentBookProgress
                    let sensitivity = WatchPageTurnSettings().crownSensitivity
                    WatchPageTurnService.shared.markLANWatchConnected(remoteAddress: remote)

                    let responseDict: [String: Any] = [
                        "status": "ok",
                        "ok": true,
                        "target": "ipad",
                        "readerReady": WatchReaderAvailabilityPolicy.isReady(
                            hasNavigator: WatchPageTurnService.shared.activeNavigator != nil,
                            applicationIsActive: UIApplication.shared.applicationState == .active
                        ),
                        "bookTitle": title,
                        "bookProgress": progress,
                        "crownSensitivity": sensitivity
                    ]

                    completionBlock(WatchPageTurnService.shared.jsonResponse(responseDict))
                }
            }
        )

        // POST /command
        webServer.addHandler(
            forMethod: "POST",
            path: "/command",
            request: ReadiumGCDWebServerDataRequest.self,
            asyncProcessBlock: { request, completionBlock in
                let json = (request as? ReadiumGCDWebServerDataRequest)?.jsonObject as? [String: Any]
                let action = json?["action"] as? String
                let requestID = json?["requestId"] as? String
                let remote = request.remoteAddressString

                Task { @MainActor in
                    WatchPageTurnService.shared.markLANWatchConnected(remoteAddress: remote)

                    guard let navigator = WatchPageTurnService.shared.activeNavigator,
                          WatchReaderAvailabilityPolicy.isReady(
                              hasNavigator: true,
                              applicationIsActive: UIApplication.shared.applicationState == .active
                          ) else {
                        completionBlock(WatchPageTurnService.shared.jsonResponse(
                            WatchPageTurnService.shared.errorPayload(
                                route: WatchPageTurnRoute.direct,
                                code: WatchPageTurnErrorCode.navigatorNotReady,
                                message: "reader is not ready"
                            ),
                            statusCode: 409
                        ))
                        return
                    }

                    guard let command = action.flatMap(PageCommand.init(rawValue:)) else {
                        completionBlock(WatchPageTurnService.shared.jsonResponse(
                            WatchPageTurnService.shared.errorPayload(
                                route: WatchPageTurnRoute.direct,
                                code: WatchPageTurnErrorCode.invalidCommand,
                                message: "invalid page command"
                            ),
                            statusCode: 409
                        ))
                        return
                    }

                    guard WatchPageTurnService.shared.shouldProcessLANCommand(requestID: requestID) else {
                        completionBlock(WatchPageTurnService.shared.jsonResponse([
                            "status": "ok",
                            "ok": true,
                            "target": "ipad",
                            "route": WatchPageTurnRoute.direct,
                            "readerReady": true,
                            "pageDirection": command.rawValue,
                            "didTurnPage": false,
                            "duplicate": true
                        ]))
                        return
                    }

                    guard !WatchPageTurnService.shared.isPageTurnSuppressed else {
                        completionBlock(WatchPageTurnService.shared.jsonResponse([
                            "status": "ok",
                            "ok": true,
                            "target": "ipad",
                            "route": WatchPageTurnRoute.direct,
                            "readerReady": true,
                            "pageDirection": command.rawValue,
                            "didTurnPage": false
                        ]))
                        return
                    }

                    let settings = WatchPageTurnSettings()

                    let succeeded: Bool
                    switch command {
                    case .next:
                        succeeded = await navigator.goForward(options: NavigatorGoOptions(animated: false))
                    case .prev:
                        succeeded = await navigator.goBackward(options: NavigatorGoOptions(animated: false))
                    }

                    if succeeded {
                        ReviewPromptManager.shared.recordWatchPageTurn()
                        NotificationCenter.default.post(name: .watchPageTurnDidSucceed, object: nil)
                    }

                    completionBlock(WatchPageTurnService.shared.jsonResponse([
                        "status": "ok",
                        "ok": true,
                        "target": "ipad",
                        "route": WatchPageTurnRoute.direct,
                        "readerReady": true,
                        "bookTitle": WatchPageTurnService.shared.currentBookTitle,
                        "bookProgress": navigator.currentLocation?.locations.totalProgression ?? 0.0,
                        "crownSensitivity": settings.crownSensitivity,
                        "pageDirection": command.rawValue,
                        "didTurnPage": succeeded
                    ]))
                }
            }
        )

        do {
            try webServer.start(options: [
                ReadiumGCDWebServerOption_Port: preferredLANPort,
                ReadiumGCDWebServerOption_BonjourName: bonjourName,
                ReadiumGCDWebServerOption_BonjourType: "_pagepilot._tcp",
                ReadiumGCDWebServerOption_AutomaticallySuspendInBackground: false
            ])
            applyLANServerState(webServer, bonjourName: bonjourName)
            print("WatchPageTurnService: LAN Server started. port=\(webServer.port) bonjour=\(bonjourName)")
        } catch {
            do {
                try webServer.start(options: [
                    ReadiumGCDWebServerOption_Port: 0,
                    ReadiumGCDWebServerOption_BonjourName: bonjourName,
                    ReadiumGCDWebServerOption_BonjourType: "_pagepilot._tcp",
                    ReadiumGCDWebServerOption_AutomaticallySuspendInBackground: false
                ])
                applyLANServerState(webServer, bonjourName: bonjourName)
                print("WatchPageTurnService: LAN Server started on fallback port. port=\(webServer.port) bonjour=\(bonjourName)")
            } catch {
                lanServerRunning = false
                lanServerPort = 0
                lanBonjourName = ""
                print("WatchPageTurnService: Failed to start LAN Server: \(error)")
            }
        }
    }

    private func applyLANServerState(_ webServer: ReadiumGCDWebServer, bonjourName: String) {
        lanServer = webServer
        lanServerRunning = true
        lanServerPort = webServer.port
        lanBonjourName = bonjourName
    }

    private func stopLANServer() {
        lanServer?.stop()
        lanServer = nil
        lanServerRunning = false
        lanServerPort = 0
        lanBonjourName = ""
        isLANWatchConnected = false
        lanResetTimer?.invalidate()
        lanResetTimer = nil
        print("WatchPageTurnService: LAN Server stopped")
    }
}

extension WatchPageTurnService: WCSessionDelegate {
    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isWatchConnected = activationState == .activated
        }
        if activationState == .activated, UIDevice.current.userInterfaceIdiom == .phone {
            WatchPageTurnSettings().syncToWatch()
            if ProPurchaseManager.shared.hasProAccess {
                PagePilotLANBrowser.shared.warmUp()
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = false
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = false
        }
        WCSession.default.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isWatchConnected = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleMessage(message, replyHandler: nil)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleMessage(message, replyHandler: replyHandler)
    }

    private func handleMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        // WCSession delivers on a background queue; hop to main for navigator / Pro state.
        DispatchQueue.main.async {
            self.handleMessageOnMain(message, replyHandler: replyHandler)
        }
    }

    private func handleMessageOnMain(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        guard let action = message["action"] as? String else {
            replyHandler?(["status": "ignored", "reason": "invalid message"])
            return
        }

        let targetRawValue = message["target"] as? String
        let target = targetRawValue.flatMap(WatchPageTurnSettings.ControlTarget.init(rawValue:))
            ?? .iPhone

        switch action {
        case "status":
            switch target {
            case .iPad where UIDevice.current.userInterfaceIdiom == .phone:
                guard ProPurchaseManager.shared.hasProAccess else {
                    replyHandler?(errorPayload(
                        route: WatchPageTurnRoute.iPhoneRelay,
                        code: WatchPageTurnErrorCode.proRequired,
                        message: "pro is required for iPad page turn"
                    ))
                    return
                }
                PagePilotLANBrowser.shared.warmUp()
                relayStatusToLAN(replyHandler: replyHandler)
            case .iPhone where UIDevice.current.userInterfaceIdiom == .phone:
                replyHandler?(localStatusPayload(route: WatchPageTurnRoute.direct))
            case .iPad where UIDevice.current.userInterfaceIdiom == .pad:
                // Watch is always paired to iPhone, but keep this path for completeness.
                replyHandler?(localStatusPayload(route: WatchPageTurnRoute.direct))
            default:
                replyHandler?(["status": "ignored", "reason": "unsupported target"])
            }

        case "turnPage":
            guard let directionString = message["direction"] as? String,
                  let command = PageCommand(rawValue: directionString)
            else {
                replyHandler?(["status": "ignored", "reason": "invalid page command"])
                return
            }
            let commandID = message["commandId"] as? String

            switch target {
            case .iPad where UIDevice.current.userInterfaceIdiom == .phone:
                guard ProPurchaseManager.shared.hasProAccess else {
                    replyHandler?(errorPayload(
                        route: WatchPageTurnRoute.iPhoneRelay,
                        code: WatchPageTurnErrorCode.proRequired,
                        message: "pro is required for iPad page turn"
                    ))
                    return
                }
                PagePilotLANBrowser.shared.warmUp()
                relayCommandToLAN(command, requestID: commandID, replyHandler: replyHandler)
            case .iPhone where UIDevice.current.userInterfaceIdiom == .phone:
                guard isReaderReady else {
                    replyHandler?(errorPayload(
                        route: WatchPageTurnRoute.direct,
                        code: WatchPageTurnErrorCode.navigatorNotReady,
                        message: "reader is not ready"
                    ))
                    return
                }
                handleCommand(command, completion: replyHandler)
            case .iPad where UIDevice.current.userInterfaceIdiom == .pad:
                // LAN path is primary; WCSession on iPad is rare. Do not require Pro here —
                // Pro is enforced on the iPhone relay entry point.
                guard isReaderReady else {
                    replyHandler?(errorPayload(
                        route: WatchPageTurnRoute.direct,
                        code: WatchPageTurnErrorCode.navigatorNotReady,
                        message: "reader is not ready"
                    ))
                    return
                }
                handleCommand(command, completion: replyHandler)
            default:
                replyHandler?(["status": "ignored", "reason": "unsupported target"])
            }

        default:
            replyHandler?(["status": "ignored", "reason": "unknown action"])
        }
    }
}

extension Notification.Name {
    static let watchPageTurnDidSucceed = Notification.Name("watchPageTurnDidSucceed")
}
