/*
 * Copyright (c) 2020 De Staat der Nederlanden, Ministerie van Volksgezondheid, Welzijn en Sport.
 *  Licensed under the EUROPEAN UNION PUBLIC LICENCE v. 1.2
 *
 *  SPDX-License-Identifier: EUPL-1.2
 */

import Combine
import ENFoundation
import Foundation

final class NetworkManager: NetworkManaging, Logging {

    init(configurationProvider: NetworkConfigurationProvider,
         responseHandlerProvider: NetworkResponseHandlerProvider,
         storageController: StorageControlling,
         session: URLSession,
         sessionDelegate: URLSessionDelegate?) {
        self.configurationProvider = configurationProvider
        self.responseHandlerProvider = responseHandlerProvider
        self.storageController = storageController
        self.session = session
        self.sessionDelegate = sessionDelegate
    }

    // MARK: CDN

    // Content retrieved via CDN.

    /// Fetches manifest from server with all available parameters
    /// - Parameter completion: return
    func getManifest(completion: @escaping (Result<Manifest, NetworkError>) -> ()) {
        let expectedContentType = HTTPContentType.zip
        let headers = [HTTPHeaderKey.acceptedContentType: expectedContentType.rawValue]

        let urlRequest = constructRequest(url: configuration.manifestUrl,
                                          method: .GET,
                                          headers: headers)

        download(request: urlRequest) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(result):
                self
                    .responseToData(for: result.0, url: result.1)
                    .flatMap(self.decodeJson(data:))
                    .mapError { $0.asNetworkError }
                    .sink(
                        receiveCompletion: { result in
                            if case let .failure(error) = result {
                                completion(.failure(error))
                            }
                        },
                        receiveValue: { (data: Manifest) in
                            completion(.success(data))
                        })
                    .store(in: &self.disposeBag)
            }
        }
    }

    /// Fetched the global app config which contains version number, manifest polling frequence and decoy probability
    /// - Parameter completion: completion description
    func getAppConfig(appConfig: String, completion: @escaping (Result<AppConfig, NetworkError>) -> ()) {
        let expectedContentType = HTTPContentType.zip
        let headers = [HTTPHeaderKey.acceptedContentType: expectedContentType.rawValue]

        let urlRequest = constructRequest(url: configuration.appConfigUrl(identifier: appConfig),
                                          method: .GET,
                                          headers: headers)

        download(request: urlRequest) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(result):
                self
                    .responseToData(for: result.0, url: result.1)
                    .flatMap(self.decodeJson(data:))
                    .mapError { $0.asNetworkError }
                    .sink(
                        receiveCompletion: { result in
                            if case let .failure(error) = result {
                                completion(.failure(error))
                            }
                        },
                        receiveValue: { data in
                            completion(.success(data))
                        })
                    .store(in: &self.disposeBag)
            }
        }
    }

    /// Fetches risk parameters used by the ExposureManager
    /// - Parameter completion: success or fail
    func getRiskCalculationParameters(identifier: String, completion: @escaping (Result<RiskCalculationParameters, NetworkError>) -> ()) {
        let expectedContentType = HTTPContentType.zip
        let headers = [HTTPHeaderKey.acceptedContentType: expectedContentType.rawValue]

        let urlRequest = constructRequest(url: configuration.riskCalculationParametersUrl(identifier: identifier),
                                          method: .GET,
                                          headers: headers)

        download(request: urlRequest) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(result):
                self
                    .responseToData(for: result.0, url: result.1)
                    .flatMap(self.decodeJson(data:))
                    .mapError { $0.asNetworkError }
                    .sink(
                        receiveCompletion: { result in
                            if case let .failure(error) = result {
                                completion(.failure(error))
                            }
                        },
                        receiveValue: { data in
                            completion(.success(data))
                        })
                    .store(in: &self.disposeBag)
            }
        }
    }

    /// Fetches TEKS
    /// - Parameters:
    ///   - id: id of the exposureKeySet
    ///   - completion: executed on complete or failure
    func getExposureKeySet(identifier: String, completion: @escaping (Result<URL, NetworkError>) -> ()) {
        let expectedContentType = HTTPContentType.zip
        let headers = [HTTPHeaderKey.acceptedContentType: expectedContentType.rawValue]

        let urlRequest = constructRequest(url: configuration.exposureKeySetUrl(identifier: identifier),
                                          method: .GET,
                                          headers: headers)

        download(request: urlRequest) { result in
            switch result {
            case let .failure(error):
                completion(.failure(error))
            case let .success(result):
                self
                    .responseToLocalUrl(for: result.0, url: result.1)
                    .mapError { $0.asNetworkError }
                    .sink(
                        receiveCompletion: { result in
                            if case let .failure(error) = result {
                                completion(.failure(error))
                            }
                        },
                        receiveValue: { url in
                            completion(.success(url))
                        })
                    .store(in: &self.disposeBag)
            }
        }
    }

    /// Upload diagnosis keys (TEKs) to the server
    /// - Parameters:
    ///   - request: PostKeysRequest
    ///   - signature: Signature to add a queryString parameter
    ///   - completion: completion nil if succes else error
    func postKeys(request: PostKeysRequest, signature: String, completion: @escaping (NetworkError?) -> ()) {
        let expectedContentType = HTTPContentType.json
        let headers = [HTTPHeaderKey.acceptedContentType: expectedContentType.rawValue]

        let urlRequest = constructRequest(url: configuration.postKeysUrl(signature: signature),
                                          method: .POST,
                                          body: request,
                                          headers: headers)

        data(request: urlRequest) { result in
            switch result {
            case .success:
                completion(nil)
            case let .failure(error):
                completion(error)
            }
        }
    }

    /// Upload decoy keys to the server
    /// - Parameters:
    ///   - diagnosisKeys: Contains all diagnosisKeys available
    ///   - completion: completion nil if succes else error
    func postStopKeys(request: PostKeysRequest, signature: String, completion: @escaping (NetworkError?) -> ()) {
        let expectedContentType = HTTPContentType.json
        let headers = [HTTPHeaderKey.acceptedContentType: expectedContentType.rawValue]

        let urlRequest = constructRequest(url: configuration.postKeysUrl(signature: signature),
                                          method: .POST,
                                          body: request,
                                          headers: headers)

        data(request: urlRequest) { result in
            switch result {
            case .success:
                completion(nil)
            case let .failure(error):
                completion(error)
            }
        }
    }

    /// Exchange a secret with the server so we can sign our keys
    /// - Parameters:
    ///   - register: Contains confirmation key
    ///   - completion: completion
    func postRegister(request: RegisterRequest, completion: @escaping (Result<LabInformation, NetworkError>) -> ()) {
        let expectedContentType = HTTPContentType.json
        let headers = [HTTPHeaderKey.acceptedContentType: expectedContentType.rawValue]

        let urlRequest = constructRequest(url: configuration.registerUrl,
                                          method: .POST,
                                          body: request,
                                          headers: headers)

        data(request: urlRequest) { result in
            self.jsonResponseHandler(result: result)
                .sink(
                    receiveCompletion: { result in
                        if case let .failure(error) = result {
                            completion(.failure(error))
                        }

                    },
                    receiveValue: { value in
                        completion(.success(value))
                    })
                .store(in: &self.disposeBag)
        }
    }

    // MARK: - Construct Request

    private func constructRequest(url: URL?,
                                  method: HTTPMethod = .GET,
                                  body: Encodable? = nil,
                                  headers: [HTTPHeaderKey: String] = [:]) -> Result<URLRequest, NetworkError> {
        guard let url = url else {
            return .failure(.invalidRequest)
        }

        var request = URLRequest(url: url,
                                 cachePolicy: .useProtocolCachePolicy,
                                 timeoutInterval: 10)
        request.httpMethod = method.rawValue

        let defaultHeaders = [
            HTTPHeaderKey.contentType: HTTPContentType.json.rawValue
        ]

        defaultHeaders.forEach { header, value in
            request.addValue(value, forHTTPHeaderField: header.rawValue)
        }

        headers.forEach { header, value in
            request.addValue(value, forHTTPHeaderField: header.rawValue)
        }

        if let body = body.flatMap({ try? self.jsonEncoder.encode(AnyEncodable($0)) }) {
            request.httpBody = body
        }

        logDebug("--REQUEST--")
        if let url = request.url { logDebug(url.debugDescription) }
        if let allHTTPHeaderFields = request.allHTTPHeaderFields { logDebug(allHTTPHeaderFields.debugDescription) }
        if let httpBody = request.httpBody { logDebug(String(data: httpBody, encoding: .utf8)!) }
        logDebug("--END REQUEST--")

        return .success(request)
    }

    // MARK: - Download Files

    fileprivate func download(request: Result<URLRequest, NetworkError>, completion: @escaping (Result<(URLResponse, URL), NetworkError>) -> ()) {
        switch request {
        case let .success(request):
            download(request: request, completion: completion)
        case let .failure(error):
            completion(.failure(error))
        }
    }

    fileprivate func download(request: URLRequest, completion: @escaping (Result<(URLResponse, URL), NetworkError>) -> ()) {
        session.dataTask(with: request) { data, response, error in
            let localUrl: URL?

            if let data = data {
                localUrl = self.write(data: data)
            } else {
                localUrl = nil
            }

            self.handleNetworkResponse(localUrl, response: response, error: error, completion: completion)
        }.resume()
    }

    private func write(data: Data) -> URL? {
        let uuid = UUID().uuidString
        let temporaryUrl = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(uuid)

        do {
            try data.write(to: temporaryUrl)
            return temporaryUrl
        } catch {
            return nil
        }
    }

    // MARK: - Download Data

    private func data(request: Result<URLRequest, NetworkError>, completion: @escaping (Result<(URLResponse, Data), NetworkError>) -> ()) {
        switch request {
        case let .success(request):
            data(request: request, completion: completion)
        case let .failure(error):
            completion(.failure(error))
        }
    }

    private func data(request: URLRequest, completion: @escaping (Result<(URLResponse, Data), NetworkError>) -> ()) {
        session.dataTask(with: request) { data, response, error in
            self.handleNetworkResponse(data,
                                       response: response,
                                       error: error,
                                       completion: completion)
        }
        .resume()
    }

    // MARK: - Utilities

    /// Checks for failures and inspects status code
    private func handleNetworkResponse<Object>(_ object: Object?,
                                               response: URLResponse?,
                                               error: Error?,
                                               completion: @escaping (Result<(URLResponse, Object), NetworkError>) -> ()) {
        if error != nil {
            completion(.failure(.invalidResponse))
            return
        }

        logDebug("--RESPONSE--")
        if let response = response as? HTTPURLResponse {
            logDebug("Finished response to URL \(response.url?.absoluteString ?? "") with status \(response.statusCode)")

            let headers = response.allHeaderFields.map { header, value in
                return String("\(header): \(value)")
            }.joined(separator: "\n")

            logDebug("Response headers: \n\(headers)")
        } else if let error = error {
            logDebug("Error with response: \(error)")
        }

        logDebug("--END RESPONSE--")

        guard let response = response,
            let object = object else {
            completion(.failure(.invalidResponse))
            return
        }

        if let error = self.inspect(response: response) {
            completion(.failure(error))
            return
        }

        completion(.success((response, object)))
    }

    private func responseToLocalUrl(for response: URLResponse, url: URL) -> AnyPublisher<URL, NetworkResponseHandleError> {
        var localUrl = Just(url)
            .setFailureType(to: NetworkResponseHandleError.self)
            .eraseToAnyPublisher()

        // unzip
        let unzipResponseHandler = responseHandlerProvider.unzipNetworkResponseHandler
        if unzipResponseHandler.isApplicable(for: response, input: url) {

            localUrl = localUrl
                .flatMap { localUrl in unzipResponseHandler.process(response: response, input: localUrl) }
                .eraseToAnyPublisher()
        }

        // verify signature
        let verifySignatureResponseHandler = responseHandlerProvider.verifySignatureResponseHandler
        if verifySignatureResponseHandler.isApplicable(for: response, input: url) {
            localUrl = localUrl
                .flatMap { localUrl in verifySignatureResponseHandler.process(response: response, input: localUrl) }
                .eraseToAnyPublisher()
        }

        return localUrl
    }

    /// Unzips, verifies signature and reads response in memory
    private func responseToData(for response: URLResponse, url: URL) -> AnyPublisher<Data, NetworkResponseHandleError> {
        let localUrl = responseToLocalUrl(for: response, url: url)

        let readFromDiskResponseHandler = responseHandlerProvider.readFromDiskResponseHandler
        if readFromDiskResponseHandler.isApplicable(for: response, input: url) {
            return localUrl
                .flatMap { localUrl in readFromDiskResponseHandler.process(response: response, input: localUrl) }
                .eraseToAnyPublisher()
        } else {
            return Fail(error: .cannotDeserialize).eraseToAnyPublisher()
        }
    }

    /// Utility function to decode JSON
    private func decodeJson<Object: Decodable>(data: Data) -> AnyPublisher<Object, NetworkResponseHandleError> {
        return Future { promise in
            do {
                let object = try self.jsonDecoder.decode(Object.self, from: data)
                self.logDebug("Response Object: \(object)")
                promise(.success(object))
            } catch {
                if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    self.logDebug("Raw JSON: \(json)")
                }
                self.logError("Error Deserializing \(Object.self): \(error.localizedDescription)")
                promise(.failure(.cannotDeserialize))
            }
        }
        .share()
        .eraseToAnyPublisher()
    }

    /// Response handler which decodes JSON
    private func jsonResponseHandler<Object: Decodable>(result: Result<(URLResponse, Data), NetworkError>) -> AnyPublisher<Object, NetworkError> {
        switch result {
        case let .success(result):
            return decodeJson(data: result.1)
                .mapError { $0.asNetworkError }
                .eraseToAnyPublisher()
        case let .failure(error):
            return Fail(error: error).eraseToAnyPublisher()
        }
    }

    /// Checks for valid HTTPResponse and status codes
    private func inspect(response: URLResponse) -> NetworkError? {
        guard let response = response as? HTTPURLResponse else {
            return .invalidResponse
        }

        switch response.statusCode {
        case 200 ... 299:
            return nil
        case 304:
            return .responseCached
        case 300 ... 399:
            return .redirection
        case 400 ... 499:
            return .resourceNotFound
        case 500 ... 599:
            return .serverError
        default:
            return .invalidResponse
        }
    }

    // MARK: - Private

    private let configurationProvider: NetworkConfigurationProvider
    private let session: URLSession
    private let sessionDelegate: URLSessionDelegate? // hold on to delegate to prevent deallocation
    private let responseHandlerProvider: NetworkResponseHandlerProvider
    private let storageController: StorageControlling

    private var configuration: NetworkConfiguration {
        return configurationProvider.configuration
    }

    private lazy var jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromUpperCamelCase

        return decoder
    }()

    private lazy var jsonEncoder = JSONEncoder()
    private var disposeBag = Set<AnyCancellable>()
}

extension NetworkResponseHandleError {
    var asNetworkError: NetworkError {
        switch self {
        case .cannotDeserialize:
            return .invalidResponse
        case .cannotUnzip:
            return .invalidResponse
        case .invalidSignature:
            return .invalidResponse
        }
    }
}
