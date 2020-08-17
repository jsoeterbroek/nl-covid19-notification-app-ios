/*
 * Copyright (c) 2020 De Staat der Nederlanden, Ministerie van Volksgezondheid, Welzijn en Sport.
 *  Licensed under the EUROPEAN UNION PUBLIC LICENCE v. 1.2
 *
 *  SPDX-License-Identifier: EUPL-1.2
 */

import Combine
import ENFoundation
import Foundation
import UIKit

private struct ExposureKeySetDetectionResult {
    let keySetHolder: ExposureKeySetHolder
    let processDate: Date?
    let isValid: Bool
}

private struct ExposureDetectionResult {
    let keySetDetectionResults: [ExposureKeySetDetectionResult]
    let exposureSummary: ExposureDetectionSummary?
    let exposureReport: ExposureReport?
}

struct ExposureReport: Codable {
    let date: Date
}

#if USE_DEVELOPER_MENU || DEBUG

    struct ProcessExposureKeySetsDataOperationOverrides {
        static var respectMaximumDailyKeySets = true
    }

#endif

final class ProcessExposureKeySetsDataOperation: ExposureDataOperation, Logging {
    // the detectExposures API is limited to 15 keysets or calls a day
    // https://developer.apple.com/documentation/exposurenotification/enmanager/3586331-detectexposures
    private let maximumDailyOfKeySetsToProcess = 15 // iOS 13.5
    private let maximumDailyExposureDetectionAPICalls = 15 // iOS 13.6+

    init(networkController: NetworkControlling,
         storageController: StorageControlling,
         exposureManager: ExposureManaging,
         exposureKeySetsStorageUrl: URL,
         configuration: ExposureConfiguration,
         userNotificationCenter: UserNotificationCenter) {
        self.networkController = networkController
        self.storageController = storageController
        self.exposureManager = exposureManager
        self.exposureKeySetsStorageUrl = exposureKeySetsStorageUrl
        self.configuration = configuration
        self.userNotificationCenter = userNotificationCenter
    }

    func execute() -> AnyPublisher<(), ExposureDataError> {
        self.logDebug("--- START PROCESSING KEYSETS ---")

        // get all keySetHolders that have not been processed before
        let exposureKeySetHolders = getStoredKeySetsHolders()
            // filter out already processed ones
            .filter { $0.processed == false }

        if exposureKeySetHolders.count > 0 {
            logDebug("Processing KeySets: \(exposureKeySetHolders.map { $0.identifier }.joined(separator: "\n"))")
        } else {
            // keep processing to make sure lastProcessDate is updated
            logDebug("No additional keysets to process")
        }

        let markKeySetsAsProcessedFirstTimeOnly = determineSkipAllExposureSetsForTheFirstTime()
        logDebug("Is processing for the first time: \(markKeySetsAsProcessedFirstTimeOnly)")

        // Batch detect exposures
        return detectExposures(for: exposureKeySetHolders, fakeProcessKeySets: markKeySetsAsProcessedFirstTimeOnly)
            // persist keySetHolders in local storage to remember which ones have been processed correctly
            .flatMap(self.persistResult(_:))
            // create an exposureReport and trigger a local notification
            .flatMap(self.createReportAndTriggerNotification(forResult:))
            // persist the ExposureReport
            .flatMap(self.persist(exposureReport:))
            // update last processing date
            .flatMap(self.updateLastProcessingDate)
            // remove all blobs for all keySetHolders - successful ones are processed and
            // should not be processed again. Failed ones should be downloaded again and
            // have already been removed from the list of keySetHolders in localStorage by persistResult(_:)
            .handleEvents(receiveOutput: removeBlobs(forResult:))
            // ignore result
            .map { _ in () }
            .handleEvents(
                receiveCompletion: { _ in self.logDebug("--- END PROCESSING KEYSETS ---") },
                receiveCancel: { self.logDebug("--- PROCESSING KEYSETS CANCELLED ---") }
            )
            .share()
            .eraseToAnyPublisher()
    }

    // MARK: - Private

    /// Retrieves all stores keySetHolders from local storage
    private func getStoredKeySetsHolders() -> [ExposureKeySetHolder] {
        return storageController.retrieveObject(identifiedBy: ExposureDataStorageKey.exposureKeySetsHolders) ?? []
    }

    /// Verifies whether the KeySetHolder URLs point to valid files
    private func verifyLocalFileUrl(forKeySetsHolder keySetHolder: ExposureKeySetHolder) -> Bool {
        var isDirectory = ObjCBool(booleanLiteral: false)

        // verify whether sig and bin files are present
        guard FileManager.default.fileExists(atPath: signatureFileUrl(forKeySetHolder: keySetHolder).path,
                                             isDirectory: &isDirectory), isDirectory.boolValue == false else {
            return false
        }

        guard FileManager.default.fileExists(atPath: binaryFileUrl(forKeySetHolder: keySetHolder).path,
                                             isDirectory: &isDirectory), isDirectory.boolValue == false else {
            return false
        }

        return true
    }

    /// Returns ExposureKeySetDetectionResult in case of a success, or in case of an error that's
    /// not related to the framework's inactiveness. When an error is thrown from here exposure detection
    /// should be stopped until the user enables the framework
    private func detectExposures(for keySetHolders: [ExposureKeySetHolder], fakeProcessKeySets: Bool) -> AnyPublisher<ExposureDetectionResult, ExposureDataError> {

        guard fakeProcessKeySets == false else {
            logDebug("Fake process all keysets")

            // mark all keysets as processed
            let keySetDetectionResults = keySetHolders.map { keySetHolder in
                return ExposureKeySetDetectionResult(keySetHolder: keySetHolder,
                                                     processDate: Date(),
                                                     isValid: true)
            }

            let detectionResult = ExposureDetectionResult(keySetDetectionResults: keySetDetectionResults,
                                                          exposureSummary: nil,
                                                          exposureReport: nil)

            return Just(detectionResult)
                .setFailureType(to: ExposureDataError.self)
                .eraseToAnyPublisher()
        }

        // filter out keysets with missing local files
        let validKeySetHolders = keySetHolders.filter(self.verifyLocalFileUrl(forKeySetsHolder:))
        let invalidKeySetHolders = keySetHolders.filter { keySetHolder in
            !validKeySetHolders.contains { $0.identifier == keySetHolder.identifier }
        }

        logDebug("Invalid KeySetHolders: \(invalidKeySetHolders.map { $0.identifier })")
        logDebug("Valid KeySetHolders: \(validKeySetHolders.map { $0.identifier })")

        // create results for the keySetHolders with missing local files
        let invalidKeySetHolderResults = invalidKeySetHolders.map { keySetHolder in
            return ExposureKeySetDetectionResult(keySetHolder: keySetHolder,
                                                 processDate: nil,
                                                 isValid: false)
        }

        // get most recent keySetHolders and limit by maxNumber
        let keySetHoldersToProcess = selectKeySetHoldersToProcess(from: validKeySetHolders)

        guard !keySetHoldersToProcess.isEmpty else {
            logDebug("Nothing left to process")

            // nothing (left) to process, return an empty summary
            let validKeySetHolderResults = validKeySetHolders.map { keySetHolder in
                return ExposureKeySetDetectionResult(keySetHolder: keySetHolder,
                                                     processDate: nil,
                                                     isValid: true)
            }

            return Just(ExposureDetectionResult(keySetDetectionResults: validKeySetHolderResults + invalidKeySetHolderResults,
                                                exposureSummary: nil,
                                                exposureReport: nil))
                .setFailureType(to: ExposureDataError.self)
                .eraseToAnyPublisher()
        }

        let diagnosisKeyUrls = keySetHoldersToProcess.flatMap {
            [signatureFileUrl(forKeySetHolder: $0), binaryFileUrl(forKeySetHolder: $0)]
        }

        logDebug("Detect exposures for keySets: \(keySetHoldersToProcess.map { $0.identifier })")

        let executeExposureDetection: AnyPublisher<ExposureDetectionResult, ExposureDataError> = Deferred {
            Future { promise in
                self.exposureManager.detectExposures(configuration: self.configuration,
                                                     diagnosisKeyURLs: diagnosisKeyUrls) { result in
                    switch result {
                    case let .success(summary):
                        self.logDebug("Successfully detected exposures: \(String(describing: summary))")

                        let validKeySetHolderResults = keySetHoldersToProcess.map { keySetHolder in
                            return ExposureKeySetDetectionResult(keySetHolder: keySetHolder,
                                                                 processDate: Date(),
                                                                 isValid: true)
                        }

                        let keySetHolderResults = invalidKeySetHolderResults + validKeySetHolderResults
                        let result = ExposureDetectionResult(keySetDetectionResults: keySetHolderResults,
                                                             exposureSummary: summary,
                                                             exposureReport: nil)

                        promise(.success(result))
                    case let .failure(error):
                        self.logDebug("Failure when detecting exposures: \(error)")

                        switch error {
                        case .bluetoothOff, .disabled, .notAuthorized, .restricted:
                            promise(.failure(error.asExposureDataError))
                        case .internalTypeMismatch:
                            promise(.failure(.internalError))
                        case .rateLimited:
                            promise(.failure(.internalError))
                        default:
                            // something else is going wrong with exposure detection
                            // mark all keysets as invalid so they will be redownloaded again
                            let validKeySetHolderResults = keySetHoldersToProcess.map { keySetHolder in
                                return ExposureKeySetDetectionResult(keySetHolder: keySetHolder,
                                                                     processDate: nil,
                                                                     isValid: false)
                            }

                            let keySetHolderResults = invalidKeySetHolderResults + validKeySetHolderResults
                            let result = ExposureDetectionResult(keySetDetectionResults: keySetHolderResults,
                                                                 exposureSummary: nil,
                                                                 exposureReport: nil)

                            promise(.success(result))
                        }
                    }
                }
            }
        }
        .eraseToAnyPublisher()

        return updateNumberOfApiCallsMade()
            .flatMap { _ in executeExposureDetection }
            .eraseToAnyPublisher()
    }

    /// Updates the local keySetHolder storage with the latest results
    private func persistResult(_ result: ExposureDetectionResult) -> AnyPublisher<ExposureDetectionResult, ExposureDataError> {
        return Deferred {
            Future { promise in
                let selectKeySetDetectionResult: (ExposureKeySetHolder) -> ExposureKeySetDetectionResult? = { keySetHolder in
                    // find result that belongs to the keySetHolder
                    result.keySetDetectionResults.first { result in result.keySetHolder.identifier == keySetHolder.identifier }
                }

                self.storageController.requestExclusiveAccess { storageController in
                    let storedKeySetHolders = storageController.retrieveObject(identifiedBy: ExposureDataStorageKey.exposureKeySetsHolders) ?? []
                    var keySetHolders: [ExposureKeySetHolder] = []

                    storedKeySetHolders.forEach { keySetHolder in
                        guard let result = selectKeySetDetectionResult(keySetHolder) else {
                            // no result for this one, just append and process it next time
                            keySetHolders.append(keySetHolder)
                            return
                        }

                        if result.processDate != nil || result.isValid {
                            // only store correctly processed or valid results - forget about incorrectly processed ones
                            // and try to download those again next time
                            keySetHolders.append(ExposureKeySetHolder(identifier: keySetHolder.identifier,
                                                                      signatureFilename: keySetHolder.signatureFilename,
                                                                      binaryFilename: keySetHolder.binaryFilename,
                                                                      processDate: result.processDate,
                                                                      creationDate: keySetHolder.creationDate))
                        }
                    }

                    storageController.store(object: keySetHolders,
                                            identifiedBy: ExposureDataStorageKey.exposureKeySetsHolders) { _ in
                        promise(.success(result))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Removes binary files for processed or invalid keySetHolders
    private func removeBlobs(forResult exposureResult: (ExposureDetectionResult, ExposureReport?)) {
        let keySetHolders = exposureResult.0
            .keySetDetectionResults
            .filter { $0.processDate != nil || $0.isValid == false }
            .map { $0.keySetHolder }

        keySetHolders.forEach { keySetHolder in
            try? FileManager.default.removeItem(at: signatureFileUrl(forKeySetHolder: keySetHolder))
            try? FileManager.default.removeItem(at: binaryFileUrl(forKeySetHolder: keySetHolder))
        }
    }

    private func getNumberOfProcessedKeySetsInLast24Hours() -> Int {
        guard let cutOffDate = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) else {
            return 0
        }

        let wasProcessedInLast24h: (ExposureKeySetHolder) -> Bool = { keySetHolder in
            guard let processDate = keySetHolder.processDate else {
                return false
            }

            return processDate > cutOffDate
        }

        return getStoredKeySetsHolders()
            .filter(wasProcessedInLast24h)
            .count
    }

    private func getNumberOfExposureDetectionApiCallsInLast24Hours() -> Int {
        let apiCalls = storageController.retrieveObject(identifiedBy: ExposureDataStorageKey.exposureApiCallDates) ?? []

        guard let cutOffDate = Calendar.current.date(byAdding: .hour, value: -24, to: Date()) else {
            return 0
        }

        let wasProcessedInLast24h: (Date) -> Bool = { date in
            return date > cutOffDate
        }

        return apiCalls
            .filter(wasProcessedInLast24h)
            .count
    }

    private func selectKeySetHoldersToProcess(from keySetsHolders: [ExposureKeySetHolder]) -> [ExposureKeySetHolder] {
        let numberOfKeySetsLeftToProcess: Int

        #if USE_DEVELOPER_MENU || DEBUG

            if ProcessExposureKeySetsDataOperationOverrides.respectMaximumDailyKeySets {
                if #available(iOS 13.6, *) {
                    let numberOfApiCallsLeft = maximumDailyExposureDetectionAPICalls - getNumberOfExposureDetectionApiCallsInLast24Hours()
                    logDebug("Number of API calls left: \(numberOfApiCallsLeft)")

                    numberOfKeySetsLeftToProcess = numberOfApiCallsLeft > 0 ? Int.max : 0
                } else {
                    numberOfKeySetsLeftToProcess = maximumDailyOfKeySetsToProcess - getNumberOfProcessedKeySetsInLast24Hours()
                }

            } else {
                numberOfKeySetsLeftToProcess = Int.max
            }

        #else

            if #available(iOS 13.6, *) {
                let numberOfApiCallsLeft = maximumDailyExposureDetectionAPICalls - getNumberOfExposureDetectionApiCallsInLast24Hours()
                logDebug("Number of API calls left: \(numberOfApiCallsLeft)")

                numberOfKeySetsLeftToProcess = numberOfApiCallsLeft > 0 ? Int.max : 0
            } else {
                numberOfKeySetsLeftToProcess = maximumDailyOfKeySetsToProcess - getNumberOfProcessedKeySetsInLast24Hours()
            }

        #endif

        logDebug("Number of keysets left to process today: \(numberOfKeySetsLeftToProcess)")

        guard numberOfKeySetsLeftToProcess > 0 else {
            return []
        }

        let keySetHoldersToProcess = keySetsHolders
            .sorted(by: { first, second in first.creationDate < second.creationDate })

        guard keySetHoldersToProcess.isEmpty == false else {
            return []
        }

        return Array(keySetHoldersToProcess.prefix(numberOfKeySetsLeftToProcess))
    }

    /// Creates the final ExposureReport and triggers a local notification using the EN framework
    private func createReportAndTriggerNotification(forResult result: ExposureDetectionResult) -> AnyPublisher<(ExposureDetectionResult, ExposureReport?), ExposureDataError> {

        logDebug("Triggering local notification")

        guard let summary = result.exposureSummary else {
            logDebug("No summary to trigger notification for")
            return Just((result, nil))
                .setFailureType(to: ExposureDataError.self)
                .eraseToAnyPublisher()
        }

        guard summary.maximumRiskScore >= configuration.minimumRiskScope else {
            logDebug("Risk Score not high enough to see this as an exposure")

            return Just((result, nil))
                .setFailureType(to: ExposureDataError.self)
                .eraseToAnyPublisher()
        }

        if let daysSinceLastExposure = daysSinceLastExposure() {
            logDebug("Had previous exposure \(daysSinceLastExposure) days ago")

            if summary.daysSinceLastExposure >= daysSinceLastExposure {
                logDebug("Previous exposure was newer than new found exposure - skipping notification")

                return Just((result, nil))
                    .setFailureType(to: ExposureDataError.self)
                    .eraseToAnyPublisher()
            }
        }

        guard let date = Calendar.current.date(byAdding: .day, value: -summary.daysSinceLastExposure, to: Date()) else {
            logError("Error triggering notification for \(summary), could not create date")
            return Just((result, nil))
                .setFailureType(to: ExposureDataError.self)
                .eraseToAnyPublisher()
        }

        logDebug("Triggering notification for \(summary)")

        return notifyUserOfExposure(daysSinceLastExposure: summary.daysSinceLastExposure,
                                    exposureReport: (result, ExposureReport(date: date)))
    }

    private func notifyUserOfExposure(daysSinceLastExposure: Int, exposureReport value: (ExposureDetectionResult, ExposureReport?)) -> AnyPublisher<(ExposureDetectionResult, ExposureReport?), ExposureDataError> {
        return Deferred {
            Future { promise in

                self.userNotificationCenter.getAuthorizationStatus { status in
                    guard status == .authorized else {
                        promise(.failure(ExposureDataError.internalError))
                        return self.logError("Not authorized to post notifications")
                    }

                    let string = (daysSinceLastExposure > 1) ? String.statusNotifiedDaysAgoOther("\(daysSinceLastExposure)") : String.statusNotifiedDaysAgoOne("\(daysSinceLastExposure)")

                    let content = UNMutableNotificationContent()
                    content.body = .exposureNotificationUserExplanation("\(string)")
                    content.sound = .default
                    content.badge = 0

                    let request = UNNotificationRequest(identifier: PushNotificationIdentifier.exposure.rawValue,
                                                        content: content,
                                                        trigger: nil)
                    self.userNotificationCenter.add(request) { error in
                        guard let error = error else {
                            return promise(.success(value))
                        }
                        self.logError("Error posting notification: \(error.localizedDescription)")
                        promise(.failure(ExposureDataError.internalError))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Stores the exposureReport in local storage (which triggers the 'notified' state)
    private func persist(exposureReport value: (ExposureDetectionResult, ExposureReport?)) -> AnyPublisher<(ExposureDetectionResult, ExposureReport?), ExposureDataError> {
        return Deferred {
            Future { promise in
                guard let exposureReport = value.1 else {
                    promise(.success(value))
                    return
                }

                self.storageController.requestExclusiveAccess { storageController in
                    let lastExposureReport = storageController.retrieveObject(identifiedBy: ExposureDataStorageKey.lastExposureReport)

                    if let lastExposureReport = lastExposureReport, lastExposureReport.date > exposureReport.date {
                        // already stored a newer report, ignore this one
                        promise(.success(value))
                    } else {
                        // store the new report
                        storageController.store(object: exposureReport,
                                                identifiedBy: ExposureDataStorageKey.lastExposureReport) { _ in
                            promise(.success(value))
                        }
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Updates the date when this operation has last run
    private func updateLastProcessingDate(_ value: (ExposureDetectionResult, ExposureReport?)) -> AnyPublisher<(ExposureDetectionResult, ExposureReport?), ExposureDataError> {
        return Deferred {
            Future { promise in
                self.storageController.requestExclusiveAccess { storageController in
                    let date = Date()

                    self.logDebug("Updating last process date to \(date)")

                    storageController.store(object: date,
                                            identifiedBy: ExposureDataStorageKey.lastExposureProcessingDate,
                                            completion: { _ in
                                                promise(.success(value))
                                            })
                }
            }
        }
        .eraseToAnyPublisher()
    }

    private func updateNumberOfApiCallsMade() -> AnyPublisher<(), ExposureDataError> {
        return Deferred {
            return Future { promise in
                self.storageController.requestExclusiveAccess { storageController in
                    var calls = storageController.retrieveObject(identifiedBy: ExposureDataStorageKey.exposureApiCallDates) ?? []

                    calls = [Date()] + calls
                    self.logDebug("Most recent API calls \(calls)")

                    if calls.count > self.maximumDailyExposureDetectionAPICalls {
                        calls = Array(calls.prefix(self.maximumDailyExposureDetectionAPICalls))
                    }

                    storageController.store(object: calls,
                                            identifiedBy: ExposureDataStorageKey.exposureApiCallDates) { _ in
                        promise(.success(()))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }

    private func signatureFileUrl(forKeySetHolder keySetHolder: ExposureKeySetHolder) -> URL {
        return exposureKeySetsStorageUrl.appendingPathComponent(keySetHolder.signatureFilename)
    }

    private func binaryFileUrl(forKeySetHolder keySetHolder: ExposureKeySetHolder) -> URL {
        return exposureKeySetsStorageUrl.appendingPathComponent(keySetHolder.binaryFilename)
    }

    private func lastStoredExposureReport() -> ExposureReport? {
        return storageController.retrieveObject(identifiedBy: ExposureDataStorageKey.lastExposureReport)
    }

    private func daysSinceLastExposure() -> Int? {
        let today = Date()

        guard
            let lastExposureDate = lastStoredExposureReport()?.date,
            let dayCount = Calendar.current.dateComponents([.day], from: lastExposureDate, to: today).day
        else {
            return nil
        }

        return dayCount
    }

    /// Returns whether the skip any exposure keySet upon first install/launch.
    /// This is required to satisfy iOS 13.5's 15 keySet per 24h rate limit until
    /// the backend provides a correct rolling mechanism.
    /// Future versions will address this in a more elegant matter (instead of just
    /// skipping any initial keySet)
    private func determineSkipAllExposureSetsForTheFirstTime() -> Bool {
        if #available(iOS 13.6, *) {
            // never skip the initial keysets on iOS 13.6 as it does not rate limit
            // by the number of keysets, but rather by the number of API calls
            return false
        }

        let lastExposureProcessingDate = storageController.retrieveObject(identifiedBy: ExposureDataStorageKey.lastExposureProcessingDate)

        // if lastExposureProcessingDate is nil, this is the first time we're processing
        return lastExposureProcessingDate == nil
    }

    private let networkController: NetworkControlling
    private let storageController: StorageControlling
    private let exposureManager: ExposureManaging
    private let exposureKeySetsStorageUrl: URL
    private let configuration: ExposureConfiguration
    private let userNotificationCenter: UserNotificationCenter
}
