#include "raw_input_plugin.h"

#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <string>
#include <utility>
#include <vector>

namespace {
constexpr UINT_PTR kForegroundContextTimerId = 1;
constexpr UINT_PTR kMouseMoveFlushTimerId = 2;
constexpr UINT kForegroundContextRefreshIntervalMs = 500;
constexpr UINT kMouseMoveFlushIntervalMs = 500;
constexpr int64_t kMouseMoveBufferWindowMicros =
    static_cast<int64_t>(kMouseMoveFlushIntervalMs) * 1000;

int64_t CurrentTimestampMicros() {
  return std::chrono::duration_cast<std::chrono::microseconds>(
             std::chrono::system_clock::now().time_since_epoch())
      .count();
}

bool SameWindowContext(const InputWindowContext& left,
                       const InputWindowContext& right) {
  return left.process_name == right.process_name &&
         left.class_name == right.class_name &&
         left.window_title == right.window_title;
}
}  // namespace

RawInputPlugin* RawInputPlugin::instance_ = nullptr;

void RawInputPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "com.flowplan/raw_input",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<RawInputPlugin>(registrar);
  channel->SetMethodCallHandler(
      [plugin_ptr = plugin.get()](const auto& call, auto result) {
        plugin_ptr->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

RawInputPlugin::RawInputPlugin(flutter::PluginRegistrarWindows* registrar) {
  instance_ = this;
  for (auto& count : key_counts_) {
    count = 0;
  }
}

RawInputPlugin::~RawInputPlugin() {
  StopBackgroundThread();
  instance_ = nullptr;
}

flutter::EncodableMap RawInputPlugin::BuildKeyDistribution() const {
  flutter::EncodableMap distribution;
  for (int i = 0; i < 256; ++i) {
    const auto count = key_counts_[i].load();
    if (count == 0) {
      continue;
    }
    distribution[flutter::EncodableValue(i)] =
        flutter::EncodableValue(static_cast<int64_t>(count));
  }
  return distribution;
}

flutter::EncodableMap RawInputPlugin::BuildMouseClicks() const {
  flutter::EncodableMap clicks;
  clicks[flutter::EncodableValue("left")] =
      flutter::EncodableValue(mouse_left_click_count_.load());
  clicks[flutter::EncodableValue("right")] =
      flutter::EncodableValue(mouse_right_click_count_.load());
  clicks[flutter::EncodableValue("middle")] =
      flutter::EncodableValue(mouse_middle_click_count_.load());
  clicks[flutter::EncodableValue("xButton1")] =
      flutter::EncodableValue(mouse_xbutton1_click_count_.load());
  clicks[flutter::EncodableValue("xButton2")] =
      flutter::EncodableValue(mouse_xbutton2_click_count_.load());
  return clicks;
}

void RawInputPlugin::AppendInputEvent(InputEventData event) {
  std::lock_guard<std::mutex> lock(input_event_mutex_);
  input_events_.push_back(std::move(event));
}

flutter::EncodableList RawInputPlugin::ConsumeInputEvents() {
  FlushBufferedMouseMove();

  std::vector<InputEventData> snapshot;
  {
    std::lock_guard<std::mutex> lock(input_event_mutex_);
    snapshot.swap(input_events_);
  }

  flutter::EncodableList events;
  for (const auto& event : snapshot) {
    flutter::EncodableMap encoded;
    encoded[flutter::EncodableValue("sequenceId")] =
        flutter::EncodableValue(static_cast<int64_t>(event.sequence_id));
    encoded[flutter::EncodableValue("timestampMicros")] =
        flutter::EncodableValue(event.timestamp_micros);
    encoded[flutter::EncodableValue("kind")] =
        flutter::EncodableValue(event.kind);
    encoded[flutter::EncodableValue("eventCount")] =
        flutter::EncodableValue(static_cast<int64_t>(event.event_count));
    if (event.has_key_code) {
      encoded[flutter::EncodableValue("keyCode")] =
          flutter::EncodableValue(static_cast<int64_t>(event.key_code));
    }
    if (!event.mouse_button.empty()) {
      encoded[flutter::EncodableValue("mouseButton")] =
          flutter::EncodableValue(event.mouse_button);
    }
    encoded[flutter::EncodableValue("wheelDelta")] =
        flutter::EncodableValue(static_cast<int64_t>(event.wheel_delta));
    encoded[flutter::EncodableValue("deltaX")] =
        flutter::EncodableValue(static_cast<int64_t>(event.delta_x));
    encoded[flutter::EncodableValue("deltaY")] =
        flutter::EncodableValue(static_cast<int64_t>(event.delta_y));
    encoded[flutter::EncodableValue("moveDistance")] =
        flutter::EncodableValue(static_cast<int64_t>(event.move_distance));
    if (!event.token_text.empty()) {
      encoded[flutter::EncodableValue("tokenText")] =
          flutter::EncodableValue(event.token_text);
    }
    if (!event.process_name.empty()) {
      encoded[flutter::EncodableValue("processName")] =
          flutter::EncodableValue(event.process_name);
    }
    if (!event.class_name.empty()) {
      encoded[flutter::EncodableValue("className")] =
          flutter::EncodableValue(event.class_name);
    }
    if (!event.window_title.empty()) {
      encoded[flutter::EncodableValue("windowTitle")] =
          flutter::EncodableValue(event.window_title);
    }
    events.push_back(flutter::EncodableValue(encoded));
  }

  return events;
}

void RawInputPlugin::BufferMouseMove(int delta_x, int delta_y, int move_distance,
                                     const InputWindowContext& context,
                                     int64_t timestamp_micros) {
  BufferedMouseMoveData buffered_to_flush;
  bool should_flush = false;

  {
    std::lock_guard<std::mutex> lock(mouse_move_mutex_);
    auto& pending = buffered_mouse_move_;
    if (pending.has_pending &&
        ((timestamp_micros - pending.started_at_micros) >=
             kMouseMoveBufferWindowMicros ||
         !SameWindowContext(pending.context, context))) {
      buffered_to_flush = pending;
      pending = BufferedMouseMoveData();
      should_flush = true;
    }

    if (!pending.has_pending) {
      pending.has_pending = true;
      pending.started_at_micros = timestamp_micros;
      pending.context = context;
    }

    pending.last_timestamp_micros = timestamp_micros;
    pending.event_count += 1;
    pending.delta_x += delta_x;
    pending.delta_y += delta_y;
    pending.move_distance += move_distance;
  }

  if (should_flush) {
    InputEventData event;
    event.sequence_id = ++input_event_sequence_;
    event.timestamp_micros = buffered_to_flush.last_timestamp_micros;
    event.kind = "mouse_move";
    event.event_count = buffered_to_flush.event_count;
    event.delta_x = buffered_to_flush.delta_x;
    event.delta_y = buffered_to_flush.delta_y;
    event.move_distance = buffered_to_flush.move_distance;
    event.process_name = buffered_to_flush.context.process_name;
    event.class_name = buffered_to_flush.context.class_name;
    event.window_title = buffered_to_flush.context.window_title;
    AppendInputEvent(std::move(event));
  }
}

void RawInputPlugin::FlushBufferedMouseMove() {
  BufferedMouseMoveData buffered;
  {
    std::lock_guard<std::mutex> lock(mouse_move_mutex_);
    if (!buffered_mouse_move_.has_pending) {
      return;
    }
    buffered = buffered_mouse_move_;
    buffered_mouse_move_ = BufferedMouseMoveData();
  }

  InputEventData event;
  event.sequence_id = ++input_event_sequence_;
  event.timestamp_micros = buffered.last_timestamp_micros;
  event.kind = "mouse_move";
  event.event_count = buffered.event_count;
  event.delta_x = buffered.delta_x;
  event.delta_y = buffered.delta_y;
  event.move_distance = buffered.move_distance;
  event.process_name = buffered.context.process_name;
  event.class_name = buffered.context.class_name;
  event.window_title = buffered.context.window_title;
  AppendInputEvent(std::move(event));
}

void RawInputPlugin::ClearBufferedMouseMove() {
  std::lock_guard<std::mutex> lock(mouse_move_mutex_);
  buffered_mouse_move_ = BufferedMouseMoveData();
}

void RawInputPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name() == "start") {
    SetLastErrorMessage(std::string());
    StartBackgroundThread();
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name() == "stop") {
    StopBackgroundThread();
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name() == "getStats") {
    FlushBufferedMouseMove();
    flutter::EncodableMap stats;
    stats[flutter::EncodableValue("keyCount")] =
        flutter::EncodableValue(key_count_.load());
    stats[flutter::EncodableValue("keyDistribution")] =
        flutter::EncodableValue(BuildKeyDistribution());
    stats[flutter::EncodableValue("mouseClickCount")] =
        flutter::EncodableValue(
            mouse_left_click_count_.load() + mouse_right_click_count_.load() +
            mouse_middle_click_count_.load() +
            mouse_xbutton1_click_count_.load() +
            mouse_xbutton2_click_count_.load());
    stats[flutter::EncodableValue("mouseClicks")] =
        flutter::EncodableValue(BuildMouseClicks());
    stats[flutter::EncodableValue("mouseMovePx")] =
        flutter::EncodableValue(mouse_move_px_.load());
    stats[flutter::EncodableValue("scrollPx")] =
        flutter::EncodableValue(scroll_px_.load());
    stats[flutter::EncodableValue("keySequence")] =
        flutter::EncodableValue(ConsumeSequenceBuffer());
    stats[flutter::EncodableValue("inputEvents")] =
        flutter::EncodableValue(ConsumeInputEvents());
    const std::string last_error = GetLastErrorMessage();
    if (!last_error.empty()) {
      stats[flutter::EncodableValue("lastError")] =
          flutter::EncodableValue(last_error);
    }
    result->Success(flutter::EncodableValue(stats));
  } else if (method_call.method_name() == "setSequenceRecording") {
    bool enabled = false;
    if (const auto* args =
            std::get_if<flutter::EncodableMap>(method_call.arguments())) {
      auto it = args->find(flutter::EncodableValue("enabled"));
      if (it != args->end()) {
        if (const auto* value = std::get_if<bool>(&it->second)) {
          enabled = *value;
        }
      }
    }
    enable_sequence_record_ = enabled;
    if (enabled) {
      std::lock_guard<std::mutex> lock(sequence_mutex_);
      sequence_buffer_.clear();
    }
    result->Success(flutter::EncodableValue(true));
  } else if (method_call.method_name() == "resetStats") {
    FlushBufferedMouseMove();
    key_count_ = 0;
    mouse_left_click_count_ = 0;
    mouse_right_click_count_ = 0;
    mouse_middle_click_count_ = 0;
    mouse_xbutton1_click_count_ = 0;
    mouse_xbutton2_click_count_ = 0;
    scroll_px_ = 0;
    mouse_move_px_ = 0;
    input_event_sequence_ = 0;
    for (auto& count : key_counts_) {
      count = 0;
    }
    {
      std::lock_guard<std::mutex> lock(sequence_mutex_);
      sequence_buffer_.clear();
    }
    {
      std::lock_guard<std::mutex> lock(input_event_mutex_);
      input_events_.clear();
    }
    ClearBufferedMouseMove();
    result->Success(flutter::EncodableValue(true));
  } else {
    result->NotImplemented();
  }
}

void RawInputPlugin::RefreshCachedForegroundWindowContext() {
  cached_window_context_ = CaptureForegroundWindowContext();
}

InputWindowContext RawInputPlugin::GetCachedForegroundWindowContext() const {
  return cached_window_context_;
}

void RawInputPlugin::StartBackgroundThread() {
  if (running_) {
    return;
  }
  running_ = true;

  bg_thread_ = std::thread([this]() {
    WNDCLASSEX wc = {};
    wc.cbSize = sizeof(WNDCLASSEX);
    wc.lpfnWndProc = RawInputWndProc;
    wc.hInstance = GetModuleHandle(nullptr);
    wc.lpszClassName = L"FlowPlanRawInputSink";
    RegisterClassEx(&wc);

    bg_hwnd_ = CreateWindowEx(0, L"FlowPlanRawInputSink", L"RawInput Sink", 0,
                              0, 0, 0, 0, HWND_MESSAGE, nullptr,
                              GetModuleHandle(nullptr), nullptr);

    if (!bg_hwnd_) {
      SetLastErrorMessage("CreateWindowEx failed for RawInput sink: " +
                          std::to_string(GetLastError()));
      running_ = false;
      return;
    }

    RefreshCachedForegroundWindowContext();
    SetTimer(bg_hwnd_, kForegroundContextTimerId,
             kForegroundContextRefreshIntervalMs, nullptr);
    SetTimer(bg_hwnd_, kMouseMoveFlushTimerId, kMouseMoveFlushIntervalMs,
             nullptr);

    RAWINPUTDEVICE rid[2] = {};
    rid[0].usUsagePage = 0x01;
    rid[0].usUsage = 0x06;
    rid[0].dwFlags = RIDEV_INPUTSINK;
    rid[0].hwndTarget = bg_hwnd_;
    rid[1].usUsagePage = 0x01;
    rid[1].usUsage = 0x02;
    rid[1].dwFlags = RIDEV_INPUTSINK;
    rid[1].hwndTarget = bg_hwnd_;

    if (!RegisterRawInputDevices(rid, 2, sizeof(RAWINPUTDEVICE))) {
      SetLastErrorMessage("RegisterRawInputDevices failed: " +
                          std::to_string(GetLastError()));
    } else {
      SetLastErrorMessage(std::string());
    }

    MSG msg;
    while (running_ && GetMessage(&msg, nullptr, 0, 0)) {
      TranslateMessage(&msg);
      DispatchMessage(&msg);
    }

    KillTimer(bg_hwnd_, kForegroundContextTimerId);
    KillTimer(bg_hwnd_, kMouseMoveFlushTimerId);
    DestroyWindow(bg_hwnd_);
    bg_hwnd_ = nullptr;
    UnregisterClass(L"FlowPlanRawInputSink", GetModuleHandle(nullptr));
  });
}

void RawInputPlugin::StopBackgroundThread() {
  if (!running_) {
    return;
  }
  FlushBufferedMouseMove();
  running_ = false;

  if (bg_hwnd_) {
    PostMessage(bg_hwnd_, WM_CLOSE, 0, 0);
  }
  if (bg_thread_.joinable()) {
    bg_thread_.join();
  }
}

void RawInputPlugin::AppendSequenceToken(const std::string& token) {
  if (!enable_sequence_record_) {
    return;
  }
  std::lock_guard<std::mutex> lock(sequence_mutex_);
  sequence_buffer_ += token;
}

std::string RawInputPlugin::ConsumeSequenceBuffer() {
  std::lock_guard<std::mutex> lock(sequence_mutex_);
  std::string snapshot = sequence_buffer_;
  sequence_buffer_.clear();
  return snapshot;
}

std::string RawInputPlugin::DescribeKeyStroke(
    const RAWKEYBOARD& keyboard) const {
  const int vkey = static_cast<int>(keyboard.VKey);
  switch (vkey) {
    case VK_BACK:
      return "[BACKSPACE]";
    case VK_RETURN:
      return "\n";
    case VK_TAB:
      return "\t";
    case VK_SPACE:
      return " ";
    case VK_ESCAPE:
      return "[ESC]";
    default:
      break;
  }

  BYTE keyboard_state[256];
  if (!GetKeyboardState(keyboard_state)) {
    return std::string();
  }

  wchar_t unicode[8] = {};
  const HKL layout = GetKeyboardLayout(0);
  const UINT scan_code = keyboard.MakeCode;
  const int result = ToUnicodeEx(static_cast<UINT>(vkey), scan_code,
                                 keyboard_state, unicode, 8, 0, layout);

  if (result > 0) {
    return WideToUtf8(std::wstring(unicode, unicode + result));
  }

  LONG key_info = static_cast<LONG>(keyboard.MakeCode << 16);
  if (keyboard.Flags & RI_KEY_E0) {
    key_info |= 1 << 24;
  }
  wchar_t key_name[128] = {};
  if (GetKeyNameTextW(key_info, key_name, 128) > 0) {
    return WideToUtf8(key_name);
  }

  return std::string();
}

InputWindowContext RawInputPlugin::CaptureForegroundWindowContext() const {
  InputWindowContext context;
  const HWND hwnd = GetForegroundWindow();
  if (!hwnd) {
    return context;
  }

  wchar_t title_buffer[512] = {};
  GetWindowTextW(hwnd, title_buffer, 512);
  context.window_title = WideToUtf8(title_buffer);

  wchar_t class_buffer[256] = {};
  GetClassNameW(hwnd, class_buffer, 256);
  context.class_name = WideToUtf8(class_buffer);

  DWORD process_id = 0;
  GetWindowThreadProcessId(hwnd, &process_id);
  if (process_id == 0) {
    return context;
  }

  HANDLE process =
      OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, process_id);
  if (!process) {
    return context;
  }

  wchar_t path_buffer[1024] = {};
  DWORD size = 1024;
  if (QueryFullProcessImageNameW(process, 0, path_buffer, &size)) {
    std::wstring full_path(path_buffer, path_buffer + size);
    const size_t last_separator = full_path.find_last_of(L"\\/");
    const std::wstring file_name =
        last_separator == std::wstring::npos
            ? full_path
            : full_path.substr(last_separator + 1);
    context.process_name = WideToUtf8(file_name);
  }

  CloseHandle(process);
  return context;
}

void RawInputPlugin::SetLastErrorMessage(const std::string& message) {
  std::lock_guard<std::mutex> lock(last_error_mutex_);
  last_error_ = message;
}

std::string RawInputPlugin::GetLastErrorMessage() const {
  std::lock_guard<std::mutex> lock(last_error_mutex_);
  return last_error_;
}

std::string RawInputPlugin::WideToUtf8(const std::wstring& value) {
  if (value.empty()) {
    return std::string();
  }

  const int bytes_needed = WideCharToMultiByte(
      CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0,
      nullptr, nullptr);
  if (bytes_needed <= 0) {
    return std::string();
  }

  std::string utf8(bytes_needed, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), utf8.data(),
                      bytes_needed, nullptr, nullptr);
  return utf8;
}

void RawInputPlugin::RecordKeyStroke(const RAWKEYBOARD& keyboard) {
  FlushBufferedMouseMove();

  const int vkey = static_cast<int>(keyboard.VKey);
  if (vkey < 0 || vkey >= 256) {
    return;
  }

  key_counts_[vkey]++;
  key_count_++;

  const std::string token = DescribeKeyStroke(keyboard);
  if (!token.empty()) {
    AppendSequenceToken(token);
  }

  const InputWindowContext context = GetCachedForegroundWindowContext();
  InputEventData event;
  event.sequence_id = ++input_event_sequence_;
  event.timestamp_micros = CurrentTimestampMicros();
  event.kind = "key_down";
  event.key_code = vkey;
  event.has_key_code = true;
  event.token_text = token;
  event.process_name = context.process_name;
  event.class_name = context.class_name;
  event.window_title = context.window_title;
  AppendInputEvent(std::move(event));
}

LRESULT CALLBACK RawInputPlugin::RawInputWndProc(HWND hwnd, UINT msg, WPARAM wp,
                                                 LPARAM lp) {
  if (msg == WM_TIMER && instance_) {
    if (wp == kForegroundContextTimerId) {
      instance_->RefreshCachedForegroundWindowContext();
      return 0;
    }
    if (wp == kMouseMoveFlushTimerId) {
      instance_->FlushBufferedMouseMove();
      return 0;
    }
  }

  if (msg != WM_INPUT || !instance_) {
    return DefWindowProc(hwnd, msg, wp, lp);
  }

  UINT size = 0;
  GetRawInputData(reinterpret_cast<HRAWINPUT>(lp), RID_INPUT, nullptr, &size,
                  sizeof(RAWINPUTHEADER));

  if (size == 0) {
    return 0;
  }

  std::vector<BYTE> buffer(size);
  if (GetRawInputData(reinterpret_cast<HRAWINPUT>(lp), RID_INPUT, buffer.data(),
                      &size, sizeof(RAWINPUTHEADER)) != size) {
    return 0;
  }

  RAWINPUT* raw = reinterpret_cast<RAWINPUT*>(buffer.data());

  if (raw->header.dwType == RIM_TYPEKEYBOARD) {
    if (raw->data.keyboard.Message == WM_KEYDOWN ||
        raw->data.keyboard.Message == WM_SYSKEYDOWN) {
      instance_->RecordKeyStroke(raw->data.keyboard);
    }
  } else if (raw->header.dwType == RIM_TYPEMOUSE) {
    auto& mouse = raw->data.mouse;
    const auto context = instance_->GetCachedForegroundWindowContext();
    const auto append_mouse_event = [&](const std::string& kind,
                                        const std::string& mouse_button,
                                        int wheel_delta, int delta_x,
                                        int delta_y, int move_distance) {
      InputEventData event;
      event.sequence_id = ++instance_->input_event_sequence_;
      event.timestamp_micros = CurrentTimestampMicros();
      event.kind = kind;
      event.mouse_button = mouse_button;
      event.wheel_delta = wheel_delta;
      event.delta_x = delta_x;
      event.delta_y = delta_y;
      event.move_distance = move_distance;
      event.process_name = context.process_name;
      event.class_name = context.class_name;
      event.window_title = context.window_title;
      instance_->AppendInputEvent(std::move(event));
    };

    if (mouse.usFlags == MOUSE_MOVE_RELATIVE &&
        (mouse.lLastX != 0 || mouse.lLastY != 0)) {
      const int64_t dx = static_cast<int64_t>(mouse.lLastX);
      const int64_t dy = static_cast<int64_t>(mouse.lLastY);
      const int64_t dist = static_cast<int64_t>(
          std::sqrt(static_cast<double>(dx * dx + dy * dy)));
      instance_->mouse_move_px_ += dist;
      instance_->BufferMouseMove(static_cast<int>(dx), static_cast<int>(dy),
                                 static_cast<int>(dist), context,
                                 CurrentTimestampMicros());
    }

    if (mouse.usButtonFlags & RI_MOUSE_LEFT_BUTTON_DOWN) {
      instance_->FlushBufferedMouseMove();
      instance_->mouse_left_click_count_++;
      append_mouse_event("mouse_button", "left", 0, 0, 0, 0);
    }
    if (mouse.usButtonFlags & RI_MOUSE_RIGHT_BUTTON_DOWN) {
      instance_->FlushBufferedMouseMove();
      instance_->mouse_right_click_count_++;
      append_mouse_event("mouse_button", "right", 0, 0, 0, 0);
    }
    if (mouse.usButtonFlags & RI_MOUSE_MIDDLE_BUTTON_DOWN) {
      instance_->FlushBufferedMouseMove();
      instance_->mouse_middle_click_count_++;
      append_mouse_event("mouse_button", "middle", 0, 0, 0, 0);
    }
    if (mouse.usButtonFlags & RI_MOUSE_BUTTON_4_DOWN) {
      instance_->FlushBufferedMouseMove();
      instance_->mouse_xbutton1_click_count_++;
      append_mouse_event("mouse_button", "x1", 0, 0, 0, 0);
    }
    if (mouse.usButtonFlags & RI_MOUSE_BUTTON_5_DOWN) {
      instance_->FlushBufferedMouseMove();
      instance_->mouse_xbutton2_click_count_++;
      append_mouse_event("mouse_button", "x2", 0, 0, 0, 0);
    }
    if (mouse.usButtonFlags & RI_MOUSE_WHEEL) {
      instance_->FlushBufferedMouseMove();
      const SHORT wheel_delta = static_cast<SHORT>(mouse.usButtonData);
      instance_->scroll_px_ += std::abs(static_cast<int>(wheel_delta));
      append_mouse_event("mouse_wheel",
                         wheel_delta >= 0 ? "wheel_up" : "wheel_down",
                         static_cast<int>(wheel_delta), 0, 0, 0);
    }
    if (mouse.usButtonFlags & RI_MOUSE_HWHEEL) {
      instance_->FlushBufferedMouseMove();
      const SHORT wheel_delta = static_cast<SHORT>(mouse.usButtonData);
      instance_->scroll_px_ += std::abs(static_cast<int>(wheel_delta));
      append_mouse_event("mouse_wheel",
                         wheel_delta >= 0 ? "wheel_right" : "wheel_left",
                         static_cast<int>(wheel_delta), 0, 0, 0);
    }
  }

  return DefWindowProc(hwnd, msg, wp, lp);
}
