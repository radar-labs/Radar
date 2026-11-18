//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class LoadMoreMessagesView: UICollectionReusableView {

    static let reuseIdentifier = "LoadMoreMessagesView"

    static let fixedHeight: CGFloat = 60

    // MARK: Init

    override init(frame: CGRect) {
        label.text = OWSLocalizedString(
            "CONVERSATION_VIEW_LOADING_MORE_MESSAGES",
            comment: "Indicates that the app is loading more messages in this conversation.",
        )
        super.init(frame: frame)
        addSubview(label)
        label.autoPinEdgesToSuperviewEdges()
        label.autoSetDimension(.height, toSize: LoadMoreMessagesView.fixedHeight)
        label.textAlignment = .center
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Subiews

    private let label = UILabel()

    // MARK: Public

    func configureForDisplay() {
        label.textColor = Theme.secondaryTextAndIconColor
        label.font = UIFont.semiboldFont(ofSize: 16)
    }
}
