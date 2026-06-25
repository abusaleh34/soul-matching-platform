import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import 'notification_bell.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final ApiService _apiService = ApiService();
  late Future<Map<String, dynamic>> _statsFuture;
  bool _isMatchingLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshStats();
  }

  void _refreshStats() {
    setState(() {
      _statsFuture = _apiService.fetchAdminStats();
    });
  }

  Future<void> _triggerMatchmakingProcess() async {
    setState(() {
      _isMatchingLoading = true;
    });

    try {
      final result = await _apiService.triggerMatchmaking();
      final focusRoomsCreated = result['focus_rooms_created'] ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'اكتملت عملية المطابقة بنجاح! تم إنشاء $focusRoomsCreated غرفة تركيز جديدة.',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: AppTheme.primaryOliveGreen,
            duration: const Duration(seconds: 4),
          )
        );
        _refreshStats();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل تشغيل المطابقة: $e', style: const TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: Colors.redAccent,
          )
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isMatchingLoading = false;
        });
      }
    }
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    return Card(
      color: Colors.white.withValues(alpha: 0.04),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: AppTheme.backgroundBeige.withValues(alpha: 0.8),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryNavyBlue,
      appBar: AppBar(
        title: const Text('لوحة تحكم الإشراف والنظام', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppTheme.backgroundIvory,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshStats,
          ),
          const NotificationBell(),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: FutureBuilder<Map<String, dynamic>>(
              future: _statsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.primaryOliveGreen));
                } else if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
                          const SizedBox(height: 16),
                          Text(
                            'خطأ في جلب بيانات الإدارة:\n${snapshot.error}',
                            style: const TextStyle(color: Colors.redAccent, fontSize: 16, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _refreshStats,
                            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryOliveGreen),
                            child: const Text('إعادة المحاولة', style: TextStyle(color: Colors.white)),
                          )
                        ],
                      ),
                    ),
                  );
                } else if (snapshot.hasData) {
                  final data = snapshot.data!;
                  final int totalUsers = data['total_users'] ?? 0;
                  final int pendingUsers = data['pending_users'] ?? 0;
                  final int activeUsers = data['active_users'] ?? 0;
                  final int matchedUsers = data['matched_users'] ?? 0;
                  final int totalMatches = data['total_matches'] ?? 0;
                  final int activeRooms = data['active_rooms'] ?? totalMatches;
                  final double avgCompat = (data['average_compatibility'] as num? ?? 0.0).toDouble();

                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header Stats Overview
                        const Text(
                          'إحصائيات المنصة الحالية',
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        _buildStatCard(
                          title: 'إجمالي المستخدمين المسجلين',
                          value: '$totalUsers مستخدم',
                          icon: Icons.people_outline,
                          color: Colors.blueAccent,
                          subtitle: 'معلقين: $pendingUsers | نشطين: $activeUsers | متطابقين: $matchedUsers',
                        ),
                        const SizedBox(height: 12),
                        _buildStatCard(
                          title: 'الغرف النشطة حالياً',
                          value: '$activeRooms غرف',
                          icon: Icons.forum_outlined,
                          color: AppTheme.primaryOliveGreen,
                          subtitle: 'غرف تركيز فعّالة وغير منتهية ($totalMatches إجمالي التوافقات)',
                        ),
                        const SizedBox(height: 12),
                        _buildStatCard(
                          title: 'متوسط نسبة التوافق للغرف',
                          value: '$avgCompat%',
                          icon: Icons.favorite_border,
                          color: Colors.amberAccent,
                          subtitle: 'محسوبة بالذكاء الاصطناعي بناءً على الاستبيان النفسي',
                        ),
                        const SizedBox(height: 40),

                        // System Operations
                        const Text(
                          'عمليات النظام التلقائية',
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.02),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.psychology, color: AppTheme.primaryOliveGreen, size: 28),
                                  SizedBox(width: 12),
                                  Text(
                                    'مطابقة المستخدمين الفعالة',
                                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'يطابق محرك Hunter داخل قاعدة البيانات المستخدمين المؤهلين (قيد الانتظار والنشطين) في نفس المدينة بناءً على السن والتوجه تلقائياً عند كل تحديث. يمكنك تشغيل دورة كنس يدوية الآن لمطابقة من انضموا مسبقاً.',
                                style: TextStyle(color: AppTheme.backgroundBeige.withValues(alpha: 0.7), fontSize: 14, height: 1.6),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton(
                                onPressed: _isMatchingLoading ? null : _triggerMatchmakingProcess,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.primaryOliveGreen,
                                  disabledBackgroundColor: Colors.grey.withValues(alpha: 0.2),
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  minimumSize: const Size(double.infinity, 54),
                                ),
                                child: _isMatchingLoading
                                    ? const SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                                      )
                                    : const Text(
                                        'تشغيل دورة المطابقة فوراً 🚀',
                                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
  }
}
