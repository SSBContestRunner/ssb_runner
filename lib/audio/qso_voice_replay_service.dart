import 'dart:typed_data';

import 'package:ssb_runner/audio/audio_loader.dart';
import 'package:ssb_runner/audio/audio_player.dart';
import 'package:ssb_runner/common/concat_bytes.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/training/training_profile.dart';

/// Everything needed to reproduce one logged QSO: the correct callsign, the
/// serial and the per-character phonic directories captured during the run.
class QsoVoiceReplayRequest {
  const QsoVoiceReplayRequest({
    required this.callsign,
    required this.exchangeAudioText,
    required this.accentDir,
    required this.phonicType,
    required this.callPhonicDirs,
    required this.exchangePhonicDirs,
  });

  final String callsign;
  final String exchangeAudioText;
  final String accentDir;
  final PhonicType phonicType;
  final List<String> callPhonicDirs;
  final List<String> exchangePhonicDirs;
}

/// Builds and plays the QSO voice replay.
///
/// The replay shares the contest [AudioPlayer] so it keeps the same noise bed
/// and QSB chain. It is only used while the session is idle (D-03), and the
/// contest pause chain is untouched: starting a training run replaces this
/// profile and resets the stream.
class QsoVoiceReplayService {
  QsoVoiceReplayService({
    required this._audioLoader,
    required this._audioPlayer,
    required this._appSettings,
  });

  final AudioLoader _audioLoader;
  final AudioPlayer _audioPlayer;
  final AppSettings _appSettings;

  bool _prepared = false;

  bool get isPlaying => _audioPlayer.isPlaying();

  /// Callsign → `59` → serial, with the RST fallback chain of D-04.
  Future<Uint8List> compose(QsoVoiceReplayRequest request) async {
    final callPcm = await _audioLoader.loadCallsignWithDirs(
      request.accentDir,
      request.callsign,
      request.callPhonicDirs,
    );
    final rstPcm = await _audioLoader.loadReplayRstAudio(request.accentDir);
    final exchangePcm = await _audioLoader.loadCallsignWithDirs(
      request.accentDir,
      request.exchangeAudioText,
      request.exchangePhonicDirs,
    );

    return concatUint8ListSync([callPcm, rstPcm, exchangePcm]);
  }

  /// Installs the replay audio environment (noise bed + QSB, volume from the
  /// settings) and starts the shared player.
  void prepare() {
    if (_prepared) {
      return;
    }
    _audioPlayer.setTrainingProfile(
      AudioTrainingProfile.fromDifficulty(
        difficulty: _appSettings.difficulty,
        volume: _appSettings.audioVolume,
        questionSeed: 0,
        audioSeed: 0,
      ),
    );
    _audioPlayer.startPlay();
    _prepared = true;
  }

  void play(Uint8List pcm) {
    _audioPlayer.addAudioData(pcm, isResetCurrentStream: true);
  }

  void interrupt() {
    _audioPlayer.resetStream();
  }

  /// Forgets the replay environment without touching the player. Used when a
  /// contest starts while a replay is preparing; the contest owns the player
  /// from then on.
  void abandon() {
    _prepared = false;
  }

  /// Tears the replay environment down. Safe to call more than once.
  void finish() {
    if (!_prepared) {
      return;
    }
    _prepared = false;
    _audioPlayer.setTrainingProfile(null);
    _audioPlayer.stopPlay();
  }
}
