// SignBridge — shared secure-storage keys and helpers

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const canStorageKey = 'signbridge_can';
const onboardingDoneKey = 'signbridge_onboarding_done';

const _storage = FlutterSecureStorage();

Future<String?> readStoredCan() async {
  final can = await _storage.read(key: canStorageKey);
  if (can == null || can.length != 6) return null;
  return can;
}

Future<void> saveCan(String can) => _storage.write(key: canStorageKey, value: can);

Future<void> clearCan() => _storage.delete(key: canStorageKey);

Future<bool> isOnboardingDone() async {
  final v = await _storage.read(key: onboardingDoneKey);
  return v == '1';
}

Future<void> markOnboardingDone() =>
    _storage.write(key: onboardingDoneKey, value: '1');
