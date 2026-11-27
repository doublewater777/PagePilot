//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Foundation
import ReadiumShared
import ReadiumStreamer
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Base module delegate, that sub-modules' delegate can extend.
/// Provides basic shared functionalities.
protocol ModuleDelegate: AnyObject {
    func presentAlert(_ title: String, message: String, from viewController: UIViewController)
    func presentError<T: UserErrorConvertible>(_ error: T, from viewController: UIViewController)
}

/// Main application module, it:
/// - owns the sub-modules (library, reader, home/desk, journal)
/// - orchestrates the communication between its sub-modules, through the modules' delegates.
final class AppModule {
    static weak var shared: AppModule?

    // App modules
    var library: LibraryModuleAPI!
    var reader: ReaderModuleAPI!
    var home: HomeModuleAPI!

    /// Root navigation controller for the unified Journal ("印记") tab.
    private(set) lazy var journalRootViewController: UINavigationController = {
        let hostingController = UIHostingController(rootView: JournalView())
        hostingController.view.backgroundColor = AppColors.uiBackground
        let nav = JournalNavigationController(rootViewController: hostingController)
        nav.setNavigationBarHidden(true, animated: false)
        nav.view.backgroundColor = AppColors.uiBackground
        return nav
    }()

    /// Pending locator to navigate to when opening a book (from Journal / MyNotes, etc.)
    var pendingNavigationTarget: (bookId: Book.Id, locator: Locator)?

    weak var tabBarController: UITabBarController?

    let readium: Readium
    let db: Database
    let cloudSync: CloudSyncService

    let books: BookRepository
    let readingSessions: ReadingSessionRepository
    let bookmarkRepository: BookmarkRepository
    let highlightRepository: HighlightRepository
    let opdsFeeds: OPDSFeedRepository

    fileprivate lazy var documentPickerDelegate = DocumentPickerDelegate(module: self)

    init() throws {
        StartupProfiler.shared.record("AppModule Init Start")

        let file = Paths.library.appendingPath("database.db", isDirectory: false)
        StartupProfiler.shared.record("AppModule: Initializing SQLite Database Queue")
        db = try Database(file: file.url)
        cloudSync = CloudSyncService(db: db)
        print("Created database at \(file.path)")

        let bookmarks = BookmarkRepository(db: db)
        let highlights = HighlightRepository(db: db)
        bookmarkRepository = bookmarks
        highlightRepository = highlights

        StartupProfiler.shared.record("AppModule: Initializing Readium Opener & Server")
        readium = Readium()
        books = BookRepository(db: db)
        readingSessions = ReadingSessionRepository(db: db)
        opdsFeeds = OPDSFeedRepository(db: db)

        StartupProfiler.shared.record("AppModule: Initializing Submodules (Library, Reader, Home)")
        library = LibraryModule(
            delegate: self,
            books: books,
            opdsFeeds: opdsFeeds,
            readium: readium
        )

        reader = ReaderModule(
            delegate: self,
            books: books,
            bookmarks: bookmarks,
            highlights: highlights,
            readium: readium
        )

        home = HomeModule(
            delegate: self,
            books: books
        )

        // Set Readium 2's logging minimum level.
        #if DEBUG
        ReadiumEnableLog(withMinimumSeverityLevel: .debug)
        #endif

        Self.shared = self

        // Do not let CloudKit act on a stale cached Pro flag during cold launch.
        // Verify StoreKit first, then let CloudSyncService apply its normal
        // preference + entitlement gate before creating/starting CKSyncEngine.
        Task { [cloudSync] in
            await ProPurchaseManager.shared.verifyCurrentEntitlements()
            await cloudSync.start()
        }

        StartupProfiler.shared.record("AppModule Init End")

        // NOTE: Orphaned-file cleanup deliberately does NOT run at launch.
        // Cold-starting from Files/Share runs an import concurrently with
        // launch; a cleanup racing it deleted freshly imported publications
        // from Documents/ before their database row existed. Cleanup now runs
        // on `applicationDidEnterBackground` (see AppDelegate).
    }

    /// Presents Settings (`MeView`) as a clean modal drawer from any screen or `⌘,`.
    @MainActor
    func presentSettings(from presenter: UIViewController? = nil) {
        let host = presenter ?? topMostPresenter()
        guard let host else { return }

        weak var presentedSheet: UIViewController?
        let settingsRoot = NavigationView {
            MeView()
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        SheetCloseButton {
                            presentedSheet?.dismiss(animated: true)
                        }
                    }
                }
        }
        .navigationViewStyle(.stack)

        let controller = UIHostingController(rootView: settingsRoot)
        let isRegular = host.traitCollection.horizontalSizeClass == .regular || UIDevice.current.userInterfaceIdiom == .pad
        controller.modalPresentationStyle = isRegular ? .formSheet : .pageSheet
        if isRegular {
            controller.preferredContentSize = CGSize(width: 580, height: 680)
        } else if let sheet = controller.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        presentedSheet = controller
        PostHogAnalytics.shared.screen("me")
        host.present(controller, animated: true)
    }

    /// Opens a book in the Reader, optionally navigating to a specific locator.
    @MainActor
    func openBook(_ book: Book, locator: Locator? = nil, microReadingMinutes: Int? = nil) {
        guard let bookId = book.id else { return }
        if let locator {
            pendingNavigationTarget = (bookId, locator)
        }
        Task { @MainActor in
            let nav = preferredReaderNavigationController()
            if nav === home.rootViewController {
                tabBarController?.selectedIndex = 0
            }
            nav.popToRootViewController(animated: false)

            do {
                guard let pub = try await library.openBook(book, sender: nav) else { return }
                if let microReadingMinutes {
                    MicroReadingLaunchStore.prepare(bookId: bookId, minutes: microReadingMinutes)
                }
                reader.presentPublication(publication: pub, book: book, in: nav)
            } catch {
                presentError(UserError(error), from: nav)
            }
        }
    }

    /// Optional Scheme-B cold-launch helper: immediately resumes the user's last-read book.
    @MainActor
    func autoOpenLastReadBookIfAvailable() {
        Task { @MainActor in
            guard let all = try? await books.allOnce(),
                  let selected = ContinueReadingSelector.select(from: all, lastReadIds: LastReadBooks.orderedIds)
            else {
                return
            }
            openBook(selected)
        }
    }

    @MainActor
    private func preferredReaderNavigationController() -> UINavigationController {
        home.rootViewController
    }

    @MainActor
    private func topMostPresenter() -> UIViewController? {
        var top: UIViewController? = tabBarController ?? home.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }

    @MainActor
    fileprivate func presentBookLimitPaywall(from vc: UIViewController) {
        let alert = UIAlertController(
            title: NSLocalizedString("library_book_limit_title", comment: ""),
            message: String(format: NSLocalizedString("library_book_limit_message", comment: ""), ProPurchaseManager.freeBookLimit),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel_button", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("library_book_limit_upgrade", comment: ""), style: .default) { _ in
            Analytics.shared.log(.paywallViewed(source: "library_book_limit"))
            let paywall = UIHostingController(rootView: PaywallView())
            paywall.modalPresentationStyle = .formSheet
            vc.present(paywall, animated: true)
        })
        vc.present(alert, animated: true)
    }
}

fileprivate final class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {
    weak var module: AppModule?

    init(module: AppModule) {
        self.module = module
        super.init()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !urls.isEmpty, let module else { return }
        let vc = module.home.rootViewController

        Task {
            do {
                try await module.library.service.importPublications(from: urls, sender: vc)
                PostHogAnalytics.shared.capture("book_imported", properties: [
                    "count": urls.count,
                    "source": "file_picker"
                ])
            } catch LibraryError.bookLimitReached {
                await MainActor.run {
                    module.presentBookLimitPaywall(from: vc)
                }
            } catch {
                module.presentError(UserError(error), from: vc)
            }
        }
    }
}

extension AppModule: ModuleDelegate {
    func presentAlert(_ title: String, message: String, from viewController: UIViewController) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            let dismissButton = UIAlertAction(title: NSLocalizedString("ok_button", comment: "Alert button"), style: .cancel)
            alert.addAction(dismissButton)
            viewController.present(alert, animated: true)
        }
    }

    func presentError<T: UserErrorConvertible>(_ error: T, from viewController: UIViewController) {
        viewController.alert(error)
    }
}

extension AppModule: LibraryModuleDelegate {
    func libraryDidSelectPublication(_ publication: Publication, book: Book) {
        reader.presentPublication(publication: publication, book: book, in: library.rootViewController)
    }
}

extension AppModule: ReaderModuleDelegate {}

extension AppModule: HomeModuleDelegate {
    func homeDidSelectContinueReading(bookId: Book.Id) {
        openBookFromHome(bookId: bookId)
    }

    func homeDidSelectMicroReading(bookId: Book.Id, minutes: Int) {
        openBookFromHome(bookId: bookId, microReadingMinutes: minutes)
    }

    func homeDidSelectGoToLibrary() {
        homeDidRequestImportLocalFiles()
    }

    func homeDidRequestImportLocalFiles() {
        DispatchQueue.main.async {
            var types = DocumentTypes.main.supportedUTTypes
            types.append(UTType.text)
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types)
            picker.allowsMultipleSelection = true
            picker.delegate = self.documentPickerDelegate
            self.home.rootViewController.present(picker, animated: true)
        }
    }

    func homeDidRequestWiFiTransfer() {
        DispatchQueue.main.async {
            PostHogAnalytics.shared.screen("wifi_transfer")
            let wifiView = WiFiTransferView(library: self.library.service)
            let controller = UIHostingController(rootView: wifiView)
            controller.modalPresentationStyle = .formSheet
            self.home.rootViewController.present(controller, animated: true)
        }
    }

    func homeDidRequestDeviceTransfer(books: [Book]) {
        DispatchQueue.main.async {
            PostHogAnalytics.shared.screen("device_transfer")
            let transferView = DeviceTransferView(books: books, library: self.library.service)
            let controller = UIHostingController(rootView: transferView)
            controller.modalPresentationStyle = .formSheet
            self.home.rootViewController.present(controller, animated: true)
        }
    }

    func homeDidRequestOPDSFeeds() {
        DispatchQueue.main.async {
            PostHogAnalytics.shared.screen("opds_catalog")
            let vc = OPDSFeedListViewController(feeds: self.opdsFeeds, library: self.library.service)
            let nav = UINavigationController(rootViewController: vc)
            nav.modalPresentationStyle = .formSheet
            self.home.rootViewController.present(nav, animated: true)
        }
    }

    func homeDidRequestBookDetails(book: Book) {
        Task { @MainActor in
            let nav = home.rootViewController
            do {
                guard let publication = try await library.openBook(book, sender: nav) else { return }
                weak var presentedSheet: UIViewController?
                let metadataView = NavigationStack {
                    PublicationMetadataView(
                        publication: publication,
                        book: book,
                        onOpen: { [weak self] in
                            presentedSheet?.dismiss(animated: true) {
                                self?.reader.presentPublication(publication: publication, book: book, in: nav)
                            }
                        }
                    )
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            SheetCloseButton {
                                presentedSheet?.dismiss(animated: true)
                            }
                        }
                    }
                }
                let controller = UIHostingController(rootView: metadataView)
                controller.modalPresentationStyle = .formSheet
                presentedSheet = controller
                nav.present(controller, animated: true)
            } catch {
                presentError(UserError(error), from: nav)
            }
        }
    }

    func homeDidRequestDeleteBooks(_ books: [Book]) async {
        for book in books {
            do {
                try await library.service.remove(book)
            } catch {
                print("AppModule: failed to delete book \(book.title): \(error)")
            }
        }
    }

    func homeDidRequestSettings() {
        Task { @MainActor in
            presentSettings(from: home.rootViewController)
        }
    }

    func homeDidRequestJournal() {
        Task { @MainActor in
            tabBarController?.selectedIndex = 1
        }
    }

    func homeDidRequestWatchSettings() {
        Task { @MainActor in
            weak var presentedSheet: UIViewController?
            let root: AnyView
            if UIDevice.current.userInterfaceIdiom == .pad {
                root = AnyView(
                    NavigationStack {
                        IPadWatchConnectionView()
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    SheetCloseButton { presentedSheet?.dismiss(animated: true) }
                                }
                            }
                    }
                )
            } else {
                root = AnyView(
                    NavigationStack {
                        WatchSettingsView()
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    SheetCloseButton { presentedSheet?.dismiss(animated: true) }
                                }
                            }
                    }
                )
            }
            let controller = UIHostingController(rootView: root)
            controller.modalPresentationStyle = .formSheet
            presentedSheet = controller
            home.rootViewController.present(controller, animated: true)
        }
    }

    private func openBookFromHome(bookId: Book.Id, microReadingMinutes: Int? = nil) {
        Task { @MainActor in
            let nav = home.rootViewController
            do {
                guard let book = try await books.get(bookId) else { return }
                guard let pub = try await library.openBook(book, sender: nav) else { return }
                if let microReadingMinutes {
                    MicroReadingLaunchStore.prepare(
                        bookId: bookId,
                        minutes: microReadingMinutes
                    )
                }
                reader.presentPublication(publication: pub, book: book, in: nav)
            } catch {
                presentError(UserError(error), from: nav)
            }
        }
    }
}
