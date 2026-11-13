#ifndef RUNNER_STARTUP_TRACE_H_
#define RUNNER_STARTUP_TRACE_H_

#include <windows.h>

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <string>

// Startup phases shared with the Dart diagnostics. The values are only used
// internally; the file format carries the names.
enum class StartupPhase {
  kEntry,
  kWindowCreated,
  kControllerCreated,
  kPluginsRegistered,
  kFirstFrame,
  kShown,
};

// Records the native startup timeline into a small append-only file under
// `%TEMP%`.
//
// Mark() and Beat() only touch atomics, so they never put IO on the startup
// path. A detached watchdog thread owns all file writes and exits once the app
// is ready (or once the observation window is over). It only holds a
// `shared_ptr` to this object so window destruction cannot race it.
class StartupTrace {
 public:
  // Creates the temp directory, writes the `entry` record and starts the
  // watchdog thread.
  static std::shared_ptr<StartupTrace> Create();

  // Directory handed to Dart via `--boot-trace-dir`.
  const std::wstring& directory() const { return directory_; }

  // Marks a completed native startup phase. No IO.
  void Mark(StartupPhase phase);

  // Updates the Dart heartbeat. Called from `ssb_boot_beat`; no IO.
  void Beat(int phase, int step);

  // Appends one record. Used for `entry`, `timeout`, `shown` and
  // `dart_stalled`.
  void WriteSnapshot(const char* state);

 private:
  StartupTrace(std::wstring directory, std::wstring path);

  void WatchdogMain();
  int64_t ElapsedUs() const;
  std::string BuildLine(const char* state) const;
  void AppendLine(const std::string& line);

  std::wstring directory_;
  std::wstring path_;

  LARGE_INTEGER qpc_frequency_{};
  LARGE_INTEGER qpc_entry_{};
  int64_t entry_utc_ms_ = 0;
  int timeout_ms_ = 10000;

  std::atomic<int64_t> window_us_{-1};
  std::atomic<int64_t> controller_us_{-1};
  std::atomic<int64_t> plugins_us_{-1};
  std::atomic<int64_t> first_frame_us_{-1};
  std::atomic<int64_t> shown_us_{-1};
  std::atomic<int> last_phase_{static_cast<int>(StartupPhase::kEntry)};
  std::atomic<bool> shown_{false};

  std::atomic<bool> has_beat_{false};
  std::atomic<int> dart_phase_{0};
  std::atomic<int> dart_step_{0};
  std::atomic<int64_t> last_beat_us_{0};
  std::atomic<bool> dart_ready_{false};
  std::atomic<bool> stall_reported_{false};
  std::atomic<int> stall_count_{0};

  std::mutex write_mutex_;
};

// Exported for Dart FFI. A no-op until Create() ran.
extern "C" __declspec(dllexport) void ssb_boot_beat(int phase, int step);

// Appends one named record from any thread.
//
// Used to bracket the close path (`wm_close`, `destroy_begin`, `destroy_end`,
// `watchdog_armed`, `watchdog_fired`), so a window that disappears without the
// process ending can be told apart from a window that is still open. No-op
// until Create() ran.
extern "C" __declspec(dllexport) void ssb_trace_mark(const char* state);

#endif  // RUNNER_STARTUP_TRACE_H_
