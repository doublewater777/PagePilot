//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

enum OnboardingSamplePublication {
    static let fileName = "PagePilot Sample.md"

    static let markdown = """
    # PagePilot Sample

    The room was quiet enough to hear the soft turn of a page. Morning light rested on the table, and for a few minutes there was nothing to hurry toward. A book was open, a cup was cooling nearby, and the next paragraph waited without asking for attention.

    Reading often begins this simply. One line leads to another. A thought starts to take shape, then changes as the page moves forward. The world outside keeps its pace, but inside a book time can slow down just enough to notice what would otherwise pass by.

    Some readers sit at a desk. Some read while eating breakfast, holding a baby, stretching after a run, or following a recipe in the kitchen. The details change, but the small pleasure is the same: staying with the text without breaking the rhythm.

    ## The Next Page

    A good reading rhythm is easy to recognize. Your eyes reach the final sentence, your attention is already leaning ahead, and the next page arrives almost before you think about it. The motion should feel natural, not like leaving the book to operate a device.

    That is the idea behind PagePilot. The reader stays on the screen in front of you, while page turns can come from the device that is most convenient in the moment. You can keep reading on iPhone or iPad and, when you want, use Apple Watch as a small remote from your wrist.

    There is nothing special you need to do with this sample. Read a little, move forward, and see how the reader feels. If you have an Apple Watch nearby, this is also a safe place to try a page turn before opening one of your own books.

    ## A Few Minutes More

    Books do not need to be long to create a sense of distance. A few pages can be enough to leave the room for a moment. The important part is continuity: the feeling that the text remains available whenever you have a spare minute, without making you rebuild your reading setup each time.

    PagePilot keeps that experience local and straightforward. Your publications live in your library, your reading position follows the book, and the reader is ready whenever you return. This sample is only here so that you can explore those basics before importing anything of your own.

    When you are ready, bring in a publication from Files, Wi-Fi transfer, or an OPDS catalog. EPUB, PDF, Markdown, text, and other supported formats can use the same library and reader flow you are using now.

    ## Your Library

    The best sample is eventually the book you actually want to read. Maybe it is a novel you have been meaning to finish, a long article saved for later, a draft you want to review away from your desk, or a reference document you return to often.

    Import one when it is convenient. Until then, this short publication can stay in the library as a place to test reading controls and page turns. You can remove it later just like any other publication.

    For now, continue to the next page and keep reading at your own pace.
    """

    static func makeURL(fileManager: FileManager = .default) throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(fileName)
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
