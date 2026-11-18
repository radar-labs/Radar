//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

public protocol CustomBackgroundColorCell: UITableViewCell {
    var customBackgroundColor: UIColor { get }
    var customSelectedBackgroundColor: UIColor { get }
}
