//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol AccountAttributesUpdater {
    /// Sets the flag to force an account attributes update then initiates an
    /// attempt after the transaction ends.
    ///
    /// - Returns: The Task asynchronously executing the attribute update.
    @discardableResult
    func scheduleAccountAttributesUpdate(authedAccount: AuthedAccount, tx: DBWriteTransaction) -> Task<Void, any Error>
}
