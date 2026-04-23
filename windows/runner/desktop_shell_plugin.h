#ifndef RUNNER_DESKTOP_SHELL_PLUGIN_H_
#define RUNNER_DESKTOP_SHELL_PLUGIN_H_

#include <windows.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <string>

class FlutterWindow;

class DesktopShellPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar,
                                    FlutterWindow* window);

  DesktopShellPlugin(flutter::PluginRegistrarWindows* registrar,
                     FlutterWindow* window);
  ~DesktopShellPlugin() override;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  bool GetLaunchAtStartupEnabled() const;
  bool SetLaunchAtStartupEnabled(bool enabled) const;
  bool HasLegacyStartupRegistryEntry() const;
  bool RemoveLegacyStartupRegistryEntry() const;
  bool StartupTaskExists() const;
  bool CreateStartupTask() const;
  bool RemoveStartupTask() const;
  bool RunSchtasks(const std::wstring& arguments, DWORD* exit_code) const;
  void ShowReminder(const std::wstring& title, const std::wstring& body) const;
  std::wstring GetCurrentUserName() const;
  std::wstring GetStartupTaskName() const;
  std::wstring GetExecutableCommand(bool start_hidden_to_tray) const;

  flutter::PluginRegistrarWindows* registrar_;
  FlutterWindow* window_;
};

#endif  // RUNNER_DESKTOP_SHELL_PLUGIN_H_
