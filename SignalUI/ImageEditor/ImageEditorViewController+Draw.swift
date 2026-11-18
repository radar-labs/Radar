//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

extension ImageEditorViewController {

    private func initializeDrawToolUIIfNecessary() {
        guard !drawToolUIInitialized else { return }

        drawToolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(drawToolbar)
        NSLayoutConstraint.activate([
            drawToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            drawToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            drawToolbar.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),
        ])

        view.addGestureRecognizer(drawToolGestureRecognizer)

        drawToolUIInitialized = true
    }

    func updateDrawToolControlsVisibility() {
        drawToolbar.alpha = topBar.alpha
        strokeWidthSliderContainer.alpha = topBar.alpha
    }

    func updateDrawToolUIVisibility() {
        let visible = mode == .draw

        if visible {
            initializeDrawToolUIIfNecessary()
        } else {
            guard drawToolUIInitialized else { return }
        }

        drawToolbar.isHidden = !visible
        drawToolGestureRecognizer.isEnabled = visible

        if visible {
            currentStrokeType = drawToolbar.strokeType
        }
    }

    static var highligherStrokeOpacity: CGFloat = 0.5

    @objc
    func handleDrawToolGesture(_ gestureRecognizer: ImageEditorPanGestureRecognizer) {
        AssertIsOnMainThread()

        owsAssertDebug(mode == .draw, "Incorrect mode [\(mode)]")

        let removeCurrentStroke = {
            if let stroke = self.currentStroke {
                self.model.remove(item: stroke)
            }
            self.currentStroke = nil
            self.currentStrokeSamples.removeAll()
        }
        let tryToAppendStrokeSample = { (locationInView: CGPoint) in
            let view = self.imageEditorView.gestureReferenceView
            let viewBounds = view.bounds
            let newSample = ImageEditorCanvasView.locationImageUnit(
                forLocationInView: locationInView,
                viewBounds: viewBounds,
                model: self.model,
                transform: self.model.currentTransform(),
            )

            if
                let prevSample = self.currentStrokeSamples.last,
                prevSample == newSample
            {
                // Ignore duplicate samples.
                return
            }
            self.currentStrokeSamples.append(newSample)
        }

        var strokeColor = drawToolbar.colorPickerBar.uiColor
        if currentStrokeType == .highlighter {
            strokeColor = strokeColor.withAlphaComponent(Self.highligherStrokeOpacity)
        }
        let unitStrokeWidth = currentStrokeUnitWidth()

        switch gestureRecognizer.state {
        case .began:
            setStrokeWidthSlider(revealed: false)

            removeCurrentStroke()

            // Apply the location history of the gesture so that the stroke reflects
            // the touch's movement before the gesture recognized.
            for location in gestureRecognizer.locationHistory {
                tryToAppendStrokeSample(location)
            }

            let locationInView = gestureRecognizer.location(in: imageEditorView.gestureReferenceView)
            tryToAppendStrokeSample(locationInView)

            let stroke = ImageEditorStrokeItem(
                color: strokeColor,
                strokeType: currentStrokeType,
                unitSamples: currentStrokeSamples,
                unitStrokeWidth: unitStrokeWidth,
            )
            model.append(item: stroke)
            currentStroke = stroke

        case .changed, .ended:
            let locationInView = gestureRecognizer.location(in: imageEditorView.gestureReferenceView)
            tryToAppendStrokeSample(locationInView)

            guard let lastStroke = self.currentStroke else {
                owsFailDebug("Missing last stroke.")
                removeCurrentStroke()
                return
            }

            // Model items are immutable; we _replace_ the
            // stroke item rather than modify it.
            let stroke = ImageEditorStrokeItem(
                itemId: lastStroke.itemId,
                color: strokeColor,
                strokeType: currentStrokeType,
                unitSamples: currentStrokeSamples,
                unitStrokeWidth: unitStrokeWidth,
            )
            model.replace(item: stroke, suppressUndo: true)

            if gestureRecognizer.state == .ended {
                currentStroke = nil
                currentStrokeSamples.removeAll()
            } else {
                currentStroke = stroke
            }

        default:
            removeCurrentStroke()
        }
    }

    class DrawToolbar: UIView {

        var strokeType: ImageEditorStrokeItem.StrokeType = .pen {
            didSet {
                updateStrokeTypeButtonImage()
            }
        }

        let colorPickerBar: ColorPickerBar

        let strokeTypeButton = UIButton(configuration: .roundMedia(
            image: UIImage(imageLiteralResourceName: "brush-pen"),
            size: 44,
        ))

        private func updateStrokeTypeButtonImage() {
            switch strokeType {
            case .pen:
                strokeTypeButton.configuration?.image = UIImage(imageLiteralResourceName: "brush-pen")
            case .highlighter:
                strokeTypeButton.configuration?.image = UIImage(imageLiteralResourceName: "brush-highlighter")
            case .blur:
                owsFailDebug("Invalid stroke type")
            }
        }

        func toggleStrokeType() {
            strokeType = strokeType == .pen ? .highlighter : .pen
        }

        init(currentColor: ColorPickerBarColor) {
            colorPickerBar = ColorPickerBar(color: currentColor)

            super.init(frame: .zero)

            preservesSuperviewLayoutMargins = true
            directionalLayoutMargins.top = 0
            directionalLayoutMargins.bottom = 2

            strokeTypeButton.setCompressionResistanceHorizontalHigh()
            updateStrokeTypeButtonImage() // just in case

            // I had to use a custom layout guide because stack view isn't centered
            // but instead has slight offset towards the trailing edge.
            let stackView = UIStackView(arrangedSubviews: [colorPickerBar, strokeTypeButton])
            stackView.translatesAutoresizingMaskIntoConstraints = false
            stackView.alignment = .center
            stackView.spacing = 8
            addSubview(stackView)
            NSLayoutConstraint.activate([
                stackView.centerXAnchor.constraint(equalTo: layoutMarginsGuide.centerXAnchor),
                stackView.leadingAnchor.constraint(greaterThanOrEqualTo: layoutMarginsGuide.leadingAnchor),
                stackView.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
                stackView.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
                {
                    let constraint = stackView.widthAnchor.constraint(
                        equalToConstant: ImageEditorViewController.preferredToolbarContentWidth,
                    )
                    constraint.priority = .defaultHigh
                    return constraint
                }(),
            ])
        }

        required init(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
