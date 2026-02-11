#include "flutter_window.h"

#include <dwmapi.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

// PW_RENDERFULLCONTENT captures DWM-composited content including alpha.
// Available on Windows 8.1+. Define if the SDK header doesn't provide it.
#ifndef PW_RENDERFULLCONTENT
#define PW_RENDERFULLCONTENT 0x00000002
#endif

// --- Undocumented SetWindowCompositionAttribute API for transparency ---
typedef enum {
  ACCENT_DISABLED = 0,
  ACCENT_ENABLE_GRADIENT = 1,
  ACCENT_ENABLE_TRANSPARENTGRADIENT = 2,
  ACCENT_ENABLE_BLURBEHIND = 3,
  ACCENT_ENABLE_ACRYLICBLURBEHIND = 4,
} ACCENT_STATE;

struct ACCENT_POLICY {
  ACCENT_STATE AccentState;
  DWORD AccentFlags;
  DWORD GradientColor;  // AABBGGRR
  DWORD AnimationId;
};

// WCA_ACCENT_POLICY = 19
struct WINDOWCOMPOSITIONATTRIBDATA {
  DWORD Attrib;
  PVOID pvData;
  SIZE_T cbData;
};

typedef BOOL(WINAPI* pfnSetWindowCompositionAttribute)(
    HWND, WINDOWCOMPOSITIONATTRIBDATA*);

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

  // Use SetWindowCompositionAttribute for true per-pixel transparency.
  // GradientColor=0x00000000 ensures no tint; AccentFlags=2 avoids border.
  auto SetWindowCompositionAttribute =
      reinterpret_cast<pfnSetWindowCompositionAttribute>(GetProcAddress(
          GetModuleHandle(L"user32.dll"), "SetWindowCompositionAttribute"));
  if (SetWindowCompositionAttribute) {
    ACCENT_POLICY accent = {ACCENT_ENABLE_TRANSPARENTGRADIENT, 2, 0, 0};
    WINDOWCOMPOSITIONATTRIBDATA data = {19, &accent, sizeof(accent)};
    SetWindowCompositionAttribute(hwnd, &data);
  } else {
    OutputDebugString(
        L"[mascot] SetWindowCompositionAttribute not available; "
        L"window transparency may not work correctly.\n");
  }

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

  FreeCachedBitmap();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::FreeCachedBitmap() {
  if (cached_dc_) {
    if (cached_old_bmp_) SelectObject(cached_dc_, cached_old_bmp_);
    if (cached_dib_) DeleteObject(cached_dib_);
    DeleteDC(cached_dc_);
    cached_dc_ = nullptr;
    cached_dib_ = nullptr;
    cached_old_bmp_ = nullptr;
    cached_bits_ = nullptr;
    cached_width_ = 0;
    cached_height_ = 0;
  }
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

    // Start native drag on new left-button press over opaque pixel,
    // but skip the close button region so Flutter can handle it.
    bool mouse_just_pressed = mouse_is_down && !mouse_was_down_;
    if (mouse_just_pressed) {
      int local_x = cursor.x - rect.left;
      int local_y = cursor.y - rect.top;
      // Close button: left=228, top=0, size=36x36 (Windows only)
      bool in_close_btn = local_x >= 228 && local_x < 264 &&
                          local_y >= 0 && local_y < 36;
      if (!in_close_btn) {
        is_dragging_ = true;
        ReleaseCapture();
        // Enter the modal window-move loop. Returns when user releases button.
        SendMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
        is_dragging_ = false;
      }
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

  // Reuse a cached DIB section to avoid allocating/freeing every 50ms.
  // Recreate only when the window size changes (e.g. DPI change).
  // Note: Both GetWindowRect and PrintWindow use physical (DPI-scaled)
  // pixels, so their coordinates are consistent at any DPI setting.
  if (!cached_dc_ || cached_width_ != width || cached_height_ != height) {
    FreeCachedBitmap();

    BITMAPINFOHEADER bmi = {};
    bmi.biSize = sizeof(BITMAPINFOHEADER);
    bmi.biWidth = width;
    bmi.biHeight = -height;  // negative = top-down
    bmi.biPlanes = 1;
    bmi.biBitCount = 32;
    bmi.biCompression = BI_RGB;

    HDC screen_dc = GetDC(nullptr);
    cached_dc_ = CreateCompatibleDC(screen_dc);
    cached_dib_ = CreateDIBSection(
        cached_dc_, reinterpret_cast<BITMAPINFO*>(&bmi),
        DIB_RGB_COLORS, &cached_bits_, nullptr, 0);
    ReleaseDC(nullptr, screen_dc);

    if (!cached_dib_ || !cached_bits_) {
      FreeCachedBitmap();
      return true;
    }

    cached_old_bmp_ = static_cast<HBITMAP>(SelectObject(cached_dc_, cached_dib_));
    cached_width_ = width;
    cached_height_ = height;
  }

  // Capture window content including DWM-composited alpha
  PrintWindow(hwnd, cached_dc_, PW_RENDERFULLCONTENT);

  // Read alpha at cursor position directly from DIB bits (BGRA format)
  BYTE* pixel =
      static_cast<BYTE*>(cached_bits_) + (local_y * width + local_x) * 4;
  BYTE alpha = pixel[3];

  return alpha < 10;
}
