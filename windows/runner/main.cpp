#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "startup_trace.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Starts the native startup timeline before anything that can block.
  auto startup_trace = StartupTrace::Create();

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // Lets the Dart side read the native timeline and publish heartbeats.
  command_line_arguments.push_back(
      "--boot-trace-dir=" +
      Utf8FromUtf16(startup_trace->directory().c_str()));

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, startup_trace);
  Win32Window::Point origin(10, 10);
  // Content size; Win32Window::Create adds the non-client area for the DPI.
  Win32Window::Size size(1108, 772);
  if (!window.Create(L"SSB Runner", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // Reaching this line means WM_QUIT was posted and the loop unwound; a hang
  // before it leaves the last record as `destroy_begin`.
  startup_trace->WriteSnapshot("loop_exit");

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
