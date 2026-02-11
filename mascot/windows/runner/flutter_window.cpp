#include "flutter_window.h"

#include <dwmapi.h>
#include <windowsx.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

// Subclass proc for the Flutter child window.
// Returns HTTRANSPARENT for all WM_NCHITTEST so hit testing falls through
// to the parent window, which decides HTCAPTION (drag) vs pass-through.
static WNDPROC g_original_child_proc = nullptr;

static LRESULT CALLBACK ChildHitTestProc(
    HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  if (msg == WM_NCHITTEST) {
    return HTTRANSPARENT;
  }
  return CallWindowProc(g_original_child_proc, hwnd, msg, wp, lp);
}

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

  HWND flutter_view = flutter_controller_->view()->GetNativeWindow();
  SetChildContent(flutter_view);

  // Subclass the Flutter child window so WM_NCHITTEST returns HTTRANSPARENT.
  // This makes hit testing fall through to the parent window.
  g_original_child_proc = reinterpret_cast<WNDPROC>(
      SetWindowLongPtr(flutter_view, GWLP_WNDPROC,
                       reinterpret_cast<LONG_PTR>(ChildHitTestProc)));

  // -- Transparent window setup --
  HWND hwnd = GetHandle();

  // Extend DWM frame into the entire client area for per-pixel transparency.
  MARGINS margins = {-1, -1, -1, -1};
  DwmExtendFrameIntoClientArea(hwnd, &margins);

  // Make the layered window fully opaque at the layer level.
  // DWM per-pixel alpha still works:
  // effective_alpha = layer_alpha(255/255) * surface_alpha = surface_alpha
  SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);

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

  // Timer to toggle WS_EX_TRANSPARENT on the parent window.
  // When transparent, clicks pass through to other applications.
  // When opaque, WM_NCHITTEST returns HTCAPTION for drag support.
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
  // Handle close button click natively.
  // The child window returns HTTRANSPARENT so Flutter can't receive clicks
  // directly - we detect the close button region and post WM_CLOSE.
  if (message == WM_LBUTTONUP) {
    // WM_LBUTTONUP lparam is in client (physical pixel) coordinates.
    int px = GET_X_LPARAM(lparam);
    int py = GET_Y_LPARAM(lparam);
    double dpi = static_cast<double>(GetDpiForWindow(hwnd));
    double scale = dpi / 96.0;
    double lx = px / scale;
    double ly = py / scale;
    if (lx >= 228 && lx < 264 && ly >= 0 && ly < 36) {
      PostMessage(hwnd, WM_CLOSE, 0, 0);
      return 0;
    }
  }

  // Handle WM_NCHITTEST BEFORE Flutter to decide drag vs click-through.
  // Opaque region -> HTCAPTION (drag-to-move).
  // Transparent region -> HTTRANSPARENT (click passes to window below).
  if (message == WM_NCHITTEST) {
    POINT pt = {GET_X_LPARAM(lparam), GET_Y_LPARAM(lparam)};
    RECT rect;
    GetWindowRect(hwnd, &rect);

    if (!PtInRect(&rect, pt)) {
      return HTNOWHERE;
    }

    // Convert physical screen coords to Flutter logical coords
    int local_x = pt.x - rect.left;
    int local_y = pt.y - rect.top;
    double dpi = static_cast<double>(GetDpiForWindow(hwnd));
    double scale = dpi / 96.0;
    double logical_x = local_x / scale;
    double logical_y = local_y / scale;

    if (IsPointInOpaqueRegion(logical_x, logical_y)) {
      // Close button: left=228, top=0, size=36x36 (logical coords)
      // Return HTCLIENT so Flutter receives the click event.
      if (logical_x >= 228 && logical_x < 264 &&
          logical_y >= 0 && logical_y < 36) {
        return HTCLIENT;
      }
      return HTCAPTION;
    }
    return HTTRANSPARENT;
  }

  if (message == WM_ERASEBKGND) {
    return 1;
  }

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
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
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
  HWND hwnd = GetHandle();
  if (!hwnd) return;

  POINT cursor;
  GetCursorPos(&cursor);

  RECT rect;
  GetWindowRect(hwnd, &rect);

  LONG exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);

  // When cursor is outside the window, keep current state
  if (!PtInRect(&rect, cursor)) {
    return;
  }

  // Convert physical pixel position to Flutter logical coordinates
  int local_x = cursor.x - rect.left;
  int local_y = cursor.y - rect.top;
  double dpi = static_cast<double>(GetDpiForWindow(hwnd));
  double scale = dpi / 96.0;
  double logical_x = local_x / scale;
  double logical_y = local_y / scale;

  if (IsPointInOpaqueRegion(logical_x, logical_y)) {
    // Opaque region: remove WS_EX_TRANSPARENT so window receives input.
    // WM_NCHITTEST will return HTCAPTION for drag support.
    if (exStyle & WS_EX_TRANSPARENT) {
      SetWindowLong(hwnd, GWL_EXSTYLE, exStyle & ~WS_EX_TRANSPARENT);
      SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
          SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    }
  } else {
    // Transparent region: set WS_EX_TRANSPARENT so clicks pass through
    // to other applications.
    if (!(exStyle & WS_EX_TRANSPARENT)) {
      SetWindowLong(hwnd, GWL_EXSTYLE, exStyle | WS_EX_TRANSPARENT);
      SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
          SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    }
  }
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
