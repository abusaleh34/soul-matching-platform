/// Curated list of Saudi cities offered in the profile city picker.
///
/// Replaces the previous device-geolocation + BigDataCloud reverse-geocode
/// path (data minimisation, PDPL): the city is now self-declared from a fixed
/// list — deterministic, no location permission, no PII egress to a third
/// party. Kept as a plain const so it is unit-testable and matching stays
/// exact-string based.
const List<String> saudiCities = [
  'الرياض',
  'جدة',
  'مكة المكرمة',
  'المدينة المنورة',
  'الدمام',
  'الخبر',
  'الظهران',
  'الأحساء',
  'القطيف',
  'الجبيل',
  'الطائف',
  'تبوك',
  'بريدة',
  'عنيزة',
  'خميس مشيط',
  'أبها',
  'حائل',
  'نجران',
  'جازان',
  'ينبع',
  'الباحة',
  'عرعر',
  'سكاكا',
  'القريات',
  'حفر الباطن',
  'الخرج',
  'الرس',
  'محايل عسير',
  'صبيا',
  'الدوادمي',
];
