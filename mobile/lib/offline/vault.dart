// Encrypted on-device storage for everything the app keeps offline.
//
// - A random 256-bit data key is generated on first run and kept in the platform keystore
//   (Android Keystore-backed encrypted prefs / iOS Keychain, this-device-only).
// - Values are sealed with AES-256-GCM (random 96-bit nonce per write, authenticated) and the
//   ciphertext is stored in SharedPreferences. Without the keystore key it is unreadable —
//   e.g. from a device backup or a rooted copy of the app's files.
// - Storage key names are hashed, so they don't reveal which stations or voters were viewed.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the data key lives. The platform keystore in the app; in memory in tests.
abstract class KeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformKeyStore implements KeyStore {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    // Readable after first unlock so background sync works; never migrates to another device.
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryKeyStore implements KeyStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

class Vault {
  static const _dataKeyName = 'checkin.vault.key.v1';
  static const _version = 'v1:';

  /// Every stored name starts with this, so the vault never touches other plugins' prefs.
  static const namePrefix = 'vault:';

  final KeyStore keyStore;
  final AesGcm _aes = AesGcm.with256bits();
  final Sha256 _sha = Sha256();
  SecretKey? _key;
  Future<void>? _opening;

  Vault(this.keyStore);

  Future<void> open() => _opening ??= _open();

  Future<void> _open() async {
    final existing = await keyStore.read(_dataKeyName);
    if (existing != null) {
      _key = SecretKey(base64Decode(existing));
    } else {
      _key = await _aes.newSecretKey();
      await keyStore.write(_dataKeyName, base64Encode(await _key!.extractBytes()));
    }
    await _migrateLegacy();
  }

  /// Hashed storage name: `vault:<group>:<sha256(name)>`. The group stays readable so whole
  /// groups (e.g. one user's cache) can be dropped without decrypting anything.
  Future<String> storageName(String group, String name) async {
    final h = await _sha.hash(utf8.encode('$group\u0000$name'));
    return '$namePrefix$group:${base64Url.encode(h.bytes).replaceAll('=', '')}';
  }

  Future<String> _seal(String plain) async {
    final box = await _aes.encrypt(utf8.encode(plain), secretKey: _key!);
    return _version + base64Encode(box.concatenation());
  }

  /// Returns null if the value can't be authenticated (tampered, or sealed with a lost key).
  Future<String?> _unseal(String stored) async {
    if (!stored.startsWith(_version)) return null;
    try {
      final box = SecretBox.fromConcatenation(base64Decode(stored.substring(_version.length)),
          nonceLength: _aes.nonceLength, macLength: _aes.macAlgorithm.macLength);
      return utf8.decode(await _aes.decrypt(box, secretKey: _key!));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String group, String name, String value) async {
    await open();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(await storageName(group, name), await _seal(value));
  }

  Future<String?> read(String group, String name) async {
    await open();
    final prefs = await SharedPreferences.getInstance();
    final k = await storageName(group, name);
    final stored = prefs.getString(k);
    if (stored == null) return null;
    final plain = await _unseal(stored);
    if (plain == null) await prefs.remove(k); // unreadable: drop it rather than fail every time
    return plain;
  }

  Future<void> delete(String group, String name) async {
    await open();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(await storageName(group, name));
  }

  /// Removes every value in groups matching [test] (e.g. other users' caches).
  Future<void> deleteGroups(bool Function(String group) test) async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith(namePrefix))) {
      final group = k.substring(namePrefix.length, k.lastIndexOf(':'));
      if (test(group)) await prefs.remove(k);
    }
  }

  /// Erases everything: all sealed values, the session token and the data key itself (so any
  /// copy of the ciphertext left elsewhere is unreadable). The next open creates a fresh key.
  Future<void> wipeAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith(namePrefix)).toList()) {
      await prefs.remove(k);
    }
    await keyStore.delete(legacyToken);
    await keyStore.delete(_dataKeyName);
    _key = null;
    _opening = null;
  }

  // ---- secrets that belong in the keystore itself ----

  Future<String?> readSecret(String name) => keyStore.read(name);
  Future<void> writeSecret(String name, String? value) =>
      value == null ? keyStore.delete(name) : keyStore.write(name, value);

  // ---- one-time migration from the plaintext storage used before encryption ----

  static const legacyToken = 'checkin.token';
  static const legacyMe = 'checkin.me';
  static const legacyOutbox = 'outbox';
  static const legacyOutboxLog = 'outbox.log';
  static const legacyLedger = 'ledger';
  static const legacyCachePrefix = 'cache:';

  Future<void> _migrateLegacy() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(legacyToken);
    if (token != null) {
      await keyStore.write(legacyToken, token);
      await prefs.remove(legacyToken);
    }
    // Records that can't be re-downloaded are re-sealed; caches are simply dropped (they refill).
    for (final (name, group) in [
      (legacyMe, 'profile'),
      (legacyOutbox, 'outbox'),
      (legacyOutboxLog, 'outbox'),
      (legacyLedger, 'ledger'),
    ]) {
      final plain = prefs.getString(name);
      if (plain == null) continue;
      await prefs.setString(await storageName(group, name), await _seal(plain));
      await prefs.remove(name);
    }
    for (final k in prefs.getKeys().where((k) => k.startsWith(legacyCachePrefix)).toList()) {
      await prefs.remove(k);
    }
  }
}

final vault = Vault(PlatformKeyStore());
