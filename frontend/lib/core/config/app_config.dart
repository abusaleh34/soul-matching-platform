/// Build-time application configuration.
///
/// Secrets (the Supabase URL + anon key) are injected at build time via
/// `--dart-define` and resolved here. There is deliberately NO hardcoded
/// fallback: a missing value fails loud so a misconfigured build cannot
/// silently connect to the wrong (or a leaked) project. See DEPLOYMENT.md.
library;

/// Immutable Supabase connection configuration.
class SupabaseConfig {
  final String url;
  final String anonKey;

  const SupabaseConfig({required this.url, required this.anonKey});
}

/// Raised when a required build-time configuration value is absent.
class MissingConfigError implements Exception {
  final String message;

  const MissingConfigError(this.message);

  @override
  String toString() => 'MissingConfigError: $message';
}

/// Resolve the Supabase config from build-time values, failing loud when any
/// required value is missing or blank. No fallback, no default project.
SupabaseConfig resolveSupabaseConfig({
  required String url,
  required String anonKey,
}) {
  final missing = <String>[];
  if (url.trim().isEmpty) missing.add('SUPABASE_URL');
  if (anonKey.trim().isEmpty) missing.add('SUPABASE_ANON_KEY');

  if (missing.isNotEmpty) {
    throw MissingConfigError(
      'Missing required build-time configuration: ${missing.join(', ')}. '
      'Provide them via --dart-define (see DEPLOYMENT.md).',
    );
  }

  return SupabaseConfig(url: url.trim(), anonKey: anonKey.trim());
}
