import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Result of `navigator.storage.estimate()`.
class BrowserStorageEstimate {
  const BrowserStorageEstimate({this.quota, this.usage});

  final int? quota;
  final int? usage;

  double? get usedFraction {
    final quota = this.quota;
    final usage = this.usage;
    if (quota == null || usage == null || quota <= 0) {
      return null;
    }
    return usage / quota;
  }
}

JSObject? _storageManager() {
  final storage = (web.window.navigator as JSObject).getProperty<JSObject?>(
    'storage'.toJS,
  );
  return storage;
}

/// Reads the origin's storage quota and usage, or null when unavailable.
Future<BrowserStorageEstimate?> browserStorageEstimate() async {
  try {
    final storage = _storageManager();
    if (storage == null) {
      return null;
    }

    final estimate = await storage
        .callMethod<JSPromise<JSObject>>('estimate'.toJS)
        .toDart;
    return BrowserStorageEstimate(
      quota: estimate.getProperty<JSNumber?>('quota'.toJS)?.toDartInt,
      usage: estimate.getProperty<JSNumber?>('usage'.toJS)?.toDartInt,
    );
  } catch (_) {
    return null;
  }
}

/// Requests persistent storage. Returns null when the API is unavailable.
Future<bool?> requestPersistentStorage() async {
  try {
    final storage = _storageManager();
    if (storage == null) {
      return null;
    }

    final granted = await storage
        .callMethod<JSPromise<JSBoolean>>('persist'.toJS)
        .toDart;
    return granted.toDart;
  } catch (_) {
    return null;
  }
}

/// Whether the document is cross-origin isolated, which is what enables the
/// multi-threaded SoLoud AudioWorklet backend.
bool get isCrossOriginIsolated => web.window.crossOriginIsolated;
