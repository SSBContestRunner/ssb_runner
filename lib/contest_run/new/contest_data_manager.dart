import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/callsign/callsign_loader.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/settings/app_settings.dart';

class ContestDataManager {
  final AudioLoader audioLoader;
  final AudioPlayer audioPlayer;
  final AppSettings appSettings;
  final AppDatabase appDatabase;
  final CallsignLoader callsignLoader;
  final DxccManager dxccManager;

  ContestDataManager({
    required this.audioLoader,
    required this.audioPlayer,
    required this.appSettings,
    required this.appDatabase,
    required this.callsignLoader,
    required this.dxccManager,
  });
}
