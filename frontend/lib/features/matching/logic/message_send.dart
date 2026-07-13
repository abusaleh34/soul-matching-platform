/// Pure logic for building a chat message insert payload.
///
/// The `messages` RLS policy requires `sender_id = auth.uid()`, so the sender
/// MUST be the authenticated session user. We never fall back to a locally
/// cached id (the old `?? localId` behaviour): a cached id sent without a live
/// session is an unauthenticated insert and is rejected with 42501.
class MessageRequest {
  final String matchId;
  final String senderId;
  final String content;

  const MessageRequest({
    required this.matchId,
    required this.senderId,
    required this.content,
  });
}

/// Returns a [MessageRequest] only when we have an authenticated user id, a
/// match id, and non-empty content; otherwise null (the caller decides how to
/// surface it — e.g. prompt re-authentication).
MessageRequest? buildMessageRequest({
  required String? authUserId,
  required String? matchId,
  required String content,
}) {
  final text = content.trim();
  if (text.isEmpty) return null;
  if (authUserId == null || authUserId.isEmpty) return null;
  if (matchId == null || matchId.isEmpty) return null;
  return MessageRequest(matchId: matchId, senderId: authUserId, content: text);
}
