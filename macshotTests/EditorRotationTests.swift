import Cocoa
import XCTest

/// Rotating the image a quarter turn in the Editor: the canvas swaps width and
/// height, every pixel lands where a real rotation puts it, annotations turn
/// with the picture, and undo puts all of it back together.
@MainActor
final class EditorRotationTests: XCTestCase {

    private func makeEditor(width: CGFloat = 300, height: CGFloat = 200) -> EditorView {
        let view = EditorView()
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.layoutEditorDocument(forImageSize: NSSize(width: width, height: height))
        view.screenshotImage = ImageProbe.quadrantImage(width: Int(width), height: Int(height))
        view.applySelection(NSRect(x: 0, y: 0, width: width, height: height))
        return view
    }

    private enum Quadrant { case red, green, blue, white }

    /// Which quadrant colour of `ImageProbe.quadrantImage` a pixel has.
    /// `y` counts from the top of the image.
    private func quadrant(_ image: NSImage?, x: Int, y: Int,
                          file: StaticString = #filePath, line: UInt = #line) -> Quadrant? {
        guard let image, let color = ImageProbe.pixelColor(image, x: x, y: y) else {
            XCTFail("no pixel at \(x),\(y)", file: file, line: line)
            return nil
        }
        let r = color.redComponent > 0.5, g = color.greenComponent > 0.5, b = color.blueComponent > 0.5
        switch (r, g, b) {
        case (true, false, false): return .red
        case (false, true, false): return .green
        case (false, false, true): return .blue
        case (true, true, true): return .white
        default:
            XCTFail("unexpected colour at \(x),\(y)", file: file, line: line)
            return nil
        }
    }

    // MARK: - The image

    func testRotatingRightSwapsTheCanvasAndTurnsThePixelsClockwise() {
        // Source, from the top: blue | white over red | green.
        let editor = makeEditor(width: 300, height: 200)
        let m = OverlayView.editorDocumentMargin

        editor.rotateImage(clockwise: true)

        XCTAssertEqual(editor.screenshotImage?.size, NSSize(width: 200, height: 300))
        XCTAssertEqual(editor.selectionRect, NSRect(x: 0, y: 0, width: 200, height: 300))
        XCTAssertEqual(editor.frame.size, NSSize(width: 200 + 2 * m, height: 300 + 2 * m),
                       "the document view follows the new image size")
        XCTAssertEqual(editor.bounds.origin, NSPoint(x: -m, y: -m))

        // Clockwise: the left edge becomes the top edge.
        let image = editor.screenshotImage
        XCTAssertEqual(quadrant(image, x: 10, y: 10), .red, "bottom-left moves to top-left")
        XCTAssertEqual(quadrant(image, x: 190, y: 10), .blue, "top-left moves to top-right")
        XCTAssertEqual(quadrant(image, x: 190, y: 290), .white, "top-right moves to bottom-right")
        XCTAssertEqual(quadrant(image, x: 10, y: 290), .green, "bottom-right moves to bottom-left")
    }

    func testRotatingLeftTurnsThePixelsCounterclockwise() {
        let editor = makeEditor(width: 300, height: 200)
        editor.rotateImage(clockwise: false)

        let image = editor.screenshotImage
        XCTAssertEqual(image?.size, NSSize(width: 200, height: 300))
        XCTAssertEqual(quadrant(image, x: 10, y: 10), .white, "top-right moves to top-left")
        XCTAssertEqual(quadrant(image, x: 190, y: 10), .green, "bottom-right moves to top-right")
        XCTAssertEqual(quadrant(image, x: 190, y: 290), .red, "bottom-left moves to bottom-right")
        XCTAssertEqual(quadrant(image, x: 10, y: 290), .blue, "top-left moves to bottom-left")
    }

    func testAQuarterTurnKeepsEveryPixelOfARetinaImage() throws {
        // 40x20 pixels shown at 20x10 points.
        let source = try XCTUnwrap(ImageProbe.quadrantImage(width: 40, height: 20)
            .cgImage(forProposedRect: nil, context: nil, hints: nil))
        let retina = NSImage(cgImage: source, size: NSSize(width: 20, height: 10))

        let turned = try XCTUnwrap(OverlayView.quarterTurned(retina, clockwise: true))
        let pixels = try XCTUnwrap(turned.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(turned.size, NSSize(width: 10, height: 20), "points swap")
        XCTAssertEqual(pixels.width, 20, "and so do pixels: nothing is resampled")
        XCTAssertEqual(pixels.height, 40)
    }

    func testFourQuarterTurnsGiveTheOriginalPictureBack() {
        let editor = makeEditor(width: 300, height: 200)
        let arrow = Annotation(tool: .arrow, startPoint: NSPoint(x: 20, y: 30),
                               endPoint: NSPoint(x: 80, y: 90), color: .red, strokeWidth: 3)
        let text = Annotation(tool: .text, startPoint: NSPoint(x: 20, y: 20),
                              endPoint: NSPoint(x: 120, y: 60), color: .red, strokeWidth: 2)
        text.textDrawRect = NSRect(x: 20, y: 20, width: 100, height: 40)
        editor.annotations = [arrow, text]

        for _ in 0..<4 { editor.rotateImage(clockwise: true) }

        let image = editor.screenshotImage
        XCTAssertEqual(image?.size, NSSize(width: 300, height: 200))
        XCTAssertEqual(quadrant(image, x: 10, y: 10), .blue)
        XCTAssertEqual(quadrant(image, x: 290, y: 10), .white)
        XCTAssertEqual(quadrant(image, x: 10, y: 190), .red)
        XCTAssertEqual(quadrant(image, x: 290, y: 190), .green)
        XCTAssertEqual(arrow.startPoint.x, 20, accuracy: 0.001)
        XCTAssertEqual(arrow.startPoint.y, 30, accuracy: 0.001)
        XCTAssertEqual(arrow.endPoint.x, 80, accuracy: 0.001)
        XCTAssertEqual(arrow.endPoint.y, 90, accuracy: 0.001)
        XCTAssertEqual(text.textDrawRect.origin.x, 20, accuracy: 0.001)
        XCTAssertEqual(text.textDrawRect.origin.y, 20, accuracy: 0.001)
        XCTAssertEqual(text.rotation, 0, "a full turn is exactly 'not rotated' again")
    }

    func testRightThenLeftIsBackWhereItStarted() {
        let editor = makeEditor(width: 300, height: 200)
        editor.rotateImage(clockwise: true)
        editor.rotateImage(clockwise: false)
        let image = editor.screenshotImage
        XCTAssertEqual(image?.size, NSSize(width: 300, height: 200))
        XCTAssertEqual(quadrant(image, x: 10, y: 10), .blue)
        XCTAssertEqual(quadrant(image, x: 290, y: 190), .green)
    }

    func testTheExportIsTheRotatedSize() throws {
        let editor = makeEditor(width: 300, height: 200)
        editor.annotations = [Annotation(tool: .filledRectangle, startPoint: NSPoint(x: 20, y: 20),
                                         endPoint: NSPoint(x: 120, y: 80), color: .black, strokeWidth: 2)]
        editor.rotateImage(clockwise: true)
        let image = try XCTUnwrap(editor.compositedImage())
        XCTAssertEqual(image.size, NSSize(width: 200, height: 300))
    }

    func testTheOverlayIsNotRotated() {
        // The fullscreen overlay's image is the screen; it can't swap sides.
        let overlay = OverlayView()
        overlay.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
        let image = ImageProbe.quadrantImage(width: 300, height: 200)
        overlay.screenshotImage = image
        overlay.applySelection(NSRect(x: 20, y: 20, width: 100, height: 80))

        overlay.rotateImage(clockwise: true)
        XCTAssertTrue(overlay.screenshotImage === image)
        XCTAssertTrue(overlay.undoStack.isEmpty, "a rotation that didn't happen must not be undoable")
    }

    // MARK: - Annotations turn with the image

    func testLinesAndStrokesAreRemappedPointByPoint() {
        let editor = makeEditor(width: 300, height: 200)
        let arrow = Annotation(tool: .arrow, startPoint: NSPoint(x: 20, y: 30),
                               endPoint: NSPoint(x: 80, y: 90), color: .red, strokeWidth: 3)
        arrow.controlPoint = NSPoint(x: 50, y: 40)
        let multi = Annotation(tool: .line, startPoint: NSPoint(x: 10, y: 10),
                               endPoint: NSPoint(x: 100, y: 10), color: .red, strokeWidth: 3)
        multi.anchorPoints = [NSPoint(x: 10, y: 10), NSPoint(x: 60, y: 50), NSPoint(x: 100, y: 10)]
        let pencil = Annotation(tool: .pencil, startPoint: NSPoint(x: 0, y: 0),
                                endPoint: NSPoint(x: 300, y: 200), color: .red, strokeWidth: 3)
        pencil.points = [NSPoint(x: 0, y: 0), NSPoint(x: 300, y: 200)]
        editor.annotations = [arrow, multi, pencil]

        // Clockwise on a 300 wide canvas: (x, y) -> (y, 300 - x).
        editor.rotateImage(clockwise: true)
        XCTAssertEqual(arrow.startPoint, NSPoint(x: 30, y: 280), "near the bottom-left ends up near the top-left")
        XCTAssertEqual(arrow.endPoint, NSPoint(x: 90, y: 220))
        XCTAssertEqual(arrow.controlPoint, NSPoint(x: 40, y: 250))
        XCTAssertEqual(multi.anchorPoints, [NSPoint(x: 10, y: 290), NSPoint(x: 50, y: 240), NSPoint(x: 10, y: 200)])
        XCTAssertEqual(pencil.points, [NSPoint(x: 0, y: 300), NSPoint(x: 200, y: 0)],
                       "the canvas corners map onto the new canvas corners")
    }

    func testRotatingLeftRemapsTheOtherWay() {
        let editor = makeEditor(width: 300, height: 200)
        let arrow = Annotation(tool: .arrow, startPoint: NSPoint(x: 20, y: 30),
                               endPoint: NSPoint(x: 80, y: 90), color: .red, strokeWidth: 3)
        editor.annotations = [arrow]

        // Counterclockwise on a 200 high canvas: (x, y) -> (200 - y, x).
        editor.rotateImage(clockwise: false)
        XCTAssertEqual(arrow.startPoint, NSPoint(x: 170, y: 20))
        XCTAssertEqual(arrow.endPoint, NSPoint(x: 110, y: 80))
    }

    func testARectangleSwapsItsSidesAndKeepsItsAngle() {
        let editor = makeEditor(width: 300, height: 200)
        let rect = Annotation(tool: .rectangle, startPoint: NSPoint(x: 20, y: 20),
                              endPoint: NSPoint(x: 120, y: 80), color: .red, strokeWidth: 3)
        rect.rotation = 0.3
        editor.annotations = [rect]

        editor.rotateImage(clockwise: true)
        XCTAssertEqual(rect.boundingRect, NSRect(x: 20, y: 180, width: 60, height: 100))
        XCTAssertEqual(rect.rotation, 0.3, accuracy: 0.0001,
                       "the swapped box at the same angle is the old shape a quarter turn further")
    }

    func testTextKeepsItsBoxAndTurnsWithThePicture() {
        let editor = makeEditor(width: 300, height: 200)
        let text = Annotation(tool: .text, startPoint: NSPoint(x: 20, y: 20),
                              endPoint: NSPoint(x: 120, y: 60), color: .red, strokeWidth: 2)
        text.textDrawRect = NSRect(x: 20, y: 20, width: 100, height: 40)
        editor.annotations = [text]

        editor.rotateImage(clockwise: true)
        // Centre (70, 40) -> (40, 230); the box itself is not reflowed.
        XCTAssertEqual(text.textDrawRect.size, NSSize(width: 100, height: 40))
        XCTAssertEqual(text.textDrawRect.midX, 40, accuracy: 0.001)
        XCTAssertEqual(text.textDrawRect.midY, 230, accuracy: 0.001)
        XCTAssertEqual(text.boundingRect.midX, 40, accuracy: 0.001, "the selection box moves with the text")
        XCTAssertEqual(text.boundingRect.midY, 230, accuracy: 0.001)
        XCTAssertEqual(text.rotation, -.pi / 2, accuracy: 0.0001, "clockwise is a negative annotation rotation")

        editor.rotateImage(clockwise: false)
        XCTAssertEqual(text.textDrawRect, NSRect(x: 20, y: 20, width: 100, height: 40))
        XCTAssertEqual(text.rotation, 0)
    }

    func testAnImageStampIsTurnedPixelForPixel() throws {
        let editor = makeEditor(width: 300, height: 200)
        let stamp = Annotation(tool: .stamp, startPoint: NSPoint(x: 20, y: 20),
                               endPoint: NSPoint(x: 100, y: 60), color: .clear, strokeWidth: 0)
        let picture = ImageProbe.quadrantImage(width: 80, height: 40)
        stamp.stampImage = picture
        editor.annotations = [stamp]

        editor.rotateImage(clockwise: true)
        // The box is the area the picture covers, which is what the canvas
        // grows to fit; a rotation angle on the old box would not be.
        XCTAssertEqual(stamp.boundingRect, NSRect(x: 20, y: 200, width: 40, height: 80))
        XCTAssertEqual(stamp.rotation, 0)
        let turned = try XCTUnwrap(stamp.stampImage)
        XCTAssertEqual(turned.size, NSSize(width: 40, height: 80))
        XCTAssertEqual(quadrant(turned, x: 5, y: 5), .red)
        XCTAssertEqual(quadrant(turned, x: 35, y: 5), .blue)

        editor.undo()
        XCTAssertTrue(stamp.stampImage === picture, "undo puts the unturned picture back")
        XCTAssertEqual(stamp.boundingRect, NSRect(x: 20, y: 20, width: 80, height: 40))
    }

    func testAnEmojiStampIsRotatedNotRasterized() {
        let editor = makeEditor(width: 300, height: 200)
        let stamp = Annotation(tool: .stamp, startPoint: NSPoint(x: 20, y: 20),
                               endPoint: NSPoint(x: 84, y: 84), color: .clear, strokeWidth: 0)
        let emoji = StampEmojis.renderEmoji("🎉", size: 64)
        stamp.stampImage = emoji
        editor.annotations = [stamp]

        editor.rotateImage(clockwise: true)
        XCTAssertTrue(stamp.stampImage === emoji, "an emoji is drawn on demand and stays sharp")
        XCTAssertEqual(stamp.boundingRect.size, NSSize(width: 64, height: 64))
        XCTAssertEqual(stamp.boundingRect.midX, 52, accuracy: 0.001)
        XCTAssertEqual(stamp.boundingRect.midY, 248, accuracy: 0.001)
        XCTAssertEqual(stamp.rotation, -.pi / 2, accuracy: 0.0001)
    }

    func testANumberBadgeTurnsAsAWhole() {
        let editor = makeEditor(width: 300, height: 200)
        let badge = Annotation(tool: .number, startPoint: NSPoint(x: 100, y: 100),
                               endPoint: NSPoint(x: 100, y: 100), color: .red, strokeWidth: 3)
        badge.number = 1
        editor.annotations = [badge]

        editor.rotateImage(clockwise: true)
        XCTAssertEqual(badge.startPoint.x, 100, accuracy: 0.001)
        XCTAssertEqual(badge.startPoint.y, 200, accuracy: 0.001)
        XCTAssertEqual(badge.rotation, -.pi / 2, accuracy: 0.0001)
    }

    // MARK: - Censors and loupes

    func testACensorWithoutASourceStaysBaked() throws {
        // Reopened from history or a project: a bake but nothing to re-bake
        // from. It must never drop to its see-through preview.
        let editor = makeEditor(width: 300, height: 200)
        let censor = Annotation(tool: .pixelate, startPoint: NSPoint(x: 20, y: 20),
                                endPoint: NSPoint(x: 120, y: 80), color: .black, strokeWidth: 2)
        let bake = ImageProbe.solidImage(width: 100, height: 60)
        censor.bakedBlurNSImage = bake
        editor.annotations = [censor]
        XCTAssertNil(censor.sourceImage)

        editor.rotateImage(clockwise: true)
        XCTAssertEqual(censor.boundingRect, NSRect(x: 20, y: 180, width: 60, height: 100))
        let turned = try XCTUnwrap(censor.bakedBlurNSImage, "rotating un-baked the censor")
        XCTAssertEqual(turned.size, NSSize(width: 60, height: 100), "the bake is turned, not stretched")

        editor.undo()
        XCTAssertTrue(censor.bakedBlurNSImage === bake, "the bake matching the restored geometry is reused")
        XCTAssertEqual(censor.boundingRect, NSRect(x: 20, y: 20, width: 100, height: 60))

        editor.redo()
        XCTAssertEqual(censor.bakedBlurNSImage?.size, NSSize(width: 60, height: 100))
    }

    func testEffectSourcesFollowTheRotatedImage() {
        let editor = makeEditor(width: 300, height: 200)
        let censor = Annotation(tool: .pixelate, startPoint: NSPoint(x: 20, y: 20),
                                endPoint: NSPoint(x: 120, y: 80), color: .black, strokeWidth: 2)
        censor.bakedBlurNSImage = ImageProbe.solidImage(width: 100, height: 60)
        let loupe = Annotation(tool: .loupe, startPoint: NSPoint(x: 100, y: 100),
                               endPoint: NSPoint(x: 160, y: 160), color: .red, strokeWidth: 2)
        loupe.loupeSourceRect = NSRect(x: 20, y: 30, width: 30, height: 30)
        editor.setAnnotations([censor, loupe])

        editor.rotateImage(clockwise: true)
        XCTAssertTrue(censor.sourceImage === editor.screenshotImage, "later re-bakes read the rotated pixels")
        XCTAssertEqual(censor.sourceImageBounds, NSRect(x: 0, y: 0, width: 200, height: 300))
        XCTAssertTrue(loupe.sourceImage === editor.screenshotImage)
        XCTAssertEqual(loupe.boundingRect, NSRect(x: 100, y: 140, width: 60, height: 60))
        XCTAssertEqual(loupe.loupeSourceRect, NSRect(x: 30, y: 250, width: 30, height: 30),
                       "the magnified spot stays on the same pixels")
        XCTAssertNotNil(loupe.bakedBlurNSImage)

        editor.undo()
        XCTAssertTrue(censor.sourceImage === editor.screenshotImage)
        XCTAssertEqual(loupe.loupeSourceRect, NSRect(x: 20, y: 30, width: 30, height: 30))
    }

    // MARK: - Undo

    func testUndoAndRedoMoveTheImageAndItsAnnotationsTogether() {
        let editor = makeEditor(width: 300, height: 200)
        let m = OverlayView.editorDocumentMargin
        let arrow = Annotation(tool: .arrow, startPoint: NSPoint(x: 20, y: 30),
                               endPoint: NSPoint(x: 80, y: 90), color: .red, strokeWidth: 3)
        editor.annotations = [arrow]
        editor.undoStack = [.added(arrow)]

        editor.rotateImage(clockwise: true)
        XCTAssertEqual(editor.undoStack.count, 2, "a rotation is one undo step")

        editor.undo()
        XCTAssertEqual(editor.screenshotImage?.size, NSSize(width: 300, height: 200))
        XCTAssertEqual(editor.selectionRect, NSRect(x: 0, y: 0, width: 300, height: 200))
        XCTAssertEqual(editor.frame.size, NSSize(width: 300 + 2 * m, height: 200 + 2 * m))
        XCTAssertEqual(quadrant(editor.screenshotImage, x: 10, y: 10), .blue)
        XCTAssertEqual(arrow.startPoint, NSPoint(x: 20, y: 30), "the arrow must line up with the image again")
        XCTAssertEqual(arrow.endPoint, NSPoint(x: 80, y: 90))
        XCTAssertEqual(editor.annotations.count, 1)

        editor.redo()
        XCTAssertEqual(editor.screenshotImage?.size, NSSize(width: 200, height: 300))
        XCTAssertEqual(editor.selectionRect, NSRect(x: 0, y: 0, width: 200, height: 300))
        XCTAssertEqual(quadrant(editor.screenshotImage, x: 10, y: 10), .red)
        XCTAssertEqual(arrow.startPoint, NSPoint(x: 30, y: 280))
        XCTAssertEqual(arrow.endPoint, NSPoint(x: 90, y: 220))
    }

    // MARK: - Helpers and the top bar

    func testRotationAnglesAreNormalized() {
        XCTAssertEqual(OverlayView.normalizedRotation(-.pi / 2 * 4), 0)
        XCTAssertEqual(OverlayView.normalizedRotation(.pi / 2 * 4), 0)
        XCTAssertEqual(OverlayView.normalizedRotation(-.pi), .pi, accuracy: 0.0001)
        XCTAssertEqual(OverlayView.normalizedRotation(.pi * 1.5), -.pi / 2, accuracy: 0.0001)
        XCTAssertEqual(OverlayView.normalizedRotation(0.3), 0.3, accuracy: 0.0001)
    }

    func testTheTopBarButtonsRotateTheEditorImage() throws {
        let editor = makeEditor(width: 300, height: 200)
        let bar = EditorTopBarView(frame: NSRect(x: 0, y: 0, width: 600, height: 32))
        bar.overlayView = editor

        func press(_ tooltip: String) throws {
            let button = try XCTUnwrap(
                bar.subviews.compactMap { $0 as? NSButton }.first { $0.toolTip == tooltip },
                "no \(tooltip) button in the editor top bar")
            let action = try XCTUnwrap(button.action)
            _ = (button.target as? NSObject)?.perform(action)
        }

        try press(L("Rotate Right"))
        XCTAssertEqual(editor.screenshotImage?.size, NSSize(width: 200, height: 300))
        XCTAssertEqual(quadrant(editor.screenshotImage, x: 10, y: 10), .red)

        try press(L("Rotate Left"))
        XCTAssertEqual(editor.screenshotImage?.size, NSSize(width: 300, height: 200))
        XCTAssertEqual(quadrant(editor.screenshotImage, x: 10, y: 10), .blue)
    }
}
