import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/contest_run/contest_manager.dart';
import 'package:ssb_runner/contest_run/data/score_data.dart';
import 'package:ssb_runner/contest_run/score_manager.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/dxcc/dxcc_manager.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/bottom_panel/time_and_score/score_area/score_area_data.dart';

class ScoreAreaCubit extends Cubit<ScoreAreaData> {
  StreamSubscription<ScoreData>? _rawScoreDataSubscription;
  StreamSubscription<ScoreData>? _verifiedScoreDataSubscription;

  ScoreAreaCubit({required BuildContext context}) : super(_obtainScoreData()) {
    _subscribeContestChange(context);
  }

  static ScoreAreaData _obtainScoreData() {
    return ScoreAreaData(
      rawScore: ScoreData.initial(),
      verifiedScore: ScoreData.initial(),
    );
  }

  void _subscribeContestChange(BuildContext context) {
    final contestManager = context.read<ContestManager>();
    final appSettings = context.read<AppSettings>();
    final appDatabase = context.read<AppDatabase>();

    contestManager.isContestRunningStream.listen((isContestRunning) {
      _unsubscribeScoreUpdate();

      if (isContestRunning) {
        final scoreManager = _createScoreManager(appSettings, appDatabase);
        _subscribeScoreUpdate(scoreManager);
      }
    });
  }

  ScoreManager _createScoreManager(
    AppSettings appSettings,
    AppDatabase appDatabase,
  ) {
    final dxccManager = DxccManager(database: appDatabase);

    return ScoreManager(
      contestId: appSettings.contestId,
      stationCallsign: appSettings.stationCallsign,
      dxccManager: dxccManager,
    );
  }

  void _subscribeScoreUpdate(ScoreManager scoreManager) {
    _rawScoreDataSubscription = scoreManager.rawScoreDataStream.stream.listen((
      scoreData,
    ) {
      emit(state.copyWith(rawScore: scoreData));
    });

    _verifiedScoreDataSubscription = scoreManager.verifiedScoreDataStream.stream
        .listen((scoreData) {
          emit(state.copyWith(verifiedScore: scoreData));
        });
  }

  void _unsubscribeScoreUpdate() {
    _rawScoreDataSubscription?.cancel();
    _verifiedScoreDataSubscription?.cancel();
  }
}
