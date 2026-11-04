import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ssb_runner/audio/accent_policy.dart';
import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/training/session_review.dart';
import 'package:ssb_runner/training/training_profile.dart';

/// Every DXCC entity the accent mapping knows about, plus entities outside it.
const _mappedDxccIds = [
  339, 177, 192, // Japan
  54, 126, 15, 288, 27, 130, 292, // Russian-speaking
  223, 279, 294, 265, 114, 122, 106, 150, 35, 38, 147, 189, 170, 34, 133, 1,
  324, 11, 142, 372, 305, 315, 159, 3, 369, 306, // South Asia
  387, 293, 299, 46, 381, 327, 375, 345, 511, 312, 143, 309, // Southeast Asia
  291, 318, 9999, // US fallback
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('auto keeps the DXCC mapping unchanged', () {
    const policy = AccentPolicy(IncomingAccent.auto);

    for (final dxccId in _mappedDxccIds) {
      expect(
        policy.resolve(isMe: false, dxccId: dxccId),
        obtainAccentByDxccId(dxccId),
        reason: 'DXCC $dxccId',
      );
    }
  });

  test('a fixed accent overrides every incoming entity', () {
    for (final accent in IncomingAccent.values) {
      final assetDir = accent.assetDir;
      if (assetDir == null) {
        continue;
      }

      final policy = AccentPolicy(accent);
      for (final dxccId in _mappedDxccIds) {
        expect(
          policy.resolve(isMe: false, dxccId: dxccId),
          assetDir,
          reason: '${accent.id} / DXCC $dxccId',
        );
      }
    }
  });

  test('own audio always uses the neutral Global voice', () {
    for (final accent in IncomingAccent.values) {
      expect(
        AccentPolicy(accent).resolve(isMe: true, dxccId: 339),
        myAudioAccentDir,
      );
    }
  });

  test('incoming accent persists and defaults to auto', () async {
    expect(IncomingAccent.fromId(null), IncomingAccent.auto);
    expect(IncomingAccent.fromId('unknown'), IncomingAccent.auto);

    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettings(prefs: prefs);
    expect(settings.incomingAccent, IncomingAccent.auto);

    settings.incomingAccent = IncomingAccent.uk;
    expect(AppSettings(prefs: prefs).incomingAccent, IncomingAccent.uk);
  });

  test('reviews record the accent and decode legacy entries as auto', () {
    final metadata = TrainingRunMetadata(
      runId: 'run-1',
      contestId: 'CQ-WPX',
      contestName: 'CQ WPX SSB',
      modeId: TrainingMode.run.id,
      difficultyId: TrainingDifficulty.standard.id,
      questionSeed: 1,
      audioSeed: 2,
      accentId: IncomingAccent.us.id,
      startedAt: DateTime.utc(2026, 1, 1, 12),
    );
    final review = TrainingRunReview.fromQsos(
      metadata: metadata,
      qsos: const [],
      score: 0,
    );

    expect(TrainingRunReview.decode(review.encode()).metadata.accentId, 'us');

    final legacy = Map<String, Object>.of(review.toJson())..remove('accentId');
    final decoded = TrainingRunReview.decode(jsonEncode(legacy));
    expect(decoded.metadata.accentId, 'auto');
  });
}
