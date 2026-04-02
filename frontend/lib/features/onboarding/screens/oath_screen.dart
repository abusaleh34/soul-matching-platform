import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'questionnaire_screen.dart';

class OathScreen extends StatelessWidget {
  final String profileId;
  const OathScreen({super.key, required this.profileId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundBeige, // Calming beige background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.primaryNavyBlue),
      ),
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
              const Icon(
                Icons.balance,
                size: 64,
                color: AppTheme.primaryNavyBlue,
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundIvory,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      "الميثاق الغليظ",
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: AppTheme.primaryOliveGreen,
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      "أُقسم بالله العظيم أن هدفي هو الزواج الشرعي، وأن أكون صادقاً في كل إجاباتي، وأن لا أستخدم هذه المنصة للعبث أو تضييع الأوقات، وأن أحفظ خصوصية كل من أُطابق معهم.",
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppTheme.primaryNavyBlue,
                        height: 1.8,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => QuestionnaireScreen(profileId: profileId),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryNavyBlue,
                  minimumSize: const Size(double.infinity, 56),
                ),
                child: const Text("أُقسم على ذلك"),
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
