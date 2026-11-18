//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum GroupInviteLinkConfiguration {
    case enabled(inviteLink: Result<GroupInviteLink, any Error>, requireAdminApproval: Bool)
    case disabled
}
