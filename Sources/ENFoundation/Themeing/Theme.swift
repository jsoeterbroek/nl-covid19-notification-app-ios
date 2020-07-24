/*
 * Copyright (c) 2020 De Staat der Nederlanden, Ministerie van Volksgezondheid, Welzijn en Sport.
 *  Licensed under the EUROPEAN UNION PUBLIC LICENCE v. 1.2
 *
 *  SPDX-License-Identifier: EUPL-1.2
 */

import Foundation
import UIKit

public protocol Theme: AnyObject {
    var fonts: Fonts { get }
    var colors: Colors { get }

    init()
}

public typealias ThemeColor = KeyPath<Colors, UIColor>

public protocol Themeable {
    var theme: Theme { get }
}

public protocol ReusableThemable: Themeable {
    func configure(with theme: Theme)
}

public final class ENTheme: Theme {
    public let fonts: Fonts
    public let colors: Colors

    public init() {
        self.fonts = ENFonts()
        self.colors = ENColors()
    }
}
