import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import 'profile_setup_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _isLoading = false;

  Future<void> _signInGuest() async {
    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.signInAnonymously();
      // Notice: No Navigator.push needed! AuthGate (main.dart) instantly redirects to ProfileSetupScreen based on onAuthStateChange hook!
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
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // Minimal, elegant branding space (e.g., Logo)
              const Icon(
                Icons.favorite_border_rounded,
                size: 80,
                color: AppTheme.primaryOliveGreen,
              ),
              const SizedBox(height: 48),
              Text(
                "لأن الأرواح جنودٌ مجندة...",
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: AppTheme.primaryOliveGreen,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                "ولا تُقاس بالسنتيمترات.",
                style: Theme.of(context).textTheme.headlineLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Text(
                "منصة توافق مبنية على القيم والأخلاق، لا على المظاهر الخادعة.",
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.primaryNavyBlue.withOpacity(0.7),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _isLoading ? null : _signInGuest,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                ),
                child: _isLoading 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppTheme.primaryNavyBlue, strokeWidth: 2))
                    : const Text("البدء بصدق (تسجيل مجهول)"),
              ),
            ],
          ),
        ),
        ), // ConstrainedBox
        ), // Center
      ),
    );
  }
}
