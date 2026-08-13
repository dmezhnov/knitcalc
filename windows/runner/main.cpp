#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <stdio.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  bool attached_console = ::AttachConsole(ATTACH_PARENT_PROCESS);
  if (!attached_console && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // `knitcalc --version` must answer without creating a window: package
  // managers (mise's registry test, our release smoke check) run it headless.
  // FLUTTER_VERSION is the full pubspec version ("1.2.3+45"), defined by
  // runner/CMakeLists.txt.
  for (const std::string &argument : command_line_arguments) {
    if (argument == "--version") {
      // With redirected standard handles (a pipe, as any caller capturing the
      // output uses) the CRT already writes where it should; only a console
      // launch with no redirection needs CONOUT$ wiring.
      HANDLE stdout_handle = ::GetStdHandle(STD_OUTPUT_HANDLE);
      if (attached_console &&
          (stdout_handle == nullptr || stdout_handle == INVALID_HANDLE_VALUE)) {
        RedirectOutputToConsole();
      }
      printf("knitcalc %s\n", FLUTTER_VERSION);
      fflush(stdout);
      return EXIT_SUCCESS;
    }
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"knitcalc", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
