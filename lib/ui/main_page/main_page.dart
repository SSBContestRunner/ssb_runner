import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ssb_runner/contest_run/new/contest_manager.dart';
import 'package:ssb_runner/l10n/generated/app_localizations.dart';
import 'package:ssb_runner/platform/audio/audio_monitor_ui.dart';
import 'package:ssb_runner/platform/capabilities.dart';
import 'package:ssb_runner/settings/app_settings.dart';
import 'package:ssb_runner/ui/main_page/app_topbar.dart';
import 'package:ssb_runner/ui/main_page/qso_console.dart';
import 'package:ssb_runner/ui/main_page/qso_log_panel.dart';
import 'package:ssb_runner/ui/main_page/rules_card.dart';
import 'package:ssb_runner/ui/main_page/session_panel.dart';
import 'package:ssb_runner/ui/main_page/settings_cubits.dart';
import 'package:ssb_runner/ui/main_page/training_review_overlay.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_result_list/qso_result_list_cubit.dart';
import 'package:ssb_runner/ui/qso_result_table/qso_voice_replay_cubit.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  @override
  void initState() {
    super.initState();
    // The console reads the F1–F12 table during the first build, so a repaired
    // configuration is queued before this callback runs. Consuming the flag
    // here keeps the notice to a single SnackBar per repair.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!context.read<AppSettings>().takeFunctionKeyRepairNotice()) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).functionKeysAutoRepaired),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) =>
              MainSettingsCubit(contestManager: context.read()),
        ),
        BlocProvider(
          create: (context) =>
              ContestSettingCubit(appSettings: context.read<AppSettings>()),
        ),
        BlocProvider(
          create: (context) =>
              StationCallsignCubit(appSettings: context.read<AppSettings>()),
        ),
        BlocProvider(
          create: (context) =>
              TrainingOptionsCubit(context.read<AppSettings>()),
        ),
        BlocProvider(
          create: (context) => QsoRecordListCubit(
            appDatabase: context.read(),
            contestManager: context.read(),
          ),
        ),
        BlocProvider(
          create: (context) {
            final contestManager = context.read<ContestManager>();
            return QsoVoiceReplayCubit(
              contestManager: contestManager,
              audioLoader: contestManager.audioLoader,
              audioPlayer: contestManager.audioPlayer,
            );
          },
        ),
      ],
      child: _HiddenPauseGuard(
        child: Stack(
          children: [
            Column(
              children: [
                AppTopbar(),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: _ConsoleGrid(),
                  ),
                ),
              ],
            ),
            const TrainingReviewOverlay(),
            buildAudioAlertToaster(),
          ],
        ),
      ),
    );
  }
}

/// A browser tab can be hidden or frozen at any time, and Flutter stops
/// delivering timers and audio callbacks. The run is paused instead of
/// pretending it kept going; resuming is an explicit action.
class _HiddenPauseGuard extends StatefulWidget {
  const _HiddenPauseGuard({required this.child});

  final Widget child;

  @override
  State<_HiddenPauseGuard> createState() => _HiddenPauseGuardState();
}

class _HiddenPauseGuardState extends State<_HiddenPauseGuard> {
  late final AppLifecycleListener _listener;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(onHide: _pause, onPause: _pause);
  }

  void _pause() {
    if (!PlatformCapabilities.pausesWhenHidden || !mounted) {
      return;
    }
    context.read<ContestManager>().pauseContest(reason: 'hidden');
  }

  @override
  void dispose() {
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ConsoleGrid extends StatelessWidget {
  const _ConsoleGrid();

  /// Narrowest console width that keeps every fixed column readable.
  ///
  /// Below it the page scrolls horizontally instead of shrinking the log into
  /// an unreadable column; the browser window is not under our control the way
  /// the desktop minimum window size is.
  static const double minWidth = 1000;

  @override
  Widget build(BuildContext context) {
    final windowWidth = MediaQuery.sizeOf(context).width;
    if (windowWidth >= minWidth) {
      return _buildGrid(context, windowWidth);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: minWidth,
            height: constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : null,
            child: _buildGrid(context, minWidth),
          ),
        );
      },
    );
  }

  Widget _buildGrid(BuildContext context, double windowWidth) {
    // The session card owns the fixed track on the right; the log column on
    // the left is Expanded and takes whatever is left. At the 1024 minimum,
    // the English timer labels need a 362dp card (113.4dp for
    // "Remaining 00:00:00" plus 12dp slack in its 2/5 share of the row), so
    // 372 keeps the label intact and shortens the log column instead. The
    // wider tiers grow the card just enough to stay comfortable.
    final sideWidth = windowWidth <= 1060
        ? 372.0
        : windowWidth <= 1180
        ? 384.0
        : 396.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            children: const [
              Expanded(child: QsoLogPanel()),
              SizedBox(height: 12),
              QsoConsole(),
            ],
          ),
        ),
        const SizedBox(width: 14),
        SizedBox(
          width: sideWidth,
          child: const Column(
            children: [
              Expanded(child: SessionPanel()),
              SizedBox(height: 12),
              RulesCard(),
            ],
          ),
        ),
      ],
    );
  }
}
