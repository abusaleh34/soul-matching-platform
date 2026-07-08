/// Pure, dependency-free helpers for the Focus Room.
///
/// Extracted so the countdown, Arabic timestamp and expiry rules can be unit
/// tested without a live Supabase stream (BRD §3.3 / remediation §1.4, §2.2).
library;

/// Formats a countdown as HH:MM:SS (never negative).
String formatCountdown(Duration d) {
  final clamped = d.isNegative ? Duration.zero : d;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(clamped.inHours)}:${two(clamped.inMinutes.remainder(60))}:${two(clamped.inSeconds.remainder(60))}';
}

/// Native Arabic 12-hour timestamp, e.g. `10:45 ص` / `05:12 م`.
String formatArabicTime(DateTime dt) {
  final local = dt.toLocal();
  final hour = local.hour;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = hour >= 12 ? 'م' : 'ص';
  final twelve = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
  // BRD example uses a zero-padded hour, e.g. 05:12 م.
  return '${twelve.toString().padLeft(2, '0')}:$minute $period';
}

/// Remaining time until [expiresAt], clamped to zero once elapsed.
Duration timeLeftUntil(DateTime expiresAt, DateTime now) {
  return now.isBefore(expiresAt) ? expiresAt.difference(now) : Duration.zero;
}

/// A room is closed when it has no expiry, its status is not 'active', or the
/// 24h countdown has elapsed. Used to gate sending messages / counselor access.
bool isRoomExpired(DateTime? expiresAt, String? roomStatus, DateTime now) {
  if (roomStatus != null && roomStatus != 'active') return true;
  if (expiresAt == null) return true;
  return !now.isBefore(expiresAt);
}

/// Parses a nullable ISO timestamp to a local DateTime, or null when invalid.
DateTime? parseTimestamp(String? iso) {
  if (iso == null) return null;
  return DateTime.tryParse(iso)?.toLocal();
}
