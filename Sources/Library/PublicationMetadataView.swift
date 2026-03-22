//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ReadiumShared
import SwiftUI

struct PublicationMetadataView: View {
    var publication: Publication

    var body: some View {
        NavigationView {
            List {
                Section(NSLocalizedString("metadata_publication", comment: "")) {
                    let title = publication.metadata.title ?? NSLocalizedString("metadata_no_title", comment: "")
                    FieldRow(title: NSLocalizedString("metadata_title", comment: ""), content: title)

                    if let id = publication.metadata.identifier {
                        FieldRow(title: NSLocalizedString("metadata_identifier", comment: ""), content: id)
                    }

                    let authors = publication.metadata.authors
                    if !authors.isEmpty {
                        FieldRow(
                            singleTitle: NSLocalizedString("metadata_author", comment: ""),
                            pluralTitle: NSLocalizedString("metadata_authors", comment: ""),
                            content: authors.map(\.name)
                        )
                    }

                    let publishers = publication.metadata.publishers
                    if !publishers.isEmpty {
                        FieldRow(
                            singleTitle: NSLocalizedString("metadata_publisher", comment: ""),
                            pluralTitle: NSLocalizedString("metadata_publishers", comment: ""),
                            content: publishers.map(\.name)
                        )
                    }

                    if let published = publication.metadata.published {
                        FieldRow(
                            title: NSLocalizedString("metadata_publication_date", comment: ""),
                            content: published.formatted(date: .long, time: .omitted)
                        )
                    }
                }

                AccessibilityMetadataView(
                    guide: AccessibilityMetadataDisplayGuide(
                        publication: publication
                    )
                )
            }
            .navigationTitle(NSLocalizedString("metadata_title", comment: ""))
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

struct AccessibilityMetadataView: View {
    var guide: AccessibilityMetadataDisplayGuide

    /// Indicates whether accessibility field with no declared information
    /// should always be visible.
    @State private var alwaysDisplayFields: Bool = false

    /// Indicates whether accessibility claims are displayed in their full
    /// descriptive statements.
    @State private var showDescriptiveStatements: Bool = false

    var body: some View {
        Section(NSLocalizedString("metadata_accessibility_claims", comment: "")) {
            Toggle(NSLocalizedString("metadata_show_fields_no_metadata", comment: ""), isOn: $alwaysDisplayFields)
            Toggle(NSLocalizedString("metadata_show_descriptive_statements", comment: ""), isOn: $showDescriptiveStatements)

            ForEach(guide.fields, id: \.id) { field in
                if shouldShow(field) {
                    FieldRow(title: field.localizedTitle) {
                        ForEach(field.statements) { statement in
                            HStack(alignment: .firstTextBaseline) {
                                Text(" •")
                                Text(AttributedString(statement.localizedString(descriptive: showDescriptiveStatements)))
                            }
                        }
                    }
                }
            }
        }
    }

    private func shouldShow(_ field: any AccessibilityDisplayField) -> Bool {
        !field.statements.isEmpty && (alwaysDisplayFields || field.shouldDisplay)
    }
}

private struct FieldRow<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
                .padding(.bottom, 2)
            content
        }
    }
}

extension FieldRow where Content == Text {
    init(title: String, content: String) {
        self.title = title
        self.content = Text(content)
    }

    init(singleTitle: String, pluralTitle: String, content: [String]) {
        title = content.count > 1 ? pluralTitle : singleTitle
        self.content = Text(content.joined(separator: ", "))
    }
}

#Preview {
    PublicationMetadataView(publication: Publication(
        manifest: Manifest(
            metadata: Metadata(
                identifier: "urn:isbn:1503222683",
                title: "Alice's Adventures in Wonderland",
                authors: [Contributor(name: "Lewis Carroll"), Contributor(name: "Other Author")]
            )
        )
    ))
}
