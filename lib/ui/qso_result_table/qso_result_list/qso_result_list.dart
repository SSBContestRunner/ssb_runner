import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_list_cubit.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_row.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_voice_replay_cubit.dart';
import 'package:toastification/toastification.dart';

class QsoRecordList extends StatefulWidget {
  const QsoRecordList({super.key});

  @override
  State<StatefulWidget> createState() {
    return _QsoResultListState();
  }
}

class _QsoResultListState extends State<QsoRecordList> {
  final _controller = ScrollController();

  void _setupAutoScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_controller.hasClients) {
        return;
      }
      _controller.jumpTo(_controller.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<QsoVoiceReplayCubit, QsoVoiceReplayState>(
      listenWhen: (previous, current) =>
          current.notice?.seq != previous.notice?.seq,
      listener: (context, state) {
        final notice = state.notice;
        if (notice == null) {
          return;
        }
        final l10n = AppLocalizations.of(context);
        toastification.show(
          title: Text(
            notice.kind == QsoVoiceReplayNoticeKind.interrupted
                ? l10n.replayInterrupted(notice.fromCall, notice.toCall)
                : l10n.replayStopped(notice.fromCall),
          ),
          type: ToastificationType.info,
          style: ToastificationStyle.fillColored,
          autoCloseDuration: const Duration(seconds: 2),
        );
      },
      child: BlocBuilder<QsoRecordListCubit, List<QsoResult>>(
        builder: (context, qsos) {
          _setupAutoScroll();
          if (qsos.isEmpty) {
            return const SizedBox.expand();
          }
          return BlocBuilder<QsoVoiceReplayCubit, QsoVoiceReplayState>(
            builder: (context, playback) {
              final cubit = context.read<QsoVoiceReplayCubit>();
              return Scrollbar(
                controller: _controller,
                child: ListView.builder(
                  controller: _controller,
                  itemBuilder: (context, index) {
                    final item = qsos[index];
                    return QsoRecordRow(
                      item: item,
                      isLatest: index == qsos.length - 1,
                      isPlaying: playback.playingId == item.id,
                      isDone: playback.doneId == item.id,
                      isInterrupted: playback.interruptedId == item.id,
                      onReplay: item.canReplay ? () => cubit.play(item) : null,
                    );
                  },
                  itemCount: qsos.length,
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
