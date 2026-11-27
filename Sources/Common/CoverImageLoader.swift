//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import ImageIO
import SwiftUI
import UIKit

/// Loads local cover images asynchronously and caches them in memory.
///
/// Drop-in replacement for the synchronous `Data(contentsOf:)` call in
/// `SendBooksView.coverThumbnail(for:)`.  Thread-safe: all cache access is
/// serialised through the actor.
actor CoverImageLoader {

    // MARK: - Cache

    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    // MARK: - Public interface

    /// Returns the cached thumbnail for `bookId` if one exists, otherwise
    /// downsamples the file at `url` asynchronously, caches it, and returns it.
    /// Returns `nil` when the file is missing or its data cannot be decoded.
    func load(url: URL, bookId: Int64, maxPixelSize: Int = 512) async -> UIImage? {
        let key = "\(bookId)-\(maxPixelSize)-\(url.path)" as NSString

        // Cache hit — no I/O needed.
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard !Task.isCancelled else { return nil }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let image = UIImage(cgImage: thumbnail)

        let cost = thumbnail.bytesPerRow * thumbnail.height
        cache.setObject(image, forKey: key, cost: cost)

        return image
    }

    /// Removes all cached images (useful when the library changes on disk).
    func clearCache() {
        cache.removeAllObjects()
    }
}

// MARK: - Editorial Procedural Book Cover

/// Generates refined, literary hardcover artwork when a publication has no embedded cover image.
/// Shared by both UIKit (`LibraryViewController`) and SwiftUI (`HomeView`, `OutlineTableView`, `PublicationMetadataView`).
enum GeneratedBookCover {
    struct Palette: Equatable {
        let top: UIColor
        let bottom: UIColor
        let accent: UIColor
        let text: UIColor
        let secondaryText: UIColor
    }

    static let palettes: [Palette] = [
        // Deep Slate Indigo
        Palette(
            top: UIColor(red: 43 / 255, green: 62 / 255, blue: 92 / 255, alpha: 1),
            bottom: UIColor(red: 25 / 255, green: 38 / 255, blue: 60 / 255, alpha: 1),
            accent: UIColor(red: 196 / 255, green: 212 / 255, blue: 238 / 255, alpha: 0.45),
            text: UIColor(red: 245 / 255, green: 247 / 255, blue: 252 / 255, alpha: 1),
            secondaryText: UIColor(red: 198 / 255, green: 210 / 255, blue: 230 / 255, alpha: 0.85)
        ),
        // Celadon Pine
        Palette(
            top: UIColor(red: 36 / 255, green: 87 / 255, blue: 83 / 255, alpha: 1),
            bottom: UIColor(red: 22 / 255, green: 56 / 255, blue: 54 / 255, alpha: 1),
            accent: UIColor(red: 185 / 255, green: 226 / 255, blue: 219 / 255, alpha: 0.45),
            text: UIColor(red: 244 / 255, green: 250 / 255, blue: 248 / 255, alpha: 1),
            secondaryText: UIColor(red: 194 / 255, green: 223 / 255, blue: 218 / 255, alpha: 0.85)
        ),
        // Terracotta Cloth
        Palette(
            top: UIColor(red: 138 / 255, green: 66 / 255, blue: 54 / 255, alpha: 1),
            bottom: UIColor(red: 95 / 255, green: 42 / 255, blue: 34 / 255, alpha: 1),
            accent: UIColor(red: 242 / 255, green: 207 / 255, blue: 188 / 255, alpha: 0.45),
            text: UIColor(red: 253 / 255, green: 247 / 255, blue: 242 / 255, alpha: 1),
            secondaryText: UIColor(red: 236 / 255, green: 205 / 255, blue: 192 / 255, alpha: 0.85)
        ),
        // Warm Parchment & Ink
        Palette(
            top: UIColor(red: 238 / 255, green: 229 / 255, blue: 212 / 255, alpha: 1),
            bottom: UIColor(red: 222 / 255, green: 210 / 255, blue: 188 / 255, alpha: 1),
            accent: UIColor(red: 112 / 255, green: 88 / 255, blue: 62 / 255, alpha: 0.35),
            text: UIColor(red: 52 / 255, green: 41 / 255, blue: 30 / 255, alpha: 1),
            secondaryText: UIColor(red: 102 / 255, green: 84 / 255, blue: 64 / 255, alpha: 0.9)
        ),
        // Moss Olive
        Palette(
            top: UIColor(red: 73 / 255, green: 89 / 255, blue: 63 / 255, alpha: 1),
            bottom: UIColor(red: 48 / 255, green: 60 / 255, blue: 41 / 255, alpha: 1),
            accent: UIColor(red: 210 / 255, green: 224 / 255, blue: 196 / 255, alpha: 0.42),
            text: UIColor(red: 247 / 255, green: 249 / 255, blue: 243 / 255, alpha: 1),
            secondaryText: UIColor(red: 209 / 255, green: 220 / 255, blue: 198 / 255, alpha: 0.85)
        ),
        // Plum Dusk
        Palette(
            top: UIColor(red: 82 / 255, green: 56 / 255, blue: 86 / 255, alpha: 1),
            bottom: UIColor(red: 52 / 255, green: 34 / 255, blue: 56 / 255, alpha: 1),
            accent: UIColor(red: 222 / 255, green: 199 / 255, blue: 227 / 255, alpha: 0.42),
            text: UIColor(red: 250 / 255, green: 246 / 255, blue: 252 / 255, alpha: 1),
            secondaryText: UIColor(red: 219 / 255, green: 198 / 255, blue: 224 / 255, alpha: 0.85)
        ),
        // Espresso Gold
        Palette(
            top: UIColor(red: 74 / 255, green: 58 / 255, blue: 47 / 255, alpha: 1),
            bottom: UIColor(red: 46 / 255, green: 35 / 255, blue: 28 / 255, alpha: 1),
            accent: UIColor(red: 230 / 255, green: 198 / 255, blue: 146 / 255, alpha: 0.48),
            text: UIColor(red: 250 / 255, green: 245 / 255, blue: 236 / 255, alpha: 1),
            secondaryText: UIColor(red: 222 / 255, green: 203 / 255, blue: 175 / 255, alpha: 0.85)
        ),
        // Mist Blue Linen
        Palette(
            top: UIColor(red: 219 / 255, green: 228 / 255, blue: 239 / 255, alpha: 1),
            bottom: UIColor(red: 198 / 255, green: 212 / 255, blue: 228 / 255, alpha: 1),
            accent: UIColor(red: 52 / 255, green: 84 / 255, blue: 124 / 255, alpha: 0.35),
            text: UIColor(red: 30 / 255, green: 45 / 255, blue: 66 / 255, alpha: 1),
            secondaryText: UIColor(red: 68 / 255, green: 89 / 255, blue: 116 / 255, alpha: 0.9)
        ),
    ]

    /// Stable FNV-1a style hash so a book always gets the same hardcover palette across launches.
    static func palette(for title: String) -> Palette {
        var hash: UInt64 = 14695981039346656037
        for byte in title.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return palettes[Int(hash % UInt64(palettes.count))]
    }

    static func renderImage(
        title: String,
        author: String? = nil,
        size: CGSize
    ) -> UIImage {
        let safeSize = CGSize(width: max(60, size.width), height: max(90, size.height))
        let palette = palette(for: title)

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: safeSize, format: format)

        return renderer.image { context in
            let cg = context.cgContext
            let rect = CGRect(origin: .zero, size: safeSize)

            // 1. Soft vertical cloth gradient
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            if let gradient = CGGradient(
                colorsSpace: colorSpace,
                colors: [palette.top.cgColor, palette.bottom.cgColor] as CFArray,
                locations: [0, 1]
            ) {
                cg.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: safeSize.width * 0.25, y: safeSize.height),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }

            // 2. Book spine shadow + subtle crease highlight on the leading edge
            let spineWidth = max(5, safeSize.width * 0.055)
            cg.setFillColor(UIColor.black.withAlphaComponent(0.16).cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: spineWidth, height: safeSize.height))

            cg.setFillColor(UIColor.white.withAlphaComponent(0.18).cgColor)
            cg.fill(CGRect(x: spineWidth, y: 0, width: 1, height: safeSize.height))

            // 3. Editorial fine frame inside cover
            let insetX = spineWidth + max(8, safeSize.width * 0.075)
            let insetY = max(10, safeSize.height * 0.07)
            let frameRect = CGRect(
                x: insetX,
                y: insetY,
                width: max(20, safeSize.width - insetX - max(8, safeSize.width * 0.075)),
                height: max(20, safeSize.height - insetY * 2)
            )
            cg.setStrokeColor(palette.accent.cgColor)
            cg.setLineWidth(0.8)
            cg.stroke(frameRect)

            // 4. Small top decorative rule
            let contentPadding: CGFloat = max(8, frameRect.width * 0.1)
            let ruleWidth = min(22, frameRect.width * 0.26)
            let ruleRect = CGRect(
                x: frameRect.minX + contentPadding,
                y: frameRect.minY + contentPadding + 2,
                width: ruleWidth,
                height: 1.5
            )
            cg.setFillColor(palette.accent.cgColor)
            cg.fill(ruleRect)

            // 5. Title in editorial serif font
            let titleFontSize = max(11, min(19, safeSize.width * 0.125))
            let baseTitleFont = UIFont.systemFont(ofSize: titleFontSize, weight: .semibold)
            let serifDescriptor = baseTitleFont.fontDescriptor.withDesign(.serif) ?? baseTitleFont.fontDescriptor
            let titleFont = UIFont(descriptor: serifDescriptor, size: titleFontSize)

            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .left
            titleStyle.lineBreakMode = .byWordWrapping
            titleStyle.lineHeightMultiple = 1.15

            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: palette.text,
                .paragraphStyle: titleStyle,
            ]

            let titleRect = CGRect(
                x: frameRect.minX + contentPadding,
                y: ruleRect.maxY + max(8, safeSize.height * 0.055),
                width: frameRect.width - contentPadding * 2,
                height: frameRect.height * 0.56
            )
            (title as NSString).draw(
                with: titleRect,
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: titleAttrs,
                context: nil
            )

            // 6. Author near the bottom edge of the frame
            let cleanAuthor = author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !cleanAuthor.isEmpty, cleanAuthor.lowercased() != "unknown" {
                let authorFontSize = max(8.5, min(11.5, safeSize.width * 0.075))
                let authorFont = UIFont.systemFont(ofSize: authorFontSize, weight: .medium)
                let authorStyle = NSMutableParagraphStyle()
                authorStyle.alignment = .left
                authorStyle.lineBreakMode = .byTruncatingTail

                let authorAttrs: [NSAttributedString.Key: Any] = [
                    .font: authorFont,
                    .foregroundColor: palette.secondaryText,
                    .paragraphStyle: authorStyle,
                ]
                let authorHeight = authorFont.lineHeight * 1.4
                let authorRect = CGRect(
                    x: frameRect.minX + contentPadding,
                    y: frameRect.maxY - contentPadding - authorHeight,
                    width: frameRect.width - contentPadding * 2,
                    height: authorHeight
                )
                (cleanAuthor as NSString).draw(
                    with: authorRect,
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    attributes: authorAttrs,
                    context: nil
                )
            }

            // 7. Subtle outer hairline border so light covers stay crisp on light backgrounds
            cg.setStrokeColor(UIColor.black.withAlphaComponent(0.08).cgColor)
            cg.setLineWidth(1)
            cg.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        }
    }
}

/// SwiftUI view matching `GeneratedBookCover` for Home, Outline, and Metadata surfaces.
struct GeneratedBookCoverView: View {
    let title: String
    var author: String? = nil

    private var palette: GeneratedBookCover.Palette {
        GeneratedBookCover.palette(for: title)
    }

    private var displayAuthor: String? {
        let trimmed = author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed.lowercased() != "unknown" else { return nil }
        return trimmed
    }

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let spineWidth = max(4, w * 0.055)
            let frameInsetX = max(6, w * 0.075)
            let frameInsetY = max(7, proxy.size.height * 0.07)

            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [Color(uiColor: palette.top), Color(uiColor: palette.bottom)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                // Book spine crease
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.black.opacity(0.16))
                        .frame(width: spineWidth)
                    Rectangle()
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 1)
                    Spacer(minLength: 0)
                }

                // Editorial inner frame + typography (compact monogram for tiny thumbnails)
                if w < 58 {
                    let initial = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
                    ZStack {
                        Rectangle()
                            .stroke(Color(uiColor: palette.accent), lineWidth: 0.75)

                        Text(initial.isEmpty ? "P" : initial)
                            .font(.system(size: max(14, w * 0.36), weight: .semibold, design: .serif))
                            .foregroundStyle(Color(uiColor: palette.text))
                    }
                    .padding(.leading, spineWidth + max(4, w * 0.08))
                    .padding(.trailing, max(4, w * 0.08))
                    .padding(.vertical, max(5, proxy.size.height * 0.08))
                } else {
                    VStack(alignment: .leading, spacing: max(5, w * 0.06)) {
                        Rectangle()
                            .fill(Color(uiColor: palette.accent))
                            .frame(width: min(22, w * 0.24), height: 1.5)

                        Text(title)
                            .font(.system(size: max(9, min(17, w * 0.118)), weight: .semibold, design: .serif))
                            .foregroundStyle(Color(uiColor: palette.text))
                            .lineLimit(4)
                            .minimumScaleFactor(0.75)
                            .multilineTextAlignment(.leading)

                        Spacer(minLength: 4)

                        if let displayAuthor {
                            Text(displayAuthor)
                                .font(.system(size: max(8, min(11, w * 0.085)), weight: .medium))
                                .foregroundStyle(Color(uiColor: palette.secondaryText))
                                .lineLimit(1)
                        }
                    }
                    .padding(max(7, w * 0.085))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .overlay(
                        Rectangle()
                            .stroke(Color(uiColor: palette.accent), lineWidth: 0.8)
                    )
                    .padding(.leading, spineWidth + frameInsetX)
                    .padding(.trailing, frameInsetX)
                    .padding(.vertical, frameInsetY)
                }
            }
        }
    }
}
