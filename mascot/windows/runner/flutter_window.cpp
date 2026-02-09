#include "flutter_window.h"

#include <dwmapi.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

// PW_RENDERFULLCONTENT captures DWM-composited content including alpha.
// Available on Windows 8.1+. Define if the SDK header doesn't provide it.
#ifndef PW_RENDERFULLCONTENT
#define PW_RENDERFULLCONTENT 0x00000002
#endif

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

  // Ensure WS_EX_LAYERED is set for per-pixel transparency
  LONG exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);
  SetWindowLong(hwnd, GWL_EXSTYLE, exStyle | WS_EX_LAYERED);

  // Extend DWM frame into the entire client area for transparency
  MARGINS margins = {-1, -1, -1, -1};
  DwmExtendFrameIntoClientArea(hwnd, &margins);

  // Disable non-client rendering (removes shadow)
  DWMNCRENDERINGPOLICY policy = DWMNCRP_DISABLED;
  DwmSetWindowAttribute(hwnd, DWMWA_NCRENDERING_POLICY, &policy,
                         sizeof(policy));

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

  bool transparent = IsTransparentAtCursor();
  bool mouse_is_down = (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0;

  LONG exStyle = GetWindowLong(hwnd, GWL_EXSTYLE);

  if (transparent) {
    // Transparent pixel - enable click-through
    if (!(exStyle & WS_EX_TRANSPARENT)) {
      SetWindowLong(hwnd, GWL_EXSTYLE, exStyle | WS_EX_TRANSPARENT);
    }
  } else {
    // Opaque pixel - disable click-through
    if (exStyle & WS_EX_TRANSPARENT) {
      SetWindowLong(hwnd, GWL_EXSTYLE, exStyle & ~WS_EX_TRANSPARENT);
    }

    // Start native drag on new left-button press over opaque pixel
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

bool FlutterWindow::IsTransparentAtCursor() {
  HWND hwnd = GetHandle();

  POINT cursor;
  GetCursorPos(&cursor);

  RECT rect;
  GetWindowRect(hwnd, &rect);

  int local_x = cursor.x - rect.left;
  int local_y = cursor.y - rect.top;
  int width = rect.right - rect.left;
  int height = rect.bottom - rect.top;

  if (width <= 0 || height <= 0) return true;
  if (local_x < 0 || local_x >= width || local_y < 0 || local_y >= height) {
    return true;
  }

  // Create a 32-bit top-down DIB section for alpha-aware pixel reading
  BITMAPINFOHEADER bmi = {};
  bmi.biSize = sizeof(BITMAPINFOHEADER);
  bmi.biWidth = width;
  bmi.biHeight = -height;  // negative = top-down
  bmi.biPlanes = 1;
  bmi.biBitCount = 32;
  bmi.biCompression = BI_RGB;

  void* bits = nullptr;
  HDC screen_dc = GetDC(nullptr);
  HDC mem_dc = CreateCompatibleDC(screen_dc);
  HBITMAP dib = CreateDIBSection(mem_dc, reinterpret_cast<BITMAPINFO*>(&bmi),
                                  DIB_RGB_COLORS, &bits, nullptr, 0);

  if (!dib || !bits) {
    if (dib) DeleteObject(dib);
    DeleteDC(mem_dc);
    ReleaseDC(nullptr, screen_dc);
    return true;
  }

  HBITMAP old_bitmap = static_cast<HBITMAP>(SelectObject(mem_dc, dib));

  // Capture window content including DWM-composited alpha
  PrintWindow(hwnd, mem_dc, PW_RENDERFULLCONTENT);

  // Read alpha at cursor position (DIB pixel format: BGRA)
  BYTE* pixel =
      static_cast<BYTE*>(bits) + (local_y * width + local_x) * 4;
  BYTE alpha = pixel[3];

  // Cleanup
  SelectObject(mem_dc, old_bitmap);
  DeleteObject(dib);
  DeleteDC(mem_dc);
  ReleaseDC(nullptr, screen_dc);

  return alpha < 10;
}
