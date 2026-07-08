import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class ApiService {
  // Cloud API base URL (FastAPI on Render).
  static const String baseUrl = 'https://soul-matching-api.onrender.com';

  String? get _currentUserId =>
      Supabase.instance.client.auth.currentUser?.id;

  String? get _accessToken =>
      Supabase.instance.client.auth.currentSession?.accessToken;

  // 1. AI match analysis for the current user.
  Future<Map<String, dynamic>> fetchMatchAnalysis() async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('خطأ: لا يوجد مستخدم مسجل الدخول حالياً.');
    }
    final response = await http.get(Uri.parse('$baseUrl/match/$userId'));
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    throw Exception('فشل في الاتصال بمحرك الذكاء الاصطناعي. الرمز: ${response.statusCode}');
  }

  // 2. Save/update the profile (directly via Supabase, gated by RLS).
  Future<String?> submitProfileSetup(Map<String, dynamic> profileData) async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('خطأ: لا يوجد مستخدم مسجل الدخول.');
    }
    profileData['id'] = userId; // bind row to the authenticated user
    final response = await Supabase.instance.client
        .from('profiles')
        .upsert(profileData)
        .select('id')
        .single();
    return response['id'] as String;
  }

  // 3. Save questionnaire answers.
  Future<bool> submitQuestionnaire(Map<String, dynamic> answers) async {
    final userId = _currentUserId;
    if (userId == null) return false;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'questionnaire_answers': answers})
          .eq('id', userId);
      return true;
    } catch (e) {
      debugPrint('Supabase questionnaire update error: $e');
      return false;
    }
  }

  // 4. Read the current account status (from profiles).
  Future<String> checkUserStatus() async {
    final userId = _currentUserId;
    if (userId == null) return 'unauthenticated';
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('account_status')
          .eq('id', userId)
          .maybeSingle();
      return response?['account_status'] ?? 'pending';
    } catch (e) {
      debugPrint('Status check error: $e');
      return 'error';
    }
  }

  // 5. Post-marriage counselor — STREAMED (JWT-authenticated; participant-only,
  //    expiry-gated on the server). Emits the cumulative advice text as chunks
  //    arrive so the UI can render it incrementally (BRD §3.5).
  Stream<String> streamCounselorAdvice(String matchId) async* {
    final token = _accessToken;
    if (token == null) {
      throw Exception('عذراً، يجب تسجيل الدخول للوصول إلى المستشار.');
    }
    final request = http.Request(
      'POST',
      Uri.parse('$baseUrl/api/post-marriage-counselor/$matchId'),
    )..headers['Authorization'] = 'Bearer $token';

    final response = await request.send();
    if (response.statusCode == 403) {
      throw Exception('انتهت صلاحية غرفة التركيز.');
    }
    if (response.statusCode != 200) {
      throw Exception('فشل في الاتصال بالمستشار الذكي. الرمز: ${response.statusCode}');
    }

    final buffer = StringBuffer();
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer.write(chunk);
      yield buffer.toString();
    }
  }

  // 6. Admin stats (JWT-authenticated; admin-only on server).
  Future<Map<String, dynamic>> fetchAdminStats() async {
    final token = _accessToken;
    if (token == null) {
      throw Exception('عذراً، يجب تسجيل الدخول للوصول للإحصائيات.');
    }
    final response = await http.get(
      Uri.parse('$baseUrl/api/admin/stats'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
    throw Exception(errorBody['detail'] ?? 'فشل تحميل الإحصائيات (${response.statusCode})');
  }

  // 7. Admin: manually run the database Hunter sweep (admin-only on server).
  Future<Map<String, dynamic>> triggerMatchmaking() async {
    final token = _accessToken;
    if (token == null) {
      throw Exception('عذراً، يجب تسجيل الدخول كمشرف.');
    }
    final response = await http.post(
      Uri.parse('$baseUrl/api/trigger-matchmaking'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes));
    }
    throw Exception('فشل تشغيل عملية المطابقة. الرمز: ${response.statusCode}');
  }

  // 8. Mark a single notification read.
  Future<void> markNotificationAsRead(String id) async {
    await Supabase.instance.client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', id);
  }

  // 9. Mark ALL of the current user's notifications read (notification center).
  Future<void> markAllNotificationsAsRead() async {
    final userId = _currentUserId;
    if (userId == null) return;
    await Supabase.instance.client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId);
  }

  // 10. Active-chat suppression: mark read ONLY notifications for this match
  //     (BRD §3.4 — do not touch unrelated notifications).
  Future<void> markMatchNotificationsAsRead(String matchId) async {
    final userId = _currentUserId;
    if (userId == null) return;
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('match_id', matchId);
    } catch (e) {
      debugPrint('markMatchNotificationsAsRead error: $e');
    }
  }

  // 11. Read receipts: mark messages I RECEIVED in this room as read
  //     (RLS only permits recipient-side updates).
  Future<void> markMessagesAsRead(String matchId) async {
    final userId = _currentUserId;
    if (userId == null) return;
    try {
      await Supabase.instance.client
          .from('messages')
          .update({'is_read': true})
          .eq('match_id', matchId)
          .neq('sender_id', userId);
    } catch (e) {
      debugPrint('markMessagesAsRead error: $e');
    }
  }
}
