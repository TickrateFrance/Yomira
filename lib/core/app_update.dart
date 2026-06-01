import 'package:flutter/foundation.dart';

enum UpdateStatus { none, soft, force }

class AppUpdate {
  const AppUpdate(this.status, this.url);
  final UpdateStatus status;
  final String url;
}

/// Global update signal. The launch check writes the status from /app-status;
/// the Dio interceptor escalates to [force] on any 426; [UpdateGate] (UI) listens.
final ValueNotifier<AppUpdate?> appUpdate = ValueNotifier<AppUpdate?>(null);

/// Force-update can never be downgraded once triggered.
void signalForceUpdate(String url) {
  if (appUpdate.value?.status == UpdateStatus.force) return;
  appUpdate.value = AppUpdate(UpdateStatus.force, url);
}
