import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/audio/qso_voice_replay_service.dart';
import 'package:ssb_runner/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('replay composes callsign, 59 and serial in that order', () async {
    final loader = _FakeAudioLoader();
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final service = QsoVoiceReplayService(
      audioLoader: loader,
      audioPlayer: AudioPlayer(),
      appSettings: AppSettings(prefs: prefs),
    );

    final pcm = await service.compose(
      const QsoVoiceReplayRequest(
        callsign: 'JA1ABC',
        exchangeAudioText: '028',
        accentDir: 'JP',
        phonicType: PhonicType.standard,
        callPhonicDirs: ['ICAO', 'Number', 'ICAO', 'ICAO', 'ICAO', 'ICAO'],
        exchangePhonicDirs: ['Number', 'Number', 'Number'],
      ),
    );

    expect(loader.loadedTexts, ['JA1ABC', '028']);
    expect(pcm, [1, 2, 3]);
  });

  test('resolved phonic dirs are cached and match the played letters', () {
    final loader = AudioLoader();

    final dirs = loader.resolvePhonicDirs('US', 'K1ABC', PhonicType.standard);
    expect(dirs, ['ICAO', 'Number', 'ICAO', 'ICAO', 'ICAO']);
    // The cache returns the same resolution instead of drawing new randoms.
    expect(
      loader.resolvePhonicDirs('US', 'K1ABC', PhonicType.standard),
      same(dirs),
    );

    expect(loader.resolvePhonicDirs('US', 'K1ABC', PhonicType.location), [
      'Location',
      'Number',
      'Location',
      'Location',
      'Location',
    ]);
  });

  test('replay callsign audio is rebuilt from the persisted dirs', () async {
    final loader = AudioLoader();

    final pcm = await loader.loadCallsignWithDirs('US', 'K1ABC', [
      'ICAO',
      'Number',
      'ICAO',
      'ICAO',
      'ICAO',
    ]);

    expect(pcm, isNotEmpty);
  });

  test('replay RST falls back to the US clip for an unknown accent', () async {
    final loader = AudioLoader();

    expect(await loader.loadReplayRstAudio('JP'), isNotEmpty);
    // XX has no Commons directory; the chain ends at US/Common/59.wav.
    expect(await loader.loadReplayRstAudio('XX'), isNotEmpty);
  });
}

class _FakeAudioLoader extends AudioLoader {
  final List<String> loadedTexts = [];

  @override
  Future<Uint8List> loadCallsignWithDirs(
    String accentDir,
    String callsign,
    List<String> dirs,
  ) async {
    loadedTexts.add(callsign);
    return Uint8List.fromList([loadedTexts.length == 1 ? 1 : 3]);
  }

  @override
  Future<Uint8List> loadReplayRstAudio(String accentDir) async =>
      Uint8List.fromList([2]);
}
