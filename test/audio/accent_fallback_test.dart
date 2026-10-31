import 'package:flutter_test/flutter_test.dart';
import 'package:ssb_runner/audio/payload_to_audio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a missing accent clip falls back to the Global voice', () async {
    // RU has no EXCH.wav, so this path exercises the fallback chain.
    final global = await loadAssetsWavPcmData('Global/Common/EXCH.wav');
    final fallback = await loadAssetsWavPcmData('RU/Common/EXCH.wav');

    expect(global, isNotEmpty);
    expect(fallback, global);
  });
}
