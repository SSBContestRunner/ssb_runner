import 'package:flutter/foundation.dart';

/// Bumped when the origin storage is close to its quota.
///
/// The UI listens and shows one warning with a pointer to Settings › System,
/// where the backup entry lives.
final ValueNotifier<int> storagePressureRevision = ValueNotifier<int>(0);

/// Bumped after the first completed session, when a backup is most valuable.
final ValueNotifier<int> backupReminderRevision = ValueNotifier<int>(0);
