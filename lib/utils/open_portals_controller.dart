import 'package:flutter/foundation.dart';

/// In-memory controller that keeps track of which sensor portals (WebViews)
/// have been opened during the current app session.
///
/// Goals:
/// - When the user taps a sensor in the Dashboard:
///   - if it's the first time, create/show its portal
///   - if it was opened before, bring it back instantly (keeping state)
/// - Keep portals alive in the background (handled by an IndexedStack)
/// - No backend persistence (session-only)
class OpenPortalsController extends ChangeNotifier {
  final List<OpenPortalEntry> _opened = [];
  String? _activeSensorId;

  List<OpenPortalEntry> get opened => List.unmodifiable(_opened);
  String? get activeSensorId => _activeSensorId;

  bool get hasActivePortal => _activeSensorId != null;

  int indexOfSensor(String sensorId) => _opened.indexWhere((e) => e.sensorId == sensorId);

  OpenPortalEntry? entryFor(String sensorId) {
    final idx = indexOfSensor(sensorId);
    if (idx < 0) return null;
    return _opened[idx];
  }

  /// Open (or re-activate) a portal for a sensor.
  ///
  /// Important: if the portal was already opened before, we *keep the original
  /// URL* by default to avoid forcing a reload (which would lose the web
  /// session/state). This matters when the backend returns a slightly different
  /// URL over time (e.g., tokenized links).
  void openOrActivate({required String sensorId, required String url, String? title}) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) return;

    final idx = indexOfSensor(sensorId);
    if (idx < 0) {
      _opened.add(OpenPortalEntry(sensorId: sensorId, url: trimmedUrl, title: title));
    } else {
      // Preserve URL to keep the existing WebView session alive.
      // Only update URL if it was previously empty.
      final existing = _opened[idx];
      final shouldUpdateUrl = existing.url.trim().isEmpty;
      if (!shouldUpdateUrl && existing.url.trim() != trimmedUrl) {
        debugPrint(
          'OpenPortalsController: ignoring URL change for $sensorId to preserve session. '
          'existing=${existing.url} new=$trimmedUrl',
        );
      }

      _opened[idx] = existing.copyWith(url: shouldUpdateUrl ? trimmedUrl : existing.url, title: title ?? existing.title);
    }
    _activeSensorId = sensorId;
    notifyListeners();
  }

  /// Explicitly refresh a portal URL (this WILL cause the WebView to reload).
  ///
  /// Use this only when you intentionally want to reset the session.
  void forceUpdateUrl({required String sensorId, required String url}) {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) return;
    final idx = indexOfSensor(sensorId);
    if (idx < 0) {
      _opened.add(OpenPortalEntry(sensorId: sensorId, url: trimmedUrl));
    } else {
      _opened[idx] = _opened[idx].copyWith(url: trimmedUrl);
    }
    notifyListeners();
  }

  /// Return to the Dashboard view (without closing portals).
  void showDashboard() {
    if (_activeSensorId == null) return;
    _activeSensorId = null;
    notifyListeners();
  }

  /// Close the currently active portal (keeps others open).
  void closeActive() {
    final active = _activeSensorId;
    if (active == null) return;
    _activeSensorId = null;
    notifyListeners();
  }

  /// Close (dispose) a portal completely.
  ///
  /// This removes it from the in-memory cache. The corresponding WebView widget
  /// will unmount and the web session will be lost.
  ///
  /// Use this when the portal itself requests to close (e.g., via JS message
  /// `Nativo.postMessage('fecharWebView')`).
  void closePortal(String sensorId) {
    debugPrint('OpenPortalsController.closePortal($sensorId) called. active=$_activeSensorId opened=${_opened.length}');
    final idx = indexOfSensor(sensorId);
    if (idx < 0) {
      // Still make sure we leave portal mode if this was the active one.
      if (_activeSensorId == sensorId) {
        _activeSensorId = null;
        debugPrint('OpenPortalsController.closePortal: sensor not found, cleared active. opened=${_opened.length}');
        notifyListeners();
      }
      return;
    }

    _opened.removeAt(idx);
    if (_activeSensorId == sensorId) _activeSensorId = null;
    debugPrint('OpenPortalsController.closePortal: removed. active=$_activeSensorId opened=${_opened.length}');
    notifyListeners();
  }

  /// Clear all opened portals (e.g., on logout).
  void clear() {
    _opened.clear();
    _activeSensorId = null;
    notifyListeners();
  }
}

@immutable
class OpenPortalEntry {
  const OpenPortalEntry({required this.sensorId, required this.url, this.title});

  final String sensorId;
  final String url;
  final String? title;

  OpenPortalEntry copyWith({String? sensorId, String? url, String? title}) {
    return OpenPortalEntry(sensorId: sensorId ?? this.sensorId, url: url ?? this.url, title: title ?? this.title);
  }
}
