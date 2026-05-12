//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

@MainActor
class PaymentsOnboardingCoordinator {

    private weak var navController: UINavigationController?
    private var depositObserver: NSObjectProtocol?

    // MARK: - Entry point

    func prepareForPresentation(inNavController navController: UINavigationController) -> UIViewController {
        self.navController = navController

        let existingUsername: Usernames.ParsedUsername? = SSKEnvironment.shared.databaseStorageRef.read { tx in
            switch DependenciesBridge.shared.localUsernameManager.usernameState(tx: tx) {
            case .available(let username, _):
                return Usernames.ParsedUsername(rawUsername: username)
            case .linkCorrupted(let username):
                return Usernames.ParsedUsername(rawUsername: username)
            case .unset, .usernameAndLinkCorrupted:
                return nil
            }
        }

        let context = UsernameOnboardingViewModel.Context(
            localUsernameManager: DependenciesBridge.shared.localUsernameManager,
            existingUsername: existingUsername
        )
        return UsernameOnboardingViewController(
            context: context,
            onConfirm: { [self] in showIntro() },
            onSkip: { [self] in showIntro() }
        )
    }

    // MARK: - Navigation

    private func showIntro() {
        guard let navController else { return }

        navController.pushViewController(
            PaymentsIntroViewController(onContinue: { [self] in showAddFundsIntro() }),
            animated: true
        )
    }

    private func showAddFundsIntro() {
        guard let navController else { return }

        if !SSKEnvironment.shared.paymentsHelperRef.arePaymentsEnabled {
            Task.detached(priority: .userInitiated) {
                SSKEnvironment.shared.databaseStorageRef.write { tx in
                    SSKEnvironment.shared.paymentsHelperRef.enablePayments(transaction: tx)
                }
            }
        }

        navController.pushViewController(
            AddFundsIntroViewController(
                onContinue: { [self] in showAddFunds() },
                onSkip: { [self] in showSetupComplete() }
            ),
            animated: true
        )
    }

    private func showAddFunds() {
        guard let navController else { return }

        startObservingDeposit()
        navController.pushViewController(
            PaymentsTransferInViewController(isOnboarding: true, onContinue: { [weak self] in self?.showSetupComplete() }),
            animated: true
        )
    }

    private func showDepositReceived(amountSats: String) {
        depositObserver = nil
        guard let navController else { return }

        navController.pushViewController(
            DepositReceivedViewController(
                amountSats: amountSats,
                onContinue: { [weak self] in self?.showSetupComplete() },
                onDepositMore: { [weak self, weak navController] in
                    navController?.popViewController(animated: true)
                    self?.startObservingDeposit()
                }
            ),
            animated: true
        )
    }

    private func showSetupComplete() {
        guard let navController else { return }

        navController.pushViewController(
            RegistrationSetupCompleteViewController(onContinue: { [weak navController] in
                guard let navController else { return }
                if let presentingVC = navController.presentingViewController {
                    presentingVC.dismiss(animated: true)
                }
            }),
            animated: true
        )
    }

    // MARK: - Demo / testing

#if DEBUG
    func startDemoFlow() {
        let delays: [Double] = [2.5, 4.5, 6.5, 8.5, 10.5, 12.5, 14.5]
        let actions: [@MainActor () -> Void] = [
            { [self] in showIntro() },
            { [self] in showAddFundsIntro() },
            { [self] in showAddFunds() },
            { [self] in showDepositReceived(amountSats: "1,250") },
            { [self] in showSetupComplete() },
        ]
        for (i, action) in actions.enumerated() {
            let delay = delays[i]
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                action()
            }
        }
    }
#endif

    // MARK: - Deposit observation

    private func startObservingDeposit() {
        depositObserver = NotificationCenter.default.addObserver(
            forName: PaymentsImpl.incomingPaymentReceived,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let picoMob = notification.userInfo?["picoMob"] as? Int64 ?? 0
            let formatted = NumberFormatter.localizedString(
                from: NSNumber(value: picoMob),
                number: .decimal
            )
            Task { @MainActor [weak self] in
                self?.showDepositReceived(amountSats: formatted)
            }
        }
    }
}
