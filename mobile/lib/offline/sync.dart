// Connectivity status and the outbox: writes made without signal are queued on the phone
// and replayed in order when the connection returns. Each carries an Idempotency-Key (so a
// retry never double-counts) and X-Recorded-At (so the server keeps the real time).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'store.dart';
import 'vault.dart';

/// True for failures where the request never got a usable answer (no signal, DNS, timeout).
bool isNetworkError(Object e) =>
    e is http.ClientException || e is TimeoutException || e.toString().contains('SocketException');

class NetStatus extends ChangeNotifier {
  bool online = true;

  /// When the data on screen was last fetched, if it came from the local cache.
  DateTime? showingCacheFrom;

  void markOnline() {
    if (!online || showingCacheFrom != null) {
      online = true;
      showingCacheFrom = null;
      notifyListeners();
      outbox.flush();
    }
  }

  void markOffline({DateTime? cacheFrom}) {
    final changed = online || (cacheFrom != null && showingCacheFrom != cacheFrom);
    online = false;
    if (cacheFrom != null && (showingCacheFrom == null || cacheFrom.isBefore(showingCacheFrom!))) {
      showingCacheFrom = cacheFrom;
    }
    if (changed) notifyListeners();
  }
}

final netStatus = NetStatus();

enum OutboxState { pending, failed }

class OutboxItem {
  final String id, userId, method, path, label;

  /// Groups items for display, e.g. 'checkin', 'mobilization', 'station:MGR-001'.
  final String scope;
  final Map<String, dynamic>? body;
  final DateTime recordedAt;
  OutboxState state;
  String? error;
  int attempts;

  OutboxItem({
    required this.id,
    required this.userId,
    required this.method,
    required this.path,
    required this.label,
    required this.scope,
    required this.body,
    required this.recordedAt,
    this.state = OutboxState.pending,
    this.error,
    this.attempts = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'user': userId,
        'method': method,
        'path': path,
        'label': label,
        'scope': scope,
        'body': body,
        'at': recordedAt.toUtc().toIso8601String(),
        'state': state.name,
        'error': error,
        'attempts': attempts,
      };

  factory OutboxItem.fromJson(Map<String, dynamic> j) => OutboxItem(
        id: j['id'],
        userId: j['user'],
        method: j['method'],
        path: j['path'],
        label: j['label'],
        scope: j['scope'] ?? '',
        body: (j['body'] as Map?)?.cast<String, dynamic>(),
        recordedAt: DateTime.parse(j['at']).toLocal(),
        state: j['state'] == 'failed' ? OutboxState.failed : OutboxState.pending,
        error: j['error'],
        attempts: j['attempts'] ?? 0,
      );

  Map<String, String> get headers => {'Idempotency-Key': id, 'X-Recorded-At': recordedAt.toUtc().toIso8601String()};
}

class SyncedEntry {
  final String label;
  final DateTime recordedAt, syncedAt;
  final bool duplicate;
  SyncedEntry(this.label, this.recordedAt, this.syncedAt, this.duplicate);
  Map<String, dynamic> toJson() =>
      {'label': label, 'at': recordedAt.toIso8601String(), 'synced': syncedAt.toIso8601String(), 'dup': duplicate};
  factory SyncedEntry.fromJson(Map<String, dynamic> j) =>
      SyncedEntry(j['label'], DateTime.parse(j['at']), DateTime.parse(j['synced']), j['dup'] ?? false);
}

/// Sends one queued request; returns normally on success or throws (ApiException / network error).
typedef OutboxSender = Future<dynamic> Function(OutboxItem item);

/// Classifies a failed send: should the queue stop (try later) or park this item as failed?
typedef FailureClassifier = ({bool stop, bool duplicate, String? message}) Function(Object error);

class Outbox extends ChangeNotifier {
  static const _key = Vault.legacyOutbox;
  static const _logKey = Vault.legacyOutboxLog;
  final List<OutboxItem> _items = [];
  final List<SyncedEntry> _log = [];
  bool _loaded = false;
  bool syncing = false;
  DateTime? lastSyncAt;
  String? currentUser;
  OutboxSender? sender;
  FailureClassifier? classify;
  Timer? _timer;

  List<OutboxItem> get mine => _items.where((i) => i.userId == currentUser).toList();
  List<OutboxItem> get pending => mine.where((i) => i.state == OutboxState.pending).toList();
  List<OutboxItem> get failed => mine.where((i) => i.state == OutboxState.failed).toList();
  List<SyncedEntry> get recent => List.unmodifiable(_log.reversed);
  int get waitingCount => pending.length;

  /// Items still waiting that touch this scope (e.g. one station).
  List<OutboxItem> forScope(String scope) => mine.where((i) => i.scope == scope).toList();

  Future<void> load() async {
    if (_loaded) return;
    try {
      _items.addAll([
        for (final j in jsonDecode(await vault.read('outbox', _key) ?? '[]') as List) OutboxItem.fromJson(j),
      ]);
      _log.addAll([
        for (final j in jsonDecode(await vault.read('outbox', _logKey) ?? '[]') as List) SyncedEntry.fromJson(j),
      ]);
    } catch (_) {
      // A corrupt store must never block the app; start clean.
    }
    _loaded = true;
    // Retry periodically while anything is waiting.
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (pending.isNotEmpty) flush();
    });
    notifyListeners();
  }

  Future<void> _persist() async {
    while (_log.length > 50) {
      _log.removeAt(0);
    }
    await vault.write('outbox', _key, jsonEncode([for (final i in _items) i.toJson()]));
    await vault.write('outbox', _logKey, jsonEncode([for (final e in _log) e.toJson()]));
  }

  Future<void> add(OutboxItem item) async {
    await load();
    _items.add(item);
    await _persist();
    notifyListeners();
  }

  /// Forget everything in memory (the vault has already been erased).
  void resetAfterWipe() {
    _items.clear();
    _log.clear();
    lastSyncAt = null;
    notifyListeners();
  }

  Future<void> discard(OutboxItem item) async {
    _items.remove(item);
    await _persist();
    notifyListeners();
  }

  /// Retry with corrected fields. A changed request needs a fresh Idempotency-Key —
  /// the old key would replay the server's earlier rejection — but keeps the original time.
  Future<void> editAndRetry(OutboxItem item, Map<String, dynamic> changes) async {
    final i = _items.indexOf(item);
    if (i < 0) return;
    _items[i] = OutboxItem(
      id: newId(),
      userId: item.userId,
      method: item.method,
      path: item.path,
      label: item.label,
      scope: item.scope,
      body: {...?item.body, ...changes},
      recordedAt: item.recordedAt,
    );
    await _persist();
    notifyListeners();
    await flush();
  }

  Future<void> retry(OutboxItem item) async {
    item.state = OutboxState.pending;
    item.error = null;
    await _persist();
    notifyListeners();
    await flush();
  }

  /// Sends waiting items oldest-first. Stops at the first network/server problem so order is kept.
  Future<void> flush() async {
    await load();
    if (syncing || sender == null || currentUser == null) return;
    final queue = pending;
    if (queue.isEmpty) return;
    syncing = true;
    notifyListeners();
    try {
      for (final item in queue) {
        item.attempts++;
        try {
          await sender!(item);
          _items.remove(item);
          _log.add(SyncedEntry(item.label, item.recordedAt, DateTime.now(), false));
        } catch (e) {
          final c = classify!(e);
          if (c.stop) break;
          if (c.duplicate) {
            _items.remove(item);
            _log.add(SyncedEntry(item.label, item.recordedAt, DateTime.now(), true));
          } else {
            item.state = OutboxState.failed;
            item.error = c.message;
          }
        } finally {
          await _persist();
          notifyListeners();
        }
      }
      if (pending.isEmpty) lastSyncAt = DateTime.now();
    } finally {
      syncing = false;
      notifyListeners();
    }
  }
}

final outbox = Outbox();
