//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI
import SwiftUI

// MARK: - ViewController

class UsernameOnboardingViewController: HostingController<UsernameOnboardingView> {
    init(
        context: UsernameOnboardingViewModel.Context,
        onConfirm: @escaping (Usernames.HashedUsername) -> Void,
        onSkip: @escaping () -> Void
    ) {
        let viewModel = UsernameOnboardingViewModel(context: context)
        super.init(wrappedView: UsernameOnboardingView(
            viewModel: viewModel,
            onConfirm: onConfirm,
            onSkip: onSkip
        ))
        OWSTableViewController2.removeBackButtonText(viewController: self)
    }
}

// MARK: - ViewModel

@MainActor
class UsernameOnboardingViewModel: ObservableObject {
    struct Context {
        let localUsernameManager: LocalUsernameManager
    }

    enum State: Equatable {
        case empty
        case tooShort
        case cannotStartWithDigit
        case invalidCharacters
        case checking
        case available(username: Usernames.ParsedUsername, hashedUsername: Usernames.HashedUsername)
        case unavailable
        case rateLimited
        case networkError
        case unknownError
    }

    @Published private(set) var nickname: String = ""
    @Published private(set) var discriminatorInput: String = String(format: "%02d", Int.random(in: 0...99))
    @Published private(set) var state: State = .empty

    private let context: Context
    private var reservationTask: Task<Void, Never>?
    private let minNicknameLength: UInt32 = RemoteConfig.current.minNicknameLength
    private let maxNicknameLength: UInt32 = RemoteConfig.current.maxNicknameLength

    init(context: Context) {
        self.context = context
    }

    var confirmedUsername: Usernames.HashedUsername? {
        if case .available(_, let hashed) = state { return hashed }
        return nil
    }

    func nicknameDidChange(_ newNickname: String) {
        nickname = newNickname
        reservationTask?.cancel()

        guard !newNickname.isEmpty else {
            state = .empty
            return
        }

        state = .checking
        triggerReservation(nickname: newNickname, discriminator: discriminatorInput)
    }

    func discriminatorDidChange(_ newDiscriminator: String) {
        let filtered = String(newDiscriminator.filter { $0.isNumber }.prefix(2))
        guard filtered != discriminatorInput else { return }
        discriminatorInput = filtered

        guard !nickname.isEmpty else { return }
        reservationTask?.cancel()
        state = .checking
        triggerReservation(nickname: nickname, discriminator: filtered)
    }

    private func triggerReservation(nickname: String, discriminator: String) {
        let task = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.attemptReservation(forNickname: nickname, desiredDiscriminator: discriminator)
        }
        reservationTask = task
    }

    private func attemptReservation(forNickname nickname: String, desiredDiscriminator: String) async {
        typealias CandidateError = Usernames.HashedUsername.CandidateGenerationError

        let candidates: Usernames.HashedUsername.GeneratedCandidates
        do {
            candidates = try Usernames.HashedUsername.generateCandidates(
                forNickname: nickname,
                minNicknameLength: minNicknameLength,
                maxNicknameLength: maxNicknameLength,
                desiredDiscriminator: desiredDiscriminator.isEmpty ? nil : desiredDiscriminator
            )
        } catch CandidateError.nicknameTooShort {
            state = .tooShort
            return
        } catch CandidateError.nicknameCannotStartWithDigit {
            state = .cannotStartWithDigit
            return
        } catch CandidateError.nicknameContainsInvalidCharacters {
            state = .invalidCharacters
            return
        } catch {
            state = .unknownError
            return
        }

#if DEBUG
        if let hash = candidates.candidateHashes.first,
           let hashedUsername = candidates.candidate(matchingHash: hash),
           let parsedUsername = Usernames.ParsedUsername(rawUsername: hashedUsername.usernameString) {
            discriminatorInput = parsedUsername.discriminator
            state = .available(username: parsedUsername, hashedUsername: hashedUsername)
            return
        }
#endif

        let result = await context.localUsernameManager.reserveUsername(usernameCandidates: candidates)
        guard !Task.isCancelled else { return }

        switch result {
        case .success(.successful(let parsedUsername, let hashedUsername)):
            discriminatorInput = parsedUsername.discriminator
            state = .available(username: parsedUsername, hashedUsername: hashedUsername)
        case .success(.rejected):
            state = .unavailable
        case .success(.rateLimited):
            state = .rateLimited
        case .failure(.networkError):
            state = .networkError
        case .failure(.otherError):
            state = .unknownError
        }
    }
}

// MARK: - View

struct UsernameOnboardingView: View {
    @ObservedObject var viewModel: UsernameOnboardingViewModel
    let onConfirm: (Usernames.HashedUsername) -> Void
    let onSkip: () -> Void

    @FocusState private var nicknameFocused: Bool
    @FocusState private var discriminatorFocused: Bool

    var body: some View {
        ScrollableContentPinnedFooterView {
            VStack(spacing: 0) {
                Spacer().frame(height: 36)
                illustrationView
                Spacer().frame(height: 28)
                Text(OWSLocalizedString(
                    "USERNAME_ONBOARDING_TITLE",
                    comment: "Title for the username setup screen shown during onboarding."
                ))
                .font(Font(UIFont.dynamicTypeFont(ofStandardSize: 26)))
                .fontWeight(.semibold)
                .foregroundStyle(Color.Signal.label)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                Spacer().frame(height: 12)

                Text(OWSLocalizedString(
                    "USERNAME_ONBOARDING_SUBTITLE",
                    comment: "Subtitle for the username setup screen during onboarding, explaining what usernames are used for on Radar and Signal."
                ))
                .font(.body)
                .foregroundStyle(Color.Signal.secondaryLabel)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

                Spacer().frame(height: 32)
                textFieldsRow
                Spacer().frame(height: 10)
                statusView
                Spacer().frame(height: 16)
            }
        } pinnedFooter: {
            Button {
                guard let hashedUsername = viewModel.confirmedUsername else { return }
                onConfirm(hashedUsername)
            } label: {
                Text(OWSLocalizedString(
                    "USERNAME_ONBOARDING_CONFIRM_BUTTON",
                    comment: "Button label to confirm the chosen username on the username setup screen during onboarding."
                ))
            }
            .buttonStyle(Registration.UI.LargePrimaryButtonStyle())
            .disabled(viewModel.confirmedUsername == nil)
            .padding(.horizontal, 40)

            Spacer().frame(height: 16)

            Button(action: onSkip) {
                Text(CommonStrings.skipButton)
                    .font(.headline)
                    .foregroundStyle(Color.Signal.accent)
            }
            .padding(.horizontal, 40)

            Spacer().frame(height: 8)
        }
        .onAppear { nicknameFocused = true }
    }

    // MARK: Illustration

    private var illustrationView: some View {
        Image("username-onboarding-illustration")
            .resizable()
            .scaledToFit()
            .frame(width: 120, height: 120)
    }

    // MARK: Text Fields

    private var textFieldsRow: some View {
        HStack(spacing: 8) {
            TextField(
                OWSLocalizedString(
                    "USERNAME_SELECTION_TEXT_FIELD_PLACEHOLDER",
                    comment: "The placeholder text for a text field where users type a desired username."
                ),
                text: Binding(
                    get: { viewModel.nickname },
                    set: { viewModel.nicknameDidChange($0) }
                )
            )
            .focused($nicknameFocused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(Color.Signal.label)
            .padding(.horizontal, 16)
            .frame(height: 52)
            .background(Color.Signal.secondaryFill)
            .clipShape(Capsule())

            discriminatorPill
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private var discriminatorPill: some View {
        ZStack {
            Color.Signal.secondaryFill

            if case .checking = viewModel.state {
                ProgressView()
                    .progressViewStyle(.circular)
            } else {
                TextField("00", text: Binding(
                    get: { viewModel.discriminatorInput },
                    set: { newValue in
                        let filtered = String(newValue.filter { $0.isNumber }.prefix(2))
                        viewModel.discriminatorDidChange(filtered)
                    }
                ))
                .focused($discriminatorFocused)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.Signal.label)
            }
        }
        .frame(width: 64, height: 52)
        .clipShape(Capsule())
        .onTapGesture { discriminatorFocused = true }
    }

    // MARK: Status

    @ViewBuilder
    private var statusView: some View {
        Group {
            switch viewModel.state {
            case .available:
                Label {
                    Text(OWSLocalizedString(
                        "USERNAME_ONBOARDING_AVAILABLE_STATUS",
                        comment: "Status label shown when the entered username is available to claim."
                    ))
                } icon: {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color.Signal.green)
                .font(.subheadline.weight(.medium))

            case .unavailable:
                Label {
                    Text(OWSLocalizedString(
                        "USERNAME_SELECTION_NOT_AVAILABLE_ERROR_MESSAGE",
                        comment: "An error message shown when the user wants to set their username to an unavailable value."
                    ))
                } icon: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Color.Signal.red)
                .font(.subheadline.weight(.medium))

            case .tooShort:
                Text(String.localizedStringWithFormat(
                    OWSLocalizedString(
                        "USERNAME_SELECTION_TOO_SHORT_ERROR_MESSAGE_%d",
                        tableName: "PluralAware",
                        comment: "An error message shown when the user has typed a username that is below the minimum character limit. Embeds {{ %d the minimum character count }}."
                    ),
                    Int(RemoteConfig.current.minNicknameLength)
                ))
                .foregroundStyle(Color.Signal.red)
                .font(.subheadline)

            case .cannotStartWithDigit:
                Text(OWSLocalizedString(
                    "USERNAME_SELECTION_CANNOT_START_WITH_DIGIT_ERROR_MESSAGE",
                    comment: "An error message shown when the user has typed a username that starts with a digit, which is invalid."
                ))
                .foregroundStyle(Color.Signal.red)
                .font(.subheadline)

            case .invalidCharacters:
                Text(OWSLocalizedString(
                    "USERNAME_SELECTION_INVALID_CHARACTERS_ERROR_MESSAGE",
                    comment: "An error message shown when the user has typed a username that has invalid characters. The character ranges \"a-z\", \"0-9\", \"_\" should not be translated, as they are literal."
                ))
                .foregroundStyle(Color.Signal.red)
                .font(.subheadline)

            case .rateLimited:
                Text(OWSLocalizedString(
                    "USERNAME_SELECTION_RESERVATION_RATE_LIMITED_ERROR_MESSAGE",
                    comment: "An error message shown when the user has attempted too many username reservations."
                ))
                .foregroundStyle(Color.Signal.red)
                .font(.subheadline)

            case .networkError:
                Text(Usernames.RemoteMutationError.networkError.localizedDescription)
                    .foregroundStyle(Color.Signal.red)
                    .font(.subheadline)

            case .unknownError:
                Text(CommonStrings.somethingWentWrongTryAgainLaterError)
                    .foregroundStyle(Color.Signal.red)
                    .font(.subheadline)

            case .empty, .checking:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

// MARK: - Preview

#if DEBUG

@available(iOS 17, *)
#Preview {
    UsernameOnboardingView(
        viewModel: UsernameOnboardingViewModel(context: .init(
            localUsernameManager: DependenciesBridge.shared.localUsernameManager
        )),
        onConfirm: { _ in },
        onSkip: {}
    )
}

#endif
