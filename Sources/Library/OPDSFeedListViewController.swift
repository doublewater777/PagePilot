//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Combine
import UIKit

/// Lists user-added OPDS feeds; add / edit / delete + tap to browse.
final class OPDSFeedListViewController: UIViewController {
    private let feedsRepo: OPDSFeedRepository
    private let library: LibraryService
    private var feeds: [OPDSFeed] = []
    private var subscriptions = Set<AnyCancellable>()
    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(feeds: OPDSFeedRepository, library: LibraryService) {
        self.feedsRepo = feeds
        self.library = library
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("opds_my_feeds", comment: "")
        view.backgroundColor = .systemGroupedBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )
        navigationItem.rightBarButtonItems = [
            editButtonItem,
            UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(presentAddFeedAlert))
        ]

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

        feedsRepo.observeAll()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                if case let .failure(error) = completion {
                    self?.alert(UserError(error))
                }
            } receiveValue: { [weak self] feeds in
                self?.feeds = feeds
                self?.tableView.reloadData()
                self?.updateBackgroundView()
            }
            .store(in: &subscriptions)
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
    }

    private func updateBackgroundView() {
        if feeds.isEmpty {
            let empty = OPDSEmptyView(
                title: NSLocalizedString("opds_empty_title", comment: ""),
                subtitle: NSLocalizedString("opds_empty_subtitle", comment: ""),
                buttonTitle: NSLocalizedString("opds_empty_add_button", comment: ""),
                action: { [weak self] in self?.presentAddFeedAlert() }
            )
            tableView.backgroundView = empty
        } else {
            tableView.backgroundView = nil
        }
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func presentAddFeedAlert() {
        presentFeedEditor(title: nil, url: nil) { [weak self] newTitle, newURL in
            Task {
                do {
                    try await self?.feedsRepo.add(OPDSFeed(title: newTitle, url: newURL))
                } catch {
                    await MainActor.run {
                        self?.alert(UserError(error))
                    }
                }
            }
        }
    }

    private func presentFeedEditor(title: String?, url: String?, onSave: @escaping (String, String) -> Void) {
        let alert = UIAlertController(
            title: NSLocalizedString("opds_add_title", comment: ""),
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { tf in
            tf.text = title
            tf.placeholder = NSLocalizedString("opds_feed_title_caption", comment: "")
        }
        alert.addTextField { tf in
            tf.text = url
            tf.placeholder = NSLocalizedString("opds_feed_url_caption", comment: "")
            tf.keyboardType = .URL
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }

        let save = UIAlertAction(title: NSLocalizedString("save_button", comment: ""), style: .default) { [weak alert, weak self] _ in
            guard let self, let alert = alert else { return }
            let t = (alert.textFields?[0].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let u = (alert.textFields?[1].text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            guard !t.isEmpty else {
                self.presentErrorAlert(message: NSLocalizedString("opds_error_enter_title", comment: ""))
                self.presentFeedEditor(title: t, url: u, onSave: onSave)
                return
            }
            guard let url = URL(string: u), url.scheme == "http" || url.scheme == "https" else {
                self.presentErrorAlert(message: NSLocalizedString("opds_error_enter_valid_url", comment: ""))
                self.presentFeedEditor(title: t, url: u, onSave: onSave)
                return
            }
            onSave(t, u)
        }
        let cancel = UIAlertAction(title: NSLocalizedString("cancel_button", comment: ""), style: .cancel)
        alert.addAction(save)
        alert.addAction(cancel)
        alert.preferredAction = save
        present(alert, animated: true)
    }

    private func presentErrorAlert(message: String) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: NSLocalizedString("ok_button", comment: ""), style: .cancel))
        present(a, animated: true)
    }
}

extension OPDSFeedListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { feeds.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let feed = feeds[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = feed.title
        content.secondaryText = feed.url
        content.image = UIImage(systemName: "books.vertical")
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let feed = feeds[indexPath.row]
        let browse = OPDSBrowseViewController(feed: feed, library: library)
        navigationController?.pushViewController(browse, animated: true)
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let delete = UIContextualAction(style: .destructive, title: NSLocalizedString("remove_button", comment: "")) { [weak self] _, _, done in
            guard let self, let id = self.feeds[indexPath.row].id else { done(false); return }
            Task {
                try? await self.feedsRepo.remove(id)
                done(true)
            }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        let feed = feeds[indexPath.row]
        presentFeedEditor(title: feed.title, url: feed.url) { [weak self] newTitle, newURL in
            guard let self, let id = feed.id else { return }
            Task {
                var updated = feed
                updated.title = newTitle
                updated.url = newURL
                try? await self.feedsRepo.update(updated)
                _ = id
            }
        }
    }
}

private final class OPDSEmptyView: UIView {
    init(title: String, subtitle: String, buttonTitle: String, action: @escaping () -> Void) {
        super.init(frame: .zero)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .preferredFont(forTextStyle: .title3)
        titleLabel.textAlignment = .center
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        subtitleLabel.textAlignment = .center
        let button = UIButton(type: .system)
        button.setTitle(buttonTitle, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel, button])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -20),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
        ])
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
}
