//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

@Observable
final class OPDSCatalogsViewModel {
    var catalogs: [OPDSCatalog] = [] {
        didSet {
            UserDefaults.standard.set(
                catalogs.map(\.toDictionary),
                forKey: userDefaultsID
            )
        }
    }

    var editingCatalog: OPDSCatalog?

    var openCatalog: ((URL, IndexPath) -> Void)?

    private let userDefaultsID = "opdsCatalogArray"
    private var isFirstAppear = false

    func viewDidAppear() {
        guard !isFirstAppear else { return }
        isFirstAppear = true
        preloadTestFeeds()
    }

    func onCatalogTap(id: OPDSCatalog.ID) {
        guard
            let openCatalog,
            let index = catalogs.firstIndex(where: { $0.id == id })
        else {
            assertionFailure("openCatalog closure have to be set")
            return
        }
        openCatalog(catalogs[index].url, IndexPath(row: index, section: 0))
    }

    func onEditCatalogTap(id: OPDSCatalog.ID) {
        guard
            let catalog = catalogs.first(where: { $0.id == id })
        else { return }
        editingCatalog = catalog
    }

    func onDeleteCatalogTap(id: OPDSCatalog.ID) {
        guard
            let index = catalogs.firstIndex(where: { $0.id == id })
        else { return }
        catalogs.remove(at: index)
    }

    func onSaveEditedCatalogTap(_ catalog: OPDSCatalog) {
        if
            let index = catalogs.firstIndex(where: { $0.id == catalog.id })
        {
            catalogs[index] = catalog
        } else {
            catalogs.append(catalog)
        }
        editingCatalog = nil
    }

    func onAddCatalogTap() {
        let newCatalog = OPDSCatalog(
            id: UUID().uuidString,
            title: "",
            url: URL(string: "http://")!
        )
        editingCatalog = newCatalog
    }

    private func preloadTestFeeds() {
        let catalogsArray = UserDefaults.standard.array(forKey: userDefaultsID) as? [[String: String]]
        catalogs = catalogsArray?
            .compactMap(OPDSCatalog.init) ?? []

        let oldVersion = UserDefaults.standard.integer(forKey: .versionKey)

        if oldVersion < .currentVersion {
            // Migrate away from the previously bundled default catalogs
            // (Project Gutenberg, Internet Archive) without wiping anything
            // the user has added manually.
            catalogs.removeAll { catalog in
                [URL].legacyDefaultURLs.contains(catalog.url)
            }
            UserDefaults.standard.set(.currentVersion, forKey: .versionKey)
        }

        if catalogs.isEmpty, oldVersion == 0 {
            // First launch ever: seed with whatever we ship as defaults
            // (currently empty).
            setDefaultCatalogs()
        }
    }

    private func setDefaultCatalogs() {
        UserDefaults.standard.set(.currentVersion, forKey: .versionKey)
        catalogs = .defaultCatalogs
    }
}

private extension String {
    static let versionKey = "VERSION_KEY"
}

private extension Int {
    /// Bumped to 3 to force a reset of the cached catalog list for users who
    /// have the previous default catalogs (Project Gutenberg, Internet Archive)
    /// stored in `UserDefaults`. Combined with an empty `defaultCatalogs`,
    /// this leaves the Catalogs tab empty on launch unless the user adds
    /// their own feed.
    static let currentVersion = 3
}

private extension Array where Element == OPDSCatalog {
    /// PagePilot does not ship any pre-configured catalogs. Users can add their
    /// own OPDS feed URLs from the Catalogs tab.
    ///
    /// This avoids App Review flagging the app as "distributing book content"
    /// (App Store Review Guideline 2.1 in the China mainland store, which
    /// requires an Internet Publishing License / 网络出版服务许可证).
    static let defaultCatalogs: [OPDSCatalog] = []
}

private extension Array where Element == URL {
    /// URLs of the catalogs that were shipped as defaults in earlier builds.
    /// Used on migration to remove them from users that upgrade, while
    /// preserving any catalog they've added manually.
    static let legacyDefaultURLs: [URL] = [
        URL(string: "https://gutenberg.org/ebooks.opds/")!,
        URL(string: "https://archive.org/services/opds/")!,
    ]
}
