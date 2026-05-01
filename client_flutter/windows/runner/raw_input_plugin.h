#ifndef RAW_INPUT_PLUGIN_H_
#define RAW_INPUT_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <atomic>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include <windows.h>

struct InputWindowContext {
  std::string process_name;
  std::string class_name;
  std::string window_title;
};

struct InputEventData {
  uint64_t sequence_id = 0;
  int64_t timestamp_micros = 0;
  std::string kind;
  int event_count = 1;
  int key_code = 0;
  bool has_key_code = false;
  std::string mouse_button;
  int wheel_delta = 0;
  int delta_x = 0;
  int delta_y = 0;
  int move_distance = 0;
  std::string token_text;
  std::string process_name;
  std::string class_name;
  std::string window_title;
};

struct BufferedMouseMoveData {
  bool has_pending = false;
  int64_t started_at_micros = 0;
  int64_t last_timestamp_micros = 0;
  int event_count = 0;
  int delta_x = 0;
  int delta_y = 0;
  int move_distance = 0;
  InputWindowContext context;
};

// RawInput telemetry plugin.
// Collects aggregate counters and an ordered input event stream.
class RawInputPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);
  explicit RawInputPlugin(flutter::PluginRegistrarWindows* registrar);
  virtual ~RawInputPlugin();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void StartBackgroundThread();
  void StopBackgroundThread();
  static LRESULT CALLBACK RawInputWndProc(HWND hwnd, UINT msg, WPARAM wp,
                                          LPARAM lp);
  void RecordKeyStroke(const RAWKEYBOARD& keyboard);
  void AppendSequenceToken(const std::string& token);
  std::string ConsumeSequenceBuffer();
  flutter::EncodableMap BuildKeyDistribution() const;
  flutter::EncodableMap BuildMouseClicks() const;
  void AppendInputEvent(InputEventData event);
  flutter::EncodableList ConsumeInputEvents();
  void BufferMouseMove(int delta_x, int delta_y, int move_distance,
                       const InputWindowContext& context,
                       int64_t timestamp_micros);
  void FlushBufferedMouseMove();
  void ClearBufferedMouseMove();
  std::string DescribeKeyStroke(const RAWKEYBOARD& keyboard) const;
  void RefreshCachedForegroundWindowContext();
  InputWindowContext GetCachedForegroundWindowContext() const;
  InputWindowContext CaptureForegroundWindowContext() const;
  void SetLastErrorMessage(const std::string& message);
  std::string GetLastErrorMessage() const;
  static std::string WideToUtf8(const std::wstring& value);

  std::atomic<int64_t> key_count_{0};
  std::atomic<int64_t> mouse_left_click_count_{0};
  std::atomic<int64_t> mouse_right_click_count_{0};
  std::atomic<int64_t> mouse_middle_click_count_{0};
  std::atomic<int64_t> mouse_xbutton1_click_count_{0};
  std::atomic<int64_t> mouse_xbutton2_click_count_{0};
  std::atomic<int64_t> scroll_px_{0};
  std::atomic<int64_t> mouse_move_px_{0};
  std::atomic<uint64_t> key_counts_[256];
  std::atomic<uint64_t> input_event_sequence_{0};

  std::thread bg_thread_;
  std::atomic<bool> running_{false};
  std::atomic<bool> enable_sequence_record_{false};
  HWND bg_hwnd_{nullptr};

  mutable std::mutex sequence_mutex_;
  std::string sequence_buffer_;

  mutable std::mutex input_event_mutex_;
  std::vector<InputEventData> input_events_;

  mutable std::mutex mouse_move_mutex_;
  BufferedMouseMoveData buffered_mouse_move_;

  InputWindowContext cached_window_context_;

  mutable std::mutex last_error_mutex_;
  std::string last_error_;

  static RawInputPlugin* instance_;
};

#endif  // RAW_INPUT_PLUGIN_H_
