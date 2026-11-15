import 'dart:async';

import 'package:ssb_runner/audio/audio_output_monitor.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:ssb_runner/ui/main_app/window_geometry.dart';
import 'package:window_manager/window_manager.dart';

/// Feeds window visibility into [AudioOutputMonitor].
///
/// Reuses the existing window discovery (`resolveAppWindow`) instead of a second
/// lookup; when no handle can be found the monitor keeps polling at the full
/// rate, which is the safe direction (design §4.1.1).
class WindowManagerVisibility implements AudioWindowVisibility {
  WindowManagerVisibility(this._window) {
    _listenerId = _window.addListener(_onWindowEvent);
  }

  /// Returns `null` when the window cannot be resolved.
  static WindowManagerVisibility? attach() {
    try {
      final window = resolveAppWindow();
      if (window == null) return null;
      return WindowManagerVisibility(window);
    } catch (error, stackTrace) {
      log.warn(
        'window visibility unavailable',
        tag: 'audio.monitor',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  final Window _window;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();
  ListenerId? _listenerId;
  bool? _lastVisible;

  @override
  bool get isVisible {
    final visible = _readVisible();
    _lastVisible = visible;
    return visible;
  }

  @override
  Stream<bool> get changes => _changes.stream;

  /// `unknown` occlusion counts as visible: never downgrade the poll rate on a
  /// platform that cannot answer.
  bool _readVisible() {
    try {
      if (_window.isMinimized) return false;
      return _window.occlusionState != WindowOcclusionState.occluded;
    } catch (_) {
      return true;
    }
  }

  void _onWindowEvent(WindowEvent event) {
    if (event is! WindowMinimizedEvent &&
        event is! WindowRestoredEvent &&
        event is! WindowOcclusionChangedEvent) {
      return;
    }
    final visible = _readVisible();
    if (visible == _lastVisible) return;
    _lastVisible = visible;
    if (!_changes.isClosed) _changes.add(visible);
  }

  @override
  Future<void> dispose() async {
    final listenerId = _listenerId;
    _listenerId = null;
    if (listenerId != null) {
      try {
        _window.removeListener(listenerId);
      } catch (_) {
        // The window may already be gone during exit.
      }
    }
    await _changes.close();
  }
}
