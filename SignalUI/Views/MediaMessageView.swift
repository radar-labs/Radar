//
// Copyright 2017 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SDWebImage
import SignalServiceKit
import UIKit

class MediaMessageView: UIView, AudioPlayerDelegate {

    private let attachment: PreviewableAttachment

    private var audioPlayer: AudioPlayer?
    private lazy var audioPlayButton = UIButton(configuration: .plain())

    // MARK: Initializers

    init(attachment: PreviewableAttachment, contentMode: UIView.ContentMode = .scaleAspectFit) {
        self.attachment = attachment

        super.init(frame: CGRect.zero)

        self.contentMode = contentMode

        recreateViews()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var contentMode: UIView.ContentMode {
        get {
            return super.contentMode
        }
        set {
            switch newValue {
            case .scaleAspectFit:
                super.contentMode = .scaleAspectFit
            case .scaleAspectFill:
                super.contentMode = .scaleAspectFill
            default:
                owsFailDebug("Invalid content mode, only scale aspect fit and fill are supported")
                super.contentMode = .scaleAspectFit
            }
            recreateViews()
        }
    }

    // MARK: - Create Views

    private func recreateViews() {
        audioPlayer = nil
        subviews.forEach { $0.removeFromSuperview() }

        if attachment.rawValue.isLoopingVideo {
            createLoopingVideoPreview()
        } else if attachment.rawValue.isAnimatedImage {
            createAnimatedPreview()
        } else if attachment.isImage {
            createImagePreview()
        } else if attachment.isVideo {
            createVideoPreview()
        } else if attachment.isAudio {
            createAudioPreview()
        } else {
            createGenericPreview()
        }
    }

    private func wrapViewsInVerticalStack(subviews: [UIView]) -> UIView {
        let stackView = UIStackView(arrangedSubviews: subviews)
        stackView.spacing = 10
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.preservesSuperviewLayoutMargins = true
        stackView.isLayoutMarginsRelativeArrangement = true
        return stackView
    }

    private func createAudioPreview() {
        let audioPlayer = AudioPlayer(attachment: attachment, audioBehavior: .playback)
        audioPlayer.delegate = self
        self.audioPlayer = audioPlayer

        var subviews = [UIView]()

        setAudioIconToPlay()
        audioPlayButton.configuration?.baseForegroundColor = .Signal.label
        audioPlayButton.addAction(
            UIAction { [weak self] _ in
                self?.audioPlayButtonPressed()
            },
            for: .primaryActionTriggered,
        )
        let buttonSize = Self.heroViewSize
        audioPlayButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            audioPlayButton.widthAnchor.constraint(equalToConstant: buttonSize),
            audioPlayButton.heightAnchor.constraint(equalToConstant: buttonSize),
        ])
        subviews.append(audioPlayButton)

        if let fileNameLabel = createFileNameLabel() {
            subviews.append(fileNameLabel)
        }

        let fileSizeLabel = createFileSizeLabel()
        subviews.append(fileSizeLabel)

        let stackView = wrapViewsInVerticalStack(subviews: subviews)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
        ])
    }

    private func createLoopingVideoPreview() {
        guard let previewImage = attachment.rawValue.videoPreview() else {
            createGenericPreview()
            return
        }
        let video = LoopingVideo(attachment)

        let loopingVideoView = LoopingVideoView()
        loopingVideoView.video = video
        if contentMode == .scaleAspectFill {
            addSubviewWithScaleAspectFillLayout(view: loopingVideoView, aspectRatio: previewImage.size.aspectRatio)
        } else {
            addSubviewWithScaleAspectFitLayout(view: loopingVideoView, aspectRatio: previewImage.size.aspectRatio)
        }
    }

    private func createAnimatedPreview() {
        guard
            attachment.isImage,
            let image = SDAnimatedImage(contentsOfFile: attachment.rawValue.dataSource.fileUrl.path),
            image.size.width > 0, image.size.height > 0
        else {
            createGenericPreview()
            return
        }

        let animatedImageView = SDAnimatedImageView()
        animatedImageView.image = image
        let aspectRatio = image.size.width / image.size.height

        if contentMode == .scaleAspectFill {
            addSubviewWithScaleAspectFillLayout(view: animatedImageView, aspectRatio: aspectRatio)
        } else {
            addSubviewWithScaleAspectFitLayout(view: animatedImageView, aspectRatio: aspectRatio)
        }
    }

    private func addSubviewWithScaleAspectFitLayout(view: UIView, aspectRatio: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)

        // This emulates the behavior of contentMode = .scaleAspectFit using iOS auto layout constraints.
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: centerXAnchor),
            view.centerYAnchor.constraint(equalTo: centerYAnchor),
            view.widthAnchor.constraint(equalTo: view.heightAnchor, multiplier: aspectRatio),
            view.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
            view.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor),
        ])
    }

    private func addSubviewWithScaleAspectFillLayout(view: UIView, aspectRatio: CGFloat) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)

        // This emulates the behavior of contentMode = .scaleAspectFill using iOS auto layout constraints.
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: centerXAnchor),
            view.centerYAnchor.constraint(equalTo: centerYAnchor),
            view.widthAnchor.constraint(equalTo: view.heightAnchor, multiplier: aspectRatio),
            view.widthAnchor.constraint(greaterThanOrEqualTo: widthAnchor),
            view.heightAnchor.constraint(greaterThanOrEqualTo: heightAnchor),
            view.widthAnchor.constraint(lessThanOrEqualTo: heightAnchor, multiplier: aspectRatio),
            view.heightAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 1 / aspectRatio),
        ])
    }

    private func createImagePreview() {
        guard
            attachment.isImage,
            let image = attachment.rawValue.image(),
            image.size.width > 0, image.size.height > 0
        else {
            createGenericPreview()
            return
        }

        let imageView = UIImageView(image: image)
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        let aspectRatio = image.size.width / image.size.height
        if contentMode == .scaleAspectFill {
            addSubviewWithScaleAspectFillLayout(view: imageView, aspectRatio: aspectRatio)
        } else {
            addSubviewWithScaleAspectFitLayout(view: imageView, aspectRatio: aspectRatio)
        }
    }

    private func createVideoPreview() {
        guard
            attachment.isVideo,
            let image = attachment.rawValue.videoPreview(),
            image.size.width > 0, image.size.height > 0
        else {
            createGenericPreview()
            return
        }

        let imageView = UIImageView(image: image)
        imageView.layer.minificationFilter = .trilinear
        imageView.layer.magnificationFilter = .trilinear
        let aspectRatio = image.size.width / image.size.height

        if contentMode == .scaleAspectFill {
            addSubviewWithScaleAspectFillLayout(view: imageView, aspectRatio: aspectRatio)
        } else {
            addSubviewWithScaleAspectFitLayout(view: imageView, aspectRatio: aspectRatio)
        }
    }

    private func createGenericPreview() {
        var subviews = [UIView]()

        let imageView = createHeroImageView(imageName: "file-display")
        subviews.append(imageView)

        let fileNameLabel = createFileNameLabel()
        if let fileNameLabel {
            subviews.append(fileNameLabel)
        }

        let fileSizeLabel = createFileSizeLabel()
        subviews.append(fileSizeLabel)

        let stackView = wrapViewsInVerticalStack(subviews: subviews)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private static var heroViewSize: CGFloat { .scaleFromIPhone5(100) }

    private func createHeroImageView(imageName: String) -> UIView {
        let imageView = UIImageView(image: UIImage(named: imageName))
        imageView.tintColor = .Signal.label
        imageView.layer.shadowColor = UIColor.black.cgColor
        let shadowScaling: CGFloat = 5.0
        imageView.layer.shadowRadius = CGFloat(2.0 * shadowScaling)
        imageView.layer.shadowOpacity = 0.25
        imageView.layer.shadowOffset = CGSize(square: 0.75 * shadowScaling)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        let imageSize = Self.heroViewSize
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: imageSize),
            imageView.heightAnchor.constraint(equalToConstant: imageSize),
        ])
        return imageView
    }

    private func formattedFileExtension() -> String? {
        guard let fileExtension = attachment.rawValue.fileExtension else {
            return nil
        }

        return String.nonPluralLocalizedStringWithFormat(
            OWSLocalizedString(
                "ATTACHMENT_APPROVAL_FILE_EXTENSION_FORMAT",
                comment: "Format string for file extension label in call interstitial view",
            ),
            fileExtension.uppercased(),
        )
    }

    private func formattedFileName() -> String? {
        guard let sourceFilename = attachment.rawValue.dataSource.sourceFilename?.filterFilename() else {
            return nil
        }
        let filename = sourceFilename.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !filename.isEmpty else {
            return nil
        }
        return filename
    }

    private func createFileNameLabel() -> UIView? {
        guard let filename = formattedFileName() ?? formattedFileExtension() else {
            return nil
        }

        let label = UILabel()
        label.text = filename
        label.textColor = .Signal.label
        label.font = .dynamicTypeHeadline
        label.textAlignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }

    private func createFileSizeLabel() -> UIView {
        let fileSize = (try? attachment.rawValue.dataSource.readLength()) ?? 0
        let label = UILabel()
        label.text = String.nonPluralLocalizedStringWithFormat(
            OWSLocalizedString(
                "ATTACHMENT_APPROVAL_FILE_SIZE_FORMAT",
                comment: "Format string for file size label in call interstitial view. Embeds: {{file size as 'N mb' or 'N kb'}}.",
            ),
            OWSFormat.localizedFileSizeString(from: fileSize),
        )
        label.textColor = .Signal.secondaryLabel
        label.font = .dynamicTypeSubheadline
        label.textAlignment = .center
        return label
    }

    // MARK: - Event Handlers

    private func audioPlayButtonPressed() {
        audioPlayer?.togglePlayState()
    }

    // MARK: - AudioPlayerDelegate

    var audioPlaybackState = AudioPlaybackState.stopped {
        didSet {
            AssertIsOnMainThread()

            ensureButtonState()
        }
    }

    func setAudioProgress(_ progress: TimeInterval, duration: TimeInterval, playbackRate: Float) { }

    func audioPlayerDidFinish() { }

    private func ensureButtonState() {
        if audioPlaybackState == .playing {
            setAudioIconToPause()
        } else {
            setAudioIconToPlay()
        }
    }

    private func setAudioIconToPlay() {
        audioPlayButton.configuration?.image = UIImage(imageLiteralResourceName: "play-circle-display")
    }

    private func setAudioIconToPause() {
        audioPlayButton.configuration?.image = UIImage(imageLiteralResourceName: "pause-circle-display")
    }
}
