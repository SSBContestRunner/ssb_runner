import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/contest_run/data/score_data.dart';
import 'package:ssb_runner/contest_run/new/contest_manager_new.dart';
import 'package:ssb_runner/contest_run/score_manager.dart';
import 'package:ssb_runner/ui/bottom_panel/time_and_score/score_area/score_area_data.dart';

class ScoreAreaCubit extends Cubit<ScoreAreaData> {
  StreamSubscription<ScoreData>? _rawScoreDataSubscription;
  StreamSubscription<ScoreData>? _verifiedScoreDataSubscription;

  ScoreAreaCubit({required BuildContext context}) : super(_initialScoreData()) {
    _subscribeContestChange(context);
  }

  static ScoreAreaData _initialScoreData() {
    return ScoreAreaData(
      rawScore: ScoreData.initial(),
      verifiedScore: ScoreData.initial(),
    );
  }

  void _subscribeContestChange(BuildContext context) {
    final contestManager = context.read<ContestManagerNew>();

    contestManager.contestRunIdStream.listen((_) {
      _unsubscribeScoreUpdate();
      emit(_initialScoreData());

      final contestRunningManager = contestManager.contestRunningManager;

      if (contestRunningManager == null) {
        return;
      }

      final scoreManager = contestRunningManager.scoreManager;
      _subscribeScoreUpdate(scoreManager);
    });
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
