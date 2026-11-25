import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/platform/audio/web/web_audio_monitor.dart';
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
bool _initializing = false;

/// Deferred initialisation progress, consumed by the web audio monitor.
///
/// Stays [AudioInitState.notAttempted] until the first user gesture, so the
/// badge never claims a fault on a page that simply has not been clicked yet.
final ValueNotifier<AudioInitState> audioInitState =
    ValueNotifier<AudioInitState>(AudioInitState.notAttempted);

/// Initialises SoLoud once. Must be called from a user gesture.
Future<bool> ensureAudioInitialized() => _pending ??= _init();

Future<bool> _init() async {
  if (SoLoud.instance.isInitialized) {
    _setInitState(AudioInitState.ready);
    return true;
  }

  _initializing = true;
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
    _setInitState(AudioInitState.ready);
    return true;
  } catch (error, stackTrace) {
    log.error(
      'SoLoud init failed, audio disabled',
      tag: 'audio.soloud',
      error: error,
      stackTrace: stackTrace,
    );
    _setInitState(AudioInitState.failed);
    return false;
  } finally {
    _initializing = false;
  }
}

/// Re-runs the deferred initialisation after a user gesture (design §5.4).
///
/// A failed result used to be cached by [_pending] forever; the retry clears
/// that cache so the "enable sound" action can actually try again.
Future<bool> retryAudioInitialized() {
  if (SoLoud.instance.isInitialized) {
    _setInitState(AudioInitState.ready);
    return Future<bool>.value(true);
  }
  // Joining an in-flight attempt avoids starting a second engine.
  if (_initializing) {
    return _pending ?? Future<bool>.value(false);
  }
  _pending = null;
  _setInitState(AudioInitState.notAttempted);
  return ensureAudioInitialized();
}

void _setInitState(AudioInitState state) {
  if (audioInitState.value == state) return;
  audioInitState.value = state;
}

Future<void> deinitializeAudioForExit() async {
  if (SoLoud.instance.isInitialized) {
    await SoLoud.instance.deinitAsync();
  }
  _pending = null;
  _setInitState(AudioInitState.notAttempted);
}
