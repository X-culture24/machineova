import 'dart:convert';

import 'package:http/http.dart' as http;

import '../offline/store.dart';
import '../offline/sync.dart';
import '../offline/vault.dart';
import 'models.dart';

/// API base URL. Defaults to the Android emulator's alias for the host machine.
/// Override with: flutter run --dart-define=API_URL=https://api.example.com
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8080');

class ApiException implements Exception {
  final int status;
  final String message;
  final String? code;
  final Map<String, dynamic> body;
  ApiException(this.status, this.message, this.code, this.body);
  @override
  String toString() => message;
}

/// No signal and nothing saved on the phone for this screen yet.
class OfflineException implements Exception {
  @override
  String toString() => "You're offline and this hasn't been loaded on this phone yet. Connect once to download it.";
}

/// Outcome of a write: sent now, or saved on the phone to sync later.
class SendResult {
  final bool queued;
  final dynamic data; // server response when sent now (null if queued)
  const SendResult.sent(this.data) : queued = false;
  const SendResult.queued()
      : queued = true,
        data = null;
}

class ApiClient {
  final http.Client _http = http.Client();
  String? _token;

  /// Signed-in user; scopes the response cache and the outbox.
  String? userId;

  /// Called when the server rejects our token, so the app can return to sign-in.
  void Function()? onUnauthorized;

  /// Called when the server says the account was deactivated — the app erases its data.
  void Function()? onRevoked;

  ApiClient() {
    outbox.sender = (item) => _req(item.method, item.path, body: item.body, headers: item.headers);
    outbox.classify = _classify;
  }

  bool get hasToken => _token != null;

  // The session token lives in the platform keystore; the profile in the encrypted vault.
  Future<void> loadToken() async {
    await vault.open();
    _token = await vault.readSecret(Vault.legacyToken);
  }

  Future<void> _saveToken(String? t) async {
    _token = t;
    await vault.writeSecret(Vault.legacyToken, t);
  }

  Future<void> _saveMe(Map<String, dynamic> raw) => vault.write('profile', Vault.legacyMe, jsonEncode(raw));

  /// The last signed-in profile, so the app can open without signal.
  Future<Me?> cachedMe() async {
    final raw = await vault.read('profile', Vault.legacyMe);
    return raw == null ? null : Me.fromJson(jsonDecode(raw));
  }

  /// Raw JSON request (no cache, no queue).
  Future<dynamic> request(String method, String path, {Map<String, String?>? query, Object? body}) =>
      _req(method, path, query: query, body: body);

  Future<dynamic> _req(String method, String path,
      {Map<String, String?>? query, Object? body, Map<String, String>? headers}) async {
    final params = _params(query);
    final uri = Uri.parse('$apiUrl$path').replace(queryParameters: params.isEmpty ? null : params);
    final req = http.Request(method, uri);
    if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
    if (headers != null) req.headers.addAll(headers);
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final http.Response res;
    try {
      res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 20)));
    } catch (e) {
      if (isNetworkError(e)) netStatus.markOffline();
      rethrow;
    }
    netStatus.markOnline();
    if (res.statusCode == 204) return null;
    final data = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body);
    if (res.statusCode >= 400) {
      final m = data is Map<String, dynamic> ? data : <String, dynamic>{};
      if (res.statusCode == 401 && path != '/api/auth/login') {
        if (m['code'] == 'account_inactive') {
          onRevoked?.call();
        } else {
          await _saveToken(null);
          onUnauthorized?.call();
        }
      }
      throw ApiException(res.statusCode, m['error'] ?? 'Request failed (${res.statusCode})', m['code'], m);
    }
    return data;
  }

  static Map<String, String> _params(Map<String, String?>? query) => {
        for (final e in (query ?? {}).entries)
          if (e.value != null && e.value!.isNotEmpty) e.key: e.value!
      };

  /// GET with offline fallback: fresh data is cached; with no signal the last copy is returned.
  Future<dynamic> get(String path, {Map<String, String?>? query}) async {
    final params = _params(query);
    final uid = userId ?? 'anon';
    try {
      final data = await _req('GET', path, query: query);
      await responseCache.put(uid, path, params, data);
      return data;
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      final c = await responseCache.get(uid, path, params);
      if (c == null) throw OfflineException();
      netStatus.markOffline(cacheFrom: c.savedAt);
      return c.data;
    }
  }

  /// Sends a write now, or — with no signal, or while older items are still waiting — saves it
  /// to the outbox. Validation errors from the server still throw [ApiException].
  Future<SendResult> send(String method, String path, Map<String, dynamic>? body,
      {required String label, required String scope}) async {
    final item = OutboxItem(
      id: newId(),
      userId: userId ?? 'anon',
      method: method,
      path: path,
      label: label,
      scope: scope,
      body: body,
      recordedAt: DateTime.now(),
    );
    if (outbox.pending.isNotEmpty) {
      // Keep the order of writes: queue behind what's waiting, then try to flush everything.
      await outbox.add(item);
      await outbox.flush();
      final stillWaiting = outbox.pending.any((i) => i.id == item.id);
      final failedNow = outbox.failed.where((i) => i.id == item.id).firstOrNull;
      if (failedNow != null) {
        await outbox.discard(failedNow);
        throw ApiException(400, failedNow.error ?? 'Rejected by the server', null, const {});
      }
      return stillWaiting ? const SendResult.queued() : const SendResult.sent(null);
    }
    try {
      return SendResult.sent(await _req(method, path, body: body, headers: item.headers));
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      await outbox.add(item);
      return const SendResult.queued();
    }
  }

  static ({bool stop, bool duplicate, String? message}) _classify(Object e) {
    if (e is ApiException) {
      if (e.code == 'already_checked_in' || e.code == 'already_mobilized') {
        return (stop: false, duplicate: true, message: e.message);
      }
      // Try again later: server trouble, session expired, or the original still in flight.
      if (e.status >= 500 || e.status == 401 || e.status == 408 || e.status == 429 || e.code == 'in_progress') {
        return (stop: true, duplicate: false, message: e.message);
      }
      return (stop: false, duplicate: false, message: e.message);
    }
    if (isNetworkError(e)) return (stop: true, duplicate: false, message: null);
    return (stop: false, duplicate: false, message: e.toString());
  }

  // ---- auth ----
  Future<Me> login(String login, String password) async {
    // Field phones may go days without signal, so ask for a longer-lived session.
    final r = await _req('POST', '/api/auth/login', body: {'login': login, 'password': password, 'remember': true});
    await _saveToken(r['token']);
    await _saveMe(r['user']);
    return Me.fromJson(r['user']);
  }

  Future<void> logout() => _saveToken(null);

  /// Confirms the signed-in user's password with the server (used to reset a forgotten PIN).
  Future<void> confirmPassword(String login, String password) async {
    final r = await _req('POST', '/api/auth/login', body: {'login': login, 'password': password, 'remember': true});
    if (r['user']?['id'] != userId) {
      throw ApiException(403, 'That password belongs to a different account', null, const {});
    }
    await _saveToken(r['token']);
  }

  Future<Me> me() async {
    final r = await _req('GET', '/api/me');
    await _saveMe(r);
    return Me.fromJson(r);
  }

  Future<void> changePassword(String current, String next) =>
      _req('POST', '/api/auth/change-password', body: {'current_password': current, 'new_password': next});

  // ---- home ----
  Future<HomeData> home() async => HomeData.fromJson(await get('/api/home'));

  // ---- events & check-in ----
  Future<List<EventItem>> events({bool activeOnly = false}) async {
    final r = await get('/api/events', query: {'active': activeOnly ? 'true' : null});
    return [for (final e in r['items'] as List) EventItem.fromJson(e)];
  }

  /// Register lookups need the server; callers handle the network error by going offline-mode.
  Future<Lookup> checkinLookup(String eventId, String nationalId) async => Lookup.fromJson(
      await _req('GET', '/api/checkins/lookup', query: {'event_id': eventId, 'national_id': nationalId}));

  Future<SendResult> checkin(String eventId, Map<String, String?> person, {required String label}) =>
      send('POST', '/api/checkins', {'event_id': eventId, ..._clean(person)}, label: label, scope: 'checkin:$eventId');

  Future<List<PersonRecord>> checkins({String? eventId, String? q}) async {
    final r = await get('/api/checkins', query: {'event_id': eventId, 'q': q});
    return [for (final p in r as List) PersonRecord.fromJson(p)];
  }

  // ---- drives & mobilization ----
  Future<List<Drive>> drives({bool activeOnly = false}) async {
    final r = await get('/api/drives', query: {'active': activeOnly ? 'true' : null});
    return [for (final d in r['items'] as List) Drive.fromJson(d)];
  }

  Future<Drive> drive(String id) async => Drive.fromJson((await get('/api/drives/$id'))['drive']);

  Future<Lookup> mobilizeLookup(String nationalId, {String? driveId}) async => Lookup.fromJson(await _req(
      'GET', '/api/mobilizations/lookup', query: {'national_id': nationalId, if (driveId != null) 'drive_id': driveId}));

  Future<SendResult> mobilize(String driveId, Map<String, String?> person, {required String label}) =>
      send('POST', '/api/mobilizations', {'drive_id': driveId, ..._clean(person)},
          label: label, scope: 'mobilization:$driveId');

  Future<List<PersonRecord>> mobilizations({String? driveId, String? q}) async {
    final r = await get('/api/mobilizations', query: {'drive_id': driveId, 'q': q});
    return [for (final p in r as List) PersonRecord.fromJson(p)];
  }

  // ---- insights ----
  Future<CheckinInsights> checkinInsights(String eventId) async =>
      CheckinInsights.fromJson(await get('/api/insights/checkins', query: {'event_id': eventId}));

  Future<MobilizationInsights> mobilizationInsights(String driveId) async =>
      MobilizationInsights.fromJson(await get('/api/insights/mobilization', query: {'drive_id': driveId}));

  static Map<String, String> _clean(Map<String, String?> m) => {
        for (final e in m.entries)
          if (e.value != null && e.value!.trim().isNotEmpty) e.key: e.value!.trim()
      };
}

final api = ApiClient();
