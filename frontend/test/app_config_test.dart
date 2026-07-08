import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/config/app_config.dart';

void main() {
  group('resolveSupabaseConfig', () {
    test('returns config when both values are present', () {
      final cfg = resolveSupabaseConfig(
        url: 'https://example.supabase.co',
        anonKey: 'anon-key-123',
      );
      expect(cfg.url, 'https://example.supabase.co');
      expect(cfg.anonKey, 'anon-key-123');
    });

    test('trims surrounding whitespace on valid values', () {
      final cfg = resolveSupabaseConfig(
        url: '  https://example.supabase.co  ',
        anonKey: '  anon-key-123  ',
      );
      expect(cfg.url, 'https://example.supabase.co');
      expect(cfg.anonKey, 'anon-key-123');
    });

    test('throws MissingConfigError when url is empty (no fallback)', () {
      expect(
        () => resolveSupabaseConfig(url: '', anonKey: 'anon-key-123'),
        throwsA(isA<MissingConfigError>()),
      );
    });

    test('throws MissingConfigError when anonKey is empty (no fallback)', () {
      expect(
        () => resolveSupabaseConfig(url: 'https://example.supabase.co', anonKey: ''),
        throwsA(isA<MissingConfigError>()),
      );
    });

    test('throws MissingConfigError when a value is only whitespace', () {
      expect(
        () => resolveSupabaseConfig(url: '   ', anonKey: 'anon-key-123'),
        throwsA(isA<MissingConfigError>()),
      );
    });

    test('error message names every missing key', () {
      expect(
        () => resolveSupabaseConfig(url: '', anonKey: ''),
        throwsA(
          predicate((e) =>
              e is MissingConfigError &&
              e.toString().contains('SUPABASE_URL') &&
              e.toString().contains('SUPABASE_ANON_KEY')),
        ),
      );
    });

    test('does NOT fall back to the leaked demo project ref', () {
      // Guards against re-introducing a hardcoded default. An empty input must
      // never resolve to the old vhayahstcouubjryilvv project.
      expect(
        () => resolveSupabaseConfig(url: '', anonKey: ''),
        throwsA(isA<MissingConfigError>()),
      );
    });
  });
}
