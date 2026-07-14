import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../onboarding/screens/welcome_screen.dart';

/// B3: settings with the delete-account (right to erasure) flow, double
/// confirmation, Arabic.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _api = ApiService();
  bool _busy = false;

  Future<bool> _confirm(String title, String body, String confirmLabel) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(body, style: const TextStyle(height: 1.6)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel, style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return r ?? false;
  }

  Future<void> _deleteAccount() async {
    if (!await _confirm('حذف الحساب', 'هل أنت متأكد من رغبتك في حذف حسابك؟', 'متابعة')) return;
    if (!await _confirm('تأكيد نهائي',
        'سيتم حذف ملفك وجميع رسائلك وبياناتك نهائيًا، ولا يمكن التراجع عن ذلك. هل تؤكد؟', 'حذف نهائي')) {
      return;
    }
    setState(() => _busy = true);
    try {
      final ok = await _api.deleteMe();
      if (!ok) throw Exception('server refused');
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('current_user_id');
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()), (r) => false);
    } catch (e) {
      debugPrint('delete account failed: $e');
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر حذف الحساب. حاول مجددًا لاحقًا.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundIvory,
      appBar: AppBar(
        title: const Text('الإعدادات', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryNavyBlue,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
              title: const Text('حذف الحساب', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('حذف نهائي لجميع بياناتك (حق المحو - PDPL)'),
              trailing: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.chevron_left),
              onTap: _busy ? null : _deleteAccount,
            ),
            const Divider(),
          ],
        ),
      ),
    );
  }
}
