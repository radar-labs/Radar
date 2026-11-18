//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

#if DEBUG

/// A minimal `UITableViewController` for displaying `UITableViewCell`s in Xcode
/// `#Previews`.
open class TablePreviewViewController: UITableViewController {

    private let cellBlock: (UITableView) -> [UITableViewCell]
    private var cells: [UITableViewCell] = []

    public init(
        style: UITableView.Style = .plain,
        cellBlock: @escaping (UITableView) -> [UITableViewCell],
    ) {
        self.cellBlock = cellBlock
        super.init(style: style)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        cells = cellBlock(tableView)
    }

    // MARK: UITableViewDataSource

    override public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return cells.count
    }

    override public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        return cells[indexPath.row]
    }
}

@available(iOS 17, *)
#Preview {
    TablePreviewViewController { _ in
        return (0..<5).map { i in
            let cell = UITableViewCell()
            var content = cell.defaultContentConfiguration()
            content.text = "Row \(i)"
            cell.contentConfiguration = content
            return cell
        }
    }
}

#endif
