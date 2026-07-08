import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/data/saudi_cities.dart';

void main() {
  group('saudiCities', () {
    test('is non-empty', () {
      expect(saudiCities, isNotEmpty);
    });

    test('has no duplicate entries', () {
      expect(saudiCities.toSet().length, saudiCities.length);
    });

    test('contains no blank entries', () {
      expect(saudiCities.any((c) => c.trim().isEmpty), isFalse);
    });

    test('includes the major cities used for matching', () {
      for (final city in ['الرياض', 'جدة', 'مكة المكرمة', 'الدمام']) {
        expect(saudiCities, contains(city));
      }
    });
  });
}
