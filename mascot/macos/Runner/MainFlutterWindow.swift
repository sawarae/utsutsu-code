import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var clickThroughTimer: Timer?
  private var isDragging = false
  private var dragOrigin: NSPoint = .zero
  private var windowOriginAtDrag: NSPoint = .zero
  /// When false, left-mouse drags are forwarded to Flutter instead of
  /// moving the window natively. Wander mode disables native drag so
  /// that Flutter's GestureDetector can handle drag-to-throw.
  private var nativeDragEnabled = true

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    flutterViewController.backgroundColor = .clear  // Flutter 3.7+ defaults to black
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    self.isOpaque = false
    self.backgroundColor = .clear
    self.hasShadow = false
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.borderless)
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = false

    // Method channel to toggle native drag from Flutter
    let channel = FlutterMethodChannel(
      name: "mascot/native_drag",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "setEnabled" {
        if let enabled = call.arguments as? Bool {
          self?.nativeDragEnabled = enabled
        }
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    startClickThroughTracking()
  }

  // MARK: - Native window dragging via sendEvent

  override func sendEvent(_ event: NSEvent) {
    if nativeDragEnabled {
      switch event.type {
      case .leftMouseDown:
        if !self.ignoresMouseEvents {
          isDragging = true
          dragOrigin = NSEvent.mouseLocation
          windowOriginAtDrag = self.frame.origin
        }
      case .leftMouseDragged:
        if isDragging {
          let current = NSEvent.mouseLocation
          let newOrigin = NSPoint(
            x: windowOriginAtDrag.x + (current.x - dragOrigin.x),
            y: windowOriginAtDrag.y + (current.y - dragOrigin.y)
          )
          self.setFrameOrigin(newOrigin)
          return  // Handle natively, don't pass to Flutter
        }
      case .leftMouseUp:
        isDragging = false
      default:
        break
      }
    }
    super.sendEvent(event)
  }

  // MARK: - Click-through on transparent areas

  private func startClickThroughTracking() {
    clickThroughTimer = Timer.scheduledTimer(
      withTimeInterval: 0.05, repeats: true
    ) { [weak self] _ in
      self?.updateClickThrough()
    }
  }

  private func updateClickThrough() {
    // Don't toggle click-through while dragging
    guard !isDragging else { return }

    let mouseLocation = NSEvent.mouseLocation
    let wFrame = self.frame

    guard wFrame.contains(mouseLocation) else { return }

    let windowPoint = NSPoint(
      x: mouseLocation.x - wFrame.origin.x,
      y: mouseLocation.y - wFrame.origin.y
    )

    self.ignoresMouseEvents = isTransparentAt(windowPoint)
  }

  private func isTransparentAt(_ windowPoint: NSPoint) -> Bool {
    guard let cgImage = CGWindowListCreateImage(
      .null,
      .optionIncludingWindow,
      CGWindowID(self.windowNumber),
      [.boundsIgnoreFraming, .bestResolution]
    ) else {
      return true
    }

    let imageW = cgImage.width
    let imageH = cgImage.height
    let scaleX = CGFloat(imageW) / self.frame.width
    let scaleY = CGFloat(imageH) / self.frame.height

    // NSWindow origin is bottom-left; CGImage origin is top-left
    let pixelX = Int(windowPoint.x * scaleX)
    let pixelY = Int((self.frame.height - windowPoint.y) * scaleY)

    guard pixelX >= 0, pixelX < imageW,
          pixelY >= 0, pixelY < imageH else {
      return true
    }

    guard let dataProvider = cgImage.dataProvider,
          let data = dataProvider.data,
          let ptr = CFDataGetBytePtr(data) else {
      return true
    }

    let bytesPerPixel = cgImage.bitsPerPixel / 8
    let bytesPerRow = cgImage.bytesPerRow
    let offset = bytesPerRow * pixelY + bytesPerPixel * pixelX

    guard offset + bytesPerPixel <= CFDataGetLength(data) else {
      return true
    }

    let alpha: UInt8
    switch cgImage.alphaInfo {
    case .premultipliedFirst, .first, .noneSkipFirst:
      alpha = ptr[offset]
    case .premultipliedLast, .last, .noneSkipLast:
      alpha = ptr[offset + bytesPerPixel - 1]
    default:
      return false  // No alpha info — assume opaque
    }

    return alpha < 10
  }

  deinit {
    clickThroughTimer?.invalidate()
  }
}
