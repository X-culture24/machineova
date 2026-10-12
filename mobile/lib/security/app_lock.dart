// App PIN lock and auto-wipe.
//
// The PIN gates the app; it is stored only as a salted PBKDF2-HMAC-SHA256 hash. The hash, the
// failed-attempt counter and the last-unlock time live in the platform keystore (not ordinary
// app storage), so they can't be reset by editing the app's files.
//
// The phone's offline data is erased when:
//   - the PIN is entered wrong [LockPolicy.maxAttempts] times in a row,
//   - the app hasn't been unlocked for [LockPolicy.wipeAfter], or
//   - the server reports the account was deactivated (remote revoke).
// Erasing deletes the vault's data key, which makes any remaining ciphertext unreadable.
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../offline/vault.dart';

/// Defaults can be tuned per build, e.g. `--dart-define=WIPE_AFTER_DAYS=7`.
class LockPolicy {
  static const lockAfter = Duration(seconds: int.fromEnvironment('LOCK_AFTER_SECONDS', defaultValue: 120));
  static const wipeAfter = Duration(days: int.fromEnvironment('WIPE_AFTER_DAYS', defaultValue: 14));
  static const maxAttempts = int.fromEnvironment('MAX_PIN_ATTEMPTS', defaultValue: 10);

  /// From this many failures, each further try waits 30 s, doubling (30 s, 1 min, 2 min…).
  static const delayFrom = 5;
  static const pinMin = 4, pinMax = 6;
  static const iterations = int.fromEnvironment('PIN_KDF_ITERATIONS', defaultValue: 120000);
}

/// Why the phone's data was erased (shown on the sign-in screen afterwards).
enum WipeReason { tooManyAttempts, inactivity, revoked }

String wipeMessage(WipeReason r) => switch (r) {
      WipeReason.tooManyAttempts => 'Too many wrong PINs — this phone\'s offline data was erased. Sign in again.',
      WipeReason.inactivity =>
        'This phone\'s offline data was erased after ${LockPolicy.wipeAfter.inDays} days without use. Sign in again.',
      WipeReason.revoked => 'Your account was deactivated, so this phone\'s data was erased. Contact your admin.',
    };

/// Rejects PINs that are trivially guessed (all one digit, or a straight run like 1234 / 9876).
String? pinProblem(String pin) {
  if (pin.length < LockPolicy.pinMin || pin.length > LockPolicy.pinMax || !RegExp(r'^\d+$').hasMatch(pin)) {
    return 'Use ${LockPolicy.pinMin}–${LockPolicy.pinMax} digits';
  }
  if (pin.split('').toSet().length == 1) return 'Too easy to guess — avoid repeating one digit';
  final d = pin.codeUnits.map((c) => c - 48).toList();
  bool run(int step) => [for (var i = 1; i < d.length; i++) d[i] - d[i - 1]].every((x) => x == step);
  if (run(1) || run(-1)) return 'Too easy to guess — avoid sequences like 1234';
  return null;
}

/// Keystore-backed PIN record and attempt bookkeeping.
class PinStore {
  static const _pinKey = 'checkin.pin.v1';
  static const _failKey = 'checkin.pin.failures';
  static const _unlockKey = 'checkin.lastUnlockAt';
  static const _bioKey = 'checkin.pin.biometric';

  final KeyStore ks;
  final int iterations;
  PinStore(this.ks, {this.iterations = LockPolicy.iterations});

  Future<List<int>> _derive(String pin, List<int> salt, int iters) async {
    final kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iters, bits: 256);
    final key = await kdf.deriveKeyFromPassword(password: pin, nonce: salt);
    return key.extractBytes();
  }

  Future<bool> hasPin() async => await ks.read(_pinKey) != null;

  Future<void> setPin(String pin) async {
    final r = Random.secure();
    final salt = List<int>.generate(16, (_) => r.nextInt(256));
    final hash = await _derive(pin, salt, iterations);
    await ks.write(_pinKey, jsonEncode({'salt': base64Encode(salt), 'hash': base64Encode(hash), 'iter': iterations}));
    await ks.delete(_failKey);
  }

  Future<int> failures() async => int.tryParse(await ks.read(_failKey) ?? '') ?? 0;

  /// Checks the PIN; on failure bumps the persistent counter. Returns true on match.
  Future<bool> verify(String pin) async {
    final raw = await ks.read(_pinKey);
    if (raw == null) return false;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final got = await _derive(pin, base64Decode(m['salt']), m['iter'] as int);
    final want = base64Decode(m['hash']);
    var diff = got.length ^ want.length;
    for (var i = 0; i < min(got.length, want.length); i++) {
      diff |= got[i] ^ want[i]; // constant-time compare
    }
    if (diff == 0) {
      await ks.delete(_failKey);
      return true;
    }
    await ks.write(_failKey, '${await failures() + 1}');
    return false;
  }

  /// Wait before the next try, given the number of failures so far.
  static Duration delayFor(int failures) =>
      failures < LockPolicy.delayFrom ? Duration.zero : Duration(seconds: 30 << (failures - LockPolicy.delayFrom));

  Future<void> markUnlocked([DateTime? at]) => ks.write(_unlockKey, (at ?? DateTime.now()).toUtc().toIso8601String());

  Future<DateTime?> lastUnlock() async {
    final v = await ks.read(_unlockKey);
    return v == null ? null : DateTime.tryParse(v);
  }

  Future<bool> biometricEnabled() async => await ks.read(_bioKey) == 'on';
  Future<void> setBiometric(bool on) => on ? ks.write(_bioKey, 'on') : ks.delete(_bioKey);

  Future<void> clear() async {
    for (final k in [_pinKey, _failKey, _unlockKey, _bioKey]) {
      await ks.delete(k);
    }
  }
}

enum AppLockState { open, needsPin, locked }

/// Gatekeeper the app shell listens to: decides between the PIN setup, lock and app screens.
class AppLock extends ChangeNotifier {
  final PinStore pins;
  final Future<void> Function(WipeReason reason) onWipe;
  AppLock(this.pins, {required this.onWipe});

  AppLockState state = AppLockState.open;
  int failures = 0;
  DateTime? retryAt;
  DateTime? _backgroundedAt;

  int get attemptsLeft => LockPolicy.maxAttempts - failures;

  /// After sign-in or restore: lock (or ask for a new PIN) before any data is shown.
  /// Returns a wipe reason if the inactivity limit has passed.
  Future<WipeReason?> onSessionStart({required bool restored}) async {
    if (restored) {
      final last = await pins.lastUnlock();
      if (last != null && DateTime.now().difference(last) > LockPolicy.wipeAfter) {
        await onWipe(WipeReason.inactivity);
        return WipeReason.inactivity;
      }
    }
    failures = await pins.failures();
    _updateRetry();
    state = !await pins.hasPin() ? AppLockState.needsPin : (restored ? AppLockState.locked : AppLockState.open);
    if (state == AppLockState.open) await pins.markUnlocked();
    notifyListeners();
    return null;
  }

  Future<void> setPin(String pin) async {
    await pins.setPin(pin);
    await pins.markUnlocked();
    failures = 0;
    retryAt = null;
    state = AppLockState.open;
    notifyListeners();
  }

  void _updateRetry() {
    final d = PinStore.delayFor(failures);
    retryAt = d == Duration.zero ? null : DateTime.now().add(d);
  }

  /// Returns null on success, or a message for the lock screen.
  Future<String?> unlock(String pin) async {
    if (retryAt != null && DateTime.now().isBefore(retryAt!)) return 'Wait before trying again';
    if (await pins.verify(pin)) {
      await _opened();
      return null;
    }
    failures = await pins.failures();
    if (failures >= LockPolicy.maxAttempts) {
      await onWipe(WipeReason.tooManyAttempts);
      return wipeMessage(WipeReason.tooManyAttempts);
    }
    _updateRetry();
    notifyListeners();
    final left = attemptsLeft;
    return left <= 3
        ? 'Wrong PIN — $left attempt${left == 1 ? '' : 's'} left before this phone\'s data is erased'
        : 'Wrong PIN';
  }

  /// Unlock after a successful biometric check (does not bypass the wipe counter's history).
  Future<void> unlockWithBiometric() => _opened();

  Future<void> _opened() async {
    await pins.markUnlocked();
    failures = 0;
    retryAt = null;
    state = AppLockState.open;
    notifyListeners();
  }

  /// Password confirmed online (forgot PIN): drop the old PIN and ask for a new one.
  Future<void> requireNewPin() async {
    await pins.clear();
    failures = 0;
    retryAt = null;
    state = AppLockState.needsPin;
    notifyListeners();
  }

  void lockNow() {
    if (state == AppLockState.open) {
      state = AppLockState.locked;
      notifyListeners();
    }
  }

  void onBackground([DateTime? at]) => _backgroundedAt = at ?? DateTime.now();

  void onForeground() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    final away = since == null ? Duration.zero : DateTime.now().difference(since);
    if (state == AppLockState.open && away >= LockPolicy.lockAfter) {
      lockNow();
    }
  }

  /// Signed out or wiped: the next user sets their own PIN.
  Future<void> reset() async {
    await pins.clear();
    state = AppLockState.open;
    failures = 0;
    retryAt = null;
    notifyListeners();
  }
}
