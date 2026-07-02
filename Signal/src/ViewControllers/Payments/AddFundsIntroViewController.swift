// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only

import SignalServiceKit
import SignalUI
import SwiftUI

class AddFundsIntroViewController: HostingController<AddFundsIntroView> {
    init(onContinue: @escaping () -> Void, onSkip: @escaping () -> Void) {
        super.init(wrappedView: AddFundsIntroView(onContinue: onContinue, onSkip: onSkip))
        OWSTableViewController2.removeBackButtonText(viewController: self)
    }
}

// MARK: -

struct AddFundsIntroView: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ScrollableContentPinnedFooterView {
            VStack(spacing: 0) {
                Spacer()

                iconView

                Spacer().frame(height: 48)

                VStack(spacing: 32) {
                    Text(OWSLocalizedString(
                        "PAYMENTS_ADD_FUNDS_INTRO_TITLE",
                        comment: "Title for the Add Funds onboarding screen."
                    ))
                    .font(Font(UIFont.dynamicTypeFont(ofStandardSize: 28)))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Signal.label)

                    Text(OWSLocalizedString(
                        "PAYMENTS_ADD_FUNDS_INTRO_SUBTITLE",
                        comment: "Subtitle for the Add Funds onboarding screen explaining where to deposit from."
                    ))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.Signal.secondaryLabel)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                }

                Spacer()
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
                onSkip()
            } label: {
                Text(OWSLocalizedString(
                    "PAYMENTS_ADD_FUNDS_INTRO_SKIP",
                    comment: "Button label to skip the Add Funds step during payments onboarding."
                ))
                .font(.headline)
                .foregroundStyle(Color.Signal.accent)
            }

            Spacer().frame(height: 8)
        }
        .background(Color.Signal.groupedBackground)
    }

    private var iconView: some View {
        Image("payments-add-funds-bitcoin")
            .resizable()
            .scaledToFit()
            .frame(width: 125, height: 125)
    }
}

// MARK: - Preview

#if DEBUG

@available(iOS 17, *)
#Preview {
    AddFundsIntroView(onContinue: {}, onSkip: {})
}

#endif
