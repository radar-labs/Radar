//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum SendMessageResult {
    case success

    /// Something happened before[^1] we branched based on ServiceIds, so the
    /// same Error applies to the entire attempt to send the message.
    ///
    /// [^1]: If we try to send to a group and every group member is
    /// unregistered, this is treated as an overall failure. There is an
    /// argument that this shouldn't be an error at all or should be
    /// per-recipient "recipients don't exist" errors.
    case overallFailure(any Error)

    /// We reached a point where we may have a different error for every
    /// recipient. It will often be the case that many recipients encounter the
    /// "same" error. (For example, we may use the multi-recipient endpoint and
    /// then copy the same Error object for every recipient, but we also may fan
    /// out to individual recipients, and they all may encounter their own
    /// equivalent network failure error.)
    case recipientsFailure(SendMessageFailure)
}
