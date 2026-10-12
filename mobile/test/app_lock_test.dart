import 'package:checkin_mobile/offline/vault.dart';
import 'package:checkin_mobile/security/app_lock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late MemoryKeyStore ks;
  late List<WipeReason> wipes;
  late AppLock lock;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ks = MemoryKeyStore();
    wipes = [];
    // Low KDF cost keeps tests fast; production uses LockPolicy.iterations.
    lock = AppLock(PinStore(ks, iterations: 1000), onWipe: (r) async => wipes.add(r));
  });

  test('weak PINs are rejected', () {
    for (final p in ['123', '1234567', '0000', '1111', '1234', '9876', '12a4']) {
      expect(pinProblem(p), isNotNull, reason: p);
    }
    for (final p in ['2580', '7391', '904417']) {
      expect(pinProblem(p), isNull, reason: p);
    }
  });

  test('new sign-in asks for a PIN; restore with a PIN is locked', () async {
    await lock.onSessionStart(restored: false);
    expect(lock.state, AppLockState.needsPin);
    await lock.setPin('2580');
    expect(lock.state, AppLockState.open);

    final relaunch = AppLock(PinStore(ks, iterations: 1000), onWipe: (r) async => wipes.add(r));
    await relaunch.onSessionStart(restored: true);
    expect(relaunch.state, AppLockState.locked);
    expect(await relaunch.unlock('2580'), isNull);
    expect(relaunch.state, AppLockState.open);
  });

  test('PIN is stored only as a salted hash in the keystore', () async {
    await lock.setPin('2580');
    expect(ks.values.values.join(), isNot(contains('2580')));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty, reason: 'nothing PIN-related in ordinary app storage');
  });

  test('failures persist across restarts and back off from the 5th', () async {
    await lock.setPin('2580');
    for (var i = 0; i < 4; i++) {
      expect(await lock.unlock('0000'), 'Wrong PIN');
    }
    expect(lock.retryAt, isNull);
    await lock.unlock('0000'); // 5th
    expect(lock.retryAt, isNotNull);
    expect(await lock.unlock('2580'), 'Wait before trying again', reason: 'even the right PIN waits');

    final relaunch = AppLock(PinStore(ks, iterations: 1000), onWipe: (r) async => wipes.add(r));
    await relaunch.onSessionStart(restored: true);
    expect(relaunch.failures, 5, reason: 'killing the app does not reset the counter');
    expect(relaunch.retryAt, isNotNull);
  });

  test('backoff doubles: 30 s, 1 min, 2 min', () {
    expect(PinStore.delayFor(4), Duration.zero);
    expect(PinStore.delayFor(5), const Duration(seconds: 30));
    expect(PinStore.delayFor(6), const Duration(seconds: 60));
    expect(PinStore.delayFor(7), const Duration(seconds: 120));
  });

  test('10 wrong PINs erase the phone', () async {
    await lock.setPin('2580');
    final pins = PinStore(ks, iterations: 1000);
    for (var i = 0; i < LockPolicy.maxAttempts - 1; i++) {
      await pins.verify('0000'); // bypass UI delays
    }
    lock = AppLock(pins, onWipe: (r) async => wipes.add(r));
    await lock.onSessionStart(restored: true);
    expect(lock.retryAt, isNotNull, reason: 'the 10th try is delayed too');
    lock.retryAt = null; // skip the wait for the test
    expect(await lock.unlock('0000'), contains('erased'));
    expect(wipes, [WipeReason.tooManyAttempts]);
  });

  test('warning shows the attempts left near the limit', () async {
    await lock.setPin('2580');
    final pins = PinStore(ks, iterations: 1000);
    for (var i = 0; i < LockPolicy.maxAttempts - 3; i++) {
      await pins.verify('0000');
    }
    lock = AppLock(pins, onWipe: (r) async => wipes.add(r));
    await lock.onSessionStart(restored: true);
    lock.retryAt = null; // skip the wait for the test
    expect(await lock.unlock('0000'), contains('2 attempts left'));
  });

  test('unused past the limit erases on next launch', () async {
    await lock.setPin('2580');
    await PinStore(ks, iterations: 1000)
        .markUnlocked(DateTime.now().subtract(LockPolicy.wipeAfter + const Duration(hours: 1)));
    final reason = await lock.onSessionStart(restored: true);
    expect(reason, WipeReason.inactivity);
    expect(wipes, [WipeReason.inactivity]);
  });

  test('used recently: no wipe', () async {
    await lock.setPin('2580');
    await PinStore(ks, iterations: 1000).markUnlocked(DateTime.now().subtract(const Duration(days: 3)));
    expect(await lock.onSessionStart(restored: true), isNull);
    expect(wipes, isEmpty);
  });

  test('re-locks after time in the background, not after a quick switch', () async {
    await lock.onSessionStart(restored: false);
    await lock.setPin('2580');
    lock.onBackground(DateTime.now().subtract(const Duration(seconds: 10)));
    lock.onForeground();
    expect(lock.state, AppLockState.open);
    lock.onBackground(DateTime.now().subtract(LockPolicy.lockAfter + const Duration(seconds: 1)));
    lock.onForeground();
    expect(lock.state, AppLockState.locked);
  });

  test('vault wipe destroys the data key so old ciphertext is unreadable', () async {
    final v = Vault(ks);
    await v.write('outbox', 'outbox', '[{"name":"Joseph Kamau"}]');
    final prefs = await SharedPreferences.getInstance();
    final name = await v.storageName('outbox', 'outbox');
    final copy = prefs.getString(name)!; // attacker kept a copy
    await v.wipeAll();
    expect(prefs.getKeys().where((k) => k.startsWith(Vault.namePrefix)), isEmpty);
    await prefs.setString(name, copy);
    expect(await v.read('outbox', 'outbox'), isNull, reason: 'new key cannot open old data');
  });
}
