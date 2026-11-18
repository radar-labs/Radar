//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

#if USE_DEBUG_UI

class DebugUIReachability: DebugUIPage {
    let name = "Reachability"

    func section(thread: TSThread?) -> OWSTableSection? {
        return OWSTableSection(title: name, items: [
            OWSTableItem(
                customCellBlock: {
                    let manager = SSKEnvironment.shared.reachabilityManagerRef
                    return OWSTableItem.buildCell(
                        itemName: "Current",
                        accessoryText: manager.currentReachabilityString,
                        accessoryType: .none,
                    )
                },
            ),
            OWSTableItem.disclosureItem(
                withText: "Live Monitor",
                actionBlock: {
                    let viewController = DebugUIReachabilityMonitorViewController()
                    UIApplication.shared.frontmostViewController?
                        .navigationController?
                        .pushViewController(viewController, animated: true)
                },
            ),
        ])
    }
}

// MARK: -

private class DebugUIReachabilityMonitorViewController: OWSTableViewController2 {

    private var events: [(Date, String)] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Reachability"
        appendEvent()
        updateContents()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reachabilityDidChange),
            name: SSKReachability.owsReachabilityDidChange,
            object: nil,
        )
    }

    @objc
    private func reachabilityDidChange() {
        appendEvent()
        updateContents()
    }

    private func appendEvent() {
        let manager = SSKEnvironment.shared.reachabilityManagerRef
        events.append((Date(), manager.currentReachabilityString))
    }

    private lazy var timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    private func updateContents() {
        let items = events.reversed().map { (date, description) in
            let timestamp = timestampFormatter.string(from: date)
            return OWSTableItem.label(
                withText: "\(timestamp)  \(description)",
                accessoryType: .none,
            )
        }
        setContents(OWSTableContents(sections: [
            OWSTableSection(title: "Events", items: items),
        ]))
    }
}

#endif
