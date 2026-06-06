// Standalone self-update helper for the Windows bundle, compiled to
// `knitcalc_updater.exe` via `dart compile exe` and shipped inside the bundle
// (see the `mise build-windows` task). The app copies it to a temp dir, spawns
// it detached, and quits; running it from temp (not the install dir it is about
// to overwrite) keeps it from locking its own target.
//
// Both native Windows and Wine/Proton keep the running executable, its DLLs and
// data files locked while the app is alive, so the bundle can only be swapped
// after the app exits — which is exactly what this helper waits for. It works
// identically on real Windows and under Wine (the Win32 calls below are ones
// Wine implements), replacing the earlier PowerShell approach.
//
// Usage: knitcalc_updater.exe <parentPid> <archivePath> <installDir> <exePath>
import 'dart:ffi';
import 'dart:io';

import 'package:knitcalc_updater/bundle_apply.dart';

void main(List<String> args) {
  if (args.length < 4) {
    return;
  }

  final parentPid = int.tryParse(args[0]) ?? 0;
  final archivePath = args[1];
  final installDir = args[2];
  final executablePath = args[3];

  _waitForProcessExit(parentPid);
  _applyWithRetry(archivePath, installDir);

  try {
    File(archivePath).deleteSync();
  } on Object {
    // Best-effort cleanup of the downloaded archive; ignore failures.
  }

  Process.start(executablePath, const [], mode: ProcessStartMode.detached);
}

/// Extracts the bundle, retrying briefly: even once the parent is signalled as
/// exited, Windows/Wine may take a moment to release its file handles.
void _applyWithRetry(String archivePath, String installDir) {
  Object? lastError;

  for (var attempt = 0; attempt < 50; attempt++) {
    try {
      applyZipOverDirectory(archivePath, installDir);
      return;
    } on Object catch (error) {
      lastError = error;
      sleep(const Duration(milliseconds: 200));
    }
  }

  throw StateError('knitcalc_updater: apply failed after retries: $lastError');
}

typedef _OpenProcessNative = IntPtr Function(Uint32, Int32, Uint32);
typedef _OpenProcessDart = int Function(int, int, int);
typedef _WaitNative = Uint32 Function(IntPtr, Uint32);
typedef _WaitDart = int Function(int, int);
typedef _CloseHandleNative = Int32 Function(IntPtr);
typedef _CloseHandleDart = int Function(int);

/// Blocks until the process [pid] has fully exited (and thus released its file
/// locks), via Win32 `OpenProcess`/`WaitForSingleObject` — both implemented by
/// Wine. Returns immediately if the process is already gone or the calls are
/// unavailable; the apply-retry loop then covers any residual lock.
void _waitForProcessExit(int pid) {
  if (pid <= 0) {
    return;
  }

  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final openProcess = kernel32
        .lookupFunction<_OpenProcessNative, _OpenProcessDart>('OpenProcess');
    final waitForSingleObject = kernel32.lookupFunction<_WaitNative, _WaitDart>(
      'WaitForSingleObject',
    );
    final closeHandle = kernel32
        .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');

    const synchronize = 0x00100000;
    const infinite = 0xFFFFFFFF;

    final handle = openProcess(synchronize, 0, pid);
    if (handle == 0) {
      return;
    }

    waitForSingleObject(handle, infinite);
    closeHandle(handle);
  } on Object {
    // Not on Windows, or the API is unavailable: fall through and let the
    // apply-retry loop wait out any remaining lock.
  }
}
