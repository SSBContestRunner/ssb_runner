import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:ssb_runner/audio/audio_alert_state.dart';
import 'package:ssb_runner/logging/app_logger.dart';

/// Reads the system output state once.
///
/// Implementations must never throw: a platform that cannot answer returns an
/// [AudioOutputStatus] with `null` fields, which the adjudicator treats as
/// `unknown` (design §4.2.2).
abstract interface class AudioOutputProbe {
  /// Whether [events] can deliver change notifications.
  bool get supportsEvents;

  /// Wake-up notifications. The value is irrelevant; the monitor always
  /// re-reads through [read] so both paths share one code path.
  Stream<void> get events;

  Future<AudioOutputStatus> read();

  Future<void> dispose();
}

/// No platform probe available: everything is `unknown`, so no badge.
class UnsupportedAudioOutputProbe implements AudioOutputProbe {
  const UnsupportedAudioOutputProbe();

  @override
  bool get supportsEvents => false;

  @override
  Stream<void> get events => const Stream<void>.empty();

  @override
  Future<AudioOutputStatus> read() async => AudioOutputStatus.unknown;

  @override
  Future<void> dispose() async {}
}

/// macOS / Windows: `MethodChannel` + `EventChannel` implemented by the runner.
///
/// Any platform failure (missing plugin, exception, malformed map) degrades to
/// `unknown` instead of an alert.
class PlatformChannelAudioOutputProbe implements AudioOutputProbe {
  static const MethodChannel _method = MethodChannel(
    'ssb_runner/audio_output',
  );
  static const EventChannel _event = EventChannel(
    'ssb_runner/audio_output/events',
  );

  Stream<void>? _events;

  @override
  bool get supportsEvents => true;

  @override
  Stream<void> get events => _events ??= _event.receiveBroadcastStream().map(
    (_) {},
  );

  @override
  Future<AudioOutputStatus> read() async {
    try {
      final raw = await _method.invokeMapMethod<String, Object?>('read');
      return statusFromPlatformMap(raw);
    } on MissingPluginException {
      return AudioOutputStatus.unknown;
    } on PlatformException {
      return const AudioOutputStatus(source: AudioProbeSource.error);
    }
  }

  @override
  Future<void> dispose() async {}
}

/// Maps the native `read` reply onto [AudioOutputStatus].
///
/// Exposed for tests; every absent or mistyped field stays `null`.
AudioOutputStatus statusFromPlatformMap(Map<String, Object?>? raw) {
  if (raw == null) return AudioOutputStatus.unknown;

  final volume = raw['volume'];
  final muted = raw['muted'];
  final hasDevice = raw['hasDevice'];
  final deviceName = raw['deviceName'];

  return AudioOutputStatus(
    hasDevice: hasDevice is bool ? hasDevice : null,
    deviceName: deviceName is String ? deviceName : null,
    volume: volume is num ? volume.toDouble().clamp(0.0, 1.0).toDouble() : null,
    muted: muted is bool ? muted : null,
    source: Platform.isMacOS
        ? AudioProbeSource.coreAudio
        : AudioProbeSource.wasapi,
  );
}

/// Linux: `pactl`, with `wpctl` as the PipeWire fallback.
///
/// No native code. A missing audio stack (the Debian smoke container) answers
/// `unknown` quietly (design §4.2.2).
class LinuxAudioOutputProbe implements AudioOutputProbe {
  StreamController<void>? _controller;
  Process? _subscribe;
  Timer? _restartTimer;

  @override
  bool get supportsEvents => true;

  @override
  Stream<void> get events {
    final existing = _controller;
    if (existing != null) return existing.stream;

    final controller = StreamController<void>.broadcast(
      onListen: _startSubscribe,
      onCancel: _stopSubscribe,
    );
    _controller = controller;
    return controller.stream;
  }

  @override
  Future<AudioOutputStatus> read() async {
    final pactl = await _readPactl();
    if (pactl != null) return pactl;

    final wpctl = await _readWpctl();
    if (wpctl != null) return wpctl;

    return const AudioOutputStatus(source: AudioProbeSource.unsupported);
  }

  @override
  Future<void> dispose() async {
    _restartTimer?.cancel();
    _restartTimer = null;
    final controller = _controller;
    _controller = null;
    await _stopSubscribe();
    await controller?.close();
  }

  Future<AudioOutputStatus?> _readPactl() async {
    try {
      final volume = await Process.run('pactl', [
        'get-sink-volume',
        '@DEFAULT_SINK@',
      ]);
      if (volume.exitCode != 0) return null;

      final mute = await Process.run('pactl', [
        'get-sink-mute',
        '@DEFAULT_SINK@',
      ]);
      if (mute.exitCode != 0) return null;

      final name = await _runQuietly('pactl', [
        'get-default-sink',
      ]).then((it) => it?.trim());

      return AudioOutputStatus(
        hasDevice: true,
        deviceName: name == null || name.isEmpty ? null : name,
        volume: parsePactlVolume('${volume.stdout}'),
        muted: parsePactlMute('${mute.stdout}'),
        source: AudioProbeSource.pactl,
      );
    } on ProcessException {
      return null;
    }
  }

  Future<AudioOutputStatus?> _readWpctl() async {
    try {
      final output = await _runQuietly('wpctl', [
        'get-volume',
        '@DEFAULT_AUDIO_SINK@',
      ]);
      if (output == null) return null;
      return parseWpctlVolume(output);
    } on ProcessException {
      return null;
    }
  }

  Future<String?> _runQuietly(String command, List<String> arguments) async {
    try {
      final result = await Process.run(command, arguments);
      if (result.exitCode != 0) return null;
      return '${result.stdout}';
    } on ProcessException {
      return null;
    }
  }

  Future<void> _startSubscribe() async {
    if (_subscribe != null) return;

    final Process process;
    try {
      process = await Process.start('pactl', ['subscribe']);
    } on ProcessException {
      // No event source: the monitor polls, which is always running anyway.
      return;
    }

    _subscribe = process;
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (!isPactlSinkEvent(line)) return;
          final controller = _controller;
          if (controller != null && !controller.isClosed) controller.add(null);
        });
    // The stream must be drained or the process blocks on a full pipe.
    process.stderr.drain<void>().catchError((_) {});

    unawaited(
      process.exitCode.then((_) {
        if (!identical(_subscribe, process)) return;
        _subscribe = null;
        _restartTimer?.cancel();
        _restartTimer = Timer(
          const Duration(seconds: 5),
          () => unawaited(_startSubscribe()),
        );
      }),
    );
  }

  Future<void> _stopSubscribe() async {
    _restartTimer?.cancel();
    _restartTimer = null;
    final process = _subscribe;
    _subscribe = null;
    if (process == null) return;
    process.kill();
    await process.exitCode.catchError((_) => -1);
  }
}

/// Whether one `pactl subscribe` line reports a sink change.
///
/// `sink-input` (per-application streams) and `source` (capture) events are
/// ignored: the monitor reads `@DEFAULT_SINK@`, so waking it for those would
/// only cost a subprocess.
bool isPactlSinkEvent(String line) => line.contains('on sink #');

/// Parses `pactl get-sink-volume` output into a 0.0–1.0 volume.
///
/// Takes the first `NN%` in the text; `null` when the text carries none.
double? parsePactlVolume(String output) {
  final match = RegExp(r'(\d{1,3})\s*%').firstMatch(output);
  if (match == null) return null;
  final percent = int.tryParse(match.group(1)!);
  if (percent == null) return null;
  return (percent.clamp(0, 100)) / 100;
}

/// Parses `pactl get-sink-mute` (`Mute: yes` / `Mute: no`).
bool? parsePactlMute(String output) {
  final match = RegExp(r'Mute:\s*(yes|no)', caseSensitive: false).firstMatch(
    output,
  );
  if (match == null) return null;
  return match.group(1)!.toLowerCase() == 'yes';
}

/// Parses `wpctl get-volume` (`Volume: 0.65`, optionally `[MUTED]`).
AudioOutputStatus parseWpctlVolume(String output) {
  final volumeMatch = RegExp(
    r'Volume:\s*([0-9.]+)',
    caseSensitive: false,
  ).firstMatch(output);
  final volume = volumeMatch == null
      ? null
      : double.tryParse(volumeMatch.group(1)!)?.clamp(0.0, 1.0).toDouble();

  return AudioOutputStatus(
    hasDevice: true,
    volume: volume,
    // Without a volume the mute marker proves nothing usable, so it stays
    // unknown too instead of claiming the output is fine.
    muted: volume == null ? null : output.toUpperCase().contains('[MUTED]'),
    source: AudioProbeSource.wpctl,
  );
}

/// Creates the probe for the current platform.
AudioOutputProbe createAudioOutputProbe() {
  if (Platform.isLinux) return LinuxAudioOutputProbe();
  if (Platform.isMacOS || Platform.isWindows) {
    return PlatformChannelAudioOutputProbe();
  }
  return const UnsupportedAudioOutputProbe();
}

/// Opens the platform's sound pane.
///
/// macOS goes through the native channel: a sandboxed release build cannot
/// spawn `open`, but `NSWorkspace` may open the settings URL. Windows and Linux
/// use the shell, and a failure on Linux (no `pavucontrol`) is harmless because
/// the dialog text is the remaining guidance (design §4.4.2).
Future<void> openSystemSoundSettings() async {
  try {
    if (Platform.isMacOS) {
      await const MethodChannel(
        'ssb_runner/audio_output',
      ).invokeMethod<void>('openSoundSettings');
      return;
    }
    if (Platform.isWindows) {
      await Process.start('cmd', [
        '/c',
        'start',
        '',
        'ms-settings:sound',
      ], runInShell: true);
      return;
    }
    if (Platform.isLinux) {
      await Process.start('pavucontrol', const []);
    }
  } catch (error, stackTrace) {
    log.warn(
      'opening sound settings failed',
      tag: 'audio.monitor',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// Reads the SoLoud engine and device state without ever throwing.
///
/// `getAudioDeviceState() == stopped` is normal: flutter_soloud parks the
/// output after 500 ms of silence (design §4.2.1), so only `uninitialized`
/// counts as a fault.
AudioEngineStatus readSoLoudEngineStatus() {
  try {
    final soloud = SoLoud.instance;
    if (!soloud.isInitialized) {
      return const AudioEngineStatus(initialized: false);
    }

    int? deviceCount;
    try {
      deviceCount = soloud.listPlaybackDevices().length;
    } catch (_) {
      // Unknown; the mute/volume reading still works.
      deviceCount = null;
    }

    return AudioEngineStatus(
      initialized: true,
      playbackDeviceCount: deviceCount,
      deviceUninitialized:
          soloud.getAudioDeviceState() == AudioDeviceState.uninitialized,
    );
  } catch (_) {
    return AudioEngineStatus.unknown;
  }
}
