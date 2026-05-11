//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

class DepositReceivedViewController: HostingController<DepositReceivedView> {
    init(
        amountSats: String,
        onContinue: @escaping () -> Void,
        onDepositMore: @escaping () -> Void
    ) {
        super.init(wrappedView: DepositReceivedView(
            amountSats: amountSats,
            onContinue: onContinue,
            onDepositMore: onDepositMore
        ))
        OWSTableViewController2.removeBackButtonText(viewController: self)
    }
}

// MARK: -

struct DepositReceivedView: View {
    let amountSats: String
    let onContinue: () -> Void
    let onDepositMore: () -> Void

    var body: some View {
        ScrollableContentPinnedFooterView {
            VStack(spacing: 0) {
                Spacer().frame(height: 48)

                HStack(spacing: 12) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.Signal.accent)

                    Text(OWSLocalizedString(
                        "DEPOSIT_RECEIVED_TITLE",
                        comment: "Title for the Deposit Received screen shown after a deposit is confirmed."
                    ))
                    .font(Font(UIFont.dynamicTypeFont(ofStandardSize: 28)))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Signal.label)
                }

                Spacer().frame(height: 32)

                amountCard

                Spacer().frame(height: 32)

                Text(OWSLocalizedString(
                    "DEPOSIT_RECEIVED_SUBTITLE",
                    comment: "Subtitle on the Deposit Received screen encouraging the user to start sending payments."
                ))
                .font(.body)
                .foregroundStyle(Color.Signal.secondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                Spacer().frame(height: 16)
            }
        } pinnedFooter: {
            Button {
                onContinue()
            } label: {
                Text(CommonStrings.continueButton)
            }
            .buttonStyle(Registration.UI.LargePrimaryButtonStyle())
            .padding(.horizontal, 40)

            Spacer().frame(height: 16)

            Button {
                onDepositMore()
            } label: {
                Text(OWSLocalizedString(
                    "DEPOSIT_RECEIVED_DEPOSIT_MORE",
                    comment: "Button on the Deposit Received screen that lets the user deposit additional funds."
                ))
                .font(.headline)
                .foregroundStyle(Color.Signal.accent)
            }

            Spacer().frame(height: 8)
        }
        .background(Color.Signal.groupedBackground)
    }

    private var amountCard: some View {
        HStack(spacing: 12) {
            Text(amountSats)
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(Color.Signal.label)

            Text(OWSLocalizedString(
                "DEPOSIT_RECEIVED_SATS_LABEL",
                comment: "Unit label 'sats' (satoshis) shown next to an amount on the Deposit Received screen."
            ))
            .font(.system(size: 52, weight: .regular))
            .foregroundStyle(Color.Signal.label.opacity(0.5))
        }
        .padding(20)
        .background(Color.Signal.secondaryFill)
        .cornerRadius(20)
    }
}

// MARK: - Preview

#if DEBUG

@available(iOS 17, *)
#Preview {
    DepositReceivedView(
        amountSats: "1,373",
        onContinue: {},
        onDepositMore: {}
    )
}

#endif
