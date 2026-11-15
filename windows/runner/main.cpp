#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "flutter_window.h"
#include "startup_trace.h"
#include "utils.h"

namespace {

// `window_manager` 0.6.0 reaches Windows through nativeapi/cnativeapi, whose DLL
// statically imports user32!GetDpiForWindow. That API only exists from Windows
// 10 version 1607 (build 14393); on 1507/1511 LoadLibrary fails with
// ERROR_PROC_NOT_FOUND (127) and every Dart call into it throws, which the app
// used to surface as a startup crash report. The portable zip has no installer
// to gate it, and by that point Dart cannot show or close a window on its own,
// so the check has to live here, before the engine starts.
constexpr wchar_t kNativeApiDll[] = L"cnativeapi.dll";
constexpr char kDpiApi[] = "GetDpiForWindow";

bool HasGetDpiForWindow() {
  HMODULE user32 = ::GetModuleHandleW(L"user32.dll");
  if (user32 == nullptr) {
    return false;
  }
  return ::GetProcAddress(user32, kDpiApi) != nullptr;
}

// Loads the real DLL once so a missing file or a broken dependency is caught
// here instead of inside the Dart isolate. The module is intentionally left
// loaded: the Dart side opens the same file and Windows then reuses this
// mapping instead of loading it a second time.
bool CanLoadNativeApi() {
  return ::LoadLibraryW(kNativeApiDll) != nullptr;
}

void ShowUnsupportedSystemMessage(bool dpi_api_missing, DWORD last_error) {
  std::wstring message;
  if (dpi_api_missing) {
    message =
        L"SSB Runner 需要 Windows 10 版本 1607（Build 14393）或更高版本。\n"
        L"当前系统版本过低，程序无法启动，请升级 Windows 后重试。\n"
        L"\n"
        L"SSB Runner requires Windows 10 version 1607 (build 14393) or newer.\n"
        L"This version of Windows is not supported. Please update Windows and "
        L"run the app again.";
  } else {
    message =
        L"SSB Runner 无法加载原生组件 cnativeapi.dll"
        L"（错误码 " +
        std::to_wstring(last_error) +
        L"）。\n"
        L"程序需要 Windows 10 版本 1607（Build 14393）或更高版本；"
        L"若系统已满足要求，请重新下载或重新安装。\n"
        L"\n"
        L"SSB Runner could not load the native component cnativeapi.dll "
        L"(error " +
        std::to_wstring(last_error) +
        L").\n"
        L"Windows 10 version 1607 (build 14393) or newer is required. If your "
        L"system already meets that, download or install the app again.";
  }
  ::MessageBoxW(nullptr, message.c_str(), L"SSB Runner",
                MB_OK | MB_ICONERROR | MB_SETFOREGROUND | MB_TOPMOST);
}

// Returns true when the app may start.
bool CheckNativeApiSupport() {
  if (!HasGetDpiForWindow()) {
    ShowUnsupportedSystemMessage(/*dpi_api_missing=*/true, 0);
    return false;
  }
  ::SetLastError(ERROR_SUCCESS);
  if (!CanLoadNativeApi()) {
    ShowUnsupportedSystemMessage(/*dpi_api_missing=*/false, ::GetLastError());
    return false;
  }
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Refuses unsupported systems before any window, log or crash reporter
  // exists, so the user gets one readable message and a clean exit.
  if (!CheckNativeApiSupport()) {
    return EXIT_FAILURE;
  }

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
