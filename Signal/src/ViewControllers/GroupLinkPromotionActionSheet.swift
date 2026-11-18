//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
public import SignalUI

public class GroupLinkPromotionActionSheet: UIView {

    private weak var conversationViewController: ConversationViewController?

    private let secretParams: GroupSecretParams
    private let inviteLinkConfiguration: GroupInviteLinkConfiguration

    weak var actionSheetController: ActionSheetController?

    init(secretParams: GroupSecretParams, conversationViewController: ConversationViewController) {
        self.secretParams = secretParams
        self.inviteLinkConfiguration = GroupLinkViewController.fetchInviteLinkConfigurationWithSneakyTransaction(secretParams: secretParams)
            .owsFailUnwrap("must have inviteLinkConfiguration when creating promotion")
        self.conversationViewController = conversationViewController

        super.init(frame: .zero)

        let titleLabel = UILabel()
        titleLabel.text = OWSLocalizedString(
            "GROUP_LINK_PROMOTION_ALERT_TITLE",
            comment: "Title for the 'group link promotion' alert view.",
        )
        titleLabel.textColor = .Signal.label
        titleLabel.font = .dynamicTypeHeadline
        titleLabel.textAlignment = .natural

        let subtitleLabel = UILabel()
        subtitleLabel.text = OWSLocalizedString(
            "GROUP_LINK_PROMOTION_ALERT_SUBTITLE",
            comment: "Subtitle for the 'group link promotion' alert view.",
        )
        subtitleLabel.textColor = .Signal.label
        subtitleLabel.font = .dynamicTypeBody
        subtitleLabel.textAlignment = .natural
        subtitleLabel.numberOfLines = 0
        subtitleLabel.lineBreakMode = .byWordWrapping

        let topStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        topStack.axis = .vertical
        topStack.spacing = 4
        topStack.isLayoutMarginsRelativeArrangement = true
        topStack.directionalLayoutMargins = .init(top: 14, leading: 14, bottom: 20, trailing: 14)
        topStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topStack)
        addConstraints([
            topStack.topAnchor.constraint(equalTo: topAnchor),
            topStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            topStack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        let buttonStackTopAnchor: NSLayoutYAxisAnchor
        if case .enabled = inviteLinkConfiguration {
            buttonStackTopAnchor = topStack.bottomAnchor
        } else {
            let switchLabel = UILabel()
            switchLabel.text = OWSLocalizedString(
                "GROUP_LINK_PROMOTION_ALERT_APPROVE_NEW_MEMBERS_SWITCH",
                comment: "Label for the 'approve new group members' switch.",
            )
            switchLabel.setCompressionResistanceHorizontalHigh()

            memberApprovalSwitch.setCompressionResistanceHorizontalHigh()

            let memberApprovalStack = UIStackView(arrangedSubviews: [
                switchLabel,
                .hStretchingSpacer(),
                memberApprovalSwitch,
            ])
            memberApprovalStack.axis = .horizontal
            memberApprovalStack.alignment = .center
            memberApprovalStack.distribution = .fill
            memberApprovalStack.layoutMargins = UIEdgeInsets(hMargin: 16, vMargin: 10)
            memberApprovalStack.isLayoutMarginsRelativeArrangement = true
            memberApprovalStack.addBackgroundView(
                withBackgroundColor: .Signal.secondaryGroupedBackground,
                cornerRadius: OWSTableViewController2.cellRounding,
            )

            let captionLabel = UILabel()
            captionLabel.text = OWSLocalizedString(
                "GROUP_LINK_PROMOTION_ALERT_APPROVE_NEW_MEMBERS_EXPLANATION",
                comment: "Explanation of the 'approve new group members' switch.",
            )
            captionLabel.textColor = .Signal.secondaryLabel
            captionLabel.font = .dynamicTypeFootnote
            captionLabel.numberOfLines = 0
            captionLabel.lineBreakMode = .byWordWrapping
            captionLabel.translatesAutoresizingMaskIntoConstraints = false

            let captionContainer = UIView()
            captionContainer.directionalLayoutMargins = .init(top: 12, leading: 16, bottom: 12, trailing: 16)
            captionContainer.addSubview(captionLabel)
            captionContainer.addConstraints([
                captionLabel.topAnchor.constraint(equalTo: captionContainer.layoutMarginsGuide.topAnchor),
                captionLabel.leadingAnchor.constraint(equalTo: captionContainer.layoutMarginsGuide.leadingAnchor),
                captionLabel.trailingAnchor.constraint(equalTo: captionContainer.layoutMarginsGuide.trailingAnchor),
                captionLabel.bottomAnchor.constraint(equalTo: captionContainer.layoutMarginsGuide.bottomAnchor),
            ])

            let middleStack = UIStackView(arrangedSubviews: [memberApprovalStack, captionContainer])
            middleStack.axis = .vertical
            middleStack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(middleStack)
            addConstraints([
                middleStack.topAnchor.constraint(equalTo: topStack.bottomAnchor),
                middleStack.leadingAnchor.constraint(equalTo: leadingAnchor),
                middleStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])

            buttonStackTopAnchor = middleStack.bottomAnchor
        }

        // Two buttons at the bottom
        let topButton: UIButton
        if case .enabled(let inviteLink, requireAdminApproval: _) = inviteLinkConfiguration {
            topButton = UIButton(
                configuration: .largePrimary(title: OWSLocalizedString(
                    "GROUP_LINK_PROMOTION_ALERT_SHARE_LINK",
                    comment: "Label for the 'share link' button in the 'group link promotion' alert view.",
                )),
                primaryAction: UIAction { [weak self] _ in
                    self?.dismissAndShareLink(inviteLink: failIfThrows { try inviteLink.get() })
                },
            )
        } else {
            topButton = UIButton(
                configuration: .largePrimary(title: OWSLocalizedString(
                    "GROUP_LINK_PROMOTION_ALERT_ENABLE_AND_SHARE_LINK",
                    comment: "Label for the 'enable and share link' button in the 'group link promotion' alert view.",
                )),
                primaryAction: UIAction { [weak self] _ in
                    self?.enableAndShareLink()
                },
            )
        }
        let cancelButton = UIButton(
            configuration: .largeSecondary(title: CommonStrings.cancelButton),
            primaryAction: UIAction { [weak self] _ in
                self?.dismissAlert()
            },
        )

        let buttonStack = UIStackView.verticalButtonStack(buttons: [topButton, cancelButton], isFullWidthButtons: true)
        buttonStack.directionalLayoutMargins = .zero
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(buttonStack)
        addConstraints([
            buttonStack.topAnchor.constraint(equalTo: buttonStackTopAnchor, constant: 12),
            buttonStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            buttonStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func present(fromViewController: UIViewController) {
        let actionSheetController = ActionSheetController()
        actionSheetController.customHeader = self
        actionSheetController.isCancelable = true
        fromViewController.presentActionSheet(actionSheetController)
        self.actionSheetController = actionSheetController
    }

    private let memberApprovalSwitch = UISwitch()

    // MARK: - Events

    private func dismissAlert() {
        actionSheetController?.dismiss(animated: true)
    }

    private func enableAndShareLink() {
        guard let actionSheetController else {
            owsFailDebug("Missing actionSheetController.")
            return
        }
        GroupLinkViewUtils.updateLinkMode(
            secretParams: secretParams,
            linkMode: .enabled(requireAdminApproval: memberApprovalSwitch.isOn),
            fromViewController: actionSheetController,
            completion: { [weak self, secretParams] in
                switch GroupLinkViewController.fetchInviteLinkConfigurationWithSneakyTransaction(secretParams: secretParams) {
                case .enabled(let inviteLink, requireAdminApproval: _):
                    self?.dismissAndShareLink(inviteLink: failIfThrows { try inviteLink.get() })
                case .disabled, nil:
                    // There was a race, and somebody else turned off the link or we deleted
                    // the group.
                    return
                }
            },
        )
    }

    private func dismissAndShareLink(inviteLink: GroupInviteLink) {
        guard let actionSheetController else {
            owsFailDebug("Missing actionSheetController.")
            return
        }
        actionSheetController.dismiss(animated: true) {
            self.showShareLinkActionSheet(inviteLink: inviteLink)
        }
    }

    private func showShareLinkActionSheet(inviteLink: GroupInviteLink) {
        guard let conversationViewController else {
            owsFailDebug("Missing conversationViewController.")
            return
        }
        let sendMessageController = SendMessageController(fromViewController: conversationViewController)
        conversationViewController.sendMessageController = sendMessageController
        GroupLinkViewUtils.showShareLinkAlert(
            inviteLink: inviteLink,
            fromViewController: conversationViewController,
            sendMessageController: sendMessageController,
        )
    }
}
