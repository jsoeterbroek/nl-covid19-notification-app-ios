/*
 * Copyright (c) 2020 De Staat der Nederlanden, Ministerie van Volksgezondheid, Welzijn en Sport.
 *  Licensed under the EUROPEAN UNION PUBLIC LICENCE v. 1.2
 *
 *  SPDX-License-Identifier: EUPL-1.2
 */

@testable import EN
import Foundation
import SnapshotTesting
import XCTest

final class RequiresUpdateViewControllerTest: XCTestCase {
    private var viewController: RequiresUpdateViewController!

    override func setUp() {
        super.setUp()

        SnapshotTesting.record = false
        SnapshotTesting.diffTool = "ksdiff"

        viewController = RequiresUpdateViewController()
    }

    // MARK: - Tests

    func testSnapshotRequiresUpdateViewController() {
        assertSnapshot(matching: viewController, as: .image())
    }
}
