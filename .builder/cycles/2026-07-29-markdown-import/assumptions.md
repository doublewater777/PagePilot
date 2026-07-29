# Assumptions

## Riskiest Assumption

Preserving common Markdown semantics through an offline Markdown → sanitized XHTML → EPUB conversion is sufficient for users to treat Markdown as a supported reading format; source fidelity beyond that is not required for the first increment.

## What Must Be True

- Import-time conversion can reuse the existing Readium EPUB Reader without a new reader module.
- A single generated EPUB reading-order document is acceptable for the first version.
- Unsupported local images are less harmful than unsafe or broken attachment access.
- Conversion remains fast enough for normal note and manuscript-sized Markdown files.

## Falsification

- Representative Markdown cannot be converted into valid XHTML that Readium opens.
- Formatting is lost to the point that the result reads like raw source.
- The additional parser materially destabilizes project generation or app builds.
- Importing Markdown introduces a security path for scripts or unsafe URL schemes.

## Existing Evidence

- PagePilot already converts TXT to EPUB at the Library boundary.
- The EPUB Reader already supports all required reading behavior after conversion.
- The existing project already depends on SwiftSoup, which can normalize and sanitize generated HTML.
