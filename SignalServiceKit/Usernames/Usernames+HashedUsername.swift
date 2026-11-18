//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

extension Usernames {
    public enum CandidateGenerationError: Error {
        case nicknameCannotBeEmpty
        case nicknameCannotStartWithDigit
        case nicknameContainsInvalidCharacters
        case nicknameTooShort
        case nicknameTooLong

        fileprivate init?(fromSignalError signalError: LibSignalClient.SignalError?) {
            guard let signalError else { return nil }

            switch signalError {
            case .nicknameCannotBeEmpty:
                self = .nicknameCannotBeEmpty
            case .nicknameCannotStartWithDigit:
                self = .nicknameCannotStartWithDigit
            case .badNicknameCharacter:
                self = .nicknameContainsInvalidCharacters
            case .nicknameTooShort:
                self = .nicknameTooShort
            case .nicknameTooLong:
                self = .nicknameTooLong
            default:
                return nil
            }
        }
    }

    public static func generateCandidates(
        forNickname nickname: String,
        minNicknameLength: UInt32,
        maxNicknameLength: UInt32,
        desiredDiscriminator: String?,
    ) throws -> [LibSignalClient.Username] {
        do {
            let nicknameLengthRange = minNicknameLength...maxNicknameLength
            if let desiredDiscriminator {
                let username = try LibSignalClient.Username(nickname: nickname, discriminator: desiredDiscriminator, withValidLengthWithin: nicknameLengthRange)
                return [username]
            }

            return try LibSignalClient.Username.candidates(
                from: nickname,
                withValidLengthWithin: nicknameLengthRange,
            )
        } catch let error {
            if
                let libSignalError = error as? SignalError,
                let generationError = CandidateGenerationError(fromSignalError: libSignalError)
            {
                throw generationError
            }

            throw error
        }
    }
}
