//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import XCTest

class OWSFileSystemTest: XCTestCase {
    func testFreeSpaceInBytes() throws {
        let result = try OWSFileSystem.freeSpaceInBytes()
        XCTAssertGreaterThan(result, 1)
    }
}
