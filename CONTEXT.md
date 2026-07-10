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

**Reading Achievement Dashboard**:
The simplified reading stats experience that presents progress, streaks, weekly rhythm, cumulative achievement, and recent trends in one calm overview.
_Avoid_: Detailed stats, analytics dashboard, report page

**Reading Cockpit**:
The home experience focused on helping the user resume reading quickly, with only lightweight reading context around the current book.
_Avoid_: Home dashboard, stats overview, feature launcher

**OPDS Feed**:
A remote catalog feed used to browse and download publications from external sources.
_Avoid_: Online library, feed URL

**Watch Page Turn**:
The Apple Watch remote-control capability that sends next-page or previous-page commands to the iPhone reader.
_Avoid_: Watch remote, remote control

**Volume Key Page Turn**:
An optional mode that maps iPhone hardware volume buttons to page-forward and page-backward actions during reading. Implemented via a hidden `MPVolumeView` + KVO on `outputVolume` with immediate reset. Runtime interception is gated by a decision chain: external audio playing → reader declares intent via `VolumeKeyBehaviorProvider` protocol → user preference for TTS mode. The active provider is registered in `viewWillAppear` and unregistered in `viewDidDisappear` of `VisualReaderViewController`; a `isKeyWindow` guard prevents interception when the reader is not the frontmost window.
_Avoid_: Volume button page turn, hardware key turn, remote volume page control

**Double Tap Page Turn**:
An optional mode that uses the Apple Watch system Double Tap gesture (index finger and thumb tap twice) on watchOS 11+ (Apple Watch Series 9 / Ultra 2 or later) to trigger a next-page command, equivalent to pressing the → button on the Watch remote screen. Implemented via `handGestureShortcut(.primaryAction, isEnabled: ...)` on the next-page button in `ContentView`. The modifier is always attached on watchOS 11+; the `isEnabled` flag (bound to the synced `doubleTapPageTurn` setting) controls whether Double Tap maps to the next-page action. This ensures stable registration across UI updates (e.g. progress refreshes from the reader). The Double Tap setting lives on the iPhone side in `WatchPageTurnSettings`, defaulting to on, and is synced to the Watch via `WCSession.updateApplicationContext`. Disabling it restores the system default Double Tap behavior (triggers the app's primary button, if any).
_Avoid_: Double tap, two-finger tap, double-click, DoubleTap

**Pro Access**:
The paid entitlement that unlocks limits such as the free bookshelf book count and deeper historical reading review.
_Avoid_: Subscription, premium mode, purchase state

**Pro Entitlement Card**:
The settings experience that presents active Pro Access as owned reading benefits rather than as a small status badge.
_Avoid_: Pro badge, membership label, upgrade banner

**ICP Filing**:
The public Chinese regulatory registration identifier shown for PagePilot's official website and app compliance information.
_Avoid_: Record number, license number, footer text
