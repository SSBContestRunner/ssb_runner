#include "startup_trace.h"

#include <cstdlib>
#include <iomanip>
#include <sstream>
#include <thread>
#include <utility>

namespace {

// The process that owns the trace stays alive until wWinMain returns, so a raw
// pointer is safe for the whole app lifetime. The global owner keeps the object
// alive even if wWinMain unwinds early.
std::atomic<StartupTrace*> g_trace{nullptr};
std::shared_ptr<StartupTrace> g_trace_owner;
std::mutex g_trace_owner_mutex;

constexpr int64_t kFileTimeToUnixEpochMs = 11644473600000LL;
constexpr int64_t kWatchdogIntervalUs = 250 * 1000;
constexpr int64_t kStallThresholdUs = 10 * 1000 * 1000;
constexpr int64_t kObservationWindowUs = 60 * 1000 * 1000;

const char* PhaseName(StartupPhase phase) {
  switch (phase) {
    case StartupPhase::kEntry:
      return "entry";
    case StartupPhase::kWindowCreated:
      return "window_created";
    case StartupPhase::kControllerCreated:
      return "controller_created";
    case StartupPhase::kPluginsRegistered:
      return "plugins_registered";
    case StartupPhase::kFirstFrame:
      return "first_frame";
    case StartupPhase::kShown:
      return "shown";
  }
  return "entry";
}

const char* DartPhaseName(bool has_beat, int phase) {
  if (!has_beat) {
    return "none";
  }
  switch (phase) {
    case 0:
      return "preFrame";
    case 1:
      return "booting";
    case 2:
      return "firstFrame";
    case 3:
      return "ready";
    default:
      return "unknown";
  }
}

int ReadTimeoutMs() {
  constexpr DWORD kBufferLength = 32;
  wchar_t buffer[kBufferLength];
  DWORD length = ::GetEnvironmentVariableW(L"SSB_RUNNER_BOOT_TIMEOUT_MS", buffer,
                                           kBufferLength);
  if (length == 0) {
    return 10000;
  }
  int value = _wtoi(buffer);
  return value > 0 ? value : 10000;
}

}  // namespace

StartupTrace::StartupTrace(std::wstring directory, std::wstring path)
    : directory_(std::move(directory)), path_(std::move(path)) {
  timeout_ms_ = ReadTimeoutMs();
  ::QueryPerformanceFrequency(&qpc_frequency_);
  ::QueryPerformanceCounter(&qpc_entry_);

  FILETIME file_time;
  ::GetSystemTimePreciseAsFileTime(&file_time);
  ULARGE_INTEGER value;
  value.LowPart = file_time.dwLowDateTime;
  value.HighPart = file_time.dwHighDateTime;
  entry_utc_ms_ =
      static_cast<int64_t>(value.QuadPart / 10000ULL) - kFileTimeToUnixEpochMs;
}

std::shared_ptr<StartupTrace> StartupTrace::Create() {
  constexpr DWORD kTempLength = MAX_PATH;
  wchar_t temp_path[kTempLength];
  DWORD length = ::GetTempPathW(kTempLength, temp_path);

  std::wstring directory = L"ssb_runner_boot";
  if (length > 0 && length < kTempLength) {
    directory = temp_path;
    while (!directory.empty() &&
           (directory.back() == L'\\' || directory.back() == L'/')) {
      directory.pop_back();
    }
    directory += L"\\ssb_runner_boot";
  }
  ::CreateDirectoryW(directory.c_str(), nullptr);

  std::wstring path = directory + L"\\boot_" +
                      std::to_wstring(::GetCurrentProcessId()) + L".log";

  auto trace = std::shared_ptr<StartupTrace>(
      new StartupTrace(std::move(directory), std::move(path)));
  trace->WriteSnapshot("entry");

  {
    std::lock_guard<std::mutex> lock(g_trace_owner_mutex);
    g_trace_owner = trace;
    g_trace.store(trace.get(), std::memory_order_release);
  }

  std::thread watchdog([trace]() { trace->WatchdogMain(); });
  watchdog.detach();

  return trace;
}

int64_t StartupTrace::ElapsedUs() const {
  if (qpc_frequency_.QuadPart == 0) {
    return 0;
  }

  LARGE_INTEGER now;
  ::QueryPerformanceCounter(&now);
  return static_cast<int64_t>((now.QuadPart - qpc_entry_.QuadPart) * 1000000LL /
                              qpc_frequency_.QuadPart);
}

void StartupTrace::Mark(StartupPhase phase) {
  const int64_t elapsed = ElapsedUs();
  last_phase_.store(static_cast<int>(phase), std::memory_order_release);

  switch (phase) {
    case StartupPhase::kEntry:
      break;
    case StartupPhase::kWindowCreated:
      window_us_.store(elapsed, std::memory_order_release);
      break;
    case StartupPhase::kControllerCreated:
      controller_us_.store(elapsed, std::memory_order_release);
      break;
    case StartupPhase::kPluginsRegistered:
      plugins_us_.store(elapsed, std::memory_order_release);
      break;
    case StartupPhase::kFirstFrame:
      first_frame_us_.store(elapsed, std::memory_order_release);
      break;
    case StartupPhase::kShown:
      shown_us_.store(elapsed, std::memory_order_release);
      shown_.store(true, std::memory_order_release);
      break;
  }
}

void StartupTrace::Beat(int phase, int step) {
  last_beat_us_.store(ElapsedUs(), std::memory_order_release);
  dart_phase_.store(phase, std::memory_order_release);
  dart_step_.store(step, std::memory_order_release);
  has_beat_.store(true, std::memory_order_release);
  // A new heartbeat re-arms the stall detector.
  stall_reported_.store(false, std::memory_order_release);
  if (phase >= 3) {
    dart_ready_.store(true, std::memory_order_release);
  }
}

std::string StartupTrace::BuildLine(const char* state) const {
  const bool has_beat = has_beat_.load(std::memory_order_acquire);
  const StartupPhase phase =
      static_cast<StartupPhase>(last_phase_.load(std::memory_order_acquire));
  const std::string state_text = state;

  int64_t elapsed = ElapsedUs();
  if (state_text == "shown") {
    const int64_t shown = shown_us_.load(std::memory_order_acquire);
    if (shown >= 0) {
      elapsed = shown;
    }
  }

  std::ostringstream line;
  line << "trace=1 state=" << state
       << " pid=" << ::GetCurrentProcessId()
       << " entry_utc_ms=" << entry_utc_ms_
       << " elapsed_us=" << elapsed
       << " phase=" << PhaseName(phase);

  const auto append_us = [&line](const char* key, int64_t value) {
    if (value >= 0) {
      line << ' ' << key << "_us=" << value;
    }
  };
  append_us("window", window_us_.load(std::memory_order_acquire));
  append_us("controller", controller_us_.load(std::memory_order_acquire));
  append_us("plugins", plugins_us_.load(std::memory_order_acquire));
  append_us("first_frame", first_frame_us_.load(std::memory_order_acquire));

  if (state_text == "timeout" || state_text == "dart_stalled") {
    const int64_t last_beat = last_beat_us_.load(std::memory_order_acquire);
    line << " dart_phase="
         << DartPhaseName(has_beat, dart_phase_.load(std::memory_order_acquire))
         << " dart_step=" << std::setfill('0') << std::setw(2)
         << dart_step_.load(std::memory_order_acquire) << std::setfill(' ');
    if (has_beat) {
      line << " dart_gap_ms=" << ((ElapsedUs() - last_beat) / 1000);
    }
  }

  line << '\n';
  return line.str();
}

void StartupTrace::AppendLine(const std::string& line) {
  HANDLE handle = ::CreateFileW(
      path_.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
      nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (handle == INVALID_HANDLE_VALUE) {
    return;
  }

  DWORD written = 0;
  ::WriteFile(handle, line.data(), static_cast<DWORD>(line.size()), &written,
              nullptr);
  ::CloseHandle(handle);
}

void StartupTrace::WriteSnapshot(const char* state) {
  const std::string line = BuildLine(state);
  std::lock_guard<std::mutex> lock(write_mutex_);
  AppendLine(line);
}

void StartupTrace::WatchdogMain() {
  const int64_t timeout_us = static_cast<int64_t>(timeout_ms_) * 1000;
  bool timeout_written = false;
  int64_t exit_after_us = -1;

  for (;;) {
    ::Sleep(static_cast<DWORD>(kWatchdogIntervalUs / 1000));
    const int64_t now = ElapsedUs();

    if (dart_ready_.load(std::memory_order_acquire)) {
      return;
    }

    if (!shown_.load(std::memory_order_acquire)) {
      if (!timeout_written && now >= timeout_us) {
        WriteSnapshot("timeout");
        timeout_written = true;
        exit_after_us = now + kObservationWindowUs;
      }
    } else if (exit_after_us < 0) {
      // The window is visible but Dart has not reported `ready` yet.
      exit_after_us = now + kObservationWindowUs;
    }

    if (!dart_ready_.load(std::memory_order_acquire) &&
        has_beat_.load(std::memory_order_acquire) &&
        !stall_reported_.load(std::memory_order_acquire) &&
        stall_count_.load(std::memory_order_acquire) < 3) {
      const int64_t last_beat = last_beat_us_.load(std::memory_order_acquire);
      if (now - last_beat >= kStallThresholdUs) {
        WriteSnapshot("dart_stalled");
        stall_reported_.store(true, std::memory_order_release);
        stall_count_.fetch_add(1, std::memory_order_release);
      }
    }

    if (exit_after_us > 0 && now >= exit_after_us) {
      return;
    }
  }
}

extern "C" __declspec(dllexport) void ssb_boot_beat(int phase, int step) {
  StartupTrace* trace = g_trace.load(std::memory_order_acquire);
  if (trace != nullptr) {
    trace->Beat(phase, step);
  }
}
