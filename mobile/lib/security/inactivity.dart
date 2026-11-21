// Auto-wipe (no app PIN: the app opens straight after sign-in).
//
// The phone's offline data is erased when:
//   - the app hasn't been used for [WipePolicy.wipeAfter], or
//   - the server reports the account was deactivated (remote revoke).
// Erasing deletes the vault's data key, which makes any remaining ciphertext unreadable.
import '../offline/vault.dart';

/// Defaults can be tuned per build, e.g. `--dart-define=WIPE_AFTER_DAYS=7`.
class WipePolicy {
  static const wipeAfter = Duration(days: int.fromEnvironment('WIPE_AFTER_DAYS', defaultValue: 14));
}

/// Why the phone's data was erased (shown on the sign-in screen afterwards).
enum WipeReason { inactivity, revoked }

String wipeMessage(WipeReason r) => switch (r) {
      WipeReason.inactivity =>
        'This phone\'s offline data was erased after ${WipePolicy.wipeAfter.inDays} days without use. Sign in again.',
      WipeReason.revoked => 'Your account was deactivated, so this phone\'s data was erased. Contact your admin.',
    };

/// When the app was last used, kept in the platform keystore (not ordinary app storage) so it
/// can't be reset by editing the app's files.
class Inactivity {
  // Same key the old PIN lock used, so phones updated from a PIN build keep their history.
  static const _lastUseKey = 'checkin.lastUnlockAt';
  // Left behind by PIN builds; deleted on first use of this one.
  static const _oldPinKeys = ['checkin.pin.v1', 'checkin.pin.failures', 'checkin.pin.biometric'];

  final KeyStore ks;
  Inactivity(this.ks);

  Future<void> markUsed([DateTime? at]) => ks.write(_lastUseKey, (at ?? DateTime.now()).toUtc().toIso8601String());

  Future<DateTime?> lastUse() async {
    final v = await ks.read(_lastUseKey);
    return v == null ? null : DateTime.tryParse(v);
  }

  /// Unused for longer than [WipePolicy.wipeAfter]? (Never true before the first use.)
  Future<bool> expired([DateTime? now]) async {
    final last = await lastUse();
    return last != null && (now ?? DateTime.now()).difference(last) > WipePolicy.wipeAfter;
  }

  /// Signed out or wiped: forget the last use, and any PIN left by an older build.
  Future<void> clear() async {
    for (final k in [_lastUseKey, ..._oldPinKeys]) {
      await ks.delete(k);
    }
  }

  Future<void> dropOldPin() async {
    for (final k in _oldPinKeys) {
      await ks.delete(k);
    }
  }
}
