# PagePilot

A clean and powerful ebook reader for iOS and Mac Catalyst.

## Features

* **书架管理** - Import and organize your local EPUB, CBZ, and PDF books
* **OPDS 目录** - Browse and download books from public OPDS feeds like Project Gutenberg and Internet Archive
* **阅读器** - Support for pagination and scrolling modes with customizable themes (light, dark, sepia)
* **阅读进度** - Automatically tracks your reading position and progress
* **阅读统计** - View today's reading time and continue where you left off
* **Apple Watch 控制** - Control page turns directly from your Apple Watch

## Supported Formats

- EPUB 2 and 3 (reflowable and fixed layout)
- CBZ (comic book archives)
- PDF
- OPDS 1.x and 2.0 feeds

## Building

This project uses [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project.

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen)
2. Generate the Xcode project:
   ```sh
   make spm
   ```
3. Open `PagePilot.xcodeproj` in Xcode and run

> [!IMPORTANT]
> The Xcode project is not committed to the repository. Run `make spm` after pulling any changes.
> By default, `make spm` uses Readium `3.9.0` when this repository has no tags. To pin another Readium revision, run `make spm commit=<tag-or-sha>`.

## Mac App and Watch Page Turns

Open the `PagePilot` scheme and choose **My Mac (Mac Catalyst)** to build the Mac app. The Mac target shares the iPad reader and library; the Watch app and Live Activity extension are embedded only in iOS builds.

To control the Mac reader from Apple Watch:

1. Open PagePilot on Mac and iPhone, enable local network access, and connect both to the same Wi-Fi network.
2. On iPhone, open **Me → Watch Page Turn → Choose Nearby iPad / Mac** and select the Mac.
3. Open a book on Mac, then use PagePilot on the Apple Watch paired with that iPhone to turn pages.

Remote page turns require Pro access on both the iPhone and reader. The iPhone relays Watch commands to the selected reader. Keep the Mac reader window open; Mac does not pair directly with Apple Watch or create Live Activities.

## Signing

Provisioning profiles are not committed to the repository. For local development, set `RD_DEVELOPMENT_TEAM` to your Apple Developer Team ID before generating the project:

```sh
export RD_DEVELOPMENT_TEAM=<your-team-id>
make spm
```

Use Xcode's signing settings or your release automation to manage development, App Store, and Watch provisioning profiles locally.

The Mac Debug build uses a local **Mac Catalyst App Development** profile named `PagePilot Mac Catalyst Development`. Register the Mac using the **Provisioning UDID shown by Xcode** (on Apple silicon this can differ from the hardware UUID), include your existing Apple Development certificate and the `com.panyang.PagePilot` App ID, then install the profile locally. Profiles and private signing keys stay outside the repository. Release signing is configured separately for the chosen distribution channel.

## Terms of Use & Privacy Policy

The official terms of use and privacy policy pages are hosted in the `docs/` folder and deployed via GitHub Pages:

*   **Terms of Use (EULA)**: [https://pagepilot.doublewaterapps.com/terms.html](https://pagepilot.doublewaterapps.com/terms.html) (aligned with Apple's Standard EULA)
*   **Privacy Policy**: [https://pagepilot.doublewaterapps.com/privacy.html](https://pagepilot.doublewaterapps.com/privacy.html) (adheres to local-first privacy principles)

## License

This project is licensed under the BSD 3-Clause License. See [LICENSE](LICENSE) for details.

Copyright (c) 2026 PagePilot. All rights reserved.
Copyright (c) 2026 Readium Foundation. All rights reserved.
