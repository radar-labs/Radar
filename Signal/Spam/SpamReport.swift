//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient
import SignalServiceKit

struct SpamReport {
    let aci: Aci
    let serverGuids: Set<String>
    let reportingToken: SpamReportingToken?

    func submit(using networkManager: NetworkManagerProtocol) async throws {
        Logger.info("reporting \(serverGuids.count) message(s) from \(aci) as spam (reportingToken? \(reportingToken != nil)")
        try await withThrowingTaskGroup(of: Void.self) { group in
            for guid in serverGuids {
                let request = OWSRequestFactory.reportSpam(from: aci, withServerGuid: guid, reportingToken: reportingToken)
                group.addTask {
                    _ = try await networkManager.asyncRequest(request)
                }
            }
            try await group.waitForAll()
        }
        Logger.info("reported \(serverGuids.count) message(s) from \(aci) as spam")
    }
}
