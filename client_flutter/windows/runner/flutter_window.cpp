#include "flutter_window.h"

#include <flutter/plugin_registrar_windows.h>
#include <optional>
#include <shellapi.h>

#include "desktop_shell_plugin.h"
#include "flutter/generated_plugin_registrant.h"
#include "raw_input_plugin.h"
#include "resource.h"

namespace {

constexpr UINT kTrayCallbackMessage = WM_APP + 101;
constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayCommandShow = 41001;
constexpr UINT kTrayCommandExit = 41002;
constexpr UINT_PTR kTrayRetryTimerId = 41003;
constexpr UINT_PTR kStartupTraySyncTimerId = 41004;
constexpr UINT kTrayRetryIntervalMs = 2000;
constexpr UINT kStartupTraySyncIntervalMs = 5000;
constexpr int kStartupTraySyncMaxAttempts = 12;

UINT GetTaskbarCreatedMessage() {
  static const UINT kTaskbarCreatedMessage =
      RegisterWindowMessageW(L"TaskbarCreated");
  return kTaskbarCreatedMessage;
}

UINT GetTrayEvent(LPARAM lparam) {
  const UINT version4_icon_id = HIWORD(lparam);
  if (version4_icon_id != 0) {
    return LOWORD(lparam);
  }
  return static_cast<UINT>(lparam);
}

POINT GetTrayAnchorPoint(WPARAM wparam, LPARAM lparam) {
  POINT cursor_pos = {};
  const UINT version4_icon_id = HIWORD(lparam);
  if (version4_icon_id != 0) {
    cursor_pos.x = static_cast<LONG>(static_cast<short>(LOWORD(wparam)));
    cursor_pos.y = static_cast<LONG>(static_cast<short>(HIWORD(wparam)));
    if (cursor_pos.x >= 0 && cursor_pos.y >= 0) {
      return cursor_pos;
    }
  }

  GetCursorPos(&cursor_pos);
  return cursor_pos;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }

  RegisterPlugins(flutter_controller_->engine());

  {
    auto raw_registrar =
        flutter_controller_->engine()->GetRegistrarForPlugin("RawInputPlugin");
    if (raw_registrar) {
      auto* typed = flutter::PluginRegistrarManager::GetInstance()
                        ->GetRegistrar<flutter::PluginRegistrarWindows>(
                            raw_registrar);
      RawInputPlugin::RegisterWithRegistrar(typed);
    }
  }

  {
    auto shell_registrar = flutter_controller_->engine()->GetRegistrarForPlugin(
        "DesktopShellPlugin");
    if (shell_registrar) {
      auto* typed = flutter::PluginRegistrarManager::GetInstance()
                        ->GetRegistrar<flutter::PluginRegistrarWindows>(
                            shell_registrar);
      DesktopShellPlugin::RegisterWithRegistrar(typed, this);
    }
  }

  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  EnsureTrayIcon();

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    if (start_hidden_to_tray_) {
      HideToTray();
      return;
    }
    Show();
  });
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  CancelStartupTraySync();
  CancelTrayIconRetry();
  RemoveTrayIcon();

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::SetMinimizeToTrayOnClose(bool enabled) {
  minimize_to_tray_on_close_ = enabled;
}

bool FlutterWindow::GetMinimizeToTrayOnClose() const {
  return minimize_to_tray_on_close_;
}

void FlutterWindow::SetStartHiddenToTray(bool enabled) {
  start_hidden_to_tray_ = enabled;
}

void FlutterWindow::RestoreFromTray() {
  const HWND handle = GetHandle();
  if (handle == nullptr) {
    return;
  }

  CancelStartupTraySync();
  EnsureTrayIcon();
  ShowWindow(handle, SW_SHOW);
  ShowWindow(handle, SW_RESTORE);
  BringWindowToTop(handle);
  SetForegroundWindow(handle);
}

void FlutterWindow::ExitFromTray() {
  exit_requested_ = true;
  minimize_to_tray_on_close_ = false;
  CancelStartupTraySync();
  CancelTrayIconRetry();
  RemoveTrayIcon();
  const HWND handle = GetHandle();
  if (handle == nullptr) {
    PostQuitMessage(0);
    return;
  }
  PostMessage(handle, WM_CLOSE, 0, 0);
}

bool FlutterWindow::ShowTrayNotification(const std::wstring& title,
                                         const std::wstring& body) {
  EnsureTrayIcon();
  if (!tray_icon_added_ || GetHandle() == nullptr) {
    return false;
  }

  NOTIFYICONDATAW icon_data = {};
  icon_data.cbSize = sizeof(NOTIFYICONDATAW);
  icon_data.hWnd = GetHandle();
  icon_data.uID = kTrayIconId;
  icon_data.uFlags = NIF_INFO;
  icon_data.dwInfoFlags = NIIF_INFO | NIIF_LARGE_ICON;
  wcsncpy_s(icon_data.szInfoTitle, title.c_str(), _TRUNCATE);
  wcsncpy_s(icon_data.szInfo, body.c_str(), _TRUNCATE);
  return Shell_NotifyIconW(NIM_MODIFY, &icon_data) == TRUE;
}

void FlutterWindow::EnsureTrayIcon() {
  const HWND handle = GetHandle();
  if (tray_icon_added_ || handle == nullptr) {
    return;
  }

  NOTIFYICONDATAW icon_data = {};
  icon_data.cbSize = sizeof(NOTIFYICONDATAW);
  icon_data.hWnd = handle;
  icon_data.uID = kTrayIconId;
  icon_data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  icon_data.uCallbackMessage = kTrayCallbackMessage;
  icon_data.hIcon =
      LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
  wcscpy_s(icon_data.szTip, L"FlowPlan");

  if (Shell_NotifyIconW(NIM_ADD, &icon_data)) {
    tray_icon_added_ = true;
    tray_icon_hwnd_ = handle;
    CancelTrayIconRetry();
    icon_data.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &icon_data);
    return;
  }

  ScheduleTrayIconRetry();
}

void FlutterWindow::ScheduleTrayIconRetry() {
  const HWND handle = GetHandle();
  if (handle == nullptr || tray_retry_scheduled_) {
    return;
  }

  if (SetTimer(handle, kTrayRetryTimerId, kTrayRetryIntervalMs, nullptr) != 0) {
    tray_retry_scheduled_ = true;
  }
}

void FlutterWindow::CancelTrayIconRetry() {
  const HWND handle = GetHandle();
  if (handle != nullptr && tray_retry_scheduled_) {
    KillTimer(handle, kTrayRetryTimerId);
  }
  tray_retry_scheduled_ = false;
}

void FlutterWindow::ScheduleStartupTraySync() {
  const HWND handle = GetHandle();
  if (handle == nullptr || startup_tray_sync_scheduled_ ||
      startup_tray_sync_remaining_ <= 0) {
    return;
  }

  if (SetTimer(handle, kStartupTraySyncTimerId, kStartupTraySyncIntervalMs,
               nullptr) != 0) {
    startup_tray_sync_scheduled_ = true;
  }
}

void FlutterWindow::CancelStartupTraySync() {
  const HWND handle = GetHandle();
  if (handle != nullptr && startup_tray_sync_scheduled_) {
    KillTimer(handle, kStartupTraySyncTimerId);
  }
  startup_tray_sync_scheduled_ = false;
  startup_tray_sync_remaining_ = 0;
}

void FlutterWindow::RemoveTrayIcon() {
  const HWND handle = tray_icon_hwnd_ != nullptr ? tray_icon_hwnd_ : GetHandle();
  if (!tray_icon_added_ || handle == nullptr) {
    tray_icon_added_ = false;
    tray_icon_hwnd_ = nullptr;
    return;
  }

  NOTIFYICONDATAW icon_data = {};
  icon_data.cbSize = sizeof(NOTIFYICONDATAW);
  icon_data.hWnd = handle;
  icon_data.uID = kTrayIconId;
  Shell_NotifyIconW(NIM_DELETE, &icon_data);
  tray_icon_added_ = false;
  tray_icon_hwnd_ = nullptr;
}

void FlutterWindow::HideToTray() {
  EnsureTrayIcon();
  if (start_hidden_to_tray_) {
    startup_tray_sync_remaining_ = kStartupTraySyncMaxAttempts;
    ScheduleStartupTraySync();
  }
  ShowWindow(GetHandle(), SW_HIDE);
}

void FlutterWindow::ShowTrayMenu(POINT cursor_pos) {
  HMENU menu = CreatePopupMenu();
  if (!menu) {
    return;
  }

  AppendMenuW(menu, MF_STRING, kTrayCommandShow,
              L"\u663e\u793a\u4e3b\u7a97\u53e3");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kTrayCommandExit, L"\u9000\u51fa");

  SetForegroundWindow(GetHandle());

  const UINT command = TrackPopupMenu(
      menu,
      TPM_RIGHTBUTTON | TPM_BOTTOMALIGN | TPM_LEFTALIGN | TPM_RETURNCMD,
      cursor_pos.x, cursor_pos.y, 0, GetHandle(), nullptr);
  switch (command) {
    case kTrayCommandShow:
      RestoreFromTray();
      break;
    case kTrayCommandExit:
      ExitFromTray();
      break;
  }
  PostMessage(GetHandle(), WM_NULL, 0, 0);
  DestroyMenu(menu);
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == GetTaskbarCreatedMessage()) {
    tray_icon_added_ = false;
    EnsureTrayIcon();
    return 0;
  }

  switch (message) {
    case WM_CLOSE:
      if (minimize_to_tray_on_close_ && !exit_requested_) {
        HideToTray();
        return 0;
      }
      break;
    case kTrayCallbackMessage: {
      const UINT tray_event = GetTrayEvent(lparam);
      switch (tray_event) {
        case NIN_SELECT:
        case NIN_KEYSELECT:
        case WM_LBUTTONUP:
        case WM_LBUTTONDBLCLK:
          RestoreFromTray();
          return 0;
        case WM_RBUTTONUP:
        case WM_CONTEXTMENU:
          ShowTrayMenu(GetTrayAnchorPoint(wparam, lparam));
          return 0;
      }
      break;
    }
    case WM_TIMER:
      if (wparam == kTrayRetryTimerId) {
        tray_retry_scheduled_ = false;
        EnsureTrayIcon();
        return 0;
      }
      if (wparam == kStartupTraySyncTimerId) {
        startup_tray_sync_scheduled_ = false;
        if (start_hidden_to_tray_ && startup_tray_sync_remaining_ > 0) {
          RemoveTrayIcon();
          EnsureTrayIcon();
          startup_tray_sync_remaining_--;
          ScheduleStartupTraySync();
        } else {
          CancelStartupTraySync();
        }
        return 0;
      }
      break;
    case WM_COMMAND:
      switch (LOWORD(wparam)) {
        case kTrayCommandShow:
          RestoreFromTray();
          return 0;
        case kTrayCommandExit:
          ExitFromTray();
          return 0;
      }
      break;
  }

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
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
