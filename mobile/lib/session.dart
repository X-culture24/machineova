import 'package:flutter/foundation.dart';

import 'api/client.dart';
import 'api/models.dart';
import 'offline/prefetch.dart';
import 'offline/store.dart';
import 'offline/sync.dart';
import 'offline/vault.dart';
import 'security/inactivity.dart';

/// Holds the signed-in user; the app rebuilds between sign-in and the shell when it changes.
class Session extends ChangeNotifier {
  Me? me;
  bool restoring = true;

  /// Set when the phone's data was erased, so the sign-in screen can say why.
  WipeReason? wiped;

  /// Which workspace the app shows: Election Ops (field roles) or Checkin.
  bool opsMode = false;

  void setOpsMode(bool v) {
    opsMode = v;
    notifyListeners();
    prefetchForOffline();
  }

  void _pickMode() => opsMode = false; // the field app is check-in and mobilize only

  Future<void> _activate(Me m) async {
    me = m;
    api.userId = m.id;
    outbox.currentUser = m.id;
    _pickMode();
    await outbox.load();
    await responseCache.clearOthers(m.id);
  }

  Future<void> restore() async {
    api.onUnauthorized = signOut;
    api.onRevoked = () => wipe(WipeReason.revoked);
    await api.loadToken();
    await outbox.load();
    if (api.hasToken) {
      try {
        final m = await api.me();
        if (!m.isFieldAgent) throw const NotFieldAgent();
        await _activate(m);
      } catch (e) {
        // No signal: open with the last profile so field work can continue offline.
        final cached = isNetworkError(e) ? await api.cachedMe() : null;
        if (cached != null && cached.isFieldAgent) {
          await _activate(cached);
        } else if (me == null) {
          await api.logout();
        }
      }
    }
    // Erased if unused past the policy limit; otherwise this launch counts as use.
    if (me != null) {
      if (await inactivity.expired()) {
        await wipe(WipeReason.inactivity);
        return;
      }
      await inactivity.dropOldPin();
      await inactivity.markUsed();
    }
    restoring = false;
    notifyListeners();
    if (me != null) {
      outbox.flush();
      prefetchForOffline();
    }
  }

  Future<void> signIn(String login, String password) async {
    final m = await api.login(login, password);
    if (!m.isFieldAgent) {
      await api.logout();
      throw const NotFieldAgent();
    }
    await _activate(m);
    wiped = null;
    await inactivity.markUsed();
    notifyListeners();
    outbox.flush();
    prefetchForOffline();
  }

  /// Queued records stay on the phone and sync the next time this user signs in.
  Future<void> signOut() async {
    await api.logout();
    await inactivity.clear();
    me = null;
    api.userId = null;
    outbox.currentUser = null;
    notifyListeners();
  }

  /// Erases all offline data on this phone — including records not yet synced — and signs out.
  Future<void> wipe(WipeReason reason) async {
    await vault.wipeAll();
    outbox.resetAfterWipe();
    ledger.resetAfterWipe();
    responseCache.resetAfterWipe();
    await inactivity.clear();
    me = null;
    api.userId = null;
    outbox.currentUser = null;
    wiped = reason;
    restoring = false;
    notifyListeners();
  }
}

final session = Session();
final inactivity = Inactivity(vault.keyStore);

/// Thrown when someone other than a field agent signs in to the field app.
class NotFieldAgent implements Exception {
  const NotFieldAgent();
  @override
  String toString() =>
      'This app is for field agents. Managers, admins and candidates sign in on the web dashboard.';
}
