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

    func presentOnboardingIfNeeded(from presentingViewController: UIViewController) {
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

            let onboardingView = OnboardingView { action in
                UserDefaults.standard.set(true, forKey: self.hasSeenOnboardingKey)
                presentingViewController.dismiss(animated: true) {
                    Task {
                        let books = await self.importPreloadedBooksIfNeeded(delayNanoseconds: 350_000_000)
                        guard action == .openSampleBook else { return }
                        if let book = books.first {
                            await self.openBookAfterOnboarding(book, from: presentingViewController)
                        } else {
                            await MainActor.run {
                                self.app?.tabBarController?.selectedIndex = 1
                            }
                        }
                    }
                }
            }

            let hostingController = UIHostingController(rootView: onboardingView)
            hostingController.modalPresentationStyle = .fullScreen
            // Present instantly without animation to prevent main tab bar flickering on cold start.
            presentingViewController.present(hostingController, animated: false)
        }
    }
}

private enum OnboardingFinishAction {
    case dismissOnly
    case openSampleBook
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

        appDelegate.presentOnboardingIfNeeded(from: rootViewController)
        
        // Performance Optimization: Only import preloaded books if the user has already seen onboarding.
        // For fresh installs, it will be triggered when onboarding gets dismissed to prevent stuttering.
        if UserDefaults.standard.bool(forKey: appDelegate.hasSeenOnboardingKey) {
            appDelegate.importPreloadedBooks(sender: rootViewController)
        } else {
            StartupProfiler.shared.record("First launch: Skipping preloaded books import during onboarding")
        }

        if let urlContext = connectionOptions.urlContexts.first,
           let url = urlContext.url.anyURL.absoluteURL {
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

        appDelegate.importPublication(from: url, sender: rootViewController)
    }
}

private struct OnboardingView: View {
    private let onFinish: (OnboardingFinishAction) -> Void

    @State private var selectedPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            symbolName: "book.closed",
            titleKey: "onboarding_welcome_title",
            messageKey: "onboarding_welcome_message"
        ),
        OnboardingPage(
            symbolName: "square.and.arrow.down",
            titleKey: "onboarding_import_title",
            messageKey: "onboarding_import_message"
        ),
        OnboardingPage(
            symbolName: "applewatch",
            titleKey: "onboarding_watch_title",
            messageKey: "onboarding_watch_message"
        ),
        OnboardingPage(
            symbolName: "ipad.and.iphone",
            titleKey: "onboarding_transfer_title",
            messageKey: "onboarding_transfer_message"
        ),
    ]

    init(onFinish: @escaping (OnboardingFinishAction) -> Void) {
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(NSLocalizedString("onboarding_later_button", comment: "Dismiss onboarding button")) {
                    onFinish(.dismissOnly)
                }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .accessibilityIdentifier("onboarding_later_button")
            }

            TabView(selection: $selectedPage) {
                ForEach(pages.indices, id: \.self) { index in
                    OnboardingPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))

            primaryButton
                .padding(.horizontal, 24)
                .padding(.bottom, 30)
        }
        .background(AppColors.background)
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-AutoDismissOnboarding") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    onFinish(.dismissOnly)
                }
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        Button(action: advance) {
            Text(advanceTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColors.accentBlue)
        .accessibilityIdentifier("onboarding_primary_button")
    }

    private var advanceTitle: String {
        if selectedPage == pages.count - 1 {
            return NSLocalizedString("onboarding_open_sample_button", comment: "")
        }
        return NSLocalizedString("onboarding_continue_button", comment: "")
    }

    private func advance() {
        guard selectedPage < pages.count - 1 else {
            onFinish(.openSampleBook)
            return
        }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            selectedPage += 1
        }
    }
}

private struct OnboardingPage {
    let symbolName: String
    let titleKey: LocalizedStringKey
    let messageKey: LocalizedStringKey
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 44)

            Image(systemName: page.symbolName)
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 112, height: 112)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color(.separator).opacity(0.18), lineWidth: 1)
                }
                .accessibilityHidden(true)

            VStack(spacing: 14) {
                Text(page.titleKey)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.8)

                Text(page.messageKey)
                    .font(.body.weight(.regular))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 34)

            Spacer(minLength: 92)
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
