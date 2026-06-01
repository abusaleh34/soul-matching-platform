import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/match_result.dart'; // تأكد أن هذا المسار صحيح في مشروعك

class ApiService {
  // الرابط السحابي الحقيقي للخادم الخاص بك
  static const String baseUrl = 'https://soul-matching-api.onrender.com';

  // 1. دالة لجلب الـ ID الخاص بالمستخدم المسجل حالياً من Supabase
  String? get _currentUserId {
    return Supabase.instance.client.auth.currentUser?.id;
  }

  // 2. دالة الاتصال بالذكاء الاصطناعي (يجب أن يتم استدعاؤها بعد حفظ الإجابات)
  Future<Map<String, dynamic>> fetchMatchAnalysis() async {
    final userId = _currentUserId;
    if (userId == null) {
      throw Exception('خطأ: لا يوجد مستخدم مسجل الدخول حالياً.');
    }

    try {
      final response = await http.get(Uri.parse('$baseUrl/match/$userId'));
      
      if (response.statusCode == 200) {
        // فك تشفير النص مع دعم اللغة العربية (UTF-8)
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        throw Exception('فشل في الاتصال بمحرك الذكاء الاصطناعي. الرمز: ${response.statusCode}');
      }
    } catch (e) {
      print("AI Match Fetch Error: $e");
      rethrow;
    }
  }

  // 3. دالة لحفظ أو تحديث بيانات الملف الشخصي (تعمل مباشرة مع Supabase)
  Future<String?> submitProfileSetup(Map<String, dynamic> profileData) async {
    final userId = _currentUserId;
    if (userId == null) {
       throw Exception('خطأ: لا يوجد مستخدم مسجل الدخول.');
    }

    try {
      // نستخدم upsert لكي نضمن أنه إذا كان الملف موجوداً يتم تحديثه، وإلا يتم إنشاؤه
      profileData['id'] = userId; // إجبار ربط البيانات بالـ ID الحالي
      
      final response = await Supabase.instance.client
          .from('profiles')
          .upsert(profileData)
          .select('id')
          .single();
          
      print("تم حفظ بيانات الملف الشخصي بنجاح للمستخدم: ${response['id']}");
      return response['id'] as String;
    } on PostgrestException catch (e) {
      print("Supabase Upsert Error: $e");
      rethrow;
    } catch (e) {
      print("General Profile Error: $e");
      rethrow;
    }
  }

  // 4. دالة لحفظ إجابات الاستبيان (تعمل مباشرة مع Supabase)
  Future<bool> submitQuestionnaire(Map<String, dynamic> answers) async {
    final userId = _currentUserId;
    if (userId == null) {
       print("لا يمكن حفظ الاستبيان: لا يوجد مستخدم مسجل الدخول.");
       return false;
    }

    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'questionnaire_answers': answers})
          .eq('id', userId);
      print("تم حفظ الإجابات بنجاح في قاعدة البيانات.");
      return true;
    } catch (e) {
      print("Supabase Update Error: $e");
      return false;
    }
  }

  // 5. دالة لفحص حالة الحساب (اختيارية، تم تعديلها لتكون ديناميكية)
  Future<String> checkUserStatus() async {
    final userId = _currentUserId;
    if (userId == null) {
      return "unauthenticated";
    }

    try {
      // قراءة الحالة مباشرة من قاعدة البيانات بدلاً من الـ Backend لتوفير الوقت
      final response = await Supabase.instance.client
          .from('users')
          .select('account_status')
          .eq('id', userId)
          .single();

      return response['account_status'] ?? "pending";
    } catch (e) {
      print("Status Check Error: $e");
      return "error";
    }
  }

  // 6. دالة لجلب نصيحة المستشار الذكي ما بعد الزواج
  Future<String> fetchCounselorAdvice(String matchId) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/post-marriage-counselor/$matchId'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        return data['advice'] ?? 'لم نتمكن من الحصول على النصيحة.';
      } else {
        throw Exception('فشل في الاتصال بالمستشار الذكي. الرمز: ${response.statusCode}');
      }
    } catch (e) {
      print("Counselor Fetch Error: $e");
      rethrow;
    }
  }

  // 7. دالة جلب إحصائيات لوحة التحكم للمشرفين (محمية بـ JWT)
  Future<Map<String, dynamic>> fetchAdminStats() async {
    final token = Supabase.instance.client.auth.currentSession?.accessToken;
    if (token == null) {
      throw Exception('عذراً، يجب تسجيل الدخول للوصول للإحصائيات.');
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/admin/stats'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        final errorBody = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(errorBody['detail'] ?? 'فشل تحميل الإحصائيات (${response.statusCode})');
      }
    } catch (e) {
      print("Fetch Admin Stats Error: $e");
      rethrow;
    }
  }

  // 8. دالة لتشغيل عملية المطابقة يدوياً للمشرف
  Future<Map<String, dynamic>> triggerMatchmaking() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/trigger-matchmaking'),
      );
      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        throw Exception('فشل تشغيل عملية المطابقة. الرمز: ${response.statusCode}');
      }
    } catch (e) {
      print("Trigger Matchmaking Error: $e");
      rethrow;
    }
  }

  // 9. دالة لتحديث حالة التنبيه إلى "مقروء"
  Future<void> markNotificationAsRead(String id) async {
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', id);
    } catch (e) {
      print("Error marking notification as read: $e");
      rethrow;
    }
  }

  // 10. دالة لتحديث حالة كافة التنبيهات إلى "مقروءة" للمستخدم الحالي
  Future<void> markAllNotificationsAsRead() async {
    final userId = _currentUserId;
    if (userId == null) return;
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId);
    } catch (e) {
      print("Error marking all notifications as read: $e");
      rethrow;
    }
  }
}