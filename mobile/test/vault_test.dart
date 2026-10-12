import 'dart:convert';

import 'package:checkin_mobile/offline/vault.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('round-trips values and stores no plaintext', () async {
    final v = Vault(MemoryKeyStore());
    await v.write('outbox', 'outbox', '{"national_id":"28651234","name":"Joseph Kamau"}');
    expect(await v.read('outbox', 'outbox'), contains('Joseph Kamau'));

    final prefs = await SharedPreferences.getInstance();
    final everything = prefs.getKeys().map((k) => '$k=${prefs.get(k)}').join('\n');
    expect(everything, isNot(contains('Joseph')));
    expect(everything, isNot(contains('28651234')));
    expect(everything, isNot(contains('outbox?')), reason: 'names are hashed');
  });

  test('each write uses a fresh nonce', () async {
    final v = Vault(MemoryKeyStore());
    final prefs = await SharedPreferences.getInstance();
    await v.write('g', 'n', 'same');
    final first = prefs.getString(await v.storageName('g', 'n'));
    await v.write('g', 'n', 'same');
    expect(prefs.getString(await v.storageName('g', 'n')), isNot(first));
  });

  test('tampered ciphertext is rejected and dropped', () async {
    final v = Vault(MemoryKeyStore());
    await v.write('g', 'n', 'secret');
    final prefs = await SharedPreferences.getInstance();
    final k = await v.storageName('g', 'n');
    final raw = base64Decode(prefs.getString(k)!.substring(3));
    raw[raw.length - 20] ^= 0x01;
    await prefs.setString(k, 'v1:${base64Encode(raw)}');
    expect(await v.read('g', 'n'), isNull);
    expect(prefs.getString(k), isNull);
  });

  test('data is unreadable without the keystore key (e.g. restored backup)', () async {
    await Vault(MemoryKeyStore()).write('profile', 'checkin.me', '{"id":"u1"}');
    final otherDevice = Vault(MemoryKeyStore()); // same prefs, different key
    expect(await otherDevice.read('profile', 'checkin.me'), isNull);
  });

  test('key persists in the keystore across launches', () async {
    final keys = MemoryKeyStore();
    await Vault(keys).write('g', 'n', 'kept');
    expect(await Vault(keys).read('g', 'n'), 'kept');
  });

  test('migrates plaintext data from the previous version', () async {
    SharedPreferences.setMockInitialValues({
      'checkin.token': 'jwt-abc',
      'checkin.me': '{"id":"u1","name":"Amina"}',
      'outbox': '[{"id":"x","label":"Check-in: Amina"}]',
      'ledger': '[]',
      'cache:u1:/api/events?': '{"at":"2026-10-11T09:00:00","data":{}}',
      'unrelated.setting': 'keep me',
    });
    final keys = MemoryKeyStore();
    final v = Vault(keys);
    await v.open();
    final prefs = await SharedPreferences.getInstance();

    expect(await keys.read('checkin.token'), 'jwt-abc', reason: 'token moves into the keystore');
    expect(prefs.getString('checkin.token'), isNull);
    expect(await v.read('profile', 'checkin.me'), contains('Amina'));
    expect(await v.read('outbox', 'outbox'), contains('Check-in: Amina'));
    for (final legacy in ['checkin.me', 'outbox', 'ledger', 'cache:u1:/api/events?']) {
      expect(prefs.getString(legacy), isNull, reason: '$legacy plaintext removed');
    }
    expect(prefs.getString('unrelated.setting'), 'keep me');
    final all = prefs.getKeys().map((k) => '${prefs.get(k)}').join();
    expect(all, isNot(contains('Amina')));
  });

  test('deleteGroups drops only matching groups', () async {
    final v = Vault(MemoryKeyStore());
    await v.write('cache.u1', '/a', '1');
    await v.write('cache.u2', '/a', '2');
    await v.write('outbox', 'outbox', '[]');
    await v.deleteGroups((g) => g.startsWith('cache.') && g != 'cache.u1');
    expect(await v.read('cache.u1', '/a'), '1');
    expect(await v.read('cache.u2', '/a'), isNull);
    expect(await v.read('outbox', 'outbox'), '[]');
  });
}
