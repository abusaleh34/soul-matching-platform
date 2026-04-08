import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/screens/welcome_screen.dart';
import 'features/onboarding/screens/profile_setup_screen.dart';
import 'features/onboarding/screens/waiting_screen.dart';
import 'features/matching/screens/focus_room_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

// Main Application Entry Point
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: 'https://vhayahstcouubjryilvv.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZoYXlhaHN0Y291dWJqcnlpbHZ2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ3MDEwMjgsImV4cCI6MjA5MDI3NzAyOH0.s-tYukv8SUlTW1Vh1iDqmzzeY4-wFUH2-VGPQrxwgEU',
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

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isLoading = true;
  Widget _currentScreen = const WelcomeScreen();

  @override
  void initState() {
    super.initState();
    _checkInitialAuth();
  }

  Future<void> _checkInitialAuth() async {
    try {
      // Small delay crucial for Flutter Web to retrieve local storage seamlessly
      await Future.delayed(const Duration(milliseconds: 500));

      // 4. Session Check: Verify initialize is done and grab the session safely.
      final session = Supabase.instance.client.auth.currentSession;
      
      // Persistant Web Amnesia Recovery Hook
      final prefs = await SharedPreferences.getInstance();
      final localId = prefs.getString('current_user_id');
      
      final currentUserId = session?.user.id ?? localId;

      if (currentUserId == null) {
        _safeRoute(const WelcomeScreen());
        return;
      }

      // 2. Strict Room and Profile Catching Engine
      try {
        // Prioritize querying the active matches table natively for any locks
        final matchRes = await Supabase.instance.client
            .from('matches')
            .select('id, match_percentage, ai_reasoning, expires_at, room_status')
            .or('user1_id.eq.$currentUserId,user2_id.eq.$currentUserId')
            .eq('room_status', 'active')
            .maybeSingle();
            
        if (matchRes != null) {
          _safeRoute(FocusRoomScreen(matchData: matchRes));
          return;
        }

        // Fallback to checking normal un-paired account setup routing hooks
        final profile = await Supabase.instance.client
            .from('profiles') // Assuming 'profiles' table
            .select('account_status')
            .eq('id', currentUserId)
            .maybeSingle();

        if (profile != null && profile['account_status'] != null) {
          final status = profile['account_status'];
          if (status == 'pending' || status == 'active') {
            _safeRoute(WaitingScreen(profileId: currentUserId));
            return;
          }
        }
        
        // Default to setup if profile is null or status is not pending/active
        _safeRoute(const ProfileSetupScreen());
      } catch (queryError) {
        // 3. Safe Fallback Routing: Route safely and log without crashing.
        debugPrint("AuthGate: Query failed. Error: $queryError");
        _safeRoute(const ProfileSetupScreen()); // Route safely per instructions
      }
    } catch (e) {
      debugPrint("AuthGate: Initial auth check failed. Error: $e");
      _safeRoute(const WelcomeScreen());
    }
  }

  void _safeRoute(Widget screen) {
    if (mounted) {
      setState(() {
        _currentScreen = screen;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundIvory,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryOliveGreen),
        ),
      );
    }

    return _currentScreen; // Relies on the robust manual initialization tracking!
  }
}
