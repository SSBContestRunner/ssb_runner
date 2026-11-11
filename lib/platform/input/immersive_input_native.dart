/// Desktop shortcuts are delivered to the app without a browser arbitration
/// step, so there is nothing to request.
Future<bool> enterTrainingInputMode() async => true;

Future<void> leaveTrainingInputMode() async {}

/// Desktop browsers are not involved, so there is no default action to block.
void installTrainingKeyGuard() {}

void removeTrainingKeyGuard() {}
