import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/logic/phone.dart';

void main() {
  group('normalizeSaudiPhone (client layer of the Saudi guard)', () {
    test('local 05.. normalizes to +9665..', () {
      expect(normalizeSaudiPhone('0512345678'), '+966512345678');
    });
    test('bare 5.. normalizes', () {
      expect(normalizeSaudiPhone('512345678'), '+966512345678');
    });
    test('already E.164 preserved', () {
      expect(normalizeSaudiPhone('+966512345678'), '+966512345678');
    });
    test('strips spaces/dashes', () {
      expect(normalizeSaudiPhone(' 05 1234-5678 '), '+966512345678');
    });
    test('garbage -> null', () {
      expect(normalizeSaudiPhone('abc'), isNull);
      expect(normalizeSaudiPhone(''), isNull);
    });
  });

  group('isAllowedSaudiPhone', () {
    test('Saudi mobile allowed', () {
      expect(isAllowedSaudiPhone('+966512345678'), isTrue);
    });
    test('non-Saudi normalizes but is not allowed', () {
      expect(normalizeSaudiPhone('+15551234567'), '+15551234567');
      expect(isAllowedSaudiPhone('+15551234567'), isFalse);
    });
    test('wrong length rejected', () {
      expect(isAllowedSaudiPhone('+96651234'), isFalse);
    });
  });
}
