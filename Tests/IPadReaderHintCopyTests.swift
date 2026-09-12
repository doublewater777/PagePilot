import Foundation
import XCTest

final class IPadReaderHintCopyTests: XCTestCase {
    func testIPadReaderHintCopyIsLocalizedForSupportedLanguages() throws {
        let expected: [String: (title: String, detail: String)] = [
            "en": (
                title: "Turn Pages with Apple Watch",
                detail: "While reading, PagePilot shows controls on your paired Apple Watch. Tap the Live Activity to open the Watch app."
            ),
            "zh-Hans": (
                title: "用 Apple Watch 翻页",
                detail: "阅读时，已配对的 Apple Watch 会显示阅读控制；点实时活动即可打开 PagePilot。"
            ),
            "de": (
                title: "Mit der Apple Watch umblättern",
                detail: "Beim Lesen zeigt PagePilot Steuerungen auf der gekoppelten Apple Watch. Tippe auf die Live-Aktivität, um die Watch-App zu öffnen."
            ),
            "es": (
                title: "Pasa páginas con el Apple Watch",
                detail: "Mientras lees, PagePilot muestra controles en tu Apple Watch emparejado. Toca la Actividad en Vivo para abrir la app del Watch."
            ),
            "fr": (
                title: "Tournez les pages avec l’Apple Watch",
                detail: "Pendant la lecture, PagePilot affiche les commandes sur votre Apple Watch jumelée. Touchez l’activité en direct pour ouvrir l’app Watch."
            ),
        ]

        for (language, strings) in expected {
            let bundleURL = try XCTUnwrap(
                Bundle.main.url(forResource: language, withExtension: "lproj"),
                "Missing localization bundle for \(language)"
            )
            let bundle = try XCTUnwrap(Bundle(url: bundleURL))

            XCTAssertEqual(
                bundle.localizedString(forKey: "onboarding_ipad_reader_hint_title", value: nil, table: nil),
                strings.title,
                "\(language) title"
            )
            XCTAssertEqual(
                bundle.localizedString(forKey: "onboarding_ipad_reader_hint_detail", value: nil, table: nil),
                strings.detail,
                "\(language) detail"
            )
        }
    }
}
