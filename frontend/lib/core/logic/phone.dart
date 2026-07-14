/// Client layer of the Saudi-only phone guard (mirrors backend `app/phone.py`).
/// Cosmetic — the server SMS hook and the DB CHECK are the real walls — but a
/// Saudi user typing `05..` or `5..` must be accepted and normalized, and a
/// non-Saudi number rejected with a clear message.
///
/// Keep [kAllowedPhonePrefixes] in sync with the backend allow-list when GCC
/// expansion happens (one line, both sides).
const List<String> kAllowedPhonePrefixes = ['+9665'];

final RegExp _saudiMobile = RegExp(r'^\+9665\d{8}$');
final RegExp _e164 = RegExp(r'^\+\d{8,15}$');

/// Best-effort E.164 normalization; local Saudi forms are interpreted as +966.
String? normalizeSaudiPhone(String? raw) {
  if (raw == null) return null;
  var s = raw.replaceAll(RegExp(r'[^\d+]'), '');
  if (s.isEmpty) return null;

  String e164;
  if (s.startsWith('00')) {
    e164 = '+${s.substring(2)}';
  } else if (s.startsWith('+')) {
    e164 = s;
  } else if (s.startsWith('966')) {
    e164 = '+$s';
  } else if (s.startsWith('0')) {
    e164 = '+966${s.substring(1)}';
  } else if (s.startsWith('5') && s.length == 9) {
    e164 = '+966$s';
  } else {
    e164 = '+$s';
  }
  return _e164.hasMatch(e164) ? e164 : null;
}

bool isAllowedSaudiPhone(String? e164) => e164 != null && _saudiMobile.hasMatch(e164);
