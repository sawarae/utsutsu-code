#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <vector>

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

  // Close button region in Flutter logical coordinates.
  // Must match Positioned(top: 0, left: 228) + size 36x36 in mascot_widget.dart.
  static constexpr double kCloseBtnLeft = 228.0;
  static constexpr double kCloseBtnTop = 0.0;
  static constexpr double kCloseBtnRight = 264.0;
  static constexpr double kCloseBtnBottom = 36.0;

  // Logical rectangle (in Flutter's coordinate system).
  struct LogicalRect {
    double x, y, w, h;
  };

  // Toggle WS_EX_TRANSPARENT based on cursor position over opaque regions.
  void UpdateClickThrough();

  // Returns true if (logical_x, logical_y) falls inside any opaque region.
  bool IsPointInOpaqueRegion(double logical_x, double logical_y) const;

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // MethodChannel for receiving opaque region updates from Dart.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  // MethodChannel for controlling native drag behavior from Dart.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> drag_channel_;

  // Opaque regions pushed from Dart (logical coordinates).
  std::vector<LogicalRect> opaque_regions_;

  // True after Dart has sent the first set of opaque regions.
  bool regions_initialized_ = false;

  // When false, WM_NCHITTEST returns HTCLIENT instead of HTCAPTION for opaque
  // regions, allowing Flutter GestureDetector to handle drag (wander mode).
  bool drag_enabled_ = true;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
