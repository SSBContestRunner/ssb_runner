#ifndef RUNNER_EXIT_WATCHDOG_H_
#define RUNNER_EXIT_WATCHDOG_H_

// Starts the exit watchdog the first time it is called.
//
// Called from the window procedure when `WM_CLOSE` arrives. A detached thread
// waits a fixed budget; if the process is still alive when it expires, the
// process is terminated with `TerminateProcess`, which skips `ExitProcess` and
// the DLL detach that can wait forever after the audio plugin was left half
// initialised (docs/design/desktop_exit_design.md §2.3).
//
// The thread is created here rather than at process start, so the startup path
// gains no thread; a normal exit ends the process long before the budget runs
// out and the watchdog simply disappears with it.
void ArmExitWatchdog();

#endif  // RUNNER_EXIT_WATCHDOG_H_
