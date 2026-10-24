import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Window title created by the Windows runner (windows/runner/main.cpp).
const _windowTitle = 'TWOK Sample Deli - Office';

/// Brings this app's window to the front of the desktop, restoring it from
/// the taskbar when minimized.
///
/// Windows can refuse [SetForegroundWindow] to a process that is not already
/// foreground, which used to leave the window restored but behind everything
/// else. The z-order is therefore forced with [SetWindowPos]: raising the
/// window to topmost puts it above every other window, and dropping the flag
/// again leaves it there as a normal window.
///
/// Nothing throws — the caller always continues with what it was doing.
void bringAppWindowToFront() {
  if (!Platform.isWindows) return;
  try {
    final hwnd = using(
      (arena) => FindWindow(null, arena.pcwstr(_windowTitle)).value,
    );
    if (hwnd.isNull) return;
    ShowWindow(hwnd, SW_RESTORE); // activates, un-minimizes
    final moveSize = SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW;
    SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, moveSize);
    SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0, moveSize);
    SetForegroundWindow(hwnd); // focus, on top of the forced z-order
  } catch (_) {
    // Focus is a nicety; the invoice flow opens even without it.
  }
}
