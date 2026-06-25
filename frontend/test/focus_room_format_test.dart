import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/utils/focus_room_format.dart';

void main() {
  group('formatCountdown', () {
    test('formats hours/minutes/seconds with padding', () {
      expect(formatCountdown(const Duration(hours: 23, minutes: 5, seconds: 9)), '23:05:09');
    });
    test('zero', () => expect(formatCountdown(Duration.zero), '00:00:00'));
    test('negative clamps to zero', () {
      expect(formatCountdown(const Duration(seconds: -10)), '00:00:00');
    });
  });

  group('formatArabicTime', () {
    test('morning uses ص', () {
      expect(formatArabicTime(DateTime(2026, 6, 20, 10, 45)), '10:45 ص');
    });
    test('afternoon uses م with zero-padded hour (BRD: 05:12 م)', () {
      expect(formatArabicTime(DateTime(2026, 6, 20, 17, 12)), '05:12 م');
    });
    test('noon is 12 م', () {
      expect(formatArabicTime(DateTime(2026, 6, 20, 12, 0)), '12:00 م');
    });
    test('midnight is 12 ص', () {
      expect(formatArabicTime(DateTime(2026, 6, 20, 0, 5)), '12:05 ص');
    });
  });

  group('timeLeftUntil', () {
    final now = DateTime(2026, 6, 20, 12, 0, 0);
    test('future returns remaining', () {
      expect(timeLeftUntil(now.add(const Duration(hours: 2)), now), const Duration(hours: 2));
    });
    test('past returns zero', () {
      expect(timeLeftUntil(now.subtract(const Duration(hours: 1)), now), Duration.zero);
    });
  });

  group('isRoomExpired', () {
    final now = DateTime(2026, 6, 20, 12, 0, 0);
    test('active + future = not expired', () {
      expect(isRoomExpired(now.add(const Duration(hours: 1)), 'active', now), isFalse);
    });
    test('active + past = expired', () {
      expect(isRoomExpired(now.subtract(const Duration(hours: 1)), 'active', now), isTrue);
    });
    test('non-active status = expired', () {
      expect(isRoomExpired(now.add(const Duration(hours: 1)), 'expired', now), isTrue);
    });
    test('null expiry = expired', () {
      expect(isRoomExpired(null, 'active', now), isTrue);
    });
  });

  group('parseTimestamp', () {
    test('null -> null', () => expect(parseTimestamp(null), isNull));
    test('invalid -> null', () => expect(parseTimestamp('not-a-date'), isNull));
    test('valid ISO -> DateTime', () {
      expect(parseTimestamp('2026-06-20T10:00:00Z'), isA<DateTime>());
    });
  });
}
