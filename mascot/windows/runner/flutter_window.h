#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"

// A window that hosts a Flutter view with transparent background,
// click-through on transparent pixels, and native drag support.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  static const UINT_PTR kClickThroughTimerId = 1;

  // Check the pixel under the cursor and toggle WS_EX_TRANSPARENT.
  // Also initiates native drag on new left-button press over opaque pixels.
  void UpdateClickThrough();

  // Returns true if the pixel under the cursor in this window is transparent.
  bool IsTransparentAtCursor();

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // True while a native window drag is in progress.
  bool is_dragging_ = false;

  // Previous left-button state for edge detection.
  bool mouse_was_down_ = false;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
