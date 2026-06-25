import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ApiService _apiService = ApiService();
  late Stream<List<Map<String, dynamic>>> _notificationsStream;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _userId = Supabase.instance.client.auth.currentUser?.id;
    if (_userId != null) {
      _notificationsStream = Supabase.instance.client
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('user_id', _userId!)
          .order('created_at', ascending: false);
    }
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dateTime = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return 'الآن';
      } else if (difference.inMinutes < 60) {
        return 'قبل ${difference.inMinutes} دقيقة';
      } else if (difference.inHours < 24) {
        return 'قبل ${difference.inHours} ساعة';
      } else {
        return '${dateTime.year}/${dateTime.month}/${dateTime.day}';
      }
    } catch (e) {
      return '';
    }
  }

  Future<void> _markAsRead(String id) async {
    try {
      await _apiService.markNotificationAsRead(id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء تحديث التنبيه: $e'))
        );
      }
    }
  }

  Future<void> _markAllAsRead() async {
    try {
      await _apiService.markAllNotificationsAsRead();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديد كافة التنبيهات كمقروءة.', style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: AppTheme.primaryOliveGreen,
          )
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ: $e'))
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryNavyBlue,
      appBar: AppBar(
        title: const Text('التنبيهات', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppTheme.backgroundIvory,
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'تحديد الكل كمقروء',
            onPressed: _markAllAsRead,
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: _userId == null
                ? const Center(child: Text('الرجاء تسجيل الدخول لعرض التنبيهات', style: TextStyle(color: Colors.white)))
                : StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _notificationsStream,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator(color: AppTheme.primaryOliveGreen));
                      }

                      final notifications = snapshot.data ?? [];

                      if (notifications.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.notifications_none, size: 80, color: AppTheme.backgroundBeige.withValues(alpha: 0.3)),
                              const SizedBox(height: 16),
                              Text(
                                'لا توجد تنبيهات حالية',
                                style: TextStyle(color: AppTheme.backgroundBeige.withValues(alpha: 0.5), fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        );
                      }

                      return ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: notifications.length,
                        itemBuilder: (context, index) {
                          final item = notifications[index];
                          final isRead = item['is_read'] as bool? ?? false;

                          return GestureDetector(
                            onTap: () {
                              if (!isRead) {
                                _markAsRead(item['id'] as String);
                              }
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isRead 
                                    ? Colors.white.withValues(alpha: 0.02) 
                                    : Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: isRead 
                                      ? Colors.white.withValues(alpha: 0.05) 
                                      : AppTheme.primaryOliveGreen.withValues(alpha: 0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isRead 
                                          ? Colors.white.withValues(alpha: 0.05) 
                                          : AppTheme.primaryOliveGreen.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      isRead ? Icons.notifications_none : Icons.notifications_active,
                                      color: isRead ? Colors.white54 : AppTheme.primaryOliveGreen,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                item['title'] ?? '',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              _formatDateTime(item['created_at'] as String?),
                                              style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          item['body'] ?? '',
                                          style: TextStyle(
                                            color: Colors.white.withValues(alpha: 0.7),
                                            fontSize: 14,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
