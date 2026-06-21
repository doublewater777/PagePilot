import ReadiumNavigator

enum ReaderEditingActions {
    /// Native actions kept for Readium copy-rights checks. Custom items use UIEditMenuInteraction.
    static let epubConfiguration: [EditingAction] = [
        .copy, .share, .lookup, .translate,
    ]
}