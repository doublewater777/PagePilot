//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import UIKit

enum ScreenOrientation: String {
    case landscape
    case portrait

    static var current: ScreenOrientation {
        let orientation = UIDevice.current.orientation
        if orientation.isLandscape {
            return .landscape
        } else if orientation.isPortrait {
            return .portrait
        }
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
           let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first {
            return window.bounds.width > window.bounds.height ? .landscape : .portrait
        }
        return .portrait
    }
}
