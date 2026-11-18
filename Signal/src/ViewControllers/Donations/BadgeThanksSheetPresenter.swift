//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

class BadgeThanksSheetPresenter {
    private enum Deps {
        static var donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore {
            DependenciesBridge.shared.donationReceiptCredentialResultStore
        }
    }

    private let db: DB
    private let donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore
    private let profileBadgeManager: ProfileBadgeManager

    private var redemptionSuccess: DonationReceiptCredentialRedemptionSuccess
    private let successMode: DonationReceiptCredentialResultStore.Mode

    private init(
        db: DB,
        donationReceiptCredentialResultStore: DonationReceiptCredentialResultStore,
        profileBadgeManager: ProfileBadgeManager,
        redemptionSuccess: DonationReceiptCredentialRedemptionSuccess,
        successMode: DonationReceiptCredentialResultStore.Mode,
    ) {
        self.db = db
        self.donationReceiptCredentialResultStore = donationReceiptCredentialResultStore
        self.profileBadgeManager = profileBadgeManager
        self.redemptionSuccess = redemptionSuccess
        self.successMode = successMode
    }

    static func fromGlobalsWithSneakyTransaction(
        successMode: DonationReceiptCredentialResultStore.Mode,
    ) -> BadgeThanksSheetPresenter? {
        guard
            let redemptionSuccess = SSKEnvironment.shared.databaseStorageRef.read(block: { tx in
                Deps.donationReceiptCredentialResultStore.getRedemptionSuccess(
                    successMode: successMode,
                    tx: tx,
                )
            })
        else {
            owsFailBeta("[Donations] Missing redemption success while trying to present badge thanks! \(successMode)")
            return nil
        }

        return .fromGlobals(
            redemptionSuccess: redemptionSuccess,
            successMode: successMode,
        )
    }

    static func fromGlobals(
        redemptionSuccess: DonationReceiptCredentialRedemptionSuccess,
        successMode: DonationReceiptCredentialResultStore.Mode,
    ) -> BadgeThanksSheetPresenter {
        return BadgeThanksSheetPresenter(
            db: DependenciesBridge.shared.db,
            donationReceiptCredentialResultStore: Deps.donationReceiptCredentialResultStore,
            profileBadgeManager: DependenciesBridge.shared.profileBadgeManager,
            redemptionSuccess: redemptionSuccess,
            successMode: successMode,
        )
    }

    @MainActor
    func presentAndRecordBadgeThanks(
        fromViewController: UIViewController,
    ) async {
        let logger = PrefixedLogger(prefix: "[Donations]", suffix: "\(successMode)")
        logger.info("Preparing to present badge thanks sheet.")

        guard
            let badge = db.read(block: { tx in
                profileBadgeManager.fetchBadgeWithId(redemptionSuccess.badgeID, tx: tx)
            })
        else {
            owsFailDebug("Missing badge for expected badge ID! \(redemptionSuccess.badgeID)", logger: logger)
            return
        }

        logger.info("Showing badge thanks sheet on receipt credential redemption.")
        let badgeThanksSheet = BadgeThanksSheet(
            receiptCredentialRedemptionSuccess: redemptionSuccess,
            newBadge: badge,
        )

        await fromViewController.awaitablePresent(badgeThanksSheet, animated: true)

        await db.awaitableWrite { tx in
            donationReceiptCredentialResultStore.setHasPresentedSuccess(
                successMode: self.successMode,
                tx: tx,
            )
        }
    }
}
