#include "flutter_window.h"

#include <dwmapi.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // -- Transparent window setup --
  HWND hwnd = GetHandle();

  // Extend DWM frame into the entire client area for per-pixel transparency.
  MARGINS margins = {-1, -1, -1, -1};
  DwmExtendFrameIntoClientArea(hwnd, &margins);

  // Set up MethodChannel for Dart to push opaque regions.
  // Dart sends a list of {x, y, w, h} maps in logical coordinates.
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(),
      "mascot/click_through",
      &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "setOpaqueRegions") {
          opaque_regions_.clear();
          const auto* args = std::get_if<flutter::EncodableList>(
              call.arguments());
          if (args) {
            for (const auto& item : *args) {
              const auto& map = std::get<flutter::EncodableMap>(item);
              opaque_regions_.push_back({
                  std::get<double>(
                      map.at(flutter::EncodableValue("x"))),
                  std::get<double>(
                      map.at(flutter::EncodableValue("y"))),
                  std::get<double>(
                      map.at(flutter::EncodableValue("w"))),
                  std::get<double>(
                      map.at(flutter::EncodableValue("h"))),
              });
            }
          }
          regions_initialized_ = true;
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  // Start click-through polling timer (50ms, matching macOS interval)
  SetTimer(hwnd, kClickThroughTimerId, 50, nullptr);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  HWND hwnd = GetHandle();
  if (hwnd) {
    KillTimer(hwnd, kClickThroughTimerId);
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_ERASEBKGND:
      // Suppress default background erase to prevent black flash in the
      // DWM glass region. Flutter paints the entire client area.
      return 1;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_TIMER:
      if (wparam == kClickThroughTimerId) {
        UpdateClickThrough();
        return 0;
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::UpdateClickThrough() {
  // Skip updates while a native drag is in progress
  if (is_dragging_) return;

  HWND hwnd = GetHandle();
  if (!hwnd) return;

  POINT cursor;
  GetCursorPos(&cursor);

  RECT rect;
  GetWindowRect(hwnd, &rect);

  // Only process when cursor is within window bounds
  if (!PtInRect(&rect, cursor)) {
    mouse_was_down_ = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;
    return;
  }

  // Convert physical pixel position to Flutter logical coordinates
  int local_x = cursor.x - rect.left;
  int local_y = cursor.y - rect.top;
  double dpi = static_cast<double>(GetDpiForWindow(hwnd));
  double scale = dpi / 96.0;
  double logical_x = local_x / scale;
  double logical_y = local_y / scale;

  bool transparent = !IsPointInOpaqueRegion(logical_x, logical_y);
  bool mouse_is_down = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;

  LONG exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);

  if (transparent) {
    // Transparent region - enable click-through
    if (!(exStyle & WS_EX_TRANSPARENT)) {
      SetWindowLong(hwnd, GWL_EXSTYLE, exStyle | WS_EX_TRANSPARENT);
    }
  } else {
    // Opaque region - disable click-through
    if (exStyle & WS_EX_TRANSPARENT) {
      SetWindowLong(hwnd, GWL_EXSTYLE, exStyle & ~WS_EX_TRANSPARENT);
    }

    // Start native drag on new left-button press over opaque region
    bool mouse_just_pressed = mouse_is_down && !mouse_was_down_;
    if (mouse_just_pressed) {
      is_dragging_ = true;
      ReleaseCapture();
      // Enter the modal window-move loop. Returns when user releases button.
      SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
      is_dragging_ = false;
    }
  }

  mouse_was_down_ = mouse_is_down;
}

bool FlutterWindow::IsPointInOpaqueRegion(double lx, double ly) const {
  // Before Dart sends regions, treat entire window as opaque (no click-through)
  if (!regions_initialized_) return true;

  for (const auto& r : opaque_regions_) {
    if (lx >= r.x && lx < r.x + r.w && ly >= r.y && ly < r.y + r.h) {
      return true;
    }
  }
  return false;
}
