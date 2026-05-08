//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import ReadiumShared
import SwiftUI
import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    private let hasSeenOnboardingKey = "hasSeenOnboarding"
    private var app: AppModule!
    private var subscriptions = Set<AnyCancellable>()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        app = try! AppModule()

        func makeItem(title: String, systemImage: String) -> UITabBarItem {
            UITabBarItem(
                title: NSLocalizedString(title, comment: "Tab bar item"),
                image: UIImage(systemName: systemImage),
                tag: 0
            )
        }

        // Home
        let homeViewController = app.home.rootViewController
        homeViewController.tabBarItem = makeItem(title: "home_tab", systemImage: "house")

        // Library
        let libraryViewController = app.library.rootViewController
        libraryViewController.tabBarItem = makeItem(title: "bookshelf_tab", systemImage: "books.vertical")

        // OPDS Feeds
        let opdsViewController = app.opds.rootViewController
        opdsViewController.tabBarItem = makeItem(title: "catalogs_tab", systemImage: "list.bullet")

        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [
            homeViewController,
            libraryViewController,
            opdsViewController,
        ]

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = .systemBackground
        tabBarController.tabBar.standardAppearance = tabBarAppearance
        tabBarController.tabBar.scrollEdgeAppearance = tabBarAppearance

        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = .systemBackground
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = tabBarController
        window?.makeKeyAndVisible()

        app.tabBarController = tabBarController
        presentOnboardingIfNeeded(from: tabBarController)

        return true
    }

    func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        guard let url = url.anyURL.absoluteURL, let vc = window?.rootViewController else {
            return false
        }

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

        return true
    }

    private func presentOnboardingIfNeeded(from presentingViewController: UIViewController) {
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

            let onboardingView = OnboardingView {
                UserDefaults.standard.set(true, forKey: self.hasSeenOnboardingKey)
                presentingViewController.dismiss(animated: true)
            }

            let hostingController = UIHostingController(rootView: onboardingView)
            hostingController.modalPresentationStyle = .fullScreen
            presentingViewController.present(hostingController, animated: true)
        }
    }
}

private struct OnboardingView: View {
    private let onFinish: () -> Void

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
    ]

    init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(NSLocalizedString("onboarding_later_button", comment: "Dismiss onboarding button"), action: onFinish)
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

            Button(action: advance) {
                Text(selectedPage == pages.count - 1
                     ? NSLocalizedString("onboarding_start_button", comment: "Start using app button")
                     : NSLocalizedString("onboarding_continue_button", comment: "Next onboarding page button"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
            .accessibilityIdentifier("onboarding_primary_button")
        }
        .background(Color(.systemGroupedBackground))
    }

    private func advance() {
        guard selectedPage < pages.count - 1 else {
            onFinish()
            return
        }

        withAnimation(.easeInOut) {
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
