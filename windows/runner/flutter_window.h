#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  void SetMinimizeToTrayOnClose(bool enabled);
  bool GetMinimizeToTrayOnClose() const;
  void SetStartHiddenToTray(bool enabled);
  void RestoreFromTray();
  void ExitFromTray();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void EnsureTrayIcon();
  void ScheduleTrayIconRetry();
  void CancelTrayIconRetry();
  void ScheduleStartupTraySync();
  void CancelStartupTraySync();
  void RemoveTrayIcon();
  void HideToTray();
  void ShowTrayMenu(POINT cursor_pos);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  bool minimize_to_tray_on_close_ = true;
  bool start_hidden_to_tray_ = false;
  bool exit_requested_ = false;
  bool tray_icon_added_ = false;
  bool tray_retry_scheduled_ = false;
  bool startup_tray_sync_scheduled_ = false;
  int startup_tray_sync_remaining_ = 0;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
