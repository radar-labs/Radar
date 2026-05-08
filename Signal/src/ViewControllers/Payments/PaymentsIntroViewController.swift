//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

class PaymentsIntroViewController: HostingController<PaymentsIntroView> {
    init(onContinue: @escaping () -> Void) {
        super.init(wrappedView: PaymentsIntroView(onContinue: onContinue))
        OWSTableViewController2.removeBackButtonText(viewController: self)
    }
}

// MARK: -

struct PaymentsIntroView: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollableContentPinnedFooterView {
            VStack(spacing: 0) {
                Spacer().frame(height: 48)

                iconsRow

                Spacer().frame(height: 48)

                Text(OWSLocalizedString(
                    "PAYMENTS_INTRO_TITLE",
                    comment: "Title for the Payments introduction screen shown during onboarding."
                ))
                .font(Font(UIFont.dynamicTypeFont(ofStandardSize: 28)))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Signal.label)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                Spacer().frame(height: 32)

                Text(OWSLocalizedString(
                    "PAYMENTS_INTRO_SUBTITLE",
                    comment: "Subtitle for the Payments introduction screen."
                ))
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.Signal.accent)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                Spacer().frame(height: 32)

                Text(OWSLocalizedString(
                    "PAYMENTS_INTRO_BODY",
                    comment: "Body text for the Payments introduction screen explaining the Bitcoin Lightning Network."
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
        }
        .background(Color.Signal.groupedBackground)
    }

    private var iconsRow: some View {
        HStack(spacing: 15) {
            Image("radar-logo")
                .resizable()
                .scaledToFit()
                .frame(width: 75, height: 75)

            Image("bitcoin-icon")
                .resizable()
                .scaledToFit()
                .frame(width: 75, height: 75)
        }
    }
}

// MARK: - Preview

#if DEBUG

@available(iOS 17, *)
#Preview {
    PaymentsIntroView(onContinue: {})
}

#endif
