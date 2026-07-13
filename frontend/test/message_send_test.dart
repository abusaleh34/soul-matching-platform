import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/matching/logic/message_send.dart';

void main() {
  group('buildMessageRequest', () {
    const matchId = '6985d605-14a3-4ada-97e3-f2172ce2eb5b';
    const uid = '65e4c3af-dedd-4643-a277-587e7162f369';

    test('returns a request for an authenticated user with content', () {
      final r = buildMessageRequest(authUserId: uid, matchId: matchId, content: '  مرحبا  ');
      expect(r, isNotNull);
      expect(r!.senderId, uid);
      expect(r.matchId, matchId);
      expect(r.content, 'مرحبا'); // trimmed
    });

    test('refuses when there is NO authenticated user (never falls back to a cached id)', () {
      // RLS requires sender_id == auth.uid(); an unauthenticated send would be
      // rejected (42501). The builder must refuse rather than send a doomed insert.
      expect(buildMessageRequest(authUserId: null, matchId: matchId, content: 'مرحبا'), isNull);
      expect(buildMessageRequest(authUserId: '', matchId: matchId, content: 'مرحبا'), isNull);
    });

    test('refuses empty / whitespace content', () {
      expect(buildMessageRequest(authUserId: uid, matchId: matchId, content: ''), isNull);
      expect(buildMessageRequest(authUserId: uid, matchId: matchId, content: '   '), isNull);
    });

    test('refuses when match id is missing', () {
      expect(buildMessageRequest(authUserId: uid, matchId: null, content: 'مرحبا'), isNull);
      expect(buildMessageRequest(authUserId: uid, matchId: '', content: 'مرحبا'), isNull);
    });
  });
}
