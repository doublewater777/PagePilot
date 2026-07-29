# Markdown Import

Linked stage: `01-hypothesis`

## User Problem

PagePilot's local-first readers may keep long-form notes, drafts, and exported reading material as Markdown. Today a `.md` or `.markdown` publication can be selected during onboarding, but Readium rejects it as an unsupported format, so the core import → open → read action breaks.

## Target User

Apple ecosystem readers who already own local Markdown reading material and want to read it in the same bookshelf and Reader used for EPUB, PDF, CBZ, and TXT.

## Desired Behavior Change

A user can import a Markdown publication from Files, Open In/share, onboarding, or Wi-Fi transfer and immediately read the formatted content in PagePilot.

## Success

- `.md` and `.markdown` files import and open as readable EPUB-backed Books.
- Common authoring constructs remain visibly distinct: headings, paragraphs, emphasis, strong text, lists, block quotes, code, links, rules, and tables.
- Malicious active HTML does not survive conversion.
- Existing TXT and publication imports do not regress.

## Out of Scope

- Editing Markdown.
- Live synchronization with the source file.
- Bundling sibling/local images or attachments.
- Executing embedded HTML, JavaScript, or remote code.
- Perfect GitHub UI parity or syntax highlighting.
