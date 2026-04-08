import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../matching/screens/match_screen.dart';

class WaitingScreen extends StatefulWidget {
  final String profileId;
  const WaitingScreen({super.key, required this.profileId});

  @override
  State<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends State<WaitingScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isLoading = false;
  String _userCity = 'منطقتك';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    setState(() {
      _isLoading = true;
    });

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    // Graceful fallback linking pipeline state if Auth is hypothetically unmounted during debugging
    final activeUserId = currentUserId ?? widget.profileId; 

    if (activeUserId.isEmpty) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("عذراً، يجب تسجيل الدخول أو إكمال الملف الشخصي لرؤية التوافق.", style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    String status = 'pending';
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('account_status, city')
          .eq('id', activeUserId)
          .maybeSingle();
      if (response != null) {
        if (response['account_status'] != null) {
           status = response['account_status'];
        }
        if (response['city'] != null && response['city'].toString().isNotEmpty) {
           setState(() {
              _userCity = response['city'];
           });
        }
      }
    } catch (e) {
      debugPrint("WaitingScreen live fetch error: $e");
    }

    if (!mounted) return;

    if (status == 'active') {
      // Once approved dynamically, fetch the majestic match result dashboard
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return Dialog(
            backgroundColor: AppTheme.backgroundIvory,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppTheme.primaryOliveGreen),
                  const SizedBox(height: 24),
                  Text(
                    "تم الاعتماد!\nجاري استخراج الميثاق والتوافق...",
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppTheme.primaryNavyBlue,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading overlay
      
      // Navigate directly passing the securely validated UUID context to invoke Python RAG APIs
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => MatchScreen(userId: activeUserId),
        ),
      );
    } else {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("جاري العمل على تحليل ملفك... يرجى الانتظار قليلاً.", style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
          backgroundColor: Colors.orangeAccent,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryNavyBlue, // Premium Dark Theme
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.primaryOliveGreen.withOpacity(0.2),
                      border: Border.all(color: AppTheme.primaryOliveGreen, width: 4),
                    ),
                    child: const Icon(Icons.fingerprint, size: 60, color: AppTheme.backgroundIvory),
                  ),
                ),
              ),
              const SizedBox(height: 56),
              Text(
                "جاري تحليل بصمتك النفسية بدقة...",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppTheme.backgroundIvory,
                  fontWeight: FontWeight.bold,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Text(
                "نحن نبحث لك عن شريك روحي في $_userCity... سنرسل لك تنبيهاً فور العثور على التوافق المثالي.",
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.backgroundBeige.withOpacity(0.8),
                  height: 1.8,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _checkStatus,
                icon: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(color: AppTheme.primaryNavyBlue, strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, color: AppTheme.primaryNavyBlue),
                label: Text(
                  _isLoading ? "جاري التحديث..." : "تحديث الحالة",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryNavyBlue),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.backgroundIvory,
                  foregroundColor: AppTheme.primaryNavyBlue,
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 8,
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        ), // ConstrainedBox
        ), // Center
      ),
    );
  }
}
