//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

class RegistrationSetupCompleteViewController: HostingController<RegistrationSetupCompleteView> {
    init(onContinue: @escaping () -> Void) {
        super.init(wrappedView: RegistrationSetupCompleteView(onContinue: onContinue))
        OWSTableViewController2.removeBackButtonText(viewController: self)
    }
}

// MARK: -

struct RegistrationSetupCompleteView: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollableContentPinnedFooterView {
            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .foregroundColor(Color.Signal.accent)

                Spacer().frame(height: 48)

                VStack(spacing: 24) {
                    Text(OWSLocalizedString(
                        "ONBOARDING_SETUP_COMPLETE_TITLE",
                        comment: "Title for the setup complete screen shown at the end of the onboarding flow."
                    ))
                    .font(Font(UIFont.dynamicTypeFont(ofStandardSize: 28)))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.Signal.label)
                    .multilineTextAlignment(.center)

                    Text(OWSLocalizedString(
                        "ONBOARDING_SETUP_COMPLETE_SUBTITLE",
                        comment: "Subtitle for the setup complete screen shown at the end of the onboarding flow."
                    ))
                    .font(.body)
                    .foregroundStyle(Color.Signal.secondaryLabel)
                    .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)

                Spacer()
            }
            .frame(maxWidth: .infinity)
        } pinnedFooter: {
            Button {
                onContinue()
            } label: {
                Text(CommonStrings.continueButton)
            }
            .buttonStyle(Registration.UI.LargePrimaryButtonStyle())
            .padding(.horizontal, 40)
        }
        .background(Color.Signal.groupedBackground)
    }
}

// MARK: -

#if DEBUG

@available(iOS 17, *)
#Preview {
    RegistrationSetupCompleteViewController(onContinue: { print("Continue tapped") })
}

#endif
