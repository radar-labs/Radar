//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

extension RegistrationCoordinatorImpl {

    enum Service {

        static func makeSVR2AuthCheckRequest(
            e164: E164,
            candidateCredentials: [SVR2AuthCredential],
            networkManager: any NetworkManagerProtocol,
            logger: PrefixedLogger,
        ) async throws -> RegistrationServiceResponses.SVR2AuthCheckResponse {
            let request = RegistrationRequestFactory.svr2AuthCredentialCheckRequest(
                e164: e164,
                credentials: candidateCredentials,
                logger: logger,
            )
            let response = try await networkManager.asyncRequest(request)
            guard response.responseStatusCode == 200 else {
                throw response.asError()
            }
            return try JSONDecoder().decode(
                RegistrationServiceResponses.SVR2AuthCheckResponse.self,
                from: response.responseBodyData ?? Data(),
            )
        }

        static func makeCreateAccountRequest(
            _ verificationMethod: RegistrationRequestFactory.VerificationMethod,
            authPassword: String,
            accountAttributes: AccountAttributes,
            skipDeviceTransfer: Bool,
            apnRegistrationId: RegistrationRequestFactory.ApnRegistrationId?,
            aciPreKeyBundle: RegistrationPreKeyUploadBundle,
            pniPreKeyBundle: RegistrationPreKeyUploadBundle?,
            networkManager: any NetworkManagerProtocol,
            logger: PrefixedLogger,
        ) async throws -> AccountResponse {
            let request = RegistrationRequestFactory.createAccountRequest(
                verificationMethod: verificationMethod,
                authPassword: authPassword,
                accountAttributes: accountAttributes,
                skipDeviceTransfer: skipDeviceTransfer,
                apnRegistrationId: apnRegistrationId,
                aciPreKeyBundle: aciPreKeyBundle,
                pniPreKeyBundle: pniPreKeyBundle,
                logger: logger,
            )
            let response: HTTPResponse
            do {
                response = try await networkManager.asyncRequest(request)
            } catch where error.httpStatusCode == 401 {
                /// The Authorization header was invalid or the provided credentials were
                /// insufficient to verify ownership of the given phone number. Response
                /// body has an optional string error message.
                return .rejectedVerificationMethod
            } catch where error.httpStatusCode == 403 {
                /// The provided registration recovery password is either incorrect or
                /// registration via reg recovery password is impossible for this number.
                return .rejectedVerificationMethod
            } catch where error.httpStatusCode == 409 {
                /// The caller has not explicitly elected to skip transferring data from
                /// another device, but a device transfer is technically possible.
                return .deviceTransferPossible
            } catch where error.httpStatusCode == 423 {
                /// An account with the given phone number already exists and has a
                /// registration lock, and the client has not provided appropriate reglock
                /// credentials (either because the user input the wrong PIN (and thus
                /// couldn't retrieve any credential) or because the client used the wrong
                /// AEP/SvrKey to generate the credential). Response body has
                /// `RegistrationLockFailureResponse`.
                let parsedResponse = try JSONDecoder().decode(
                    RegistrationServiceResponses.RegistrationLockFailureResponse.self,
                    from: error.httpResponseData ?? Data(),
                )
                return .reglockFailure(parsedResponse)
            }
            guard response.responseStatusCode == 200 else {
                throw response.asError()
            }
            let parsedResponse = try JSONDecoder().decode(
                AccountIdentityResponse.self,
                from: response.responseBodyData ?? Data(),
            )
            return .success(AccountIdentity(
                localIdentifiers: parsedResponse.localIdentifiers,
                authPassword: authPassword,
                hasPreviouslyUsedSVR: parsedResponse.storageCapable,
            ))
        }

        static func makeChangeNumberRequest(
            _ verificationMethod: RegistrationRequestFactory.VerificationMethod,
            reglockToken: RegistrationLock?,
            authPassword: String,
            pniChangeNumberParameters: PniDistribution.Parameters,
            networkManager: any NetworkManagerProtocol,
            logger: PrefixedLogger,
        ) async throws -> AccountResponse {
            let request = RegistrationRequestFactory.changeNumberRequest(
                verificationMethod: verificationMethod,
                reglockToken: reglockToken,
                pniChangeNumberParameters: pniChangeNumberParameters,
                logger: logger,
            )
            let response: HTTPResponse
            do {
                response = try await networkManager.asyncRequest(request)
            } catch where error.httpStatusCode == 401 {
                /// The provided credentials were insufficient to verify ownership of the
                /// given phone number.
                return .rejectedVerificationMethod
            } catch where error.httpStatusCode == 403 {
                /// The provided registration recovery password is either incorrect or
                /// registration via reg recovery password is impossible for this number.
                return .rejectedVerificationMethod
            } catch where error.httpStatusCode == 409 {
                /// The devices to notify in the request did not match the known linked
                /// devices.
                Logger.error("Got mismatched device list information for change number")
                // TODO[PNP]: What should be done about this category of error?
                throw error
            } catch where error.httpStatusCode == 410 {
                /// The devices to notify in the request were correct, but their provided
                /// registrationIds did not match.
                Logger.error("Got mismatched device list information for change number")
                // TODO[PNP]: What should be done about this category of error?
                throw error
            } catch where error.httpStatusCode == 423 {
                /// An account with the given phone number already exists and has a
                /// registration lock, and the client has not provided appropriate reglock
                /// credentials (either because the user input the wrong PIN (and thus
                /// couldn't retrieve any credential) or because the client used the wrong
                /// AEP/SvrKey to generate the credential). Response body has
                /// `RegistrationLockFailureResponse`.
                let parsedResponse = try JSONDecoder().decode(
                    RegistrationServiceResponses.RegistrationLockFailureResponse.self,
                    from: error.httpResponseData ?? Data(),
                )
                return .reglockFailure(parsedResponse)
            }
            guard response.responseStatusCode == 200 else {
                throw response.asError()
            }
            let parsedResponse = try JSONDecoder().decode(
                AccountIdentityResponse.self,
                from: response.responseBodyData ?? Data(),
            )
            return .success(AccountIdentity(
                localIdentifiers: parsedResponse.localIdentifiers,
                authPassword: authPassword,
                hasPreviouslyUsedSVR: parsedResponse.storageCapable,
            ))
        }

        static func makeWhoAmIRequest(
            auth: ChatServiceAuth,
            networkManager: any NetworkManagerProtocol,
        ) async throws -> AccountIdentityResponse {
            let request = WhoAmIRequestFactory.whoAmIRequest(auth: auth)
            let response = try await networkManager.asyncRequest(request)
            guard response.responseStatusCode >= 200, response.responseStatusCode < 300 else {
                throw response.asError()
            }
            return try JSONDecoder().decode(AccountIdentityResponse.self, from: response.responseBodyData ?? Data())
        }
    }
}
