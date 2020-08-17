/*
 * Copyright (c) 2020 De Staat der Nederlanden, Ministerie van Volksgezondheid, Welzijn en Sport.
 *  Licensed under the EUROPEAN UNION PUBLIC LICENCE v. 1.2
 *
 *  SPDX-License-Identifier: EUPL-1.2
 */

import Combine
@testable import ENCore
import Foundation
import SnapshotTesting
import XCTest

final class MoreInformationViewControllerTests: TestCase {

    private var viewController: MoreInformationViewController!
    private let listener = MoreInformationListenerMock()
    private let tableViewDelegate = UITableViewDelegateMock()
    private let tableViewDataSource = UITableViewDataSourceMock()

    // MARK: - Setup

    override func setUp() {
        super.setUp()

        recordSnapshots = false

        viewController = MoreInformationViewController(listener: listener,
                                                       theme: theme,
                                                       testPhaseStream: Just(false).eraseToAnyPublisher(),
                                                       bundleInfoDictionary: nil)
    }

    // MARK: - Tests

    func test_snapshot_moreInformationViewController() {
        snapshots(matching: viewController)
    }

    func test_snapshot_moreInformationViewController_testVersion() {
        let viewController = MoreInformationViewController(listener: listener,
                                                           theme: theme,
                                                           testPhaseStream: Just(true).eraseToAnyPublisher(), bundleInfoDictionary: ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "12345"])

        self.snapshots(matching: viewController)
    }

    func test_didSelectItem_about() {
        viewController.didSelect(identifier: .about)

        XCTAssertEqual(listener.moreInformationRequestsAboutCallCount, 1)
    }

    func test_didSelectItem_share() {
        viewController.didSelect(identifier: .share)

        XCTAssertEqual(listener.moreInformationRequestsSharingCallCount, 1)
    }

    func test_didSelectItem_infected() {
        viewController.didSelect(identifier: .infected)

        XCTAssertEqual(listener.moreInformationRequestsInfectedCallCount, 1)
    }

    func test_didSelectItem_receivedNotification() {
        viewController.didSelect(identifier: .receivedNotification)

        XCTAssertEqual(listener.moreInformationRequestsReceivedNotificationCallCount, 1)
    }

    func test_didSelectItem_requestTest() {
        viewController.didSelect(identifier: .requestTest)

        XCTAssertEqual(listener.moreInformationRequestsRequestTestCallCount, 1)
    }
}
