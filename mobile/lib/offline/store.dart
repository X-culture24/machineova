// Local persistence for offline use: cached server responses and a small ledger of
// what this phone has recorded (for offline duplicate warnings).
import 'dart:convert';
import 'dart:math';

import 'vault.dart';

/// Random v4-style id for idempotency keys and outbox items.
String newId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class Cached {
  final dynamic data;
  final DateTime savedAt;
  Cached(this.data, this.savedAt);
}

/// Last good response per GET request, so screens still open with no signal.
class ResponseCache {
  final Map<String, Cached> _mem = {};

  /// Vault group per user, so one user's cache can be dropped without touching another's.
  static String _group(String userId) => 'cache.$userId';

  static String _name(String path, Map<String, String> query) {
    final q = query.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return '$path?${q.map((e) => '${e.key}=${e.value}').join('&')}';
  }

  Future<void> put(String userId, String path, Map<String, String> query, dynamic data) async {
    final name = _name(path, query);
    final c = Cached(data, DateTime.now());
    _mem['$userId|$name'] = c;
    await vault.write(_group(userId), name, jsonEncode({'at': c.savedAt.toIso8601String(), 'data': data}));
  }

  Future<Cached?> get(String userId, String path, Map<String, String> query) async {
    final name = _name(path, query);
    final hit = _mem['$userId|$name'];
    if (hit != null) return hit;
    final raw = await vault.read(_group(userId), name);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return _mem['$userId|$name'] = Cached(m['data'], DateTime.parse(m['at']));
    } catch (_) {
      return null;
    }
  }

  void resetAfterWipe() => _mem.clear();

  /// Drops cached data for every user except [keepUserId] (e.g. a shared phone).
  Future<void> clearOthers(String keepUserId) async {
    await vault.deleteGroups((g) => g.startsWith('cache.') && g != _group(keepUserId));
    _mem.removeWhere((k, _) => !k.startsWith('$keepUserId|'));
  }
}

/// What this phone has checked in / mobilized recently, so offline lookups can warn about repeats.
class Ledger {
  static const _key = Vault.legacyLedger;
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  Future<void> _load() async {
    if (_loaded) return;
    final raw = await vault.read('ledger', _key);
    if (raw != null) {
      try {
        _items = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      } catch (_) {
        _items = [];
      }
    }
    _loaded = true;
  }

  Future<void> _save() async {
    // Keep two days — enough for "already checked in today" and short offline spells.
    final cutoff = DateTime.now().subtract(const Duration(days: 2));
    _items.removeWhere((e) => DateTime.parse(e['at']).isBefore(cutoff));
    await vault.write('ledger', _key, jsonEncode(_items));
  }

  void resetAfterWipe() {
    _items = [];
    _loaded = false;
  }

  static String _day(DateTime t) => t.toIso8601String().substring(0, 10);

  Future<void> add(
      {required String kind, required String group, required String nationalId, required String name}) async {
    await _load();
    _items.add({'kind': kind, 'group': group, 'nid': nationalId, 'name': name, 'at': DateTime.now().toIso8601String()});
    await _save();
  }

  /// A check-in of this ID at this event today, recorded on this phone.
  Future<DateTime?> checkedInToday(String eventId, String nationalId) async {
    await _load();
    final today = _day(DateTime.now());
    for (final e in _items.reversed) {
      if (e['kind'] == 'checkin' &&
          e['group'] == eventId &&
          e['nid'] == nationalId &&
          _day(DateTime.parse(e['at'])) == today) {
        return DateTime.parse(e['at']);
      }
    }
    return null;
  }

  /// A mobilization of this ID by this phone (mobilization is once per organization).
  Future<DateTime?> mobilized(String nationalId) async {
    await _load();
    for (final e in _items.reversed) {
      if (e['kind'] == 'mobilization' && e['nid'] == nationalId) return DateTime.parse(e['at']);
    }
    return null;
  }
}

final responseCache = ResponseCache();
final ledger = Ledger();
