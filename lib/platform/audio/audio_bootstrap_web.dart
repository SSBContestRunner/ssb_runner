import 'dart:async';
import 'dart:js_interop';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/platform/web/browser_storage.dart';

/// Audio engine flavor chosen by `init_soloud.js`: `mt` when the page is
/// cross-origin isolated, `st` when it is not.
@JS('self.flutter_soloud_build')
external JSString? get _soloudBuildFlavor;

String _backendLabel() {
  try {
    return _soloudBuildFlavor?.toDart ?? 'unknown';
  } catch (_) {
    return 'unknown';
  }
}

/// Browsers only allow audio to start after a user gesture, so the engine is
/// created on the first click instead of during boot.
bool get initializesAudioAtStartup => false;

Future<bool>? _pending;

/// Initialises SoLoud once. Must be called from a user gesture.
Future<bool> ensureAudioInitialized() => _pending ??= _init();

Future<bool> _init() async {
  if (SoLoud.instance.isInitialized) {
    return true;
  }

  try {
    await SoLoud.instance.init(channels: Channels.mono);
    log.info(
      'SoLoud initialized',
      tag: 'audio.soloud',
      fields: <String, Object?>{
        'backend': _backendLabel(),
        'cross_origin_isolated': isCrossOriginIsolated,
      },
    );
    return true;
  } catch (error, stackTrace) {
    log.error(
      'SoLoud init failed, audio disabled',
      tag: 'audio.soloud',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  }
}

Future<void> deinitializeAudioForExit() async {
  if (SoLoud.instance.isInitialized) {
    await SoLoud.instance.deinitAsync();
  }
}
