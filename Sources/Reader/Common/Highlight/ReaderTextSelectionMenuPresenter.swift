import ReadiumNavigator
import ReadiumShared
import UIKit
import WebKit

@MainActor
final class ReaderTextSelectionMenuPresenter: NSObject, UIEditMenuInteractionDelegate {
    private weak var hostView: UIView?
    private weak var viewController: EPUBViewController?
    private var interaction: UIEditMenuInteraction?

    func attach(to view: UIView, viewController: EPUBViewController) {
        hostView = view
        self.viewController = viewController

        if let interaction {
            view.removeInteraction(interaction)
        }

        let interaction = UIEditMenuInteraction(delegate: self)
        view.addInteraction(interaction)
        self.interaction = interaction
    }

    func present(selection: Selection) {
        guard let hostView, let frame = selection.frame else { return }

        let sourcePoint = CGPoint(x: frame.midX, y: frame.minY)
        let configuration = UIEditMenuConfiguration(identifier: nil, sourcePoint: sourcePoint)
        interaction?.presentEditMenu(with: configuration)
    }

    func editMenuInteraction(
        _ interaction: UIEditMenuInteraction,
        menuFor configuration: UIEditMenuConfiguration,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        guard let viewController else { return nil }

        var secondaryActions: [UIAction] = [
            UIAction(
                title: NSLocalizedString("reader_lookup", comment: ""),
                image: UIImage(systemName: "character.book.closed")
            ) { _ in
                viewController.performWebViewAction(["lookup", "_lookup:", "define:", "_define:"])
            },
            UIAction(
                title: NSLocalizedString("reader_translate", comment: ""),
                image: UIImage(systemName: "translate")
            ) { _ in
                viewController.performWebViewAction(["translate:", "_translate:"])
            },
        ]

        if !viewController.publication.isProtected {
            secondaryActions.append(
                UIAction(
                    title: NSLocalizedString("reader_share", comment: ""),
                    image: UIImage(systemName: "square.and.arrow.up")
                ) { _ in
                    viewController.shareCurrentSelection()
                }
            )
        }

        let moreMenu = UIMenu(
            title: "",
            image: UIImage(systemName: "chevron.right"),
            options: [],
            children: secondaryActions
        )

        return UIMenu(children: [
            UIAction(
                title: NSLocalizedString("reader_highlight", comment: ""),
                image: UIImage(systemName: "highlighter")
            ) { _ in
                viewController.highlightSelection()
            },
            UIAction(
                title: NSLocalizedString("reader_add_note", comment: ""),
                image: UIImage(systemName: "note.text.badge.plus")
            ) { _ in
                viewController.addNoteToSelection()
            },
            UIAction(
                title: NSLocalizedString("reader_copy", comment: ""),
                image: UIImage(systemName: "doc.on.doc")
            ) { _ in
                Task {
                    await viewController.copySelection()
                }
            },
            moreMenu,
        ])
    }
}