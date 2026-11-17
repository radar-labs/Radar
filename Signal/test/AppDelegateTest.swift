//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal

class AppDelegateTest: XCTestCase {
    @MainActor
    func testApplicationShortcutItems() throws {
        func hasNewMessageShortcut(_ shortcuts: [UIApplicationShortcutItem]) -> Bool {
            shortcuts.contains(where: { $0.type.contains("quickCompose") })
        }

        let unregistered = AppLifecycleManager.applicationShortcutItems(isRegistered: false)
        XCTAssertFalse(hasNewMessageShortcut(unregistered))

        let registered = AppLifecycleManager.applicationShortcutItems(isRegistered: true)
        XCTAssertTrue(hasNewMessageShortcut(registered))
    }
}
