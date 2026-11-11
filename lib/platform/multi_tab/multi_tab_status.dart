import 'package:flutter/foundation.dart';

/// Bumped when another tab running the app is detected.
final ValueNotifier<int> multiTabRevision = ValueNotifier<int>(0);
