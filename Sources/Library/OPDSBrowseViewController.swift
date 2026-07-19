//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Kingfisher
import ReadiumOPDS
import ReadiumShared
import UIKit

/// Browses a single OPDS feed: lists navigation links (sub-catalogs) and
/// publications; downloads the tapped publication into the bookshelf via
/// `LibraryService.importPublication`.
final class OPDSBrowseViewController: UIViewController {
    private let feed: OPDSFeed
    private let library: LibraryService
    private let onPublicationImported: ((Book) -> Void)?
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    private var navigationLinks: [Link] = []
    private var publications: [Publication] = []
    private var nextURL: URL?
    private var loading = false

    init(
        feed: OPDSFeed,
        library: LibraryService,
        onPublicationImported: ((Book) -> Void)? = nil
    ) {
        self.feed = feed
        self.library = library
        self.onPublicationImported = onPublicationImported
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = feed.title
        view.backgroundColor = .systemGroupedBackground

        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        loadFeed(at: URL(string: feed.url))
    }

    private func loadFeed(at url: URL?) {
        guard let url, !loading else { return }
        loading = true
        let spinner = UIActivityIndicatorView(style: .medium)
        spinner.startAnimating()
        spinner.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 44)
        tableView.tableFooterView = spinner

        OPDSParser.parseURL(url: url) { [weak self] parseData, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.loading = false
                self.tableView.tableFooterView = nil

                if let error {
                    let msg = String(format: NSLocalizedString("opds_load_error_detail", comment: ""), error.localizedDescription)
                    self.presentErrorAlert(message: msg)
                    return
                }
                guard let parseData, let parsed = parseData.feed else {
                    self.presentErrorAlert(message: NSLocalizedString("opds_load_error", comment: ""))
                    return
                }

                // ponytail: append-only pagination, dedupe by self href when next page loads.
                let incomingPubs = parsed.publications
                if url.absoluteString == self.feed.url {
                    self.publications = incomingPubs
                    self.navigationLinks = parsed.navigation
                } else {
                    let existing = Set(self.publications.compactMap { $0.links.first(where: { $0.rels.contains(.`self`) })?.href })
                    self.publications.append(contentsOf: incomingPubs.filter { pub in
                        pub.links.first(where: { $0.rels.contains(.`self`) }).map { !existing.contains($0.href) } ?? true
                    })
                }
                self.nextURL = parsed.links.first(where: { $0.rels.contains(.next) }).flatMap { URL(string: $0.href) }

                if self.navigationLinks.isEmpty, self.publications.isEmpty {
                    self.tableView.backgroundView = self.makeEmptyView()
                } else {
                    self.tableView.backgroundView = nil
                }
                self.tableView.reloadData()
            }
        }
    }

    private func makeEmptyView() -> UIView {
        let label = UILabel()
        label.text = NSLocalizedString("opds_no_content", comment: "")
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        let container = UIView()
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    private func presentErrorAlert(message: String) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: NSLocalizedString("ok_button", comment: ""), style: .cancel))
        present(a, animated: true)
    }

    /// Finds the first acquisition link (open-access preferred) and returns an absolute download URL.
    private func downloadURL(for pub: Publication) -> URL? {
        let candidates: [LinkRelation] = [
            .opdsAcquisitionOpenAccess,
            .opdsAcquisition,
            .opdsAcquisitionSample,
        ]
        for rel in candidates {
            if let link = pub.links.first(where: { $0.rels.contains(rel) }),
               let url = URL(string: link.href, relativeTo: URL(string: feed.url))
            {
                return url.absoluteURL
            }
        }
        return nil
    }

    private enum Section: Int, CaseIterable {
        case navigation = 0
        case publications = 1
    }
}

extension OPDSBrowseViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .navigation:
            return navigationLinks.count
        case .publications:
            return publications.count + (nextURL == nil ? 0 : 1)
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .navigation:
            return navigationLinks.isEmpty ? nil : NSLocalizedString("opds_section_navigation", comment: "")
        case .publications:
            return publications.isEmpty ? nil : NSLocalizedString("opds_section_books", comment: "")
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)

        switch Section(rawValue: indexPath.section)! {
        case .navigation:
            let link = navigationLinks[indexPath.row]
            var content = cell.defaultContentConfiguration()
            content.text = link.title ?? NSLocalizedString("opds_untitled", comment: "")
            content.image = UIImage(systemName: "folder")
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell

        case .publications:
            // Load-more cell
            if indexPath.row == publications.count, nextURL != nil {
                var content = cell.defaultContentConfiguration()
                content.text = NSLocalizedString("opds_loading", comment: "")
                content.textProperties.color = .secondaryLabel
                cell.contentConfiguration = content
                cell.accessoryType = .none
                return cell
            }

            let pub = publications[indexPath.row]
            var content = UIListContentConfiguration.subtitleCell()
            content.text = pub.metadata.title ?? NSLocalizedString("opds_untitled", comment: "")
            content.secondaryText = pub.metadata.authors.map(\.name).joined(separator: ", ")
            cell.contentConfiguration = content

            if let thumbHref = pub.links.first(where: { $0.rels.contains(.opdsImageThumbnail) || $0.rels.contains(.opdsImage) })?.href,
               let url = URL(string: thumbHref, relativeTo: URL(string: feed.url))?.absoluteURL
            {
                cell.imageView?.kf.setImage(with: url, placeholder: UIImage(systemName: "book"))
            } else {
                cell.imageView?.image = UIImage(systemName: "book")
            }
            cell.accessoryType = downloadURL(for: pub) == nil ? .none : .disclosureIndicator
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch Section(rawValue: indexPath.section)! {
        case .navigation:
            let link = navigationLinks[indexPath.row]
            guard let url = URL(string: link.href, relativeTo: URL(string: feed.url))?.absoluteURL else {
                presentErrorAlert(message: NSLocalizedString("opds_error_enter_valid_url", comment: ""))
                return
            }
            let subFeed = OPDSFeed(title: link.title ?? NSLocalizedString("opds_untitled", comment: ""), url: url.absoluteString)
            let vc = OPDSBrowseViewController(
                feed: subFeed,
                library: library,
                onPublicationImported: onPublicationImported
            )
            navigationController?.pushViewController(vc, animated: true)

        case .publications:
            // Load-more row
            if indexPath.row == publications.count, nextURL != nil {
                loadFeed(at: nextURL)
                return
            }

            let pub = publications[indexPath.row]
            guard let url = downloadURL(for: pub) else {
                presentErrorAlert(message: NSLocalizedString("opds_no_acquisition_link", comment: ""))
                return
            }
            guard let absolute = AnyURL(string: url.absoluteString)?.absoluteURL else {
                presentErrorAlert(message: NSLocalizedString("opds_error_enter_valid_url", comment: ""))
                return
            }

            let spinner = UIActivityIndicatorView(style: .medium)
            spinner.startAnimating()
            navigationItem.titleView = spinner

            Task { [weak self] in
                defer { DispatchQueue.main.async { self?.navigationItem.titleView = nil } }
                do {
                    guard let book = try await self?.library.importPublication(
                        from: absolute,
                        sender: self,
                        progress: { _ in }
                    ) else {
                        return
                    }
                    await MainActor.run {
                        if let onPublicationImported = self?.onPublicationImported {
                            onPublicationImported(book)
                        } else {
                            self?.presentErrorAlert(message: NSLocalizedString("opds_download_done", comment: ""))
                        }
                    }
                } catch LibraryError.bookLimitReached {
                    await MainActor.run {
                        self?.presentErrorAlert(message: NSLocalizedString("library_book_limit_title", comment: ""))
                    }
                } catch {
                    await MainActor.run {
                        self?.presentErrorAlert(message: NSLocalizedString("opds_failure_message", comment: ""))
                    }
                }
            }
        }
    }
}
