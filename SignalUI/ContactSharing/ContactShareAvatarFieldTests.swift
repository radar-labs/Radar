//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing
import UIKit

@testable import SignalServiceKit
@testable import SignalUI

@MainActor
struct ContactShareAvatarFieldTests {

    private let redImageData = makeImageData(color: .red)
    private let blueImageData = makeImageData(color: .blue)

    @Test
    func testOffersTheSystemContactPhotoFirstAndSelectsIt() throws {
        let field = try #require(ContactShareAvatarField(contactShareDraft: makeDraft(
            systemContactAvatarImageData: redImageData,
            signalAvatarImageData: blueImageData,
        )))

        #expect(field.options.map(\.source) == [.systemContact, .signal])
        #expect(field.selectedSource == .systemContact)
    }

    @Test
    func testSelectsTheSignalPhotoWhenThereIsNoSystemContactPhoto() throws {
        let field = try #require(ContactShareAvatarField(contactShareDraft: makeDraft(signalAvatarImageData: blueImageData)))

        #expect(field.options.map(\.source) == [.signal])
        #expect(field.selectedSource == .signal)
    }

    @Test
    func testOffersIdenticalPhotosOnce() throws {
        let field = try #require(ContactShareAvatarField(contactShareDraft: makeDraft(
            systemContactAvatarImageData: redImageData,
            signalAvatarImageData: redImageData,
        )))

        #expect(field.options.map(\.source) == [.systemContact])
    }

    @Test
    func testHasNoFieldWhenThereAreNoPhotos() {
        #expect(ContactShareAvatarField(contactShareDraft: makeDraft()) == nil)
    }

    @Test
    func testSharesTheSelectedPhoto() throws {
        let field = try #require(ContactShareAvatarField(contactShareDraft: makeDraft(
            systemContactAvatarImageData: redImageData,
            signalAvatarImageData: blueImageData,
        )))
        field.selectedSource = .signal

        let result = makeDraft()
        field.applyToContact(contact: result)

        #expect(result.selectedAvatarImageData == blueImageData)
    }

    @Test
    func testSharesNoPhotoWhenInitialsAreSelected() throws {
        let field = try #require(ContactShareAvatarField(contactShareDraft: makeDraft(systemContactAvatarImageData: redImageData)))
        field.selectedSource = nil

        let result = makeDraft()
        field.applyToContact(contact: result)

        #expect(result.selectedAvatarImageData == nil)
    }

    // MARK: - Helpers

    private func makeDraft(
        systemContactAvatarImageData: Data? = nil,
        signalAvatarImageData: Data? = nil,
    ) -> ContactShareDraft {
        ContactShareDraft(
            name: OWSContactName(givenName: "Ada", familyName: "Lovelace"),
            addresses: [],
            emails: [],
            phoneNumbers: [],
            aci: nil,
            signalNickname: nil,
            signalNote: nil,
            existingAvatarAttachment: nil,
            systemContactAvatarImageData: systemContactAvatarImageData,
            signalAvatarImageData: signalAvatarImageData,
            selectedAvatarImageData: systemContactAvatarImageData ?? signalAvatarImageData,
        )
    }

    private static func makeImageData(color: UIColor) -> Data {
        UIGraphicsImageRenderer(size: .square(4)).pngData { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: .square(4)))
        }
    }
}
