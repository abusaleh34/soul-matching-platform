import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/screens/welcome_screen.dart';
import 'features/onboarding/screens/profile_setup_screen.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

// Main Application Entry Point
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: 'https://vhayahstcouubjryilvv.supabase.co',
    anonKey: '***REMOVED***',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  runApp(const SmartMatchingApp());
}

class SmartMatchingApp extends StatelessWidget {
  const SmartMatchingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Matching Platform',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      
      // Enforce RTL (Right-to-Left) Native Arabic Support
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ar', 'SA'), // Saudi Arabia Arabic
      ],
      locale: const Locale('ar', 'SA'),
      
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: AppTheme.primaryOliveGreen)),
          );
        }
        
        final session = Supabase.instance.client.auth.currentSession;
        if (session != null) {
          return const ProfileSetupScreen();
        }
        
        return const WelcomeScreen();
      },
    );
  }
}
