import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_app/window_geometry.dart';

const _windowContentSizeKey = 'setting_window_content_size';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('minimumFrameFor', () {
    test('macOS title bar', () {
      expect(
        minimumFrameFor(kMinWindowContentSize, const Size(0, 24)),
        const Size(1108, 796),
      );
    });

    test('Windows non-client area', () {
      expect(
        minimumFrameFor(kMinWindowContentSize, const Size(16, 39)),
        const Size(1124, 811),
      );
    });

    test('borderless window equals the content size', () {
      expect(
        minimumFrameFor(kMinWindowContentSize, Size.zero),
        kMinWindowContentSize,
      );
    });
  });

  group('clampWindowContentSize', () {
    const minimum = kMinWindowContentSize;

    test('raises a size below the minimum', () {
      expect(
        clampWindowContentSize(const Size(800, 600), minimum, null),
        minimum,
      );
    });

    test('keeps a size inside the work area', () {
      expect(
        clampWindowContentSize(
          const Size(1400, 900),
          minimum,
          const Size(1920, 1080),
        ),
        const Size(1400, 900),
      );
    });

    test('caps a size above the work area', () {
      expect(
        clampWindowContentSize(
          const Size(2400, 1400),
          minimum,
          const Size(1920, 1080),
        ),
        const Size(1920, 1080),
      );
    });

    test('only applies the lower bound without a work area', () {
      expect(
        clampWindowContentSize(const Size(2400, 1400), minimum, null),
        const Size(2400, 1400),
      );
    });
  });

  group('AppSettings.windowContentSize', () {
    test('is null when never saved', () async {
      final settings = await _settings();

      expect(settings.windowContentSize, isNull);
    });

    test('round-trips a saved content size', () async {
      final settings = await _settings();

      settings.saveWindowContentSize(const Size(1400, 900));

      expect(settings.windowContentSize, const Size(1400, 900));
    });

    for (final raw in const [
      'abc',
      '1108x',
      '1108x772x1',
      '-1x-1',
      'NaNxNaN',
      '0x0',
    ]) {
      test('treats "$raw" as no saved value', () async {
        final settings = await _settings(rawWindowContentSize: raw);

        expect(settings.windowContentSize, isNull);
      });
    }

    test('parses a well-formed value', () async {
      final settings = await _settings(rawWindowContentSize: '1108x772');

      expect(settings.windowContentSize, const Size(1108, 772));
    });
  });
}

Future<AppSettings> _settings({String? rawWindowContentSize}) async {
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(),
  );
  if (rawWindowContentSize != null) {
    await prefs.setString(_windowContentSizeKey, rawWindowContentSize);
  }
  return AppSettings(prefs: prefs);
}
