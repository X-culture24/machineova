import 'package:flutter/foundation.dart';

import 'api/client.dart';
import 'api/models.dart';
import 'offline/prefetch.dart';
import 'offline/store.dart';
import 'offline/sync.dart';
import 'offline/vault.dart';
import 'security/app_lock.dart';

/// Holds the signed-in user; the app rebuilds between sign-in, PIN, lock and the shell when it changes.
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

  void _pickMode() => opsMode = me != null && me!.hasOps && !me!.hasCheckin;

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
        await _activate(await api.me());
      } catch (e) {
        // No signal: open with the last profile so field work can continue offline.
        final cached = isNetworkError(e) ? await api.cachedMe() : null;
        if (cached != null) {
          await _activate(cached);
        } else if (me == null) {
          await api.logout();
        }
      }
    }
    // Locked on every launch; erased if unused past the policy limit.
    if (me != null && await appLock.onSessionStart(restored: true) != null) {
      restoring = false;
      notifyListeners();
      return;
    }
    restoring = false;
    notifyListeners();
    if (me != null) {
      outbox.flush();
      prefetchForOffline();
    }
  }

  Future<void> signIn(String login, String password) async {
    await _activate(await api.login(login, password));
    wiped = null;
    await appLock.onSessionStart(restored: false); // asks for a new PIN
    notifyListeners();
    outbox.flush();
    prefetchForOffline();
  }

  /// Queued records stay on the phone and sync the next time this user signs in.
  Future<void> signOut() async {
    await api.logout();
    await appLock.reset();
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
    await appLock.reset();
    me = null;
    api.userId = null;
    outbox.currentUser = null;
    wiped = reason;
    restoring = false;
    notifyListeners();
  }
}

final session = Session();
final appLock = AppLock(PinStore(vault.keyStore), onWipe: session.wipe);
