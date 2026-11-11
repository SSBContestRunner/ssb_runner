import 'dart:async';
import 'dart:io';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:ssb_runner/logging/app_logger.dart';

/// Desktop starts the engine during boot so the first segment never waits.
bool get initializesAudioAtStartup => true;

/// Environment variable that skips audio initialisation when set to `1`.
///
/// SoLoud starts its engine on a worker isolate, and on hosts whose CoreAudio
/// stack is unusable (the headless macOS VMs used by CI, for example) that call
/// dies inside Apple's `AVAudioSession` with a SIGSEGV. A native crash cannot
/// be intercepted by the catch below and takes the whole process down, so
/// callers that only need the rest of the app to run--notably the macOS smoke
/// test--use this to opt out.
const String _disableAudioEnv = 'SSB_RUNNER_DISABLE_AUDIO';

Future<bool>? _pending;

/// Initialises SoLoud once. Returns whether the engine is usable.
Future<bool> ensureAudioInitialized() => _pending ??= _init();

Future<bool> _init() async {
  if (SoLoud.instance.isInitialized) {
    return true;
  }

  if (Platform.environment[_disableAudioEnv] == '1') {
    log.warn(
      'SoLoud init skipped by environment',
      tag: 'audio.soloud',
      fields: <String, Object?>{'env': _disableAudioEnv},
    );
    return false;
  }

  try {
    await SoLoud.instance.init(channels: Channels.mono);
    log.info(
      'SoLoud initialized',
      tag: 'audio.soloud',
      fields: const <String, Object?>{'backend': 'native'},
    );
    return true;
  } catch (error, stackTrace) {
    // Audio failure must not stop the rest of the app from starting.
    log.error(
      'SoLoud init failed, audio disabled',
      tag: 'audio.soloud',
      error: error,
      stackTrace: stackTrace,
    );
    return false;
  }
}

/// Releases the audio device off the UI isolate.
///
/// Unconditional: `SoLoud.isInitialized` is false for the whole initialisation,
/// so gating on it is what let a half-initialised engine reach `ExitProcess`.
/// On an engine that never initialised, `deinitAsync()` only spawns an isolate
/// and the native `dispose()` returns immediately.
///
/// The synchronous `deinit()` is forbidden here: it runs the native teardown on
/// the UI isolate, and a blocked teardown would freeze the 5 s fallback timer
/// with it.
Future<void> deinitializeAudioForExit() => SoLoud.instance.deinitAsync();
