//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import SwiftUI

struct EditOPDSCatalogView: View {
    @State var catalog: OPDSCatalog
    var onSave: (OPDSCatalog) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var showErrorAlert = false
    @State private var errorTitle = ""
    @State private var errorMessage = ""
    @State private var urlString: String

    init(
        catalog: OPDSCatalog,
        onSave: @escaping (OPDSCatalog) -> Void
    ) {
        self.catalog = catalog
        self.onSave = onSave
        urlString = catalog.url.absoluteString
    }

    var body: some View {
        NavigationView {
            formContent
        }
    }

    private var formContent: some View {
        Form {
            Section(header: Text(NSLocalizedString("opds_feed_title_caption", comment: ""))) {
                TextField(NSLocalizedString("opds_feed_title_caption", comment: ""), text: $catalog.title)
                TextField(NSLocalizedString("opds_feed_url_caption", comment: ""), text: $urlString)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
        }
        .navigationBarItems(
            leading: Button(NSLocalizedString("cancel_button", comment: "")) {
                dismiss()
            },
            trailing: Button(NSLocalizedString("confirm_button", comment: "")) {
                validateAndSave()
            }
        )
        .alert(isPresented: $showErrorAlert) {
            Alert(
                title: Text(errorTitle),
                message: Text(errorMessage),
                dismissButton: .default(Text(NSLocalizedString("ok_button", comment: "")))
            )
        }
    }

    private func validateAndSave() {
        let trimmedTitle = catalog.title.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedTitle.isEmpty {
            errorTitle = NSLocalizedString("opds_error_title_required", comment: "")
            errorMessage = NSLocalizedString("opds_error_enter_title", comment: "")
            showErrorAlert = true
            return
        }

        if
            let url = URL(string: urlString),
            url.scheme != nil,
            url.host != nil
        {
            catalog.url = url
            onSave(catalog)
            dismiss()
        } else {
            errorTitle = NSLocalizedString("opds_error_invalid_url", comment: "")
            errorMessage = NSLocalizedString("opds_error_enter_valid_url", comment: "")
            showErrorAlert = true
        }
    }
}

#Preview {
    EditOPDSCatalogView(
        catalog: OPDSCatalog(
            id: UUID().uuidString,
            title: "OPDS 2.0 Test Catalog",
            url: URL(string: "https://test.opds.io/2.0/home.json")!
        ),
        onSave: { _ in }
    )
}
