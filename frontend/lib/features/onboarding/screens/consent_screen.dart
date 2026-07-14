import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/logic/consent.dart';
import '../../../core/theme/app_theme.dart';

/// B2: blocking, versioned consent. On accept, record_consent(current version)
/// then run [onConsented]. Text summarizes legal/consent_v1_ar.md (DRAFT).
class ConsentScreen extends StatefulWidget {
  final VoidCallback onConsented;
  const ConsentScreen({super.key, required this.onConsented});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await Supabase.instance.client
          .rpc('record_consent', params: {'p_version': kCurrentConsentVersion});
      if (mounted) widget.onConsented();
    } catch (e) {
      debugPrint('record_consent failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر حفظ الموافقة. حاول مجددًا.')),
        );
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundIvory,
      appBar: AppBar(
        title: const Text('الموافقة على الخصوصية', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryNavyBlue,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              children: [
                const Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('قبل المتابعة، يرجى الاطلاع والموافقة:',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryNavyBlue)),
                        SizedBox(height: 16),
                        _Point('تُرسَل إجابات الاستبيان النفسي فقط (بدون اسمك أو رقمك) إلى نموذج ذكاء اصطناعي تابع لطرف ثالث (Google) لتحليل توافقك. لا يُرسَل اسمك أو رقمك إطلاقًا.'),
                        _Point('تُحفظ بياناتك حاليًا على خوادم في فرانكفورت (ألمانيا) خلال المرحلة التجريبية، وستُنقل إلى داخل المملكة قبل الإطلاق الرسمي وفق نظام حماية البيانات الشخصية.'),
                        _Point('يمكنك حذف حسابك وكل بياناتك في أي وقت من الإعدادات؛ ولن يحتفظ الطرف الآخر برسائلك.'),
                        _Point('الخدمة متاحة حاليًا للأرقام السعودية فقط وهي في مرحلة تجريبية.'),
                        SizedBox(height: 12),
                        Text('بالضغط على «أوافق» فإنك تقرّ بقراءة ما سبق وتوافق عليه (الإصدار 1).',
                            style: TextStyle(color: Colors.black54)),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: Semantics(
                      button: true,
                      label: 'أوافق على الخصوصية',
                      child: ElevatedButton(
                        onPressed: _busy ? null : _accept,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryOliveGreen,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: _busy
                            ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('أوافق', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  final String text;
  const _Point(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle, color: AppTheme.primaryOliveGreen, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.7, color: Colors.black87))),
          ],
        ),
      );
}
