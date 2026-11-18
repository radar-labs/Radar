//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol ConversationHeaderViewDelegate: AnyObject {
    func didTapConversationHeaderView(_ conversationHeaderView: ConversationHeaderView)
    func didTapConversationHeaderViewAvatar(_ conversationHeaderView: ConversationHeaderView)
}

class ConversationHeaderView: UIView {

    weak var delegate: ConversationHeaderViewDelegate?

    var titleIcon: UIImage? {
        get {
            return titleIconView.image
        }
        set {
            titleIconView.image = newValue
            titleIconView.isHidden = newValue == nil
        }
    }

    let titleLabel: UILabel = {
        let label = UILabel()
        label.textColor = UIColor.Signal.label
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.setContentHuggingHigh()
        return label
    }()

    let subtitleLabel: UILabel = {
        let label = UILabel()
        label.textColor = .Signal.label
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.setContentHuggingHigh()
        return label
    }()

    private let titleIconView: UIImageView = {
        let titleIconView = UIImageView()
        titleIconView.isHidden = true
        titleIconView.contentMode = .scaleAspectFit
        titleIconView.setCompressionResistanceHigh()
        return titleIconView
    }()

    @available(iOS, deprecated: 26)
    private var useCompactVerticalLayout: Bool {
        // iPhones in portrait, iPads etc.
        if traitCollection.verticalSizeClass == .regular { return false }

        // Most recent iOS versions (starting with 17) seem to always have 44 dp navigation bar,
        // even on smaller devices in landscape.
        if bounds.size.height >= 44 { return false }

        return true
    }

    private var avatarSizeClass: ConversationAvatarView.Configuration.SizeClass {
        // One size for the navigation bar on iOS 26.
        if #available(iOS 26, *) { return .forty }

        return useCompactVerticalLayout ? .twentyFour : .thirtySix
    }

    private(set) lazy var avatarView = ConversationAvatarView(
        sizeClass: avatarSizeClass,
        localUserDisplayMode: .noteToSelf,
    )

    override init(frame: CGRect) {
        super.init(frame: frame)

        // Fixed size for "Verified" checkmark.
        titleIconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleIconView.heightAnchor.constraint(equalToConstant: 16),
            titleIconView.widthAnchor.constraint(equalTo: titleIconView.heightAnchor),
        ])

        let titleColumns = UIStackView(arrangedSubviews: [titleLabel, titleIconView])
        titleColumns.spacing = 5
        titleColumns.translatesAutoresizingMaskIntoConstraints = false
        // There is a strange bug where an initial height of 0
        // breaks the layout, so set an initial height.
        titleColumns.heightAnchor.constraint(greaterThanOrEqualToConstant: titleLabel.font.lineHeight.rounded(.up)).isActive = true

        let textRows = UIStackView(arrangedSubviews: [titleColumns, subtitleLabel])
        textRows.axis = .vertical
        textRows.alignment = .leading
        textRows.distribution = .fillProportionally

        let rootStack = UIStackView(arrangedSubviews: [avatarView, textRows])
        rootStack.isLayoutMarginsRelativeArrangement = true
        rootStack.axis = .horizontal
        rootStack.alignment = .center
        rootStack.spacing = 8

        let rootView: UIView
        if #available(iOS 26, *) {
            rootStack.directionalLayoutMargins = .init(top: 2, leading: 2, bottom: 2, trailing: 16)
            rootStack.heightAnchor.constraint(equalToConstant: 44).isActive = true

            let glassEffect = UIGlassEffect(style: .regular)
            glassEffect.isInteractive = true
            let glassEffectView = UIVisualEffectView(effect: glassEffect)
            glassEffectView.clipsToBounds = true
            glassEffectView.cornerConfiguration = .capsule()

            rootStack.translatesAutoresizingMaskIntoConstraints = false
            glassEffectView.contentView.addSubview(rootStack)
            NSLayoutConstraint.activate([
                rootStack.topAnchor.constraint(equalTo: glassEffectView.topAnchor),
                rootStack.leadingAnchor.constraint(equalTo: glassEffectView.leadingAnchor),
                rootStack.trailingAnchor.constraint(equalTo: glassEffectView.trailingAnchor),
                rootStack.bottomAnchor.constraint(equalTo: glassEffectView.bottomAnchor),
            ])

            rootView = glassEffectView
        } else {
            rootStack.directionalLayoutMargins = .init(hMargin: 0, vMargin: 4)

            rootView = rootStack
        }

        addSubview(rootView)
        rootView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            rootView.topAnchor.constraint(equalTo: topAnchor),
            rootView.leadingAnchor.constraint(equalTo: leadingAnchor),
            rootView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            rootView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Embed a small glass view behind the avatar so that it's never visible to the user.
        // Glass views react to content underneath and update appearance (light / dark)
        // automatically. Using newer API for detecting trait collection changes it's now
        // possible to attach a small handler that will force UILabels to have
        // the same light or dark style as the glass view.
        if
            #available(iOS 26, *),
            CurrentAppContext().appUserDefaults().bool(forKey: "DisableChatHeaderContentTracking") == false
        {
            let glassTrackingView = UIVisualEffectView(effect: UIGlassEffect(style: .regular))
            rootStack.insertSubview(glassTrackingView, at: 0)
            glassTrackingView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                glassTrackingView.widthAnchor.constraint(equalToConstant: 10),
                glassTrackingView.heightAnchor.constraint(equalToConstant: 10),
                glassTrackingView.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),
                glassTrackingView.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
            ])

            glassTrackingView.contentView.registerForTraitChanges(
                [UITraitUserInterfaceStyle.self],
                handler: { [weak textRows] (view: UIView, _) in
                    textRows?.overrideUserInterfaceStyle = view.traitCollection.userInterfaceStyle
                },
            )
        }

        rootView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(didTapView)))
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(threadViewModel: ThreadViewModel) {
        avatarView.updateWithSneakyTransactionIfNecessary { config in
            if threadViewModel.threadRecord.isReleaseNotesThread {
                config.dataSource = .asset(avatar: AvatarBuilder.releaseNotesIcon(), badge: nil)
            } else {
                config.dataSource = .thread(threadViewModel.threadRecord)
            }

            config.storyConfiguration = .autoUpdate()
            config.applyConfigurationSynchronously()
        }
    }

    override var bounds: CGRect {
        didSet {
            if #unavailable(iOS 26), oldValue.height != bounds.height {
                updateVerticalLayoutIfNecessary()
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        // Grow to fill as much of the navbar as possible.
        return .init(width: .greatestFiniteMagnitude, height: UIView.noIntrinsicMetric)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if #unavailable(iOS 26), traitCollection.verticalSizeClass != previousTraitCollection?.verticalSizeClass {
            updateVerticalLayoutIfNecessary()
        }
    }

    @available(iOS, deprecated: 26)
    private func updateVerticalLayoutIfNecessary() {
        avatarView.updateWithSneakyTransactionIfNecessary { config in
            config.sizeClass = avatarSizeClass
        }
        // Single line of text when vertically compact layout.
        subtitleLabel.isHidden = useCompactVerticalLayout
    }

    // MARK: Spinning Title

    func updateTitleSpinning() {
        let key = "spin"
        if InMemorySettings.spinningConversationTitle {
            guard layer.animation(forKey: key) == nil else { return }
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.toValue = NSNumber(value: Double.pi * 2)
            animation.duration = 1
            animation.isCumulative = true
            animation.repeatCount = .greatestFiniteMagnitude
            layer.add(animation, forKey: key)
        } else {
            layer.removeAnimation(forKey: key)
        }
    }

    // MARK: Delegate Methods

    @objc
    private func didTapView(tapGesture: UITapGestureRecognizer) {
        guard let delegate, tapGesture.state == .recognized else {
            return
        }

        if avatarView.bounds.contains(tapGesture.location(in: avatarView)) {
            delegate.didTapConversationHeaderViewAvatar(self)
            return
        }

        delegate.didTapConversationHeaderView(self)
    }
}
