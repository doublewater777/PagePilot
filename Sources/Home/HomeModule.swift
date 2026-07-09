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

    init(delegate: HomeModuleDelegate?, books: BookRepository) {
        self.delegate = delegate
        self.books = books
    }

    private(set) lazy var rootViewController: UINavigationController = {
        let homeView = HomeView(
            viewModel: HomeViewModel(books: books),
            delegate: delegate
        )
        let hostingController = UIHostingController(rootView: homeView)
        hostingController.view.backgroundColor = UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: 15 / 255, green: 16 / 255, blue: 19 / 255, alpha: 1)
            }
            return UIColor(red: 246 / 255, green: 248 / 255, blue: 252 / 255, alpha: 1)
        }
        let navigationController = UINavigationController(rootViewController: hostingController)
        navigationController.setNavigationBarHidden(true, animated: false)
        navigationController.view.backgroundColor = hostingController.view.backgroundColor
        return navigationController
    }()
}
