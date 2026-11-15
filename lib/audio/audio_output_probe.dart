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
      // One JSON read instead of three text commands (design §5 I). The extra
      // `info` call only happens when several sinks exist: picking the wrong
      // one would report another device's volume.
      final rawSinks = await _runQuietly('pactl', [
        '--format=json',
        'list',
        'sinks',
      ]);
      if (rawSinks == null) return null;
      final sinks = parsePactlSinks(rawSinks);
      if (sinks == null) return null;

      String? defaultName;
      if (sinks.length > 1) {
        final rawInfo = await _runQuietly('pactl', ['--format=json', 'info']);
        defaultName = rawInfo == null
            ? null
            : parsePactlDefaultSink(rawInfo);
      }

      final sink = selectPactlSink(sinks, defaultName);
      if (sink == null) {
        // No sink at all, or none of them is the default endpoint: apps cannot
        // play (design P-5).
        return const AudioOutputStatus(
          hasDevice: false,
          source: AudioProbeSource.pactl,
        );
      }

      return AudioOutputStatus(
        hasDevice: true,
        deviceName: sink.name,
        volume: sink.volume,
        muted: sink.muted,
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

/// One sink from `pactl --format=json list sinks`.
class PactlSink {
  const PactlSink({this.name, this.volume, this.muted});

  /// Symbolic name, the same value `pactl info` reports as `default_sink_name`.
  final String? name;

  /// Normalized volume, 0.0–1.0.
  final double? volume;
  final bool? muted;
}

/// Parses `pactl --format=json list sinks`.
///
/// Returns `null` when the text is not the expected JSON array: an older pactl
/// without `--format=json` must fall back to `wpctl` instead of pretending the
/// machine has no device. An empty list really means the server has no sink
/// (design P-5).
List<PactlSink>? parsePactlSinks(String output) {
  final Object? decoded;
  try {
    decoded = jsonDecode(output);
  } on FormatException {
    return null;
  }
  if (decoded is! List) return null;

  return <PactlSink>[
    for (final entry in decoded)
      if (entry is Map)
        PactlSink(
          name: entry['name'] is String ? entry['name'] as String : null,
          volume: _pactlSinkVolume(entry['volume']),
          muted: entry['mute'] is bool ? entry['mute'] as bool : null,
        ),
  ];
}

/// Picks the sink apps play through.
///
/// A single sink is the default by definition; with several, the server's
/// `default_sink_name` must match one of them. `null` means there is no usable
/// default endpoint, which the probe reports as `hasDevice == false`
/// (design P-5).
PactlSink? selectPactlSink(List<PactlSink> sinks, String? defaultSinkName) {
  if (sinks.isEmpty) return null;
  if (sinks.length == 1) return sinks.single;
  if (defaultSinkName == null) return null;
  for (final sink in sinks) {
    if (sink.name == defaultSinkName) return sink;
  }
  return null;
}

/// Reads the first channel of a pactl volume object.
///
/// The wire value is a Pascal volume: `65536` is 100%.
double? _pactlSinkVolume(Object? raw) {
  if (raw is! Map) return null;
  for (final channel in raw.values) {
    if (channel is! Map) continue;
    final value = channel['value'];
    if (value is num) return (value / 65536).clamp(0.0, 1.0).toDouble();
  }
  return null;
}

/// Parses `default_sink_name` from `pactl --format=json info`.
///
/// `null` covers both an unparsable reply and a server that has no default
/// sink: the probe treats the latter as "no output device" (design P-5).
String? parsePactlDefaultSink(String output) {
  final Object? decoded;
  try {
    decoded = jsonDecode(output);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final name = decoded['default_sink_name'];
  return name is String && name.isNotEmpty ? name : null;
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
/// Only atomic queries: enumerating playback devices (`listPlaybackDevices()`)
/// is a synchronous FFI call that costs hundreds of microseconds and blocks the
/// UI isolate, so device existence comes from the platform probe instead
/// (design [`audio_output_probe_performance_design.md`] §6.3 A).
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

    return AudioEngineStatus(
      initialized: true,
      deviceUninitialized:
          soloud.getAudioDeviceState() == AudioDeviceState.uninitialized,
    );
  } catch (_) {
    return AudioEngineStatus.unknown;
  }
}
