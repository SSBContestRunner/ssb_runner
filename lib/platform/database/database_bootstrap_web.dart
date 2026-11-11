import 'dart:async';

import 'package:ssb_runner/db/history_maintenance.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/platform/database/database_info.dart';
import 'package:ssb_runner/platform/web/browser_storage.dart';

export 'database_info.dart';

/// How often the origin quota is re-read while the app is open.
const Duration _quotaCheckInterval = Duration(minutes: 5);

/// Warn when this much of the quota is used.
const double _quotaWarningFraction = 0.9;

Future<DatabaseBootstrap>? _pending;
Timer? _quotaTimer;

/// Whether the current pressure episode was already reported, so the warning
/// is shown once instead of every check interval.
bool _pressureReported = false;

/// Requests persistent storage and records the quota for the startup log.
///
/// There is no directory to prepare: drift picks OPFS or IndexedDB when it opens
/// the database and reports the chosen implementation through `onResult`.
Future<DatabaseBootstrap> ensureDatabaseReady() => _pending ??= _prepare();

Future<DatabaseBootstrap> _prepare() async {
  final granted = await requestPersistentStorage();
  final estimate = await browserStorageEstimate();
  final persisted = granted ?? false;

  final bootstrap = DatabaseBootstrap.web(
    implementation: 'wasm',
    persistent: persisted,
    quota: estimate?.quota,
    usage: estimate?.usage,
  );

  log.info(
    'browser storage resolved',
    tag: 'db',
    fields: <String, Object?>{
      'implementation': bootstrap.implementation,
      'persisted': persisted,
      'persist_api': granted != null,
      'quota': estimate?.quota,
      'usage': estimate?.usage,
    },
  );

  _startQuotaMonitor();
  return bootstrap;
}

/// Keeps an eye on the quota so a full origin is visible before a write fails.
void _startQuotaMonitor() {
  _quotaTimer?.cancel();
  _quotaTimer = Timer.periodic(_quotaCheckInterval, (_) async {
    final estimate = await browserStorageEstimate();
    final used = estimate?.usedFraction;
    if (used == null) {
      return;
    }

    if (used >= _quotaWarningFraction) {
      log.warn(
        'browser storage almost full',
        tag: 'db',
        fields: <String, Object?>{
          'quota': estimate?.quota,
          'usage': estimate?.usage,
          'used_fraction': used.toStringAsFixed(2),
        },
      );
      if (!_pressureReported) {
        _pressureReported = true;
        storagePressureRevision.value++;
      }
      return;
    }

    // Hysteresis: allow a new warning only after usage drops clearly below
    // the threshold, so hovering at 90% does not turn into a toast loop.
    if (used < 0.85) {
      _pressureReported = false;
    }

    log.debug(
      'browser storage usage',
      tag: 'db',
      fields: <String, Object?>{
        'quota': estimate?.quota,
        'usage': estimate?.usage,
        'used_fraction': used.toStringAsFixed(2),
      },
    );
  });
}
