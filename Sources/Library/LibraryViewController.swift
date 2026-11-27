//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import Kingfisher
import MobileCoreServices
import ReadiumNavigator
import ReadiumShared
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WebKit

protocol LibraryViewControllerFactory {
    func make() -> LibraryViewController
}

class LibraryViewController: UIViewController, Loggable {
    private var books: [Book] = []

    enum ReadingFilter: String, CaseIterable {
        case all, reading, unread, finished
        var title: String { NSLocalizedString("library_filter_" + rawValue, comment: "Reading status") }
        var symbol: String {
            switch self {
            case .all: return "books.vertical"
            case .reading: return "book"
            case .unread: return "book.closed"
            case .finished: return "checkmark.circle"
            }
        }
    }
    private var readingFilter: ReadingFilter = .all

    func setReadingFilter(_ filter: ReadingFilter) {
        readingFilter = filter
        loadViewIfNeeded()
        title = filter.title
        applyFilteringAndReload()
    }

    // MARK: - Keyboard shortcuts (Mac Catalyst)

    /// Library-scoped shortcuts: import a book and focus the search field.
    override var keyCommands: [UIKeyCommand]? {
        let commands = [
            UIKeyCommand(
                title: NSLocalizedString("sc_import_book", comment: "Keyboard shortcut: import a book"),
                action: #selector(addBookFromDevice),
                input: "o",
                modifierFlags: .command
            ),
            UIKeyCommand(
                title: NSLocalizedString("sc_focus_search", comment: "Keyboard shortcut: focus search"),
                action: #selector(focusSearch),
                input: "f",
                modifierFlags: .command
            ),
        ]
        #if targetEnvironment(macCatalyst)
        for command in commands { command.wantsPriorityOverSystemBehavior = true }
        #endif
        return commands
    }

    #if targetEnvironment(macCatalyst)
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !searchController.isActive { becomeFirstResponder() }
    }
    #endif

    @objc private func focusSearch() {
        guard let searchController else { return }
        searchController.isActive = true
        searchController.searchBar.becomeFirstResponder()
    }

    weak var lastFlippedCell: PublicationCollectionViewCell?

    var library: LibraryService!

    var opdsFeeds: OPDSFeedRepository!

    weak var libraryDelegate: LibraryModuleDelegate?

    private var subscriptions = Set<AnyCancellable>()

    lazy var loadingIndicator = PublicationIndicator()

    // Editing and multi-select support
    private var isEditingBooks: Bool = false
    private var selectedBookIds = Set<Int64>()
    
    // Bottom floating delete toolbar
    private var deleteToolbar: UIVisualEffectView!
    private var deleteButton: UIButton!
    private var deleteToolbarBottomConstraint: NSLayoutConstraint!
    private var deleteToolbarHiddenConstraint: NSLayoutConstraint!

    // Search and caching support
    private var searchController: UISearchController!
    private var searchText: String = ""
    private var latestDBBooks: [Book] = []
    private var allAvailableBooks: [Book] = []
    private var removedMockBookIds = Set<Int64>()
    private var coverCache = [Int64: UIImage]()
    private var generatedCoverCache = [String: UIImage]()

    enum SortMode: String {
        case recentAdded
        case recentRead
        case title
        case author
    }
    
    private var currentSortMode: SortMode {
        get {
            let saved = UserDefaults.standard.string(forKey: "LibrarySortMode") ?? ""
            return SortMode(rawValue: saved) ?? .recentAdded
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "LibrarySortMode")
        }
    }
    
    private func setSortMode(_ mode: SortMode) {
        currentSortMode = mode
        updateNavigationBarButtons()
        applyFilteringAndReload()
    }

    enum ViewMode: String {
        case grid
        case list
    }
    
    var currentViewMode: ViewMode {
        get {
            #if targetEnvironment(macCatalyst)
            return .grid
            #else
            let saved = UserDefaults.standard.string(forKey: "LibraryViewMode") ?? ""
            return ViewMode(rawValue: saved) ?? .grid
            #endif
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "LibraryViewMode")
        }
    }
    
    private func setViewMode(_ mode: ViewMode) {
        print("[PagePilot LOG] setViewMode called with mode: \(mode.rawValue)")
        currentViewMode = mode
        updateNavigationBarButtons()
        
        collectionView.collectionViewLayout.invalidateLayout()
        
        // Force viewWillLayoutSubviews to run immediately so the new itemSize is computed
        view.setNeedsLayout()
        view.layoutIfNeeded()
        
        // Force transition visible cells to the new layout mode constraints
        for cell in collectionView.visibleCells {
            if let pubCell = cell as? PublicationCollectionViewCell {
                pubCell.configureMode(mode)
            }
        }
        
        collectionView.reloadData()
    }
    
    private func markBookAsRead(id: Int64) {
        LastReadBooks.record(id: id)

        if currentSortMode == .recentRead {
            applyFilteringAndReload()
        }
    }

    private func makeControlMenu() -> UIMenu {
        let selectAction = UIAction(title: NSLocalizedString("library_select_books", comment: ""), image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
            self?.toggleEditingMode()
        }
        
        #if !targetEnvironment(macCatalyst)
        let gridModeAction = UIAction(title: NSLocalizedString("library_view_mode_grid", comment: ""), image: UIImage(systemName: "square.grid.2x2"), state: currentViewMode == .grid ? .on : .off) { [weak self] _ in
            self?.setViewMode(.grid)
        }
        let listModeAction = UIAction(title: NSLocalizedString("library_view_mode_list", comment: ""), image: UIImage(systemName: "list.bullet"), state: currentViewMode == .list ? .on : .off) { [weak self] _ in
            self?.setViewMode(.list)
        }
        let viewModeMenu = UIMenu(title: NSLocalizedString("library_view_mode_title", comment: ""), image: UIImage(systemName: "square.grid.2x2"), children: [gridModeAction, listModeAction])
        #endif
        
        let recentReadAction = UIAction(title: NSLocalizedString("library_sort_recent_read", comment: ""), image: UIImage(systemName: "book"), state: currentSortMode == .recentRead ? .on : .off) { [weak self] _ in
            self?.setSortMode(.recentRead)
        }
        let titleAction = UIAction(title: NSLocalizedString("library_sort_title", comment: ""), image: UIImage(systemName: "textformat"), state: currentSortMode == .title ? .on : .off) { [weak self] _ in
            self?.setSortMode(.title)
        }
        let authorAction = UIAction(title: NSLocalizedString("library_sort_author", comment: ""), image: UIImage(systemName: "person"), state: currentSortMode == .author ? .on : .off) { [weak self] _ in
            self?.setSortMode(.author)
        }
        let recentImportedAction = UIAction(title: NSLocalizedString("library_sort_recent_added", comment: ""), image: UIImage(systemName: "clock"), state: currentSortMode == .recentAdded ? .on : .off) { [weak self] _ in
            self?.setSortMode(.recentAdded)
        }
        let sortMenu = UIMenu(title: NSLocalizedString("library_sort_title_menu", comment: ""), image: UIImage(systemName: "arrow.up.arrow.down"), children: [recentReadAction, titleAction, authorAction, recentImportedAction])
        
        #if targetEnvironment(macCatalyst)
        let menuItems = [sortMenu]
        #else
        let menuItems = [viewModeMenu, sortMenu]
        #endif
        let inlineMenu = UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: menuItems)
        return UIMenu(title: "", children: [selectAction, inlineMenu])
    }

    @IBOutlet var collectionView: UICollectionView! {
        didSet {
            collectionView.contentInset = UIEdgeInsets(top: 6, left: 18,
                                                       bottom: 32, right: 18)
            collectionView.register(UINib(nibName: "PublicationCollectionViewCell", bundle: nil),
                                    forCellWithReuseIdentifier: "publicationCollectionViewCell")
            collectionView.delegate = self
            collectionView.dataSource = self
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Setup UI components first so deleteButton/searchController exist
        // before updateLocalizedContent() tries to reference them.
        setupDeleteToolbar()
        setupSearchController()

        updateLocalizedContent()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, previous: UITraitCollection) in
            guard self.traitCollection.hasDifferentColorAppearance(comparedTo: previous) else { return }
            self.deleteToolbar?.layer.borderColor = UIColor.separator.cgColor
        }
        view.backgroundColor = AppColors.uiBackground
        collectionView.backgroundColor = AppColors.uiBackground
        collectionView.alwaysBounceVertical = true

        library.allBooks()
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case let .failure(error) = completion {
                    self.libraryDelegate?.presentError(UserError(error), from: self)
                }
            } receiveValue: { [weak self] newBooks in
                guard let self = self else { return }
                self.latestDBBooks = newBooks
                self.applyFilteringAndReload()
                
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-AutoOpenFirstBook"), !newBooks.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.collectionView(self.collectionView, didSelectItemAt: IndexPath(item: 0, section: 0))
                    }
                }
                #endif
            }
            .store(in: &subscriptions)

        // 注册书架顶部筛选 Header View
        collectionView.register(LibraryHeaderView.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "LibraryHeaderView")

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-AutoStartEditing") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.toggleEditingMode()
                if !self.books.isEmpty, let firstId = self.books[0].id?.rawValue {
                    self.selectedBookIds.insert(firstId)
                    self.updateDeleteButtonTitle()
                    self.collectionView.reloadData()
                }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-AutoSearchGatsby") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.searchController.isActive = true
                self.searchController.searchBar.text = "Gatsby"
                self.searchText = "Gatsby"
                self.applyFilteringAndReload()
            }
        }
        #endif
    }

    override func viewWillAppear(_ animated: Bool) {
        navigationController?.setNavigationBarHidden(false, animated: animated)
        super.viewWillAppear(animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        lastFlippedCell?.flipMenu()
        super.viewWillDisappear(animated)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        PostHogAnalytics.shared.recordPostureChange(size: size)
        collectionView?.collectionViewLayout.invalidateLayout()
    }

    func updateLocalizedContent() {
        #if targetEnvironment(macCatalyst)
        title = readingFilter.title
        #else
        title = NSLocalizedString("library_title", comment: "")
        #endif
        collectionView?.accessibilityLabel = NSLocalizedString("library_a11y_label", comment: "Accessibility label for the library collection view")
        searchController?.searchBar.placeholder = NSLocalizedString("library_search_placeholder", comment: "")
        updateNavigationBarButtons()
        updateDeleteButtonTitle()
        collectionView?.reloadData()
    }

    private func makeAddBookButton() -> UIBarButtonItem {
        UIBarButtonItem(
            systemItem: .add,
            menu: UIMenu(
                children: [
                    UIAction(title: NSLocalizedString("library_import_local", comment: ""), image: UIImage(systemName: "folder")) { [weak self] _ in
                        self?.addBookFromDevice()
                    },
                    UIAction(title: NSLocalizedString("library_wifi_transfer", comment: ""), image: UIImage(systemName: "wifi")) { [weak self] _ in
                        self?.presentWiFiTransfer()
                    },
                    UIAction(title: NSLocalizedString("library_device_transfer", comment: ""), image: UIImage(systemName: "ipad.and.iphone")) { [weak self] _ in
                        self?.presentDeviceTransfer()
                    },
                    UIAction(title: NSLocalizedString("opds_add_feed", comment: ""), image: UIImage(systemName: "books.vertical")) { [weak self] _ in
                        self?.presentOPDSFeeds()
                    },
                ]
            )
        )
    }

    private func makeSelectButton() -> UIBarButtonItem {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: nil,
            action: nil
        )
        button.menu = makeControlMenu()
        return button
    }

    private func makeCancelButton() -> UIBarButtonItem {
        UIBarButtonItem(
            title: NSLocalizedString("cancel_button", comment: ""),
            style: .done,
            target: self,
            action: #selector(toggleEditingMode)
        )
    }

    private func updateNavigationBarButtons() {
        if isEditingBooks {
            navigationItem.rightBarButtonItems = [makeCancelButton()]
        } else {
            #if targetEnvironment(macCatalyst)
            navigationItem.rightBarButtonItems = [makeAddBookButton(), makeSelectButton()]
            #else
            navigationItem.rightBarButtonItems = [makeSelectButton(), makeAddBookButton()]
            #endif
        }
    }

    @objc private func toggleEditingMode() {
        isEditingBooks.toggle()
        selectedBookIds.removeAll()
        
        // Disable search during editing to avoid index mismatch
        if isEditingBooks {
            searchController.isActive = false
            searchController.searchBar.isEnabled = false
            navigationItem.hidesSearchBarWhenScrolling = true
        } else {
            searchController.searchBar.isEnabled = true
            navigationItem.hidesSearchBarWhenScrolling = false
        }
        
        updateNavigationBarButtons()
        updateDeleteToolbarVisibility()
        updateDeleteButtonTitle()
        
        collectionView.reloadData()
    }

    private func setupSearchController() {
        searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = NSLocalizedString("library_search_placeholder", comment: "")
        navigationItem.searchController = searchController
        definesPresentationContext = true
        navigationItem.hidesSearchBarWhenScrolling = false
    }

    private func applyFilteringAndReload() {
        #if DEBUG
        var debugBooks = latestDBBooks.filter { book in
            guard let id = book.id?.rawValue else { return true }
            return !removedMockBookIds.contains(id)
        }
        
        // Progress for the first book (Pride & Prejudice) if it has no progression
        if !debugBooks.isEmpty && !removedMockBookIds.contains(debugBooks[0].id?.rawValue ?? -1) {
            debugBooks[0].progression = debugBooks[0].progression > 0 ? debugBooks[0].progression : 0.45
        }
        
        // Mock book 2: Not Started
        if !removedMockBookIds.contains(9992) {
            var book2 = Book(
                id: Book.Id(rawValue: 9992),
                title: "The Great Gatsby",
                authors: "F. Scott Fitzgerald",
                type: "application/epub+zip",
                url: AnyURL(string: "mock_url_2")!
            )
            book2.progression = 0.0
            book2.created = Date(timeIntervalSinceNow: -3600)
            debugBooks.append(book2)
        }
        
        // Mock book 3: Completed
        if !removedMockBookIds.contains(9993) {
            var book3 = Book(
                id: Book.Id(rawValue: 9993),
                title: "1984",
                authors: "George Orwell",
                type: "application/epub+zip",
                url: AnyURL(string: "mock_url_3")!
            )
            book3.progression = 1.0
            book3.created = Date(timeIntervalSinceNow: -7200)
            debugBooks.append(book3)
        }
        
        var filteredBooks = debugBooks
        #else
        var filteredBooks = latestDBBooks
        #endif

        self.allAvailableBooks = filteredBooks

        filteredBooks = filteredBooks.filter {
            switch readingFilter {
            case .all: return true
            case .reading: return $0.progression > 0 && $0.progression < 0.99
            case .unread: return $0.progression <= 0
            case .finished: return $0.progression >= 0.99
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            filteredBooks = filteredBooks.filter { book in
                let titleMatch = book.title.localizedCaseInsensitiveContains(query)
                let authorMatch = book.authors?.localizedCaseInsensitiveContains(query) ?? false
                return titleMatch || authorMatch
            }
        }
        
        // 按照当前的排序模式进行排序
        switch currentSortMode {
        case .recentAdded:
            filteredBooks.sort { $0.created > $1.created }
        case .recentRead:
            let lastReadIds = LastReadBooks.orderedIds
            filteredBooks.sort { (b1, b2) -> Bool in
                let id1 = b1.id?.rawValue ?? 0
                let id2 = b2.id?.rawValue ?? 0
                
                let idx1 = lastReadIds.firstIndex(of: id1)
                let idx2 = lastReadIds.firstIndex(of: id2)
                
                switch (idx1, idx2) {
                case let (i1?, i2?):
                    return i1 < i2
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return b1.created > b2.created
                }
            }
        case .title:
            filteredBooks.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .author:
            filteredBooks.sort { (b1, b2) -> Bool in
                let a1 = b1.authors ?? ""
                let a2 = b2.authors ?? ""
                if a1.isEmpty && !a2.isEmpty { return false }
                if !a1.isEmpty && a2.isEmpty { return true }
                return a1.localizedCompare(a2) == .orderedAscending
            }
        }
        
        self.books = filteredBooks
        self.collectionView.reloadData()
    }

    private func setupDeleteToolbar() {
        let blurEffect = UIBlurEffect(style: .systemChromeMaterial)
        deleteToolbar = UIVisualEffectView(effect: blurEffect)
        deleteToolbar.translatesAutoresizingMaskIntoConstraints = false
        deleteToolbar.layer.cornerRadius = 22
        deleteToolbar.clipsToBounds = true
        
        deleteToolbar.layer.borderWidth = 0.5
        deleteToolbar.layer.borderColor = UIColor.separator.cgColor
        
        view.addSubview(deleteToolbar)
        
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = .systemRed
        config.baseForegroundColor = .white
        config.cornerStyle = .large
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 15, weight: .bold)
            return outgoing
        }
        
        deleteButton = UIButton(configuration: config)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.addTarget(self, action: #selector(deleteSelectedBooks), for: .touchUpInside)
        
        deleteToolbar.contentView.addSubview(deleteButton)
        
        NSLayoutConstraint.activate([
            deleteToolbar.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            deleteToolbar.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            deleteToolbar.heightAnchor.constraint(equalToConstant: 64),
            
            deleteButton.leadingAnchor.constraint(equalTo: deleteToolbar.contentView.leadingAnchor, constant: 16),
            deleteButton.trailingAnchor.constraint(equalTo: deleteToolbar.contentView.trailingAnchor, constant: -16),
            deleteButton.topAnchor.constraint(equalTo: deleteToolbar.contentView.topAnchor, constant: 10),
            deleteButton.bottomAnchor.constraint(equalTo: deleteToolbar.contentView.bottomAnchor, constant: -10)
        ])
        
        deleteToolbarBottomConstraint = deleteToolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        deleteToolbarHiddenConstraint = deleteToolbar.topAnchor.constraint(equalTo: view.bottomAnchor, constant: 20)
        
        deleteToolbarHiddenConstraint.isActive = true
        deleteToolbarBottomConstraint.isActive = false
        
        updateDeleteButtonTitle()
    }

    private func updateDeleteButtonTitle() {
        let count = selectedBookIds.count
        if count > 0 {
            let formatString = NSLocalizedString("library_delete_selected_count", comment: "")
            deleteButton?.setTitle(String(format: formatString, count), for: .normal)
            deleteButton?.isEnabled = true
            deleteButton?.alpha = 1.0
        } else {
            deleteButton?.setTitle(NSLocalizedString("library_delete_books", comment: ""), for: .normal)
            deleteButton?.isEnabled = false
            deleteButton?.alpha = 0.5
        }
    }

    private func updateDeleteToolbarVisibility() {
        guard deleteToolbarHiddenConstraint != nil, deleteToolbarBottomConstraint != nil else { return }
        if isEditingBooks {
            deleteToolbarHiddenConstraint.isActive = false
            deleteToolbarBottomConstraint.isActive = true
        } else {
            deleteToolbarBottomConstraint.isActive = false
            deleteToolbarHiddenConstraint.isActive = true
        }
        
        UIView.animate(withDuration: 0.35, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func deleteSelectedBooks() {
        let count = selectedBookIds.count
        guard count > 0 else { return }
        
        let alert = UIAlertController(
            title: NSLocalizedString("library_delete_confirm_title", comment: ""),
            message: String(format: NSLocalizedString("library_delete_confirm_message", comment: ""), count),
            preferredStyle: .alert
        )
        
        let deleteAction = UIAlertAction(title: NSLocalizedString("library_delete_button", comment: ""), style: .destructive) { [weak self] _ in
            guard let self = self else { return }
            
            self.view.addSubview(self.loadingIndicator)
            self.view.isUserInteractionEnabled = false
            
            Task {
                defer {
                    DispatchQueue.main.async {
                        self.loadingIndicator.removeFromSuperview()
                        self.view.isUserInteractionEnabled = true
                        self.toggleEditingMode()
                    }
                }
                
                let booksToDelete = self.books.filter { book in
                    if let id = book.id?.rawValue {
                        return self.selectedBookIds.contains(id)
                    }
                    return false
                }
                
                for id in self.selectedBookIds {
                    self.removedMockBookIds.insert(id)
                }
                
                for book in booksToDelete {
                    if book.id?.rawValue != 9992 && book.id?.rawValue != 9993 {
                        do {
                            try await self.library.remove(book)
                        } catch {
                            print("Failed to delete book: \(book.title), error: \(error)")
                        }
                    }
                }
                
                self.applyFilteringAndReload()
            }
        }
        
        let cancelAction = UIAlertAction(title: NSLocalizedString("cancel_button", comment: ""), style: .cancel)
        alert.addAction(deleteAction)
        alert.addAction(cancelAction)
        present(alert, animated: true)
    }

    static let iPadLayoutNumberPerRow: [ScreenOrientation: Int] = [.portrait: 4, .landscape: 5]
    static let iPhoneLayoutNumberPerRow: [ScreenOrientation: Int] = [.portrait: 2, .landscape: 3]

    static let layoutNumberPerRow: [UIUserInterfaceIdiom: [ScreenOrientation: Int]] = [
        .pad: LibraryViewController.iPadLayoutNumberPerRow,
        .phone: LibraryViewController.iPhoneLayoutNumberPerRow,
    ]

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        let idiom = { () -> UIUserInterfaceIdiom in
            if traitCollection.horizontalSizeClass == .regular || UIDevice.current.userInterfaceIdiom == .pad {
                return .pad
            }
            return .phone
        }()

        let layoutNumberPerRow: [UIUserInterfaceIdiom: [ScreenOrientation: Int]] = [
            .pad: LibraryViewController.iPadLayoutNumberPerRow,
            .phone: LibraryViewController.iPhoneLayoutNumberPerRow,
        ]

        guard let deviceLayoutNumberPerRow = layoutNumberPerRow[idiom] else { return }
        guard let numberPerRow = deviceLayoutNumberPerRow[.current] else { return }

        guard let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        #if targetEnvironment(macCatalyst)
        collectionView.contentInset = UIEdgeInsets(top: 24, left: 28, bottom: 28, right: 28)
        #endif
        let contentWidth = collectionView.bounds.width - collectionView.adjustedContentInset.left - collectionView.adjustedContentInset.right

        let minimumSpacing = CGFloat(14)
        let width: CGFloat
        let height: CGFloat

        if currentViewMode == .list {
            flowLayout.minimumLineSpacing = 12
            flowLayout.minimumInteritemSpacing = 0
            width = contentWidth
            height = 104
        } else {
            flowLayout.minimumLineSpacing = 22
            flowLayout.minimumInteritemSpacing = minimumSpacing
            width = floor((contentWidth - CGFloat(numberPerRow - 1) * minimumSpacing) / CGFloat(numberPerRow))
            height = width * 1.46 + 74
        }

        flowLayout.itemSize = CGSize(width: width, height: height)
        #if targetEnvironment(macCatalyst)
        flowLayout.headerReferenceSize = .zero
        #else
        flowLayout.headerReferenceSize = allAvailableBooks.isEmpty ? .zero : CGSize(width: contentWidth, height: 50)
        #endif
    }

    @objc func addBookFromDevice() {
        var types = DocumentTypes.main.supportedUTTypes
        types.append(UTType.text)

        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: types)
        documentPicker.delegate = self
        present(documentPicker, animated: true, completion: nil)
    }

    private func presentWiFiTransfer() {
        PostHogAnalytics.shared.screen("wifi_transfer")
        let wifiView = WiFiTransferView(library: library)
        let hostingController = UIHostingController(rootView: wifiView)
        hostingController.modalPresentationStyle = .formSheet
        present(hostingController, animated: true)
    }

    private func presentDeviceTransfer() {
        PostHogAnalytics.shared.screen("device_transfer")
        let transferView = DeviceTransferView(books: books, library: library)
        let hostingController = UIHostingController(rootView: transferView)
        hostingController.modalPresentationStyle = .formSheet
        present(hostingController, animated: true)
    }

    private func presentOPDSFeeds() {
        PostHogAnalytics.shared.screen("opds_catalog")
        let vc = OPDSFeedListViewController(feeds: opdsFeeds, library: library)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    private func presentBookLimitPaywall() {
        let alert = UIAlertController(
            title: NSLocalizedString("library_book_limit_title", comment: ""),
            message: String(format: NSLocalizedString("library_book_limit_message", comment: ""), ProPurchaseManager.freeBookLimit),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel_button", comment: ""), style: .cancel))
        alert.addAction(UIAlertAction(title: NSLocalizedString("library_book_limit_upgrade", comment: ""), style: .default) { [weak self] _ in
            guard let self else { return }
            Analytics.shared.log(.paywallViewed(source: "library_book_limit"))
            let paywall = UIHostingController(rootView: PaywallView())
            paywall.modalPresentationStyle = .formSheet
            self.present(paywall, animated: true)
        })
        present(alert, animated: true)
    }
}

// MARK: - UIDocumentPickerDelegate.

extension LibraryViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        importFiles(at: urls)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        importFiles(at: [url])
    }

    private func importFiles(at urls: [URL]) {
        Task {
            do {
                try await library.importPublications(from: urls, sender: self)
                PostHogAnalytics.shared.capture("book_imported", properties: [
                    "count": urls.count,
                    "source": "file_picker"
                ])
            } catch LibraryError.bookLimitReached {
                await MainActor.run {
                    presentBookLimitPaywall()
                }
            } catch {
                libraryDelegate?.presentError(UserError(error), from: self)
            }
        }
    }
}

// MARK: - CollectionView Datasource.

extension LibraryViewController: UICollectionViewDelegateFlowLayout, UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if books.isEmpty {
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                collectionView.backgroundView = makeFilteredEmptyView(
                    icon: "magnifyingglass",
                    message: NSLocalizedString("library_empty_search", comment: "")
                )
            } else if readingFilter != .all {
                collectionView.backgroundView = makeFilteredEmptyView(
                    icon: readingFilter.symbol,
                    message: NSLocalizedString("library_empty_filtered", comment: "")
                )
            } else {
                collectionView.backgroundView = makeEmptyLibraryView()
            }
        } else {
            collectionView.backgroundView = nil
        }

        return books.count
    }

    private func makeFilteredEmptyView(icon: String, message: String) -> UIView {
        let container = UIView(frame: collectionView.bounds)
        container.backgroundColor = .clear

        let imageView = UIImageView(image: UIImage(
            systemName: icon,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 32, weight: .light)
        ))
        imageView.tintColor = .tertiaryLabel
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = message
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [imageView, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -20),
            label.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, multiplier: 0.72),
        ])

        return container
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "publicationCollectionViewCell", for: indexPath) as! PublicationCollectionViewCell
        cell.coverImageView.image = nil

        cell.isAccessibilityElement = true
        cell.accessibilityHint = NSLocalizedString("library_publication_a11y_hint", comment: "Accessibility hint for the publication collection cell")

        let book = books[indexPath.item]
        cell.progress = Float(book.progression)
        cell.isEditingMode = isEditingBooks
        if let bookId = book.id?.rawValue {
            cell.isSelectedForEditing = selectedBookIds.contains(bookId)
        } else {
            cell.isSelectedForEditing = false
        }
        cell.delegate = self
        cell.accessibilityLabel = book.title
        cell.titleLabel.text = book.title
        let authorText = book.authors?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAuthor = (authorText?.isEmpty == false && authorText?.lowercased() != "unknown") ? authorText : nil
        cell.authorLabel.text = resolvedAuthor
        cell.authorLabel.isHidden = (resolvedAuthor == nil)

        // Load image asynchronously to avoid blocking the main thread with disk I/O.
        let flowLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout
        if let bookId = book.id?.rawValue, let cachedImage = coverCache[bookId] {
            cell.coverImageView.image = cachedImage
        } else if let coverURL = book.cover {
            cell.coverImageView.image = defaultCover(layout: flowLayout, description: book.title, author: authorText)
            let bookId = book.id?.rawValue
            let coverFileURL = coverURL.url
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self,
                      let data = try? Data(contentsOf: coverFileURL),
                      let cover = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    if let bookId = bookId {
                        self.coverCache[bookId] = cover
                    }
                    guard let currentIndexPath = self.collectionView.indexPath(for: cell),
                          currentIndexPath.item < self.books.count,
                          self.books[currentIndexPath.item].id?.rawValue == bookId else { return }
                    cell.coverImageView.image = cover
                }
            }
        } else {
            cell.coverImageView.image = defaultCover(layout: flowLayout, description: book.title, author: authorText)
        }

        cell.configureMode(currentViewMode)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        guard kind == UICollectionView.elementKindSectionHeader else {
            return UICollectionReusableView()
        }
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "LibraryHeaderView", for: indexPath) as! LibraryHeaderView
        header.configure(
            selectedFilter: readingFilter,
            counts: filterCounts(),
            onSelect: { [weak self] filter in
                guard let self, self.readingFilter != filter else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                self.readingFilter = filter
                self.applyFilteringAndReload()
            }
        )
        return header
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        #if targetEnvironment(macCatalyst)
        return .zero
        #else
        guard !allAvailableBooks.isEmpty else { return .zero }
        let width = max(0, collectionView.bounds.width - collectionView.adjustedContentInset.left - collectionView.adjustedContentInset.right)
        return CGSize(width: width, height: 48)
        #endif
    }

    private func filterCounts() -> [ReadingFilter: Int] {
        var reading = 0
        var unread = 0
        var finished = 0
        for book in allAvailableBooks {
            if book.progression >= 0.99 {
                finished += 1
            } else if book.progression > 0 {
                reading += 1
            } else {
                unread += 1
            }
        }
        return [
            .all: allAvailableBooks.count,
            .reading: reading,
            .unread: unread,
            .finished: finished,
        ]
    }

    func defaultCover(layout: UICollectionViewFlowLayout?, description: String, author: String? = nil) -> UIImage {
        let width = max(110, min(180, layout?.itemSize.width ?? 120))
        let height = width * 1.46
        let cacheKey = "\(description)|\(author ?? "")|\(Int(width))"
        if let cached = generatedCoverCache[cacheKey] {
            return cached
        }
        let image = GeneratedBookCover.renderImage(
            title: description,
            author: author,
            size: CGSize(width: width, height: height)
        )
        generatedCoverCache[cacheKey] = image
        return image
    }

    private func makeEmptyLibraryView() -> UIView {
        let container = UIView(frame: collectionView.bounds)
        container.backgroundColor = .clear

        let visualView: UIView
        if let emptyArt = UIImage(named: "EmptyLibraryArt") {
            let shadowWrapper = UIView()
            shadowWrapper.translatesAutoresizingMaskIntoConstraints = false
            shadowWrapper.backgroundColor = .clear
            shadowWrapper.layer.shadowColor = UIColor.black.cgColor
            shadowWrapper.layer.shadowOpacity = traitCollection.userInterfaceStyle == .dark ? 0.35 : 0.09
            shadowWrapper.layer.shadowRadius = 14
            shadowWrapper.layer.shadowOffset = CGSize(width: 0, height: 6)

            let artImageView = UIImageView(image: emptyArt)
            artImageView.translatesAutoresizingMaskIntoConstraints = false
            artImageView.contentMode = .scaleAspectFill
            artImageView.clipsToBounds = true
            artImageView.layer.cornerRadius = 18
            artImageView.layer.cornerCurve = .continuous
            artImageView.layer.borderWidth = 0.6
            artImageView.layer.borderColor = UIColor.label.withAlphaComponent(0.08).cgColor
            shadowWrapper.addSubview(artImageView)

            NSLayoutConstraint.activate([
                shadowWrapper.widthAnchor.constraint(equalToConstant: 216),
                shadowWrapper.heightAnchor.constraint(equalToConstant: 158),
                artImageView.topAnchor.constraint(equalTo: shadowWrapper.topAnchor),
                artImageView.leadingAnchor.constraint(equalTo: shadowWrapper.leadingAnchor),
                artImageView.trailingAnchor.constraint(equalTo: shadowWrapper.trailingAnchor),
                artImageView.bottomAnchor.constraint(equalTo: shadowWrapper.bottomAnchor),
            ])
            visualView = shadowWrapper
        } else {
            let iconContainer = UIView()
            iconContainer.translatesAutoresizingMaskIntoConstraints = false
            iconContainer.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.12)
            iconContainer.layer.cornerRadius = 20

            let icon = UIImageView(image: UIImage(systemName: "books.vertical"))
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.tintColor = .systemBlue
            icon.contentMode = .scaleAspectFit
            iconContainer.addSubview(icon)

            NSLayoutConstraint.activate([
                iconContainer.widthAnchor.constraint(equalToConstant: 72),
                iconContainer.heightAnchor.constraint(equalToConstant: 72),
                icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 30),
                icon.heightAnchor.constraint(equalToConstant: 30),
            ])
            visualView = iconContainer
        }

        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = NSLocalizedString("home_empty_title", comment: "")
        titleLabel.font = .preferredFont(forTextStyle: .title3)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center

        let messageLabel = UILabel()
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.text = NSLocalizedString("library_empty_message", comment: "Hint message when the library is empty")
        messageLabel.font = .preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(addBookFromDevice), for: .touchUpInside)
        button.clipsToBounds = true
        button.layer.cornerRadius = 14

        let gradientSize = CGSize(width: 1, height: 44)
        let renderer = UIGraphicsImageRenderer(size: gradientSize)
        let gradientImage = renderer.image { ctx in
            let colors = [
                UIColor(red: 0.12, green: 0.47, blue: 0.85, alpha: 1).cgColor,
                UIColor(red: 0.08, green: 0.66, blue: 0.58, alpha: 1).cgColor,
            ]
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil) else { return }
            ctx.cgContext.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: gradientSize.width, y: 0), options: [])
        }

        var configuration = UIButton.Configuration.plain()
        configuration.title = NSLocalizedString("library_import_local", comment: "")
        configuration.image = UIImage(systemName: "folder")
        configuration.imagePadding = 8
        configuration.baseForegroundColor = .white
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            return outgoing
        }
        configuration.background.image = gradientImage
        configuration.background.imageContentMode = .scaleToFill
        button.configuration = configuration

        let stackView = UIStackView(arrangedSubviews: [visualView, titleLabel, messageLabel, button])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 14
        stackView.setCustomSpacing(18, after: messageLabel)
        container.addSubview(stackView)

        NSLayoutConstraint.activate([
            messageLabel.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, multiplier: 0.72),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),

            stackView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -24),
        ])

        return container
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let book = books[indexPath.item]
        
        if !isEditingBooks && book.url.hasPrefix("mock_url") {
            let alert = UIAlertController(
                title: NSLocalizedString("library_demo_book_title", comment: ""),
                message: String(format: NSLocalizedString("library_demo_book_message", comment: ""), book.title),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: NSLocalizedString("ok_button", comment: ""), style: .default))
            self.present(alert, animated: true)
            return
        }

        if isEditingBooks {
            guard let bookId = book.id?.rawValue else { return }
            
            if selectedBookIds.contains(bookId) {
                selectedBookIds.remove(bookId)
            } else {
                selectedBookIds.insert(bookId)
            }
            
            if let cell = collectionView.cellForItem(at: indexPath) as? PublicationCollectionViewCell {
                cell.isSelectedForEditing = selectedBookIds.contains(bookId)
            }
            
            updateDeleteButtonTitle()
            return
        }

        Task {
            guard
                let libraryDelegate = libraryDelegate,
                let cell = collectionView.cellForItem(at: indexPath)
            else {
                return
            }
            cell.contentView.addSubview(self.loadingIndicator)
            collectionView.isUserInteractionEnabled = false

            defer {
                loadingIndicator.removeFromSuperview()
                collectionView.isUserInteractionEnabled = true
            }

            do {
                guard let pub = try await library.openBook(book, sender: self) else {
                    return
                }
                if let bookId = book.id?.rawValue {
                    markBookAsRead(id: bookId)
                }
                libraryDelegate.libraryDidSelectPublication(pub, book: book)
            } catch {
                libraryDelegate.presentError(UserError(error), from: self)
            }
        }
    }
}

extension LibraryViewController: PublicationCollectionViewCellDelegate {
    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard !isEditingBooks, indexPath.item < books.count else { return nil }
        let book = books[indexPath.item]
        let bookID = book.id
        let isDemo = book.url.hasPrefix("mock_url")
        let openTitle = book.progression > 0
            ? NSLocalizedString("library_context_continue", comment: "")
            : NSLocalizedString("library_context_open", comment: "")

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            var actions: [UIMenuElement] = [
                UIAction(title: openTitle, image: UIImage(systemName: "book")) { [weak self] _ in
                    guard let self, let index = self.books.firstIndex(where: { $0.id == bookID }) else { return }
                    let path = IndexPath(item: index, section: 0)
                    self.collectionView(collectionView, didSelectItemAt: path)
                },
            ]

            if !isDemo {
                actions.append(
                    UIAction(title: NSLocalizedString("library_context_details", comment: ""), image: UIImage(systemName: "info.circle")) { [weak self] _ in
                        guard let self, let index = self.books.firstIndex(where: { $0.id == bookID }) else { return }
                        let path = IndexPath(item: index, section: 0)
                        self.presentMetadata(forCellAt: path)
                    }
                )
            }

            #if !targetEnvironment(macCatalyst)
            actions.append(
                UIAction(title: NSLocalizedString("library_context_select", comment: ""), image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
                    guard let self else { return }
                    if !self.isEditingBooks {
                        self.toggleEditingMode()
                    }
                    if let rawID = bookID?.rawValue {
                        self.selectedBookIds.insert(rawID)
                        self.updateDeleteButtonTitle()
                        self.collectionView.reloadData()
                    }
                }
            )
            #endif

            let deleteAction = UIAction(
                title: NSLocalizedString("remove_button", comment: ""),
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                guard let self, let index = self.books.firstIndex(where: { $0.id == bookID }) else { return }
                let path = IndexPath(item: index, section: 0)
                self.removePublicationFromLibrary(forCellAt: path)
            }

            let destructiveGroup = UIMenu(title: "", options: .displayInline, children: [deleteAction])
            actions.append(destructiveGroup)

            return UIMenu(title: book.title, children: actions)
        }
    }

    func removePublicationFromLibrary(forCellAt indexPath: IndexPath) {
        let book = books[indexPath.item]

        let removePublicationAlert = UIAlertController(
            title: NSLocalizedString("library_delete_alert_title", comment: "Title of the publication remove confirmation alert"),
            message: NSLocalizedString("library_delete_alert_message", comment: "Message of the publication remove confirmation alert"),
            preferredStyle: .alert
        )
        let removeAction = UIAlertAction(title: NSLocalizedString("remove_button", comment: "Button to confirm the deletion of a publication"), style: .destructive, handler: { _ in
            Task {
                do {
                    if let rawID = book.id?.rawValue, rawID == 9992 || rawID == 9993 {
                        await MainActor.run {
                            self.removedMockBookIds.insert(rawID)
                            self.applyFilteringAndReload()
                        }
                    } else {
                        try await self.library.remove(book)
                    }
                } catch {
                    self.libraryDelegate?.presentError(UserError(error), from: self)
                }
            }
        })
        let cancelAction = UIAlertAction(title: NSLocalizedString("cancel_button", comment: "Button to cancel the deletion of a publication"), style: .cancel)

        removePublicationAlert.addAction(removeAction)
        removePublicationAlert.addAction(cancelAction)
        present(removePublicationAlert, animated: true, completion: nil)
    }

    func presentMetadata(forCellAt indexPath: IndexPath) {
        let book = books[indexPath.row]

        Task {
            do {
                guard let pub = try await library.openBook(book, sender: self) else {
                    return
                }
                let metadataView = PublicationMetadataView(
                    publication: pub,
                    book: book,
                    onOpen: { [weak self] in
                        guard let self else { return }
                        if let bookId = book.id?.rawValue {
                            self.markBookAsRead(id: bookId)
                        }
                        self.navigationController?.popViewController(animated: false)
                        self.libraryDelegate?.libraryDidSelectPublication(pub, book: book)
                    }
                )
                let pubMetadataViewController = UIHostingController(rootView: metadataView)
                pubMetadataViewController.hidesBottomBarWhenPushed = true
                self.navigationController?.pushViewController(pubMetadataViewController, animated: true)
            } catch {
                libraryDelegate?.presentError(UserError(error), from: self)
            }
        }
    }

    /// Used to reset ui of the last flipped cell, we must not have two cells
    /// flipped at the same time
    func cellFlipped(_ cell: PublicationCollectionViewCell) {
        lastFlippedCell?.flipMenu()
        lastFlippedCell = cell
    }
}

class PublicationIndicator: UIView {
    private lazy var pillView: UIVisualEffectView = {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerRadius = 16
        blur.layer.cornerCurve = .continuous
        blur.clipsToBounds = true
        return blur
    }()

    lazy var indicator: UIActivityIndicatorView = {
        let result = UIActivityIndicatorView(style: .medium)
        result.translatesAutoresizingMaskIntoConstraints = false
        self.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        self.addSubview(pillView)
        pillView.contentView.addSubview(result)

        NSLayoutConstraint.activate([
            pillView.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            pillView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
            pillView.widthAnchor.constraint(equalToConstant: 56),
            pillView.heightAnchor.constraint(equalToConstant: 56),
            result.centerXAnchor.constraint(equalTo: pillView.contentView.centerXAnchor),
            result.centerYAnchor.constraint(equalTo: pillView.contentView.centerYAnchor),
        ])

        return result
    }()

    override func didMoveToSuperview() {
        super.didMoveToSuperview()

        guard let superView = superview else { return }
        translatesAutoresizingMaskIntoConstraints = false

        let horizontalConstraint = NSLayoutConstraint(item: self, attribute: .centerX, relatedBy: .equal, toItem: superView, attribute: .centerX, multiplier: 1.0, constant: 0.0)
        let verticalConstraint = NSLayoutConstraint(item: self, attribute: .centerY, relatedBy: .equal, toItem: superView, attribute: .centerY, multiplier: 1.0, constant: 0.0)
        let widthConstraint = NSLayoutConstraint(item: self, attribute: .width, relatedBy: .equal, toItem: superView, attribute: .width, multiplier: 1.0, constant: 0.0)
        let heightConstraint = NSLayoutConstraint(item: self, attribute: .height, relatedBy: .equal, toItem: superView, attribute: .height, multiplier: 1.0, constant: 0.0)

        superView.addConstraints([horizontalConstraint, verticalConstraint, widthConstraint, heightConstraint])

        indicator.startAnimating()
    }

    override func removeFromSuperview() {
        indicator.stopAnimating()
        super.removeFromSuperview()
    }
}

// MARK: - Premium Glassmorphic Empty Library View Components

private class GradientView: UIView {
    override class var layerClass: AnyClass {
        return CAGradientLayer.self
    }
    
    var gradientLayer: CAGradientLayer {
        return layer as! CAGradientLayer
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        gradientLayer.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
    }
}

private class BounceButton: UIButton {
    private let gradientView = GradientView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        // Configure gradient view
        gradientView.translatesAutoresizingMaskIntoConstraints = false
        gradientView.isUserInteractionEnabled = false
        gradientView.layer.cornerRadius = 14
        gradientView.clipsToBounds = true
        gradientView.gradientLayer.colors = [
            UIColor(red: 0.12, green: 0.47, blue: 0.85, alpha: 1).cgColor, // Vibrant Blue
            UIColor(red: 0.08, green: 0.66, blue: 0.58, alpha: 1).cgColor  // Teal
        ]
        
        insertSubview(gradientView, at: 0)
        
        NSLayoutConstraint.activate([
            gradientView.leadingAnchor.constraint(equalTo: leadingAnchor),
            gradientView.trailingAnchor.constraint(equalTo: trailingAnchor),
            gradientView.topAnchor.constraint(equalTo: topAnchor),
            gradientView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        
        // Setup configuration and styling
        var config = UIButton.Configuration.plain()
        config.title = NSLocalizedString("library_import_local", comment: "")
        config.image = UIImage(systemName: "folder")
        config.imagePadding = 8
        config.baseForegroundColor = .white
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
            return outgoing
        }
        self.configuration = config
        
        // Button shadow
        layer.shadowColor = UIColor(red: 0.12, green: 0.47, blue: 0.85, alpha: 0.3).cgColor
        layer.shadowOpacity = 0.6
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.masksToBounds = false
        
        // Scale interactions
        addTarget(self, action: #selector(animateTouchDown), for: .touchDown)
        addTarget(self, action: #selector(animateTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }
    
    @objc private func animateTouchDown() {
        UIView.animate(withDuration: 0.1, delay: 0, options: [.beginFromCurrentState], animations: {
            self.transform = CGAffineTransform(scaleX: 0.95, y: 0.95)
        })
    }
    
    @objc private func animateTouchUp() {
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: [.beginFromCurrentState], animations: {
            self.transform = .identity
        })
    }
}

private class EmptyLibraryView: UIView {
    var onImportAction: (() -> Void)?
    
    private let shadowWrapper = UIView()
    private let cardView = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }
    
    private func setupViews() {
        backgroundColor = .clear
        
        // 1. Add background glowing blobs
        let blob1 = UIView()
        blob1.translatesAutoresizingMaskIntoConstraints = false
        blob1.backgroundColor = UIColor(red: 0.08, green: 0.66, blue: 0.58, alpha: 0.15) // Teal
        blob1.layer.cornerRadius = 100
        blob1.clipsToBounds = true
        
        let blob2 = UIView()
        blob2.translatesAutoresizingMaskIntoConstraints = false
        blob2.backgroundColor = UIColor(red: 0.12, green: 0.47, blue: 0.85, alpha: 0.15) // Blue
        blob2.layer.cornerRadius = 120
        blob2.clipsToBounds = true
        
        addSubview(blob1)
        addSubview(blob2)
        
        // Full screen blur layer to diffuse blobs
        let backdropBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
        backdropBlur.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backdropBlur)
        
        // 2. Card View with shadow wrapper
        shadowWrapper.translatesAutoresizingMaskIntoConstraints = false
        shadowWrapper.backgroundColor = .clear
        shadowWrapper.layer.shadowColor = UIColor.black.cgColor
        shadowWrapper.layer.shadowOffset = CGSize(width: 0, height: 8)
        shadowWrapper.layer.shadowRadius = 18
        shadowWrapper.layer.masksToBounds = false
        
        cardView.translatesAutoresizingMaskIntoConstraints = false
        cardView.layer.cornerRadius = 24
        cardView.layer.borderWidth = 1.0
        cardView.clipsToBounds = true
        
        shadowWrapper.addSubview(cardView)
        addSubview(shadowWrapper)
        
        // 3. Stack View inside card
        let iconContainer = GradientView()
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.layer.cornerRadius = 20
        iconContainer.clipsToBounds = true
        iconContainer.gradientLayer.colors = [
            UIColor(red: 0.29, green: 0.38, blue: 0.93, alpha: 1).cgColor, // Indigo
            UIColor(red: 0.08, green: 0.66, blue: 0.58, alpha: 1).cgColor  // Teal
        ]
        
        let icon = UIImageView(image: UIImage(systemName: "books.vertical"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        iconContainer.addSubview(icon)
        
        let titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = NSLocalizedString("home_empty_title", comment: "")
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        
        let messageLabel = UILabel()
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.text = NSLocalizedString("library_empty_message", comment: "")
        messageLabel.font = .systemFont(ofSize: 14, weight: .regular)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        
        let button = BounceButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(buttonTapped), for: .touchUpInside)
        
        let stackView = UIStackView(arrangedSubviews: [iconContainer, titleLabel, messageLabel, button])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 16
        stackView.setCustomSpacing(24, after: messageLabel)
        
        cardView.contentView.addSubview(stackView)
        
        // 4. Constraints
        NSLayoutConstraint.activate([
            // Blobs
            blob1.topAnchor.constraint(equalTo: topAnchor, constant: 100),
            blob1.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            blob1.widthAnchor.constraint(equalToConstant: 200),
            blob1.heightAnchor.constraint(equalToConstant: 200),
            
            blob2.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -120),
            blob2.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -40),
            blob2.widthAnchor.constraint(equalToConstant: 240),
            blob2.heightAnchor.constraint(equalToConstant: 240),
            
            // Backdrop Blur
            backdropBlur.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdropBlur.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdropBlur.topAnchor.constraint(equalTo: topAnchor),
            backdropBlur.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            // Shadow Wrapper & Card
            shadowWrapper.centerXAnchor.constraint(equalTo: centerXAnchor),
            shadowWrapper.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            shadowWrapper.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.85).withPriority(.defaultHigh),
            shadowWrapper.widthAnchor.constraint(lessThanOrEqualToConstant: 340),
            
            cardView.leadingAnchor.constraint(equalTo: shadowWrapper.leadingAnchor),
            cardView.trailingAnchor.constraint(equalTo: shadowWrapper.trailingAnchor),
            cardView.topAnchor.constraint(equalTo: shadowWrapper.topAnchor),
            cardView.bottomAnchor.constraint(equalTo: shadowWrapper.bottomAnchor),
            
            // Stack View inside Card
            stackView.topAnchor.constraint(equalTo: cardView.contentView.topAnchor, constant: 28),
            stackView.bottomAnchor.constraint(equalTo: cardView.contentView.bottomAnchor, constant: -28),
            stackView.leadingAnchor.constraint(equalTo: cardView.contentView.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: cardView.contentView.trailingAnchor, constant: -24),
            
            // Icon Container
            iconContainer.widthAnchor.constraint(equalToConstant: 76),
            iconContainer.heightAnchor.constraint(equalToConstant: 76),
            
            // Icon inside Container
            icon.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 36),
            icon.heightAnchor.constraint(equalToConstant: 36),
            
            // Button inside Stack
            button.heightAnchor.constraint(equalToConstant: 46),
            button.leadingAnchor.constraint(equalTo: cardView.contentView.leadingAnchor, constant: 28),
            button.trailingAnchor.constraint(equalTo: cardView.contentView.trailingAnchor, constant: -28)
        ])
        
        updateAppearance()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, previous: UITraitCollection) in
            if self.traitCollection.hasDifferentColorAppearance(comparedTo: previous) {
                self.updateAppearance()
            }
        }
    }
    
    private func updateAppearance() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        
        // Card border color depending on Light/Dark mode
        cardView.layer.borderColor = isDark ?
            UIColor.white.withAlphaComponent(0.08).cgColor :
            UIColor.white.withAlphaComponent(0.16).cgColor
            
        // Shadow opacity depending on Light/Dark mode
        shadowWrapper.layer.shadowOpacity = isDark ? 0.25 : 0.09
    }
    
    @objc private func buttonTapped() {
        onImportAction?()
    }
}

// Extension helper to set priority inline
private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}


// MARK: - UISearchResultsUpdating
extension LibraryViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        searchText = searchController.searchBar.text ?? ""
        applyFilteringAndReload()
    }
}

// MARK: - LibraryHeaderView (Horizontal Reading-Status Filter Pills)

class LibraryHeaderView: UICollectionReusableView {
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private var buttons: [LibraryViewController.ReadingFilter: UIButton] = [:]
    private var onSelect: ((LibraryViewController.ReadingFilter) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        backgroundColor = .clear

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        addSubview(scrollView)

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 8
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        for filter in LibraryViewController.ReadingFilter.allCases {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.addAction(UIAction { [weak self] _ in
                self?.onSelect?(filter)
            }, for: .primaryActionTriggered)
            buttons[filter] = button
            stackView.addArrangedSubview(button)
        }
    }

    func configure(
        selectedFilter: LibraryViewController.ReadingFilter,
        counts: [LibraryViewController.ReadingFilter: Int],
        onSelect: @escaping (LibraryViewController.ReadingFilter) -> Void
    ) {
        self.onSelect = onSelect
        let isDark = traitCollection.userInterfaceStyle == .dark

        for filter in LibraryViewController.ReadingFilter.allCases {
            guard let button = buttons[filter] else { continue }
            let isSelected = (filter == selectedFilter)
            let count = counts[filter] ?? 0
            let titleText = count > 0 ? "\(filter.title) \(count)" : filter.title

            var config = UIButton.Configuration.filled()
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 13, bottom: 7, trailing: 13)
            config.baseBackgroundColor = isSelected
                ? AppColors.uiAccentBlue
                : (isDark ? UIColor.white.withAlphaComponent(0.08) : UIColor.white)
            config.baseForegroundColor = isSelected ? .white : .secondaryLabel

            var attrs = AttributeContainer()
            attrs.font = UIFont.systemFont(ofSize: 13, weight: isSelected ? .semibold : .medium)
            config.attributedTitle = AttributedString(titleText, attributes: attrs)

            button.configuration = config
            button.layer.cornerRadius = 16
            button.layer.borderWidth = isSelected ? 0 : 0.75
            button.layer.borderColor = (isDark ? UIColor.white.withAlphaComponent(0.08) : UIColor.black.withAlphaComponent(0.06)).cgColor
        }
    }
}
