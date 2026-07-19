//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import AVFoundation
import Combine
import OSLog
import ReadiumShared
import SwiftUI
import UIKit

private enum MainTabIdentifier {
    static let home = "home"
    static let library = "library"
    static let me = "me"
}

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    let hasSeenOnboardingKey = "hasSeenOnboarding"
    private(set) var app: AppModule!
    private var launchError: Error?
    private var subscriptions = Set<AnyCancellable>()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        StartupProfiler.shared.record("AppDelegate didFinishLaunching Start")
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ResetOnboarding") {
            UserDefaults.standard.removeObject(forKey: hasSeenOnboardingKey)
            OnboardingProgressStore().reset()
        }
        #endif
        AppAppearancePreferences.configureLocalization()
        configureAudioSession()
        WatchPageTurnSettings.migrateDefaultTargetIfNeeded()
        do {
            app = try AppModule()
            observeAppearancePreferences()
            ReviewPromptManager.shared.recordAppLaunch()
        } catch {
            launchError = error
            print("Failed to initialize AppModule: \(error)")
        }

        // Activate Watch connectivity early so the session state is always
        // current, even before the reader is opened.
        WatchPageTurnService.shared.activate()

        // Verify Pro entitlements on launch.
        Task {
            await ProPurchaseManager.shared.verifyCurrentEntitlements()
        }

        // Re-assert the reading-reminder schedule (cleared by reinstall / OS).
        Task {
            await ReadingReminderScheduler.shared.reschedule()
        }

        StartupProfiler.shared.record("AppDelegate didFinishLaunching End")
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    /// Configures the shared `AVAudioSession` so that audio features (audiobook
    /// playback and text-to-speech) keep playing when the app is sent to the
    /// background or the device is locked.
    ///
    /// Without this, the default `soloAmbient` category silences audio as soon
    /// as the app is backgrounded, which makes the `audio` UIBackgroundMode
    /// declared in Info.plist appear non-functional during App Review.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio
            )
        } catch {
            print("Failed to configure AVAudioSession: \(error)")
        }
    }

    func makeRootViewController() -> UIViewController {
        guard app != nil else {
            return makeLaunchFailureViewController()
        }

        let homeViewController = app.home.rootViewController
        let libraryViewController = app.library.rootViewController

        let meView = NavigationView { MeView() }
            .navigationViewStyle(.stack)
        let meViewController = UIHostingController(rootView: meView)

        let tabBarController: UITabBarController
        if #available(iOS 18.0, *) {
            tabBarController = makeModernTabBarController(
                homeViewController: homeViewController,
                libraryViewController: libraryViewController,
                meViewController: meViewController
            )
        } else {
            tabBarController = makeLegacyTabBarController(
                homeViewController: homeViewController,
                libraryViewController: libraryViewController,
                meViewController: meViewController
            )
        }

        configureTabBarAppearance(for: tabBarController)
        app.tabBarController = tabBarController
        return tabBarController
    }

    @available(iOS 18.0, *)
    private func makeModernTabBarController(
        homeViewController: UIViewController,
        libraryViewController: UIViewController,
        meViewController: UIViewController
    ) -> UITabBarController {
        func makeTab(
            titleKey: String,
            systemImage: String,
            identifier: String,
            viewController: UIViewController
        ) -> UITab {
            UITab(
                title: NSLocalizedString(titleKey, comment: "Tab bar item"),
                image: UIImage(systemName: systemImage),
                identifier: identifier,
                viewControllerProvider: { _ in viewController }
            )
        }

        let tabBarController = UITabBarController(tabs: [
            makeTab(titleKey: "home_tab", systemImage: "house", identifier: MainTabIdentifier.home, viewController: homeViewController),
            makeTab(titleKey: "bookshelf_tab", systemImage: "books.vertical", identifier: MainTabIdentifier.library, viewController: libraryViewController),
            makeTab(titleKey: "me_tab", systemImage: "person.crop.circle", identifier: MainTabIdentifier.me, viewController: meViewController),
        ])
        tabBarController.customizationIdentifier = "com.panyang.PagePilot.main"

        if UIDevice.current.userInterfaceIdiom == .pad {
            tabBarController.mode = .tabSidebar
            tabBarController.sidebar.preferredLayout = .tile
        }

        return tabBarController
    }

    private func makeLegacyTabBarController(
        homeViewController: UIViewController,
        libraryViewController: UIViewController,
        meViewController: UIViewController
    ) -> UITabBarController {
        func makeItem(title: String, systemImage: String) -> UITabBarItem {
            UITabBarItem(
                title: NSLocalizedString(title, comment: "Tab bar item"),
                image: UIImage(systemName: systemImage),
                tag: 0
            )
        }

        homeViewController.tabBarItem = makeItem(title: "home_tab", systemImage: "house")
        libraryViewController.tabBarItem = makeItem(title: "bookshelf_tab", systemImage: "books.vertical")
        meViewController.tabBarItem = makeItem(title: "me_tab", systemImage: "person.crop.circle")

        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [
            homeViewController,
            libraryViewController,
            meViewController,
        ]
        return tabBarController
    }

    private func configureTabBarAppearance(for tabBarController: UITabBarController) {
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = .systemBackground
        tabBarController.tabBar.standardAppearance = tabBarAppearance
        tabBarController.tabBar.scrollEdgeAppearance = tabBarAppearance

        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = .systemGroupedBackground
        navBarAppearance.shadowColor = .clear
        navBarAppearance.shadowImage = UIImage()
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
    }

    private func makeLaunchFailureViewController() -> UIViewController {
        let message = launchError.map { UserError($0).message } ?? "error".localized
        let view = VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.red)
            Text("PagePilot")
                .font(.title2.bold())
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)

        return UIHostingController(rootView: view)
    }

    func updateTabBarLocalization() {
        guard app != nil else { return }
        guard let tabBarController = app.tabBarController else { return }

        if #available(iOS 18.0, *) {
            tabBarController.tab(forIdentifier: MainTabIdentifier.home)?.title =
                NSLocalizedString("home_tab", comment: "Tab bar item")
            tabBarController.tab(forIdentifier: MainTabIdentifier.library)?.title =
                NSLocalizedString("bookshelf_tab", comment: "Tab bar item")
            tabBarController.tab(forIdentifier: MainTabIdentifier.me)?.title =
                NSLocalizedString("me_tab", comment: "Tab bar item")
            return
        }

        guard let tabBarItems = tabBarController.tabBar.items, tabBarItems.count >= 3 else { return }

        tabBarItems[0].title = NSLocalizedString("home_tab", comment: "Tab bar item")
        tabBarItems[1].title = NSLocalizedString("bookshelf_tab", comment: "Tab bar item")
        tabBarItems[2].title = NSLocalizedString("me_tab", comment: "Tab bar item")
    }

    private func observeAppearancePreferences() {
        NotificationCenter.default.publisher(for: AppAppearancePreferences.languageDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateTabBarLocalization()
                self?.updateVisibleLocalization()
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: AppAppearancePreferences.themeDidChange)
            .receive(on: RunLoop.main)
            .sink { _ in
                UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                    .forEach(AppAppearancePreferences.applyTheme(to:))
            }
            .store(in: &subscriptions)
    }

    private func updateVisibleLocalization() {
        guard app != nil else { return }
        app.library.rootViewController.viewControllers
            .compactMap { $0 as? LibraryViewController }
            .forEach { $0.updateLocalizedContent() }
    }

    private let preloadedBooksKey = "preloadedBooksImported"

    /// Imports preloaded sample books from the app bundle on first launch (fire-and-forget).
    func importPreloadedBooks(sender rootVC: UIViewController) {
        Task {
            _ = await importPreloadedBooksIfNeeded(delayNanoseconds: 400_000_000)
        }
    }

    /// Imports preloaded books if needed and returns bookshelf books (for opening a sample).
    @discardableResult
    func importPreloadedBooksIfNeeded(delayNanoseconds: UInt64 = 0) async -> [Book] {
        guard let app else { return [] }

        let log = Logger(subsystem: "com.panyang.PagePilot", category: "PreloadedBooks")

        if UserDefaults.standard.bool(forKey: preloadedBooksKey) {
            log.info("Already imported, loading existing books")
            return (try? await app.books.allOnce()) ?? []
        }

        guard let resourceURL = Bundle.main.resourceURL else {
            log.error("No resource URL")
            return []
        }

        let fileManager = FileManager.default
        var files: [URL] = []

        let preloadedDir = resourceURL.appendingPathComponent("PreloadedBooks")
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: preloadedDir.path, isDirectory: &isDir), isDir.boolValue {
            if let contents = try? fileManager.contentsOfDirectory(at: preloadedDir, includingPropertiesForKeys: nil) {
                files = contents.filter { $0.pathExtension == "epub" }
            }
        }

        if files.isEmpty {
            log.info("PreloadedBooks directory not found or empty. Searching bundle root...")
            if let contents = try? fileManager.contentsOfDirectory(at: resourceURL, includingPropertiesForKeys: nil) {
                files = contents.filter { $0.pathExtension == "epub" && $0.lastPathComponent == "pride_prejudice.epub" }
            }
        }

        if files.isEmpty, let fallbackURL = Bundle.main.url(forResource: "pride_prejudice", withExtension: "epub") {
            log.info("Using Bundle.main.url fallback for pride_prejudice.epub")
            files = [fallbackURL]
        }

        guard !files.isEmpty else {
            log.error("No preloaded epub files found")
            return []
        }

        log.info("Found \(files.count) file(s) to import: \(files.map(\.lastPathComponent).joined(separator: ", "))")

        let libraryService = app.library!
        StartupProfiler.shared.record("importPreloadedBooks Triggered")
        StartupProfiler.shared.record("importPreloadedBooks detached background Task Start")

        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }

        var imported: [Book] = []
        for fileURL in files {
            guard let absoluteURL = fileURL.anyURL.absoluteURL else {
                log.error("Failed to create AbsoluteURL for \(fileURL.lastPathComponent)")
                continue
            }

            log.info("Importing: \(absoluteURL.string)")
            do {
                StartupProfiler.shared.record("Start importing: \(fileURL.lastPathComponent)")
                let book = try await libraryService.importPublication(from: absoluteURL, sender: nil)
                imported.append(book)
                log.info("Imported book: \(book.title)")
                StartupProfiler.shared.record("Finish importing: \(book.title)")
            } catch {
                log.error("Import failed for \(fileURL.lastPathComponent): \(String(describing: error))")
                StartupProfiler.shared.record("Import failed for: \(fileURL.lastPathComponent)")
            }
        }

        UserDefaults.standard.set(true, forKey: preloadedBooksKey)
        log.info("All preloaded books import finished")
        StartupProfiler.shared.record("All preloaded books import finished")
        StartupProfiler.shared.printSummary()

        if imported.isEmpty {
            return (try? await app.books.allOnce()) ?? []
        }
        return imported
    }

    @MainActor
    func openBookAfterOnboarding(_ book: Book, from rootViewController: UIViewController) async {
        guard let app else { return }

        app.tabBarController?.selectedIndex = 1
        let nav = app.library.rootViewController
        nav.popToRootViewController(animated: false)

        do {
            guard let publication = try await app.library.openBook(book, sender: nav) else { return }
            UserDefaults.standard.set(true, forKey: hasSeenOnboardingKey)
            app.reader.presentPublication(publication: publication, book: book, in: nav)
        } catch {
            presentErrorIfPossible(error, from: nav)
        }
    }

    private func presentErrorIfPossible(_ error: Error, from viewController: UIViewController) {
        if let convertible = error as? UserErrorConvertible {
            viewController.alert(convertible)
        } else {
            print(error)
        }
    }

    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard let url = url.anyURL.absoluteURL, let vc = activeRootViewController else {
            return false
        }

        if !UserDefaults.standard.bool(forKey: hasSeenOnboardingKey) {
            NotificationCenter.default.post(name: .onboardingImportURLRequested, object: url.url)
            return true
        }

        importPublication(from: url, sender: vc)
        return true
    }

    func importPublication(from url: AbsoluteURL, sender vc: UIViewController) {
        guard app != nil else { return }

        Task {
            do {
                try await app.library.importPublication(from: url, sender: vc, progress: { _ in })
            } catch {
                guard let error = error as? UserErrorConvertible else {
                    print(error)
                    return
                }
                vc.alert(error)
            }
        }
    }

    private var activeRootViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }

    func presentOnboardingIfNeeded(
        from presentingViewController: UIViewController,
        initialURL: AbsoluteURL? = nil
    ) {
        guard app != nil else { return }

        guard !UserDefaults.standard.bool(forKey: hasSeenOnboardingKey) else {
            return
        }

        DispatchQueue.main.async { [weak self, weak presentingViewController] in
            guard
                let self,
                let presentingViewController,
                presentingViewController.presentedViewController == nil
            else {
                return
            }

            let platform: OnboardingFlow.Platform = UIDevice.current.userInterfaceIdiom == .pad
                ? .iPad
                : .iPhone
            let progressStore = OnboardingProgressStore()
            let flow = progressStore.load(platform: platform)

            let onboardingView = OnboardingView(
                flow: flow,
                importPublication: { [weak self, weak presentingViewController] url in
                    guard let self,
                          let presentingViewController,
                          let absoluteURL = url.anyURL.absoluteURL
                    else {
                        throw LibraryError.importFailed(URLError(.badURL))
                    }
                    let book = try await self.app.library.importPublication(
                        from: absoluteURL,
                        sender: presentingViewController
                    )
                    guard let bookID = book.id?.rawValue else {
                        throw LibraryError.importFailed(URLError(.cannotCreateFile))
                    }
                    // A successfully imported user publication replaces the bundled sample.
                    UserDefaults.standard.set(true, forKey: self.preloadedBooksKey)
                    return OnboardingPublicationPresentation(
                        bookID: bookID,
                        title: book.title,
                        coverURL: book.cover?.url
                    )
                },
                loadSamplePublication: { [weak self] in
                    guard let self else { return nil }
                    let books = await self.importPreloadedBooksIfNeeded()
                    guard let book = books.first, let bookID = book.id?.rawValue else { return nil }
                    return OnboardingPublicationPresentation(
                        bookID: bookID,
                        title: book.title,
                        coverURL: book.cover?.url
                    )
                },
                loadPublication: { [weak self] rawBookID in
                    guard let self,
                          let book = try? await self.app.books.get(Book.Id(rawValue: rawBookID))
                    else {
                        return nil
                    }
                    return OnboardingPublicationPresentation(
                        bookID: rawBookID,
                        title: book.title,
                        coverURL: book.cover?.url
                    )
                },
                onFlowChange: { flow in
                    progressStore.save(flow)
                },
                onOpenPublication: { [weak self, weak presentingViewController] rawBookID, _ in
                    guard let self, let presentingViewController else { return }
                    presentingViewController.dismiss(animated: true) {
                        Task {
                            guard let book = try? await self.app.books.get(Book.Id(rawValue: rawBookID)) else {
                                return
                            }
                            await self.openBookAfterOnboarding(book, from: presentingViewController)
                        }
                    }
                },
                onFinish: { [weak self, weak presentingViewController] in
                    guard let self, let presentingViewController else { return }
                    UserDefaults.standard.set(true, forKey: self.hasSeenOnboardingKey)
                    presentingViewController.dismiss(animated: true)
                },
                initialURL: initialURL?.url
            )

            let hostingController = UIHostingController(rootView: onboardingView)
            hostingController.modalPresentationStyle = .fullScreen
            // Present instantly without animation to prevent main tab bar flickering on cold start.
            presentingViewController.present(hostingController, animated: false)
        }
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private var appDelegate: AppDelegate {
        UIApplication.shared.delegate as! AppDelegate
    }

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        StartupProfiler.shared.record("SceneDelegate willConnectTo Start")
        guard let windowScene = scene as? UIWindowScene else { return }

        let rootViewController = appDelegate.makeRootViewController()
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = rootViewController
        window.makeKeyAndVisible()
        AppAppearancePreferences.applyTheme(to: window)
        self.window = window

        if ProcessInfo.processInfo.arguments.contains("-SelectMeTab")
            || ProcessInfo.processInfo.arguments.contains("-SelectSettingsTab") {
            if let tabBar = rootViewController as? UITabBarController {
                tabBar.selectedIndex = 2
            }
        }

        if ProcessInfo.processInfo.arguments.contains("-SelectLibraryTab") {
            if let tabBar = rootViewController as? UITabBarController {
                tabBar.selectedIndex = 1
            }
        }

        let initialURL = connectionOptions.urlContexts.first?.url.anyURL.absoluteURL
        let hasSeenOnboarding = UserDefaults.standard.bool(forKey: appDelegate.hasSeenOnboardingKey)
        appDelegate.presentOnboardingIfNeeded(
            from: rootViewController,
            initialURL: hasSeenOnboarding ? nil : initialURL
        )
        
        // Performance Optimization: Only import preloaded books if the user has already seen onboarding.
        // For fresh installs, it will be triggered when onboarding gets dismissed to prevent stuttering.
        if UserDefaults.standard.bool(forKey: appDelegate.hasSeenOnboardingKey) {
            appDelegate.importPreloadedBooks(sender: rootViewController)
        } else {
            StartupProfiler.shared.record("First launch: Skipping preloaded books import during onboarding")
        }

        if hasSeenOnboarding, let url = initialURL {
            appDelegate.importPublication(from: url, sender: rootViewController)
        }
        StartupProfiler.shared.record("SceneDelegate willConnectTo End")
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard
            let url = URLContexts.first?.url.anyURL.absoluteURL,
            let rootViewController = window?.rootViewController
        else {
            return
        }

        if UserDefaults.standard.bool(forKey: appDelegate.hasSeenOnboardingKey) {
            appDelegate.importPublication(from: url, sender: rootViewController)
        } else {
            NotificationCenter.default.post(name: .onboardingImportURLRequested, object: url.url)
        }
    }
}


import QuartzCore

final class StartupProfiler {
    static let shared = StartupProfiler()
    
    struct Event: Codable {
        let name: String
        let timestamp: Double
        let relativeTimeMs: Double
    }
    
    private let startTime: Double
    private var events: [Event] = []
    private let queue = DispatchQueue(label: "com.pagepilot.startupprofiler", qos: .utility)
    
    private init() {
        self.startTime = CACurrentMediaTime()
        let startEvent = Event(name: "App Launch Start", timestamp: startTime, relativeTimeMs: 0.0)
        events.append(startEvent)
    }
    
    func record(_ eventName: String) {
        let now = CACurrentMediaTime()
        let elapsed = (now - startTime) * 1000.0
        queue.async {
            let event = Event(name: eventName, timestamp: now, relativeTimeMs: elapsed)
            self.events.append(event)
            self.saveToFile()
        }
    }
    
    func printSummary() {
        queue.async {
            print("=== StartupProfiler Summary ===")
            for event in self.events {
                print(String(format: "[%.3f ms] %@", event.relativeTimeMs, event.name))
            }
            print("===============================")
        }
    }
    
    private func saveToFile() {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        let fileURL = documentsDirectory.appendingPathComponent("startup_performance.json")
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(self.events)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save startup performance json: \(error)")
        }
    }
}
