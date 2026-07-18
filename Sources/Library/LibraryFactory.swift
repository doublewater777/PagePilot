//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import ReadiumShared
import UIKit

final class LibraryFactory {
    private let storyboard = UIStoryboard(name: "Library", bundle: nil)
    private let libraryService: LibraryService
    private let opdsFeeds: OPDSFeedRepository

    init(libraryService: LibraryService, opdsFeeds: OPDSFeedRepository) {
        self.libraryService = libraryService
        self.opdsFeeds = opdsFeeds
    }
}

extension LibraryFactory: LibraryViewControllerFactory {
    func make() -> LibraryViewController {
        let library = storyboard.instantiateViewController(withIdentifier: "LibraryViewController") as! LibraryViewController
        library.library = libraryService
        library.opdsFeeds = opdsFeeds
        return library
    }
}
