//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

public class AudioWaveformManagerMock: AudioWaveformManager {

    public init() {}

    public func cachedAudioWaveform(attachment: Attachment) -> Task<AudioWaveform, Error> {
        return Task {
            return try AudioWaveform(levels: [0])
        }
    }

    public func computeAudioWaveform(audioFilePath: String) throws -> AudioWaveform {
        return try AudioWaveform(levels: [0])
    }

    public func computeAudioWaveform(encryptedAudioFilePath: String, attachmentKey: AttachmentKey, plaintextDataLength: UInt32, mimeType: String) throws -> AudioWaveform {
        return try AudioWaveform(levels: [0])
    }
}

#endif
