//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(TransientOutgoingMessage)
public class TransientOutgoingMessage: TSOutgoingMessage {
    override public class var supportsSecureCoding: Bool { true }

    override public var shouldBeSaved: Bool { false }
}
