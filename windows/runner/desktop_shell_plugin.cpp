#include "desktop_shell_plugin.h"

#include <windows.h>

#include <memory>
#include <string>
#include <vector>

#include "flutter_window.h"

namespace {

constexpr wchar_t kStartupRegistryPath[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
#if defined(NDEBUG)
constexpr wchar_t kStartupValueName[] = L"FlowPlan";
constexpr wchar_t kStartupTaskName[] = L"FlowPlan Startup";
#else
constexpr wchar_t kStartupValueName[] = L"FlowPlan Debug";
constexpr wchar_t kStartupTaskName[] = L"FlowPlan Debug Startup";
#endif
constexpr wchar_t kStartupToTrayArgument[] = L" --startup-to-tray";

bool ReadBoolArgument(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    const char* key,
    bool fallback) {
  if (const auto* args =
          std::get_if<flutter::EncodableMap>(method_call.arguments())) {
    auto it = args->find(flutter::EncodableValue(key));
    if (it != args->end()) {
      if (const auto* value = std::get_if<bool>(&it->second)) {
        return *value;
      }
    }
  }
  return fallback;
}

std::wstring EscapeScheduledTaskArgument(const std::wstring& value) {
  std::wstring escaped;
  escaped.reserve(value.size() * 2);
  for (const wchar_t character : value) {
    if (character == L'"') {
      escaped += L"\\\"";
    } else {
      escaped.push_back(character);
    }
  }
  return escaped;
}

}  // namespace

void DesktopShellPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar,
    FlutterWindow* window) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "com.flowplan/desktop_shell",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<DesktopShellPlugin>(registrar, window);
  channel->SetMethodCallHandler(
      [plugin_ptr = plugin.get()](const auto& call, auto result) {
        plugin_ptr->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

DesktopShellPlugin::DesktopShellPlugin(
    flutter::PluginRegistrarWindows* registrar,
    FlutterWindow* window)
    : registrar_(registrar), window_(window) {}

DesktopShellPlugin::~DesktopShellPlugin() = default;

void DesktopShellPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == "setCloseToTrayEnabled") {
    const bool enabled = ReadBoolArgument(method_call, "enabled", true);
    if (window_ != nullptr) {
      window_->SetMinimizeToTrayOnClose(enabled);
    }
    result->Success(flutter::EncodableValue(enabled));
    return;
  }

  if (method_call.method_name() == "getLaunchAtStartupEnabled") {
    result->Success(
        flutter::EncodableValue(GetLaunchAtStartupEnabled()));
    return;
  }

  if (method_call.method_name() == "setLaunchAtStartupEnabled") {
    const bool enabled = ReadBoolArgument(method_call, "enabled", false);
    const bool applied = SetLaunchAtStartupEnabled(enabled);
    result->Success(flutter::EncodableValue(applied));
    return;
  }

  result->NotImplemented();
}

bool DesktopShellPlugin::GetLaunchAtStartupEnabled() const {
  if (StartupTaskExists()) {
    CreateStartupTask();
    RemoveLegacyStartupRegistryEntry();
    return true;
  }

  if (HasLegacyStartupRegistryEntry()) {
    const bool migrated = CreateStartupTask();
    if (migrated) {
      RemoveLegacyStartupRegistryEntry();
    }
    return true;
  }

  return false;
}

bool DesktopShellPlugin::SetLaunchAtStartupEnabled(bool enabled) const {
  if (enabled) {
    const bool created = CreateStartupTask();
    if (created) {
      RemoveLegacyStartupRegistryEntry();
    }
    return StartupTaskExists();
  }

  const bool task_removed = RemoveStartupTask();
  const bool registry_removed = RemoveLegacyStartupRegistryEntry();
  if (!task_removed || !registry_removed) {
    return false;
  }
  return !StartupTaskExists() && !HasLegacyStartupRegistryEntry();
}

bool DesktopShellPlugin::HasLegacyStartupRegistryEntry() const {
  wchar_t buffer[32768] = {};
  DWORD buffer_size = sizeof(buffer);
  const LSTATUS status = RegGetValueW(
      HKEY_CURRENT_USER, kStartupRegistryPath, kStartupValueName, RRF_RT_REG_SZ,
      nullptr, buffer, &buffer_size);
  if (status != ERROR_SUCCESS) {
    return false;
  }

  const std::wstring configured_command(buffer);
  return configured_command == GetExecutableCommand(true) ||
         configured_command == GetExecutableCommand(false);
}

bool DesktopShellPlugin::RemoveLegacyStartupRegistryEntry() const {
  HKEY key = nullptr;
  const LSTATUS open_status = RegOpenKeyExW(
      HKEY_CURRENT_USER, kStartupRegistryPath, 0, KEY_SET_VALUE, &key);
  if (open_status == ERROR_FILE_NOT_FOUND) {
    return true;
  }
  if (open_status != ERROR_SUCCESS) {
    return false;
  }

  LSTATUS status = RegDeleteValueW(key, kStartupValueName);
  if (status == ERROR_FILE_NOT_FOUND) {
    status = ERROR_SUCCESS;
  }
  RegCloseKey(key);
  return status == ERROR_SUCCESS;
}

bool DesktopShellPlugin::StartupTaskExists() const {
  DWORD exit_code = 1;
  const std::wstring arguments =
      L"/Query /TN \"" + GetStartupTaskName() + L"\"";
  if (!RunSchtasks(arguments, &exit_code)) {
    return false;
  }
  return exit_code == 0;
}

bool DesktopShellPlugin::CreateStartupTask() const {
  const std::wstring command = EscapeScheduledTaskArgument(
      GetExecutableCommand(true));
  std::wstring arguments =
      L"/Create /TN \"" + GetStartupTaskName() +
      L"\" /SC ONLOGON /DELAY 0000:15 /RL HIGHEST /IT";
  const std::wstring current_user = GetCurrentUserName();
  if (!current_user.empty()) {
    arguments +=
        L" /RU \"" + EscapeScheduledTaskArgument(current_user) + L"\"";
  }
  arguments += L" /TR \"" + command + L"\" /F";
  DWORD exit_code = 1;
  if (!RunSchtasks(arguments, &exit_code)) {
    return false;
  }
  return exit_code == 0;
}

bool DesktopShellPlugin::RemoveStartupTask() const {
  if (!StartupTaskExists()) {
    return true;
  }

  DWORD exit_code = 1;
  const std::wstring arguments =
      L"/Delete /TN \"" + GetStartupTaskName() + L"\" /F";
  if (!RunSchtasks(arguments, &exit_code)) {
    return false;
  }
  return exit_code == 0;
}

bool DesktopShellPlugin::RunSchtasks(const std::wstring& arguments,
                                     DWORD* exit_code) const {
  wchar_t system_directory[MAX_PATH] = {};
  std::wstring executable_path = L"schtasks.exe";
  const UINT directory_length =
      GetSystemDirectoryW(system_directory, MAX_PATH);
  if (directory_length > 0 && directory_length < MAX_PATH) {
    executable_path.assign(system_directory, directory_length);
    executable_path += L"\\schtasks.exe";
  }

  std::wstring command_line = L"\"" + executable_path + L"\" " + arguments;
  std::vector<wchar_t> buffer(command_line.begin(), command_line.end());
  buffer.push_back(L'\0');

  STARTUPINFOW startup_info = {};
  startup_info.cb = sizeof(startup_info);
  startup_info.dwFlags = STARTF_USESHOWWINDOW;
  startup_info.wShowWindow = SW_HIDE;

  PROCESS_INFORMATION process_info = {};
  const BOOL created = CreateProcessW(
      executable_path.c_str(), buffer.data(), nullptr, nullptr, FALSE,
      CREATE_NO_WINDOW, nullptr, nullptr, &startup_info, &process_info);
  if (!created) {
    return false;
  }

  const DWORD wait_result =
      WaitForSingleObject(process_info.hProcess, 15000);
  if (wait_result != WAIT_OBJECT_0) {
    TerminateProcess(process_info.hProcess, 1);
    CloseHandle(process_info.hThread);
    CloseHandle(process_info.hProcess);
    return false;
  }

  DWORD local_exit_code = 1;
  const BOOL got_exit_code =
      GetExitCodeProcess(process_info.hProcess, &local_exit_code);
  CloseHandle(process_info.hThread);
  CloseHandle(process_info.hProcess);
  if (!got_exit_code) {
    return false;
  }

  if (exit_code != nullptr) {
    *exit_code = local_exit_code;
  }
  return true;
}

std::wstring DesktopShellPlugin::GetCurrentUserName() const {
  DWORD required_size = 0;
  GetUserNameW(nullptr, &required_size);
  if (required_size == 0) {
    return L"";
  }

  std::vector<wchar_t> buffer(required_size, L'\0');
  if (!GetUserNameW(buffer.data(), &required_size) || required_size == 0) {
    return L"";
  }

  const size_t length =
      required_size > 0 ? static_cast<size_t>(required_size - 1) : 0;
  return std::wstring(buffer.data(), length);
}

std::wstring DesktopShellPlugin::GetStartupTaskName() const {
  return kStartupTaskName;
}

std::wstring DesktopShellPlugin::GetExecutableCommand(
    bool start_hidden_to_tray) const {
  std::wstring path(MAX_PATH, L'\0');
  const DWORD length = GetModuleFileNameW(nullptr, path.data(),
                                          static_cast<DWORD>(path.size()));
  if (length == 0) {
    return L"";
  }

  path.resize(length);
  std::wstring command = L"\"" + path + L"\"";
  if (start_hidden_to_tray) {
    command += kStartupToTrayArgument;
  }
  return command;
}
