//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

extension UITableView {
    /// Force the table view to recompute the height of its rows.
    ///
    /// Useful for tables with rows that use AutoLayout and need to tell their
    /// owning table that their height may have changed, for example due to the
    /// contents of the cell having changed.
    ///
    /// - Warning
    /// If the table view uses `UITableViewDiffableDataSource` you should
    /// instead use `reconfigureItems` on the data source's snapshot. Otherwise,
    /// you run the risk of snapshot changes overlapping with this method, which
    /// will cause a crash.
    public func recomputeRowHeights() {
        if
            let dataSource,
            String(describing: type(of: dataSource)).contains("Diffable")
        {
            owsFailDebug("Not suitable for this table view: see the warning in the doc comment on this method.")
        }

        beginUpdates()
        endUpdates()
    }
}
