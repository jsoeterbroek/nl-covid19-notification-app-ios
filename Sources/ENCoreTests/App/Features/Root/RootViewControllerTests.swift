/*
 * Copyright (c) 2020 De Staat der Nederlanden, Ministerie van Volksgezondheid, Welzijn en Sport.
 *  Licensed under the EUROPEAN UNION PUBLIC LICENCE v. 1.2
 *
 *  SPDX-License-Identifier: EUPL-1.2
 */

@testable import ENCore
import Foundation
import XCTest

final class RootViewControllerTests: TestCase {
    private var viewController: RootViewController!
    private let router = RootRoutingMock()

    override func setUp() {
        super.setUp()

        viewController = RootViewController(theme: theme)
        viewController.router = router
    }

    func test_didCompleteOnboarding_callsDetachOnboardingAndRouteToMain() {
        XCTAssertEqual(router.detachOnboardingAndRouteToMainCallCount, 0)

        viewController.didCompleteOnboarding()

        XCTAssertEqual(router.detachOnboardingAndRouteToMainCallCount, 1)
    }
}
