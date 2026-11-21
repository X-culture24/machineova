import 'package:checkin_mobile/offline/vault.dart';
import 'package:checkin_mobile/security/inactivity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('never used: no wipe', () async {
    expect(await Inactivity(MemoryKeyStore()).expired(), isFalse);
  });

  test('used recently: no wipe; unused past the limit: wipe', () async {
    final i = Inactivity(MemoryKeyStore());
    final now = DateTime.now();
    await i.markUsed(now.subtract(const Duration(days: 3)));
    expect(await i.expired(now), isFalse);
    await i.markUsed(now.subtract(WipePolicy.wipeAfter + const Duration(hours: 1)));
    expect(await i.expired(now), isTrue);
  });

  test('a PIN left by an older build is removed; the last use is kept', () async {
    final ks = MemoryKeyStore();
    await ks.write('checkin.pin.v1', 'old-hash');
    await ks.write('checkin.pin.failures', '3');
    final i = Inactivity(ks);
    await i.markUsed();
    await i.dropOldPin();
    expect(await ks.read('checkin.pin.v1'), isNull);
    expect(await ks.read('checkin.pin.failures'), isNull);
    expect(await i.lastUse(), isNotNull);
  });

  test('sign out forgets the last use', () async {
    final i = Inactivity(MemoryKeyStore());
    await i.markUsed();
    await i.clear();
    expect(await i.lastUse(), isNull);
  });
}
