import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:ssb_runner/platform/audio/web/web_audio_monitor.dart';
import 'package:web/web.dart' as web;

/// Browser-side implementation of the signals consumed by [WebAudioMonitor].
///
/// This is the only web audio file that touches `package:web`, so the decision
/// logic stays VM-testable (design §5.3).
bool webAudioEngineInitialized() => SoLoud.instance.isInitialized;

/// Reads the engine's device state, mapping it onto the monitor's own enum.
WebAudioDeviceState webAudioDeviceState() {
  try {
    switch (SoLoud.instance.getAudioDeviceState()) {
      case AudioDeviceState.uninitialized:
        return WebAudioDeviceState.uninitialized;
      case AudioDeviceState.stopped:
        return WebAudioDeviceState.stopped;
      case AudioDeviceState.started:
        return WebAudioDeviceState.started;
      case AudioDeviceState.starting:
        return WebAudioDeviceState.starting;
      case AudioDeviceState.stopping:
        return WebAudioDeviceState.stopping;
    }
  } catch (_) {
    return WebAudioDeviceState.unknown;
  }
}

/// Reads the Web Audio context state through flutter_soloud's miniaudio
/// instance, or `null` when the internal path is unavailable.
///
/// `window.miniaudio.devices[0].webaudio.state` is not a public API, so every
/// missing field or exception is treated as "cannot tell" (design §9 R1).
String? webAudioContextState() {
  try {
    final miniaudio = (web.window as JSObject).getProperty<JSObject?>(
      'miniaudio'.toJS,
    );
    if (miniaudio == null) return null;

    final devices = miniaudio.getProperty<JSArray<JSObject?>>('devices'.toJS);
    if (devices.length == 0) return null;

    final device = devices.toDart.first;
    if (device == null) return null;

    final webaudio = device.getProperty<JSObject?>('webaudio'.toJS);
    return webaudio?.getProperty<JSString?>('state'.toJS)?.toDart;
  } catch (_) {
    return null;
  }
}

/// Whether the page is currently visible.
bool webAudioPageVisible() => web.document.visibilityState == 'visible';

/// Emits on every `visibilitychange`.
Stream<bool> webAudioVisibilityChanges() {
  return web.CustomEventProviders.visibilityChangeEvent
      .forTarget(web.document)
      .map((_) => webAudioPageVisible());
}
