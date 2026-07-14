import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/logic/consent.dart';

void main() {
  group('needsConsent', () {
    test('true when never consented (null / 0)', () {
      expect(needsConsent(null), isTrue);
      expect(needsConsent(0), isTrue);
    });

    test('false when consented to the current version', () {
      expect(needsConsent(kCurrentConsentVersion), isFalse);
    });

    test('true when consented version is older than current', () {
      expect(needsConsent(kCurrentConsentVersion - 1), isTrue);
    });

    test('false when stored is newer (never downgrade-prompt)', () {
      expect(needsConsent(kCurrentConsentVersion + 1), isFalse);
    });
  });
}
