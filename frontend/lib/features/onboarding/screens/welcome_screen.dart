import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import 'profile_setup_screen.dart';
import '../../../main.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> with TickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
        CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic));
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _signInGuest() async {
    setState(() => _isLoading = true);
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        // Stale session exists, bypass signInAnonymously and immediately route
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const AuthGate()),
          );
        }
        return;
      }
      
      await Supabase.instance.client.auth.signInAnonymously();
      
      // Add a tiny buffer to allow local storage persistence on Web
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Immediately force navigation to AuthGate instead of waiting for Stream
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const AuthGate()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("فشل المصادقة: $e", style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Tajawal')),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundIvory,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 48.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeroSection(context),
                    const SizedBox(height: 64),
                    _buildFeatureSection(context),
                    const SizedBox(height: 64),
                    _buildFooterSection(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Column(
          children: [
            // Abstract Icon Collection
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppTheme.primaryOliveGreen.withOpacity(0.05),
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                   Icon(Icons.fingerprint_rounded, size: 90, color: AppTheme.primaryOliveGreen.withOpacity(0.15)),
                   const Icon(Icons.psychology_rounded, size: 45, color: AppTheme.primaryOliveGreen),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Text(
              "لأن الأرواح جنودٌ مجندة...\nولا تُقاس بالمظاهر.",
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                color: AppTheme.primaryNavyBlue,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 24),
            Text(
              "أول منصة زواج تعتمد على الذكاء الاصطناعي لتحليل التوافق الفكري والروحي، بعيداً عن السطحية والتشتت.",
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppTheme.primaryNavyBlue.withOpacity(0.7),
                height: 1.6,
              ),
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureSection(BuildContext context) {
    return Column(
      children: [
        Text(
          "لماذا نحن مختلفون؟",
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: AppTheme.primaryOliveGreen,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(height: 40),
        _buildFeatureCard(
          context,
          icon: Icons.psychology_rounded,
          title: "توافق مبني على العلم، لا الصدفة",
          body: "نحول إجاباتك إلى بصمة رقمية من 1500 بُعد نفسي، لنضعك فقط أمام من يتحدث لغتك الفكرية.",
          delay: 0.2,
        ),
        const SizedBox(height: 20),
        _buildFeatureCard(
          context,
          icon: Icons.lock_outline_rounded,
          title: "نهاية التشتت (غرفة التركيز)",
          body: "إذا اخترت التعارف، تُغلق بقية الخيارات. لا مجال للدردشات المتعددة، بل اهتمام كامل بشخص واحد.",
          delay: 0.4,
        ),
        const SizedBox(height: 20),
        _buildFeatureCard(
          context,
          icon: Icons.history_edu_rounded,
          title: "قصيدتكم الأولى",
          body: "عند حدوث التوافق، سيكتب الذكاء الاصطناعي تحليلاً عميقاً وقصيدة شعرية تروي قصة انسجامكما.",
          delay: 0.6,
        ),
      ],
    );
  }

  Widget _buildFeatureCard(BuildContext context, {required IconData icon, required String title, required String body, required double delay}) {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 800),
      curve: Interval(delay, 1.0, curve: Curves.easeOutCubic),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryNavyBlue.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.backgroundBeige.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppTheme.primaryOliveGreen, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                textDirection: TextDirection.rtl,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryNavyBlue,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.primaryNavyBlue.withOpacity(0.7),
                      height: 1.6,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterSection(BuildContext context) {
    return Column(
      children: [
        Divider(color: AppTheme.primaryNavyBlue.withOpacity(0.08)),
        const SizedBox(height: 48),
        Text(
          "الزواج قرار واعٍ... استثمر دقائق في الإجابة بتجرد، واترك لنا مهمة البحث في بحر الأرواح.",
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppTheme.primaryNavyBlue.withOpacity(0.8),
            height: 1.6,
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
        ),
        const SizedBox(height: 32),
        _buildPrimaryButton(context),
      ],
    );
  }

  Widget _buildPrimaryButton(BuildContext context) {
    return ElevatedButton(
      onPressed: _isLoading ? null : _signInGuest,
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 60),
        backgroundColor: AppTheme.primaryOliveGreen,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 0, // AppTheme elevatedButtonTheme dictates elevation 0, but slightly prominent is fine.
      ),
      child: _isLoading
          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Text(
              "البدء بصدق (إنشاء بصمتك النفسية)",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
    );
  }
}
