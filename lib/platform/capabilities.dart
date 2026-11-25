import 'package:flutter/foundation.dart';

/// Platform capability matrix.
///
/// Business code must not branch on [kIsWeb]; it either queries these flags or
/// depends on the dedicated port under `lib/platform/`. [kIsWeb] itself is only
/// allowed inside port implementations and user-facing copy.
abstract final class PlatformCapabilities {
  static bool get isWeb => kIsWeb;

  /// Desktop window controls (size, opacity, focus) only exist natively.
  static bool get hasNativeWindow => !isWeb;

  /// Browsers own the F1–F12 and Space/Tab defaults, so a run needs a key
  /// guard; native apps receive the shortcuts directly.
  static bool get supportsImmersiveInput => isWeb;

  /// A save dialog that returns a filesystem path only exists natively.
  static bool get supportsSaveDialog => !isWeb;

  /// `navigator.storage.persist()` is a browser API.
  static bool get supportsStoragePersistence => isWeb;

  /// System output volume, mute and device can be read from desktop APIs only;
  /// a browser exposes none of them.
  static bool get supportsAudioOutputMonitoring => !isWeb;

  /// A browser cannot keep a session running while the page is hidden, so the
  /// run is paused instead of pretending it continued.
  static bool get pausesWhenHidden => isWeb;
}
