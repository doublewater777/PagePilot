//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import UIKit

protocol PublicationMenuViewControllerDelegate: AnyObject {
    func metadataButtonTapped()
    func removeButtonTapped()
    func cancelButtonTapped()
}

class PublicationMenuViewController: UIViewController {
    weak var delegate: PublicationMenuViewControllerDelegate?

    @IBOutlet var metadataButton: UIButton!
    @IBOutlet var removeButton: UIButton!
    @IBOutlet var cancelButton: UIButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        metadataButton.setTitle(NSLocalizedString("metadata_button", comment: ""), for: .normal)
        removeButton.setTitle(NSLocalizedString("remove_button", comment: ""), for: .normal)
        cancelButton.setTitle(NSLocalizedString("cancel_button", comment: ""), for: .normal)
    }

    @IBAction func metadataButtonTapped(_ sender: Any) {
        delegate?.metadataButtonTapped()
    }

    @IBAction func removeButtonTapped(_ sender: Any) {
        delegate?.removeButtonTapped()
    }

    @IBAction func cancelButtonTapped(_ sender: Any) {
        delegate?.cancelButtonTapped()
    }
}
