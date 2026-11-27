//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Foundation
import ReadiumShared
import SwiftUI
import UIKit

protocol HomeModuleAPI {
    var delegate: HomeModuleDelegate? { get }
    var rootViewController: UINavigationController { get }
}

protocol HomeModuleDelegate: ModuleDelegate {
    /// Called when user wants to continue reading or open a book.
    func homeDidSelectContinueReading(bookId: Book.Id)

    /// Called when user starts a time-boxed reading session.
    func homeDidSelectMicroReading(bookId: Book.Id, minutes: Int)

    /// Called when user wants to go to library / import a book.
    func homeDidSelectGoToLibrary()

    /// Opens the system document picker to import local EPUB/PDF/TXT/Markdown books.
    func homeDidRequestImportLocalFiles()

    /// Presents Wi-Fi transfer sheet.
    func homeDidRequestWiFiTransfer()

    /// Presents device-to-device transfer sheet.
    func homeDidRequestDeviceTransfer(books: [Book])

    /// Presents OPDS catalog browser sheet.
    func homeDidRequestOPDSFeeds()

    /// Presents publication metadata details sheet for a book.
    func homeDidRequestBookDetails(book: Book)

    /// Deletes one or more books from the library.
    func homeDidRequestDeleteBooks(_ books: [Book]) async

    /// Opens the Settings modal drawer.
    func homeDidRequestSettings()

    /// Switches to the Journal tab (reading rhythm & quote box).
    func homeDidRequestJournal()

    /// Opens Apple Watch / iPad Watch connection settings sheet.
    func homeDidRequestWatchSettings()
}

private final class HomeNavigationController: UINavigationController {
    private var didBecomeActiveObserver: NSObjectProtocol?

    override func viewDidLoad() {
        super.viewDidLoad()

        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.enforceHiddenNavigationBar()
        }
        enforceHiddenNavigationBar()
    }

    deinit {
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        enforceHiddenNavigationBar()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        enforceHiddenNavigationBar()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        enforceHiddenNavigationBar()
    }

    private func enforceHiddenNavigationBar() {
        // Desk owns the hidden-navigation-bar policy only while its root view
        // controller is visible. Pushed screens such as Reader manage their own
        // navigation bar visibility.
        guard topViewController === viewControllers.first else { return }
        guard !isNavigationBarHidden else { return }
        setNavigationBarHidden(true, animated: false)
    }
}

final class HomeModule: HomeModuleAPI {
    weak var delegate: HomeModuleDelegate?

    private let books: BookRepository

    init(delegate: HomeModuleDelegate?, books: BookRepository) {
        self.delegate = delegate
        self.books = books
    }

    private(set) lazy var rootViewController: UINavigationController = {
        let viewModel = HomeViewModel(books: books)
        let homeView = HomeRootView(
            viewModel: viewModel,
            delegate: delegate
        )
        let hostingController = UIHostingController(rootView: homeView)
        hostingController.view.backgroundColor = AppColors.uiBackground
        let navigationController = HomeNavigationController(rootViewController: hostingController)
        navigationController.setNavigationBarHidden(true, animated: false)
        navigationController.view.backgroundColor = hostingController.view.backgroundColor
        return navigationController
    }()
}
