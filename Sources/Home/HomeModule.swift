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
    /// Called when user wants to continue reading a book
    func homeDidSelectContinueReading(bookId: Book.Id)

    /// Called when user wants to go to library tab
    func homeDidSelectGoToLibrary()
}

final class HomeModule: HomeModuleAPI {
    weak var delegate: HomeModuleDelegate?

    private let books: BookRepository
    let readingTimeManager: ReadingTimeManager

    init(delegate: HomeModuleDelegate?, books: BookRepository) {
        self.delegate = delegate
        self.books = books
        self.readingTimeManager = ReadingTimeManager()
    }

    private(set) lazy var rootViewController: UINavigationController = {
        let homeView = HomeView(
            viewModel: HomeViewModel(books: books, readingTimeManager: readingTimeManager),
            delegate: delegate
        )
        let hostingController = UIHostingController(rootView: homeView)
        let navigationController = UINavigationController(rootViewController: hostingController)
        navigationController.isNavigationBarHidden = true
        return navigationController
    }()
}
