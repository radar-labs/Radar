//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

class BlockListViewController: OWSTableViewController2 {

    override init() {
        super.init()

        title = NSLocalizedString(
            "SETTINGS_BLOCK_LIST_TITLE",
            comment: "Label for the block list section of the settings view",
        )
    }

    override func viewDidLoad() {
        updateContactList(reloadTableView: false)

        super.viewDidLoad()

        SUIEnvironment.shared.contactsViewHelperRef.addObserver(self)

        tableView.estimatedRowHeight = 60
        tableView.register(ContactTableViewCell.self, forCellReuseIdentifier: ContactTableViewCell.reuseIdentifier)
    }

    private func updateContactList(reloadTableView: Bool) {
        let avatarBuilder = SSKEnvironment.shared.avatarBuilderRef
        let contactManager = SSKEnvironment.shared.contactManagerRef
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let recipientStore = DependenciesBridge.shared.recipientDatabaseTable

        let contents = OWSTableContents()

        // "Add" section
        let sectionAddContact = OWSTableSection(items: [
            OWSTableItem.disclosureItem(
                withText: NSLocalizedString(
                    "SETTINGS_BLOCK_LIST_ADD_BUTTON",
                    comment: "A label for the 'add phone number' button in the block list table.",
                ),
                actionBlock: { [weak self] in
                    let viewController = AddToBlockListViewController()
                    viewController.delegate = self
                    self?.navigationController?.pushViewController(viewController, animated: true)
                },
            ),
        ])
        sectionAddContact.footerTitle = NSLocalizedString(
            "BLOCK_USER_BEHAVIOR_EXPLANATION",
            comment: "An explanation of the consequences of blocking another user.",
        )
        contents.add(sectionAddContact)

        struct BlockedRecipient {
            var address: SignalServiceAddress
            var comparableName: ComparableDisplayName
            var blockedAt: BlockedTimestamp
        }
        struct BlockedGroup {
            var groupId: Data
            var groupName: String
            var groupAvatar: UIImage?
            var blockedAt: BlockedTimestamp
        }
        let blockedRecipients: [BlockedRecipient]
        let blockedGroups: [BlockedGroup]
        (blockedRecipients, blockedGroups) = databaseStorage.read { tx in
            let recipientResult: [BlockedRecipient]
            let blockedRecipients = recipientStore.fetchBlockedRecipients(tx: tx)
            let blockedComparableNames = contactManager.comparableNames(for: blockedRecipients.map(\.address), tx: tx)
            recipientResult = zip(blockedRecipients, blockedComparableNames).map { recipient, comparableName in
                return BlockedRecipient(
                    address: recipient.address,
                    comparableName: comparableName,
                    blockedAt: recipient.blockedAt,
                )
            }.sorted(by: {
                if $0.blockedAt != $1.blockedAt {
                    return $0.blockedAt > $1.blockedAt
                }
                return $0.comparableName < $1.comparableName
            })
            let groupResult: [BlockedGroup]
            let blockedGroups = GroupStore().fetchBlockedGroups(tx: tx)
            groupResult = blockedGroups.map { groupRecord in
                let groupThread = groupRecord.threadId.flatMap {
                    return TSGroupThread.threadUniqueId(forThreadId: $0, tx: tx)
                }.flatMap {
                    return TSGroupThread.fetchViaCache(uniqueId: $0, transaction: tx)
                }
                let groupModel = groupThread?.groupModel
                let groupName = groupModel?.groupName ?? OWSLocalizedString(
                    "UNKNOWN_GROUP",
                    comment: "Title shown for a group when it's name isn't known. Visible for blocked groups whose name isn't known.",
                )
                let groupAvatarImage: UIImage? = {
                    if let avatarData = groupModel?.avatarDataState.dataIfPresent {
                        return UIImage(data: avatarData)
                    }

                    return avatarBuilder.defaultAvatarImage(
                        forGroupId: groupRecord.groupId,
                        diameterPoints: AvatarBuilder.standardAvatarSizePoints,
                        transaction: tx,
                    )
                }()
                return BlockedGroup(
                    groupId: groupRecord.groupId,
                    groupName: groupName,
                    groupAvatar: groupAvatarImage,
                    blockedAt: groupRecord.blockedAt,
                )
            }.sorted(by: {
                if $0.blockedAt != $1.blockedAt {
                    return $0.blockedAt > $1.blockedAt
                }
                switch $0.groupName.localizedCaseInsensitiveCompare($1.groupName) {
                case .orderedAscending:
                    return true
                case .orderedDescending:
                    return false
                case .orderedSame:
                    return $0.groupId.hexadecimalString < $0.groupId.hexadecimalString
                }
            })
            return (recipientResult, groupResult)
        }

        let recipientSectionItems = blockedRecipients.map { blockedRecipient in
            OWSTableItem(
                dequeueCellBlock: { tableView in
                    let cell = tableView.dequeueReusableCell(ContactTableViewCell.self).owsFailUnwrap("must exist")
                    var config = ContactCellView.Configuration(
                        address: blockedRecipient.address,
                        localUserDisplayMode: .asUser,
                    )
                    config.attributedSubtitle = Self.localizedBlockedAt(blockedRecipient.blockedAt).map(NSAttributedString.init(string:))
                    databaseStorage.read { tx in
                        cell.configure(configuration: config, transaction: tx)
                    }
                    return cell
                },
                actionBlock: { [weak self] in
                    guard let self else { return }
                    BlockListUIUtils.showUnblockAddressActionSheet(blockedRecipient.address, from: self) { isBlocked in
                        if !isBlocked {
                            // Reload if unblocked.
                            self.updateContactList(reloadTableView: true)
                        }
                    }
                },
            )
        }
        if !recipientSectionItems.isEmpty {
            contents.add(OWSTableSection(
                title: NSLocalizedString(
                    "BLOCK_LIST_BLOCKED_USERS_SECTION",
                    comment: "Section header for users that have been blocked",
                ),
                items: recipientSectionItems,
            ))
        }

        let groupSectionItems = blockedGroups.map { blockedGroup in
            return OWSTableItem(
                dequeueCellBlock: { tableView in
                    let cell = tableView.dequeueReusableCell(ContactTableViewCell.self).owsFailUnwrap("must exist")
                    var config = ContactCellView.Configuration(
                        name: blockedGroup.groupName,
                        avatar: blockedGroup.groupAvatar,
                    )
                    config.attributedSubtitle = Self.localizedBlockedAt(blockedGroup.blockedAt).map(NSAttributedString.init(string:))
                    databaseStorage.read { tx in
                        cell.configure(configuration: config, transaction: tx)
                    }
                    return cell
                },
                actionBlock: { [weak self] in
                    guard let self else { return }
                    BlockListUIUtils.showUnblockGroupActionSheet(
                        groupId: blockedGroup.groupId,
                        groupNameOrDefault: blockedGroup.groupName,
                        from: self,
                        completion: { isBlocked in
                            if !isBlocked {
                                self.updateContactList(reloadTableView: true)
                            }
                        },
                    )
                },
            )
        }
        if !groupSectionItems.isEmpty {
            contents.add(OWSTableSection(
                title: NSLocalizedString(
                    "BLOCK_LIST_BLOCKED_GROUPS_SECTION",
                    comment: "Section header for groups that have been blocked",
                ),
                items: groupSectionItems,
            ))
        }

        setContents(contents, shouldReload: reloadTableView)
    }

    private static func localizedBlockedAt(_ blockedAt: BlockedTimestamp) -> String? {
        guard let blockedAtDate = blockedAt.asDate else {
            return nil
        }
        let format = OWSLocalizedString(
            "BLOCKED_AT",
            comment: "Shown as a subtitle for recipients & groups you've blocked to indicate when you blocked them. The replacement is a formatted date.",
        )
        return String.nonPluralLocalizedStringWithFormat(format, DateUtil.dateFormatter.string(from: blockedAtDate))
    }
}

extension BlockListViewController: ContactsViewHelperObserver {

    func contactsViewHelperDidUpdateContacts() {
        updateContactList(reloadTableView: true)
    }
}

extension BlockListViewController: AddToBlockListDelegate {

    func addToBlockListComplete() {
        navigationController?.popToViewController(self, animated: true)
    }
}
