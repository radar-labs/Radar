//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

protocol CVViewStateDelegate: AnyObject {
    func viewStateUIModeDidChange(oldValue: ConversationUIMode)
}

// MARK: -

// This can be a simple place to hang CVC's mutable view state.
//
// These properties should only be accessed on the main thread.
class CVViewState {
    weak var delegate: CVViewStateDelegate?

    let threadUniqueId: String
    var conversationStyle: ConversationStyle
    var inputToolbar: ConversationInputToolbar?
    let headerView = ConversationHeaderView()

    var bottomBarContainer = UIView.container()
    var requestView: UIView?
    var bannerStackView: UIStackView?
    var groupNameCollisionFinder: GroupMembershipNameCollisionFinder?

    var isDismissingInteractively = false

    var isViewCompletelyAppeared = false
    var isViewVisible = false
    var shouldAnimateKeyboardChanges = false
    var isInPreviewPlatter = false
    let viewCreationDate = Date()
    var hasAppliedFirstLoad = false

    var isUserScrolling = false
    var scrollingAnimationCompletionTimer: Timer?
    var hasScrollingAnimation: Bool {
        AssertIsOnMainThread()

        return scrollingAnimationCompletionTimer != nil
    }

    var scrollActionForSizeTransition: CVScrollAction?
    var scrollActionForUpdate: CVScrollAction?
    var lastKnownDistanceFromBottom: CGFloat?
    var lastSearchedText: String?

    var activeCellAnimations = Set<UUID>()

    func beginCellAnimation(identifier: UUID) {
        activeCellAnimations.insert(identifier)
    }

    func endCellAnimation(identifier: UUID) {
        activeCellAnimations.remove(identifier)
    }

    var bottomViewType: CVCBottomViewType = .none

    var uiMode: ConversationUIMode = .normal {
        didSet {
            AssertIsOnMainThread()
            let didChange = uiMode != oldValue
            if didChange {
                selectionState.reset()
                delegate?.viewStateUIModeDidChange(oldValue: oldValue)
            }
        }
    }

    enum SelectionAnimationState { case idle, willAnimate, animating }
    var selectionAnimationState: SelectionAnimationState = .idle

    let selectionState = CVSelectionState()
    let textExpansion = CVTextExpansion()
    let spoilerState = SpoilerRenderState()
    let messageSwipeActionState = CVMessageSwipeActionState()

    var isDarkThemeEnabled: Bool = Theme.isDarkThemeEnabled

    var sendMessageController: SendMessageController?

    let mediaCache = CVMediaCache()

    let contactShareViewHelper = ContactShareViewHelper()

    var userHasScrolled = false

    var groupCallBarButtonItem: UIBarButtonItem?

    var lastMessageSentDate: Date?

    let scrollDownButton = ConversationScrollButton(iconName: "chevron-down")
    var isHidingScrollDownButton = false
    let scrollToNextMentionButton = ConversationScrollButton(iconName: "at")
    var isHidingScrollToNextMentionButton = false
    var scrollUpdateTimer: Timer?
    var isWaitingForDeceleration = false
    var highlightedMessageId: String?
    var focusedMessageId: String?

    var actionOnOpen: ConversationViewAction = .none

    var readTimer: Timer?
    var reloadTimer: Timer?

    var lastSortIdMarkedRead: UInt64 = 0
    var isMarkingAsRead = false

    // MARK: - Gestures

    var collectionViewGestureRecongnizersConfigured = false
    let collectionViewTapGestureRecognizer = SingleOrDoubleTapGestureRecognizer()
    let collectionViewLongPressGestureRecognizer = UILongPressGestureRecognizer()
    let collectionViewContextMenuGestureRecognizer = UILongPressGestureRecognizer()
    var collectionViewContextMenuSecondaryClickRecognizer = UITapGestureRecognizer()
    let collectionViewPanGestureRecognizer = UIPanGestureRecognizer()

    var collectionViewActiveContextMenuInteraction: ChatHistoryContextMenuInteraction?
    var longPressHandler: CVLongPressHandler?
    var panHandler: CVPanHandler?

    // MARK: -

    var initialScrollState: CVInitialScrollState?

    var presentationStatus: CVPresentationStatus = .notYetPresented

    let backgroundContainer = CVBackgroundContainer()
    var wallpaperViewBuilder: WallpaperViewBuilder?
    var chatColor: ColorOrGradientSetting

    weak var reactionsDetailSheet: ReactionsDetailSheet?

    var lastKeyboardAnimationDate: Date?

    // MARK: - Voice Messages

    var inProgressVoiceMessage: VoiceMessageInProgressDraft?

    // MARK: - Gift Badges

    var shakenGiftMessageIds = Set<String>()

    var unwrappedGiftMessageIds = Set<String>()

    // MARK: - Collapse Sets

    /// The set of collapse set IDs that have been expanded by the user.
    /// Resets to empty when leaving the conversation.
    var expandedCollapseSets = Set<String>()

    // MARK: - Attachment downloads

    var manuallyCanceledDownloadsMessageIds = Set<String>()

    // MARK: -

    init(
        threadUniqueId: String,
        conversationStyle: ConversationStyle,
        chatColor: ColorOrGradientSetting,
        wallpaperViewBuilder: WallpaperViewBuilder?,
    ) {
        self.threadUniqueId = threadUniqueId
        self.conversationStyle = conversationStyle
        self.chatColor = chatColor
        self.wallpaperViewBuilder = wallpaperViewBuilder
    }
}

// MARK: -

extension ConversationViewController {

    var threadViewModel: ThreadViewModel { renderState.threadViewModel }

    var conversationViewModel: ConversationViewModel { renderState.conversationViewModel }

    var thread: TSThread { threadViewModel.threadRecord }

    var disappearingMessagesConfiguration: DisappearingMessagesConfigurationRecord { threadViewModel.disappearingMessagesConfiguration }

    var conversationStyle: ConversationStyle {
        get { viewState.conversationStyle }
        set {
            viewState.conversationStyle = newValue
            if #available(iOS 26, *) {
                let tintColor = newValue.chatColorValue.asChatUIElementTintColor()
                viewState.scrollDownButton.badgeTintColor = tintColor
                viewState.scrollToNextMentionButton.badgeTintColor = tintColor
            }
        }
    }

    var headerView: ConversationHeaderView { viewState.headerView }

    var inputToolbar: ConversationInputToolbar? {
        get { viewState.inputToolbar }
        set { viewState.inputToolbar = newValue }
    }

    var bottomBarContainer: UIView {
        viewState.bottomBarContainer
    }

    var requestView: UIView? {
        get { viewState.requestView }
        set { viewState.requestView = newValue }
    }

    var bannerStackView: UIStackView? {
        get { viewState.bannerStackView }
        set { viewState.bannerStackView = newValue }
    }

    var isDismissingInteractively: Bool {
        get { viewState.isDismissingInteractively }
        set { viewState.isDismissingInteractively = newValue }
    }

    var isViewCompletelyAppeared: Bool {
        get { viewState.isViewCompletelyAppeared }
        set { viewState.isViewCompletelyAppeared = newValue }
    }

    var shouldAnimateKeyboardChanges: Bool {
        get { viewState.shouldAnimateKeyboardChanges }
        set { viewState.shouldAnimateKeyboardChanges = newValue }
    }

    var isUserScrolling: Bool {
        get { viewState.isUserScrolling }
        set { viewState.isUserScrolling = newValue }
    }

    var scrollingAnimationCompletionTimer: Timer? {
        get { viewState.scrollingAnimationCompletionTimer }
        set { viewState.scrollingAnimationCompletionTimer = newValue }
    }

    var hasScrollingAnimation: Bool { viewState.hasScrollingAnimation }

    var uiMode: ConversationUIMode {
        get { viewState.uiMode }
        set {
            let oldValue = viewState.uiMode
            guard oldValue != newValue else {
                return
            }
            viewState.uiMode = newValue
            uiModeDidChange(oldValue: oldValue)
        }
    }

    var isShowingSelectionUI: Bool { viewState.uiMode.hasSelectionUI }

    var lastSearchedText: String? {
        get { viewState.lastSearchedText }
        set { viewState.lastSearchedText = newValue }
    }

    var isDarkThemeEnabled: Bool {
        get { viewState.isDarkThemeEnabled }
        set { viewState.isDarkThemeEnabled = newValue }
    }

    var mediaCache: CVMediaCache { viewState.mediaCache }

    var groupCallBarButtonItem: UIBarButtonItem? {
        get { viewState.groupCallBarButtonItem }
        set { viewState.groupCallBarButtonItem = newValue }
    }

    var lastMessageSentDate: Date? {
        get { viewState.lastMessageSentDate }
        set { viewState.lastMessageSentDate = newValue }
    }

    var actionOnOpen: ConversationViewAction {
        get { viewState.actionOnOpen }
        set { viewState.actionOnOpen = newValue }
    }

    // MARK: - Gestures

    var collectionViewGestureRecongnizersConfigured: Bool {
        get { viewState.collectionViewGestureRecongnizersConfigured }
        set { viewState.collectionViewGestureRecongnizersConfigured = newValue }
    }

    var collectionViewTapGestureRecognizer: SingleOrDoubleTapGestureRecognizer {
        viewState.collectionViewTapGestureRecognizer
    }

    var collectionViewLongPressGestureRecognizer: UILongPressGestureRecognizer {
        viewState.collectionViewLongPressGestureRecognizer
    }

    var collectionViewContextMenuGestureRecognizer: UILongPressGestureRecognizer {
        viewState.collectionViewContextMenuGestureRecognizer
    }

    var collectionViewContextMenuSecondaryClickRecognizer: UITapGestureRecognizer {
        viewState.collectionViewContextMenuSecondaryClickRecognizer
    }

    var collectionViewPanGestureRecognizer: UIPanGestureRecognizer {
        viewState.collectionViewPanGestureRecognizer
    }

    var collectionViewActiveContextMenuInteraction: ChatHistoryContextMenuInteraction? {
        get { viewState.collectionViewActiveContextMenuInteraction }
        set { viewState.collectionViewActiveContextMenuInteraction = newValue }
    }

    var backgroundContainer: CVBackgroundContainer { viewState.backgroundContainer }
    var reactionsDetailSheet: ReactionsDetailSheet? {
        get { viewState.reactionsDetailSheet }
        set { viewState.reactionsDetailSheet = newValue }
    }

    var contactShareViewHelper: ContactShareViewHelper { viewState.contactShareViewHelper }
}

// MARK: -

extension CVViewState {

    var asCoreState: CVCoreState {
        CVCoreState(conversationStyle: conversationStyle, mediaCache: mediaCache)
    }
}

// MARK: -

// Accessors for the non-@objc properties.
extension ConversationViewController {

    var longPressHandler: CVLongPressHandler? {
        get { viewState.longPressHandler }
        set { viewState.longPressHandler = newValue }
    }

    var panHandler: CVPanHandler? {
        get { viewState.panHandler }
        set { viewState.panHandler = newValue }
    }

    var selectionState: CVSelectionState { viewState.selectionState }

    func isTextExpanded(interactionId: String) -> Bool {
        viewState.textExpansion.isTextExpanded(interactionId: interactionId)
    }

    func setTextExpanded(interactionId: String) {
        viewState.textExpansion.setTextExpanded(interactionId: interactionId)
    }

    var initialScrollState: CVInitialScrollState? {
        get { viewState.initialScrollState }
        set { viewState.initialScrollState = newValue }
    }

    var lastKnownDistanceFromBottom: CGFloat? {
        get { viewState.lastKnownDistanceFromBottom }
        set { viewState.lastKnownDistanceFromBottom = newValue }
    }

    var sendMessageController: SendMessageController? {
        get { viewState.sendMessageController }
        set { viewState.sendMessageController = newValue }
    }
}

// This struct facilitates passing around a few key
// pieces of CVC state during async loads.
struct CVCoreState {
    let conversationStyle: ConversationStyle
    let mediaCache: CVMediaCache
}

class CVTextExpansion {
    private var expandedTextInteractionsIds = Set<String>()

    init(expandedTextInteractionsIds: Set<String>? = nil) {
        if let expandedTextInteractionsIds {
            self.expandedTextInteractionsIds = expandedTextInteractionsIds
        }
    }

    func isTextExpanded(interactionId: String) -> Bool {
        expandedTextInteractionsIds.contains(interactionId)
    }

    func setTextExpanded(interactionId: String) {
        expandedTextInteractionsIds.insert(interactionId)
    }

    func copy() -> CVTextExpansion {
        CVTextExpansion(expandedTextInteractionsIds: expandedTextInteractionsIds)
    }

    //    // TODO: collapseCutoffDate
    //    let collapseCutoffDate = Date()
}

class CVMessageSwipeActionState {
    struct Progress {
        let xOffset: CGFloat
    }

    typealias ProgressMap = [String: Progress]
    private var progressMap = ProgressMap()

    init(progressMap: ProgressMap? = nil) {
        if let progressMap {
            self.progressMap = progressMap
        }
    }

    func getProgress(interactionId: String) -> Progress? {
        progressMap[interactionId]
    }

    func setProgress(interactionId: String, progress: Progress) {
        progressMap[interactionId] = progress
    }

    func resetProgress(interactionId: String) {
        progressMap[interactionId] = nil
    }

    func copy() -> CVMessageSwipeActionState {
        CVMessageSwipeActionState(progressMap: progressMap)
    }
}

// Describes the initial scroll state when we present CVC.
//
// Initial scroll state only applies until the first time
// CVC.viewDidAppear() is called.
struct CVInitialScrollState {
    let focusMessageId: String?
}

// Records whether or not the conversation view
// has ever reached these milestones of its lifecycle.
enum CVPresentationStatus: UInt, CustomStringConvertible {
    case notYetPresented = 0
    case firstViewWillAppearHasBegun
    case firstViewWillAppearHasCompleted
    case firstViewDidAppearHasBegun
    case firstViewDidAppearHasCompleted

    var description: String {
        switch self {
        case .notYetPresented:
            return ".notYetPresented"
        case .firstViewWillAppearHasBegun:
            return ".firstViewWillAppearHasBegun"
        case .firstViewWillAppearHasCompleted:
            return ".firstViewWillAppearHasCompleted"
        case .firstViewDidAppearHasBegun:
            return ".firstViewDidAppearHasBegun"
        case .firstViewDidAppearHasCompleted:
            return ".firstViewDidAppearHasCompleted"
        }
    }
}

extension ConversationViewController {

    var presentationStatus: CVPresentationStatus { viewState.presentationStatus }

    private func updatePresentationStatus(_ value: CVPresentationStatus) {
        AssertIsOnMainThread()

        if viewState.presentationStatus.rawValue < value.rawValue {
            viewState.presentationStatus = value
        }
    }

    func viewWillAppearDidBegin() {
        updatePresentationStatus(.firstViewWillAppearHasBegun)
    }

    func viewWillAppearDidComplete() {
        updatePresentationStatus(.firstViewWillAppearHasCompleted)
    }

    func viewDidAppearDidBegin() {
        updatePresentationStatus(.firstViewDidAppearHasBegun)
    }

    func viewDidAppearDidComplete() {
        updatePresentationStatus(.firstViewDidAppearHasCompleted)
    }

    var hasViewWillAppearEverBegun: Bool {
        viewState.presentationStatus.rawValue >= CVPresentationStatus.firstViewWillAppearHasBegun.rawValue
    }

    var hasViewDidAppearEverBegun: Bool {
        viewState.presentationStatus.rawValue >= CVPresentationStatus.firstViewDidAppearHasBegun.rawValue
    }

    var hasViewDidAppearEverCompleted: Bool {
        viewState.presentationStatus.rawValue >= CVPresentationStatus.firstViewDidAppearHasCompleted.rawValue
    }

    var viewHasEverAppeared: Bool {
        hasViewDidAppearEverCompleted
    }
}
