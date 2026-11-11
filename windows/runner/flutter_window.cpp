#include "flutter_window.h"

#include <cstdlib>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             std::shared_ptr<StartupTrace> startup_trace)
    : project_(project), startup_trace_(std::move(startup_trace)) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  // The HWND exists at this point; the controller below is the next phase.
  // Marking here (rather than after Create returns) keeps the phase order
  // monotonic, because Create returns only after OnCreate finished.
  if (startup_trace_) {
    startup_trace_->Mark(StartupPhase::kWindowCreated);
  }

  // Test hook: widens the controller-creation window so the native timeout
  // record can be exercised on a healthy machine.
  constexpr DWORD kDelayLength = 32;
  wchar_t delay_buffer[kDelayLength];
  if (::GetEnvironmentVariableW(L"SSB_RUNNER_BOOT_DELAY_MS", delay_buffer,
                                kDelayLength) > 0) {
    const int delay_ms = _wtoi(delay_buffer);
    if (delay_ms > 0) {
      ::Sleep(static_cast<DWORD>(delay_ms));
    }
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (startup_trace_) {
    startup_trace_->Mark(StartupPhase::kControllerCreated);
  }
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  if (startup_trace_) {
    startup_trace_->Mark(StartupPhase::kPluginsRegistered);
  }
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    if (startup_trace_) {
      startup_trace_->Mark(StartupPhase::kFirstFrame);
    }
    this->Show();
    if (startup_trace_) {
      startup_trace_->Mark(StartupPhase::kShown);
      startup_trace_->WriteSnapshot("shown");
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
