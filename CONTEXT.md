# PagePilot

PagePilot is a local-first ebook reader for iOS with Apple Watch page-turn control. This glossary defines the product language agents should use when planning issues, tests, diagnostics, and architecture work.

## Language

**Book**:
A user's saved reading item in the bookshelf, including metadata, cover, stored location, reading progress, and per-book preferences.
_Avoid_: Item, asset, record

**Publication**:
A readable digital work opened through Readium, such as an EPUB, CBZ, PDF, or OPDS-discovered resource.
_Avoid_: File, document, ebook

**Bookshelf**:
The user's local collection of imported books.
_Avoid_: Library grid, collection view, catalog

**Library**:
The app area and service boundary responsible for importing, listing, opening, and removing books from the bookshelf.
_Avoid_: Shelf manager, book manager

**Reader**:
The app area responsible for presenting an opened publication for reading.
_Avoid_: Viewer, navigator UI

**Reading Progress**:
The saved reading position and total progression for a book.
_Avoid_: Bookmark, cursor, page state

**Reading Stats**:
Aggregated reading activity such as today's reading time and continue-reading state.
_Avoid_: Analytics, metrics

**OPDS Feed**:
A remote catalog feed used to browse and download publications from external sources.
_Avoid_: Online library, feed URL

**Watch Page Turn**:
The Apple Watch remote-control capability that sends next-page or previous-page commands to the iPhone reader.
_Avoid_: Watch remote, remote control

**Pro Access**:
The paid entitlement that unlocks limits such as the free bookshelf book count.
_Avoid_: Subscription, premium mode, purchase state
