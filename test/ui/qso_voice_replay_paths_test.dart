import 'dart:typed_data';

import 'package:drift/native.dart';
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
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/contest_run/new/contest_data_manager.dart';
import 'package:ssb_runner/contest_run/new/contest_input_handler.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/contest_type/contest_type.dart';
import 'package:ssb_runner/contest_type/exchange_manager.dart';
import 'package:ssb_runner/contest_type/score_calculator.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_voice_replay_cubit.dart';

QsoResult _row({required int id, required String call}) {
  return QsoResult(
    id: id,
    call: QsoResultField(data: call, isCorrect: false),
    exchange: QsoResultField(data: '0012', isCorrect: false),
    utc: '14:23:45',
    corrections: '$call 0012',
    correctCall: call,
    correctExchange: '0012',
    accentDir: 'US',
    phonicTypeId: 'standard',
    callPhonicDirs: const ['ICAO', 'Number', 'ICAO', 'ICAO', 'ICAO', 'ICAO'],
    exchangePhonicDirs: const ['Number', 'Number', 'Number', 'Number'],
    hasCorrection: true,
    canReplay: true,
  );
}

Future<void> _waitUntil(bool Function() condition, {String? reason}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for ${reason ?? 'condition'}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late QsoVoiceReplayCubit cubit;
  late _FakeReplayService service;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
    final settings = AppSettings(prefs: prefs);
    database = AppDatabase(NativeDatabase.memory());

    final dataManager = ContestDataManager(
      audioLoader: AudioLoader(),
      audioPlayer: AudioPlayer(),
      appSettings: settings,
      appDatabase: database,
      callsignLoader: CallsignLoader(),
      dxccManager: DxccManager(database: database),
      inputHandler: ContestInputHandler(),
    );
    service = _FakeReplayService(settings: settings);
    cubit = QsoVoiceReplayCubit(
      contestManager: _ReplayContestManager(
        contestDataManager: dataManager,
      ),
      audioLoader: AudioLoader(),
      audioPlayer: AudioPlayer(),
      service: service,
    );
  });

  tearDown(() async {
    await cubit.close();
    await database.close();
  });

  test('natural end returns straight to the replay icon', () async {
    cubit.play(_row(id: 1, call: 'K1ABC'));
    expect(cubit.state.playingId, 1);

    await _waitUntil(
      () => service.events.contains('play'),
      reason: 'playback to start',
    );
    service.playing = false;

    await _waitUntil(
      () => cubit.state.playingId == null,
      reason: 'natural end',
    );
    expect(cubit.state.notice, isNull);
    expect(service.events, contains('finish'));
  });

  test('taking over another row ends on the replay icon', () async {
    cubit.play(_row(id: 1, call: 'K1ABC'));
    await _waitUntil(
      () => service.events.contains('play'),
      reason: 'first playback to start',
    );

    cubit.play(_row(id: 2, call: 'K2DEF'));
    expect(cubit.state.playingId, 2);
    expect(cubit.state.notice?.kind, QsoVoiceReplayNoticeKind.interrupted);
    expect(cubit.state.notice?.fromCall, 'K1ABC');
    expect(cubit.state.notice?.toCall, 'K2DEF');
    expect(service.events, contains('interrupt'));

    await _waitUntil(
      () => service.events.where((event) => event == 'play').length >= 2,
      reason: 'second playback to start',
    );
    service.playing = false;
    await _waitUntil(
      () => cubit.state.playingId == null,
      reason: 'new playback to end',
    );
  });

  test('stopping the playing row returns to the replay icon', () async {
    cubit.play(_row(id: 1, call: 'K1ABC'));
    await _waitUntil(
      () => service.events.contains('play'),
      reason: 'playback to start',
    );

    cubit.stop();
    expect(cubit.state.playingId, isNull);
    expect(cubit.state.notice?.kind, QsoVoiceReplayNoticeKind.stopped);
    expect(cubit.state.notice?.fromCall, 'K1ABC');
    expect(service.events, contains('finish'));

    // Nothing re-enters a transient state afterwards.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(cubit.state.playingId, isNull);
  });
}

class _ReplayContestManager extends ContestManager {
  _ReplayContestManager({required super.contestDataManager});

  @override
  ContestType? get contestType => const _ReplayContestType();
}

class _ReplayContestType implements ContestType {
  const _ReplayContestType();

  @override
  RegExp get allowExchangeRegex => RegExp('[0-9]');

  @override
  ScoreCalculator get scoreCalculator => throw UnimplementedError();

  @override
  ExchangeManager get exchangeManager => throw UnimplementedError();

  @override
  String buildMyExchange(int qsoNumber) => '$qsoNumber';

  @override
  String formatExchangeForAudio(String exchange) => exchange;
}

class _FakeReplayService extends QsoVoiceReplayService {
  _FakeReplayService({required AppSettings settings})
    : super(
        audioLoader: AudioLoader(),
        audioPlayer: AudioPlayer(),
        appSettings: settings,
      );

  final List<String> events = [];
  bool playing = false;

  @override
  bool get isPlaying => playing;

  @override
  Future<Uint8List> compose(QsoVoiceReplayRequest request) async =>
      Uint8List.fromList(const [1, 2, 3]);

  @override
  void prepare() => events.add('prepare');

  @override
  void play(Uint8List pcm) {
    playing = true;
    events.add('play');
  }

  @override
  void interrupt() {
    playing = false;
    events.add('interrupt');
  }

  @override
  void abandon() => events.add('abandon');

  @override
  void finish() => events.add('finish');
}
