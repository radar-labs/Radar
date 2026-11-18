//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Stores state related to SVR; e.g. do we have backups at all, etc.
public struct SVRLocalStorage {
    let backupAttemptStore = NewKeyValueStore(collection: "SVR.Completed")
}
