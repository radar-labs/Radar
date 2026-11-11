//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

enum CLVRowChangeType {
    case delete(oldIndexPath: IndexPath)
    case insert(newIndexPath: IndexPath)
    case move(oldIndexPath: IndexPath, newIndexPath: IndexPath)
    case update(oldIndexPath: IndexPath)

    // MARK: -

    var logSafeDescription: String {
        switch self {
        case .delete(let oldIndexPath):
            return "delete(oldIndexPath: \(oldIndexPath))"
        case .insert(let newIndexPath):
            return "insert(newIndexPath: \(newIndexPath))"
        case .move(let oldIndexPath, let newIndexPath):
            return "move(oldIndexPath: \(oldIndexPath), newIndexPath: \(newIndexPath))"
        case .update(let oldIndexPath):
            return "update(oldIndexPath: \(oldIndexPath))"
        }
    }
}

// MARK: -

struct CLVRowChange {
    let type: CLVRowChangeType
    let threadUniqueId: String

    // MARK: -

    var logSafeDescription: String {
        "\(type), \(threadUniqueId)"
    }
}

// MARK: -

enum CLVLoadResult {
    case renderStateForReset(renderState: CLVRenderState)
    case renderStateWithRowChanges(renderState: CLVRenderState, rowChanges: [CLVRowChange])
    case reloadTable
    case noChanges
}

// MARK: -

public class CLVLoader {

    static func loadRenderStateForReset(viewInfo: CLVViewInfo, transaction: DBReadTransaction) -> CLVLoadResult {
        AssertIsOnMainThread()

        let renderState = Self.loadRenderStateInternal(viewInfo: viewInfo, transaction: transaction)
        return CLVLoadResult.renderStateForReset(renderState: renderState)
    }

    private static func loadRenderStateInternal(viewInfo: CLVViewInfo, transaction: DBReadTransaction) -> CLVRenderState {
        let threadFinder = ThreadFinder()
        let isViewingArchive = viewInfo.chatListMode == .archive

        let pinnedThreadUniqueIds: [String]
        let visibleThreadUniqueIds: [String]
        if isViewingArchive {
            pinnedThreadUniqueIds = []
            visibleThreadUniqueIds = threadFinder.visibleArchivedThreadUniqueIds(transaction: transaction)
        } else {
            let pinnedThreadManager = DependenciesBridge.shared.pinnedThreadManager
            pinnedThreadUniqueIds = pinnedThreadManager.pinnedThreads(
                filterToVisible: true,
                tx: transaction,
            ).map(\.uniqueId)
            visibleThreadUniqueIds = threadFinder.visibleInboxThreadUniqueIds(
                filteredBy: viewInfo.inboxFilter,
                requiredVisibleThreadIds: viewInfo.requiredVisibleThreadIds,
                transaction: transaction,
            )
        }

        let pinnedThreadUniqueIdsToRender = Set(pinnedThreadUniqueIds).intersection(visibleThreadUniqueIds)

        return CLVRenderState(
            viewInfo: viewInfo,
            // Preserve the order from pinnedThreadUniqueIds
            pinnedThreadUniqueIds: pinnedThreadUniqueIds.filter({ pinnedThreadUniqueIdsToRender.contains($0) }),
            // Preserve the order from visibleThreadUniqueIds
            unpinnedThreadUniqueIds: visibleThreadUniqueIds.filter({ !pinnedThreadUniqueIdsToRender.contains($0) }),
        )
    }

    static func loadRenderStateAndDiff(
        viewInfo: CLVViewInfo,
        updatedItemIds: Set<String>,
        lastRenderState: CLVRenderState,
        transaction: DBReadTransaction,
    ) -> CLVLoadResult {
        do {
            return try loadRenderStateAndDiffInternal(
                viewInfo: viewInfo,
                updatedItemIds: updatedItemIds,
                lastRenderState: lastRenderState,
                transaction: transaction,
            )
        } catch {
            owsFailDebug("Error: \(error)")
            // Fail over to reloading the table view with a new render state.
            return loadRenderStateForReset(viewInfo: viewInfo, transaction: transaction)
        }
    }

    static func newRenderStateWithViewInfo(_ viewInfo: CLVViewInfo, lastRenderState: CLVRenderState) -> CLVLoadResult {
        .renderStateWithRowChanges(
            renderState: CLVRenderState(
                viewInfo: viewInfo,
                pinnedThreadUniqueIds: lastRenderState.pinnedThreadUniqueIds,
                unpinnedThreadUniqueIds: lastRenderState.unpinnedThreadUniqueIds,
            ),
            rowChanges: [],
        )
    }

    private static func loadRenderStateAndDiffInternal(
        viewInfo: CLVViewInfo,
        updatedItemIds allUpdatedItemIds: Set<String>,
        lastRenderState: CLVRenderState,
        transaction: DBReadTransaction,
    ) throws -> CLVLoadResult {

        // Ignore updates to non-visible threads.
        var updatedItemIds = Set<String>()
        for threadId in allUpdatedItemIds {
            guard let thread = TSThread.fetchViaCache(uniqueId: threadId, transaction: transaction) else {
                // Missing thread, it was deleted and should no longer be visible.
                continue
            }
            if thread.shouldThreadBeVisible {
                updatedItemIds.insert(threadId)
            }
        }

        let newRenderState = Self.loadRenderStateInternal(viewInfo: viewInfo, transaction: transaction)

        let countsChanged = lastRenderState.pinnedThreadUniqueIds.count != newRenderState.pinnedThreadUniqueIds.count
            || lastRenderState.unpinnedThreadUniqueIds.count != newRenderState.unpinnedThreadUniqueIds.count

        if countsChanged {
            return .renderStateForReset(renderState: newRenderState)
        }

        if lastRenderState.sections.map(\.type) != newRenderState.sections.map(\.type) {
            return .renderStateForReset(renderState: newRenderState)
        }

        // Incremental diff is only safe for in-place updates (read state, last message, etc.)
        let oldPinnedThreadIds: [String] = lastRenderState.pinnedThreadUniqueIds
        let oldUnpinnedThreadIds: [String] = lastRenderState.unpinnedThreadUniqueIds
        let newPinnedThreadIds: [String] = newRenderState.pinnedThreadUniqueIds
        let newUnpinnedThreadIds: [String] = newRenderState.unpinnedThreadUniqueIds

        struct CLVBatchUpdateValue: BatchUpdateValue {
            let threadUniqueId: String
            var batchUpdateId: String { threadUniqueId }
        }

        let oldPinnedValues = oldPinnedThreadIds.map { CLVBatchUpdateValue(threadUniqueId: $0) }
        let newPinnedValues = newPinnedThreadIds.map { CLVBatchUpdateValue(threadUniqueId: $0) }
        let oldUnpinnedValues = oldUnpinnedThreadIds.map { CLVBatchUpdateValue(threadUniqueId: $0) }
        let newUnpinnedValues = newUnpinnedThreadIds.map { CLVBatchUpdateValue(threadUniqueId: $0) }

        let pinnedChangedValues = newPinnedValues.filter { updatedItemIds.contains($0.threadUniqueId) }
        let unpinnedChangedValues = newUnpinnedValues.filter { updatedItemIds.contains($0.threadUniqueId) }

        let pinnedBatchUpdateItems: [BatchUpdate.Item] = try BatchUpdate.build(
            viewType: .uiTableView,
            oldValues: oldPinnedValues,
            newValues: newPinnedValues,
            changedValues: pinnedChangedValues,
        )
        let unpinnedBatchUpdateItems: [BatchUpdate.Item] = try BatchUpdate.build(
            viewType: .uiTableView,
            oldValues: oldUnpinnedValues,
            newValues: newUnpinnedValues,
            changedValues: unpinnedChangedValues,
        )

        func rowChangeType(forBatchUpdateType batchUpdateType: BatchUpdateType, section: (CLVRenderState) -> Int) -> CLVRowChangeType {
            switch batchUpdateType {
            case .delete(let oldIndex):
                .delete(oldIndexPath: IndexPath(row: oldIndex, section: section(lastRenderState)))
            case .insert(let newIndex):
                .insert(newIndexPath: IndexPath(row: newIndex, section: section(newRenderState)))
            case .move(let oldIndex, let newIndex):
                .move(
                    oldIndexPath: IndexPath(row: oldIndex, section: section(lastRenderState)),
                    newIndexPath: IndexPath(row: newIndex, section: section(newRenderState)),
                )
            case .update(let oldIndex, _):
                .update(oldIndexPath: IndexPath(row: oldIndex, section: section(lastRenderState)))
            }
        }

        func rowChanges(forBatchUpdateItems batchUpdateItems: [BatchUpdate<CLVBatchUpdateValue>.Item], section: (CLVRenderState) -> Int) -> [CLVRowChange] {
            batchUpdateItems.map { item in
                CLVRowChange(
                    type: rowChangeType(forBatchUpdateType: item.updateType, section: section),
                    threadUniqueId: item.value.threadUniqueId,
                )
            }
        }

        let pinnedRowChanges = rowChanges(forBatchUpdateItems: pinnedBatchUpdateItems, section: { $0.sectionIndex(for: .pinned)! })
        let unpinnedRowChanges = rowChanges(forBatchUpdateItems: unpinnedBatchUpdateItems, section: { $0.sectionIndex(for: .unpinned)! })

        let allRowChanges = pinnedRowChanges + unpinnedRowChanges

        return .renderStateWithRowChanges(renderState: newRenderState, rowChanges: allRowChanges)
    }
}

// MARK: -

extension Collection where Element: Equatable {
    func firstIndexAsInt(of element: Element) -> Int? {
        guard let index = firstIndex(of: element) else { return nil }
        return distance(from: startIndex, to: index)
    }
}
