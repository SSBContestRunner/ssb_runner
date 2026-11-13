#include "exit_watchdog.h"

#include <windows.h>

#include <atomic>
#include <cstdlib>

#include "startup_trace.h"

namespace {

// Matches the Dart-side fallback: whatever the exit path does, the process is
// gone five seconds after the close request.
constexpr DWORD kExitWatchdogTimeoutMs = 5000;

// Guards against arming twice: the engine re-posts WM_CLOSE after Dart answers
// the exit request, and a second thread would change nothing but cost.
std::atomic<bool> g_armed{false};

// Never signalled during a normal run: the wait below is the whole point. It is
// an event rather than Sleep so the thread goes to sleep immediately.
HANDLE g_event = nullptr;

DWORD WINAPI WatchdogMain(LPVOID) {
  if (::WaitForSingleObject(g_event, kExitWatchdogTimeoutMs) == WAIT_OBJECT_0) {
    return 0;
  }

  // Reaching here means the process outlived its exit budget. Only a
  // termination skips the DLL detach that may be waiting; see the header.
  ssb_trace_mark("watchdog_fired");
  ::TerminateProcess(::GetCurrentProcess(), EXIT_SUCCESS);
  return 0;
}

}  // namespace

void ArmExitWatchdog() {
  if (g_armed.exchange(true, std::memory_order_acq_rel)) {
    return;
  }

  ssb_trace_mark("watchdog_armed");

  g_event = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
  if (g_event == nullptr) {
    return;
  }

  // Detached on purpose: the thread either fires or dies with the process. The
  // handle is closed so the process does not hold an unused kernel object.
  HANDLE thread = ::CreateThread(nullptr, 0, WatchdogMain, nullptr, 0, nullptr);
  if (thread != nullptr) {
    ::CloseHandle(thread);
  }
}
