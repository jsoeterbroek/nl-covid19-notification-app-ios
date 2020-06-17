/*
 * Copyright (c) 2020 De Staat der Nederlanden, Ministerie van Volksgezondheid, Welzijn en Sport.
 *  Licensed under the EUROPEAN UNION PUBLIC LICENCE v. 1.2
 *
 *  SPDX-License-Identifier: EUPL-1.2
 */

import Foundation
import ZIPFoundation

enum NetworkManagerError: Error {
    case emptyResponse
}

final class NetworkManager: NetworkManaging {

    init(configuration: NetworkConfiguration, urlSession: URLSession = URLSession.shared) {
        self.configuration = configuration
        self.session = urlSession
    }

    // MARK: CDN

    // Content retrieved via CDN.

    /// Fetches manifest from server with all available parameters
    /// - Parameter completion: return
    func getManifest(completion: @escaping (Result<Manifest, Error>) -> ()) {
        session.get(self.configuration.manifestUrl) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            do {
                guard let data = data else {
                    throw NetworkManagerError.emptyResponse
                }

                let manifest = try JSONDecoder().decode(Manifest.self, from: data)

                // TODO: SAVE IN USER DEFAULTS!!!
                completion(.success(manifest))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Fetched the global app config which contains version number, manifest polling frequence and decoy probability
    /// - Parameter completion: completion description
    func getAppConfig(appConfig: String, completion: @escaping (Result<AppConfig, Error>) -> ()) {
        session.get(self.configuration.appConfigUrl(param: appConfig)) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            do {
                guard let data = data else {
                    throw NetworkManagerError.emptyResponse
                }
                let appConfig = try JSONDecoder().decode(AppConfig.self, from: data)
                completion(.success(appConfig))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Fetches risk parameters used by the ExposureManager
    /// - Parameter completion: success or fail
    func getRiskCalculationParameters(appConfig: String, completion: @escaping (Result<RiskCalculationParameters, Error>) -> ()) {
        session.get(self.configuration.riskCalculationParametersUrl(param: appConfig)) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            do {
                guard let data = data else {
                    throw NetworkManagerError.emptyResponse
                }

                let riskCalculationParameters = try JSONDecoder().decode(RiskCalculationParameters.self, from: data)
                completion(.success(riskCalculationParameters))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Fetches TEKS
    /// - Parameters:
    ///   - id: id of the exposureKeySet
    ///   - completion: executed on complete or failure
    func getDiagnosisKeys(_ id: String, completion: @escaping (Result<ExposureKeySet, Error>) -> ()) {
        session.download(self.configuration.exposureKeySetUrl(param: id)) { url, response, error in

            guard let url = url else {
                completion(.failure(NetworkManagerError.emptyResponse))
                return
            }

            do {
                let exposureKeySet = try ExposureKeySet(url: url)
                completion(.success(exposureKeySet))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// Upload diagnosis keys (TEKs) to the server
    /// - Parameters:
    ///   - diagnosisKeys: Contains all diagnosisKeys available
    ///   - completion: completion nil if succes else error
    func postKeys(diagnosisKeys: DiagnosisKeys, completion: @escaping (Error?) -> ()) {
        session.post(self.configuration.postKeysUrl, object: diagnosisKeys) { data, response, error in
            completion(error)
        }
    }

    /// Upload decoy keys to the server
    /// - Parameters:
    ///   - diagnosisKeys: Contains all diagnosisKeys available
    ///   - completion: completion nil if succes else error
    func postStopKeys(diagnosisKeys: DiagnosisKeys, completion: @escaping (Error?) -> ()) {
        session.post(self.configuration.postKeysUrl, object: diagnosisKeys) { data, response, error in
            completion(error)
        }
    }

    /// Exchange a secret with the server so we can sign our keys
    /// - Parameters:
    ///   - register: Contains confirmation key
    ///   - completion: completion
    func postRegister(register: Register, completion: @escaping (Result<LabInformation, Error>) -> ()) {
        session.post(self.configuration.registerUrl, object: register) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            do {
                guard let data = data else {
                    throw NetworkManagerError.emptyResponse
                }

                let labInformation = try JSONDecoder().decode(LabInformation.self, from: data)
                completion(.success(labInformation))
            } catch {
                completion(.failure(error))
            }
        }
    }

    private let configuration: NetworkConfiguration
    private let session: URLSession
}
