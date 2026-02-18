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
  /// When true, the window is in wander mode and click-through tracking
  /// is disabled (the entire window is the mascot).
  private var isWanderMode = false
  /// When true, the window is in swarm mode and click-through uses
  /// entity bounding box hit-testing instead of CGWindowListCreateImage.
  private var isSwarmMode = false
  /// Bounding boxes of swarm entities for click-through hit testing.
  private var entityRects: [(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)] = []

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

    // Start fully transparent to prevent yellow flash before Flutter renders
    self.alphaValue = 0

    // Method channel for Flutter to signal readiness
    let readyChannel = FlutterMethodChannel(
      name: "mascot/window_ready",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    readyChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "show":
        self?.alphaValue = 1
        result(nil)
      case "setCloseBtnRect":
        if let args = call.arguments as? [String: Double],
           let left = args["left"], let top = args["top"], let size = args["size"] {
          self?.closeBtnLeft = CGFloat(left)
          self?.closeBtnTop = CGFloat(top)
          self?.closeBtnSize = CGFloat(size)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

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

    // Method channel for wander mode (skips click-through tracking)
    let wanderChannel = FlutterMethodChannel(
      name: "mascot/wander_mode",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    wanderChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "setEnabled" {
        if let enabled = call.arguments as? Bool {
          self?.isWanderMode = enabled
          if enabled {
            // Wander mascots are always interactive - no click-through needed
            self?.clickThroughTimer?.invalidate()
            self?.clickThroughTimer = nil
            self?.ignoresMouseEvents = false
          }
        }
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // Method channel for swarm mode (entity rect hit-testing)
    let swarmChannel = FlutterMethodChannel(
      name: "mascot/swarm_mode",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    swarmChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setEnabled":
        if let enabled = call.arguments as? Bool {
          self?.isSwarmMode = enabled
          if enabled {
            // Disable native window drag — Flutter handles entity dragging
            self?.nativeDragEnabled = false
            // Stop bitmap-based click-through, use entity rect hit-testing
            self?.clickThroughTimer?.invalidate()
            self?.clickThroughTimer = nil
            self?.startEntityRectTracking()
          }
        }
        result(nil)
      case "updateEntityRects":
        if let rects = call.arguments as? [[String: Double]] {
          self?.entityRects = rects.compactMap { dict in
            guard let x = dict["x"], let y = dict["y"],
                  let w = dict["w"], let h = dict["h"] else { return nil }
            return (x: CGFloat(x), y: CGFloat(y), w: CGFloat(w), h: CGFloat(h))
          }
        }
        result(nil)
      default:
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

  // Close button area in logical coordinates, sent from Flutter via method channel.
  // Defaults to an impossible rect so the exemption never fires until Flutter provides values.
  private var closeBtnLeft: CGFloat = -1
  private var closeBtnTop: CGFloat = -1
  private var closeBtnSize: CGFloat = 0

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

    // NSWindow coordinates: origin at bottom-left, Flutter: origin at top-left
    let flutterY = wFrame.height - windowPoint.y
    let inCloseBtn = windowPoint.x >= closeBtnLeft
      && windowPoint.x <= closeBtnLeft + closeBtnSize
      && flutterY >= closeBtnTop
      && flutterY <= closeBtnTop + closeBtnSize

    if inCloseBtn {
      self.ignoresMouseEvents = false
    } else {
      self.ignoresMouseEvents = isTransparentAt(windowPoint)
    }
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

  // MARK: - Swarm entity rect click-through

  private var entityRectTimer: Timer?

  private func startEntityRectTracking() {
    entityRectTimer = Timer.scheduledTimer(
      withTimeInterval: 0.05, repeats: true
    ) { [weak self] _ in
      self?.updateEntityRectClickThrough()
    }
  }

  private func updateEntityRectClickThrough() {
    guard !isDragging else { return }

    let mouseLocation = NSEvent.mouseLocation
    let wFrame = self.frame
    guard wFrame.contains(mouseLocation) else { return }

    let localX = CGFloat(mouseLocation.x - wFrame.origin.x)
    let localY = CGFloat(wFrame.height - (mouseLocation.y - wFrame.origin.y))

    let overEntity = entityRects.contains { r in
      localX >= r.x && localX <= r.x + r.w &&
      localY >= r.y && localY <= r.y + r.h
    }
    self.ignoresMouseEvents = !overEntity
  }

  deinit {
    clickThroughTimer?.invalidate()
    entityRectTimer?.invalidate()
  }
}
