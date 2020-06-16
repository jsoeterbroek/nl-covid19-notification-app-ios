/*
 * Copyright (c) 2020 De Staat der Nederlanden, Ministerie van Volksgezondheid, Welzijn en Sport.
 *  Licensed under the EUROPEAN UNION PUBLIC LICENCE v. 1.2
 *
 *  SPDX-License-Identifier: EUPL-1.2
 */

import Foundation
import UIKit

final class ExposureController: ExposureControlling {

    init(mutableStateStream: MutableExposureStateStreaming,
         exposureManager: ExposureManaging?) {
        self.mutableStateStream = mutableStateStream
        self.exposureManager = exposureManager
    }

    // MARK: - ExposureControlling

    func activate() {
        guard let exposureManager = exposureManager else {
            updateStatusStream()
            return
        }

        exposureManager.activate { _ in
            self.updateStatusStream()
        }
    }

    func requestExposureNotificationPermission() {
        exposureManager?.setExposureNotificationEnabled(true) { _ in
            self.updateStatusStream()
        }
    }

    func requestPushNotificationPermission(_ completion: @escaping (() -> ())) {
        let uncc = UNUserNotificationCenter.current()

        uncc.getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized {
                DispatchQueue.main.async {
                    completion()
                }
            }
        }

        uncc.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
            DispatchQueue.main.async {
                completion()
            }
        }
    }

    func confirmExposureNotification() {
        // Not implemented yet
    }

    // MARK: - Private

    private func updateStatusStream() {
        guard let exposureManager = exposureManager else {
            mutableStateStream.update(state: .init(notified: isNotified, activeState: .inactive(.requiresOSUpdate)))
            return
        }

        let activeState: ExposureActiveState

        switch exposureManager.getExposureNotificationStatus() {
        case .active:
            activeState = .active
        case let .inactive(error) where error == .bluetoothOff:
            activeState = .inactive(.bluetoothOff)
        case let .inactive(error) where error == .disabled || error == .restricted:
            activeState = .inactive(.disabled)
        case let .inactive(error) where error == .notAuthorized:
            activeState = .notAuthorized
        case let .inactive(error) where error == .unknown:
            // Most likely due to code signing issues
            activeState = .inactive(.disabled)
        case .inactive:
            activeState = .inactive(.disabled)
        case .notAuthorized:
            activeState = .notAuthorized
        case .authorizationDenied:
            activeState = .authorizationDenied
        }

        mutableStateStream.update(state: .init(notified: isNotified, activeState: activeState))
    }

    private var isNotified: Bool {
        // TODO: Replace with right value
        return false
    }

    private let mutableStateStream: MutableExposureStateStreaming
    private let exposureManager: ExposureManaging?
}