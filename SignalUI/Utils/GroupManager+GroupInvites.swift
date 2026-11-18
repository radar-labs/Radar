//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient
public import SignalServiceKit

public extension GroupManager {

    @MainActor
    static func leaveGroupOrDeclineInviteAsyncWithUI(
        groupThread: TSGroupThread,
        fromViewController: UIViewController,
        replacementAdminAci: Aci? = nil,
        success: (() -> Void)?,
    ) {
        // Note: Requests to join aren't handled by this method.
        // Note: If we *aren't* a member, this method turns into a no-op.
        owsAssertDebug(groupThread.groupModel.groupMembership.isLocalUserFullOrInvitedMember, "must be member")

        ModalActivityIndicatorViewController.present(
            fromViewController: fromViewController,
            title: CommonStrings.updatingModal,
            canCancel: false,
            asyncBlock: { modal in
                do {
                    let databaseStorage = SSKEnvironment.shared.databaseStorageRef
                    let leavePromise = await databaseStorage.awaitableWrite { tx in
                        return self.localLeaveGroupOrDeclineInvite(
                            groupThread: groupThread,
                            replacementAdminAci: replacementAdminAci,
                            waitForMessageProcessing: true,
                            tx: tx,
                        )
                    }
                    _ = try await leavePromise.awaitable()
                    modal.dismiss { success?() }
                } catch {
                    owsFailDebug("Leave group failed: \(error)")
                    modal.dismiss {
                        OWSActionSheets.showActionSheet(
                            title: OWSLocalizedString(
                                "LEAVE_GROUP_FAILED",
                                comment: "Error indicating that a group could not be left.",
                            ),
                        )
                    }
                }
            },
        )
    }

    @MainActor
    static func acceptGroupInviteWithModal(
        _ groupThread: TSGroupThread,
        fromViewController: UIViewController,
    ) async throws {
        do {
            try await ModalActivityIndicatorViewController.presentAndPropagateResult(
                from: fromViewController,
                title: CommonStrings.joiningGroupModal,
            ) {
                guard let groupModelV2 = groupThread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid group model")
                }

                try await self.localAcceptInviteToGroupV2(
                    secretParams: groupModelV2.secretParams(),
                    waitForMessageProcessing: true,
                )
            }
        } catch {
            OWSActionSheets.showActionSheet(title: OWSLocalizedString(
                "GROUPS_INVITE_ACCEPT_INVITE_FAILED",
                comment: "Error indicating that an error occurred while accepting an invite.",
            ))
            throw error
        }
    }
}
