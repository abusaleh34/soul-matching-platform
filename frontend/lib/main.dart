import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/screens/welcome_screen.dart';
import 'features/onboarding/screens/profile_setup_screen.dart';
import 'features/onboarding/screens/waiting_screen.dart';
import 'features/matching/screens/focus_room_screen.dart';
import 'features/matching/screens/match_decision_screen.dart';
import 'features/matching/screens/admin_dashboard_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/app_config.dart';

// Build-time configuration, injected via --dart-define (see DEPLOYMENT.md).
// No hardcoded fallback: a missing value fails loud below.
const String _kSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _kSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

// Main Application Entry Point
void main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Always expose the semantics tree (accessibility + testability on web).
  binding.ensureSemantics();

  final SupabaseConfig config;
  try {
    config = resolveSupabaseConfig(
      url: _kSupabaseUrl,
      anonKey: _kSupabaseAnonKey,
    );
  } on MissingConfigError catch (e) {
    // Fail loud: never boot against a fallback/leaked project.
    debugPrint(e.toString());
    runApp(const ConfigErrorApp());
    return;
  }

  await Supabase.initialize(
    url: config.url,
    anonKey: config.anonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  runApp(const SmartMatchingApp());
}

/// Shown when required build-time configuration is missing. The app cannot
/// safely connect to Supabase, so it refuses to proceed rather than silently
/// falling back to a default project.
class ConfigErrorApp extends StatelessWidget {
  const ConfigErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'SA'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ar', 'SA')],
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: const Color(0xFF1B2A4A),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.error_outline, color: Colors.white, size: 56),
                  SizedBox(height: 16),
                  Text(
                    'تعذّر تشغيل التطبيق: الإعدادات الأساسية غير متوفرة.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'يرجى التواصل مع فريق الدعم الفني. (خطأ في التهيئة)',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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

      // Web deep-link: /admin is guarded by server-verified is_admin (BRD §3.6/§4.1).
      onGenerateRoute: (settings) {
        if (settings.name == '/admin') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => const AdminGate(),
          );
        }
        return null;
      },
    );
  }
}

/// Authorises the admin dashboard: shows it only when the signed-in user has
/// the server-side is_admin flag (a kDebugMode-only @admin.com bypass is kept
/// strictly behind kDebugMode and never affects release builds).
class AdminGate extends StatefulWidget {
  const AdminGate({super.key});

  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  bool _loading = true;
  bool _allowed = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    bool allowed = false;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        final profile = await Supabase.instance.client
            .from('profiles')
            .select('is_admin')
            .eq('id', user.id)
            .maybeSingle();
        final isAdmin = profile?['is_admin'] as bool? ?? false;
        final debugBypass = kDebugMode && (user.email ?? '').endsWith('@admin.com');
        allowed = isAdmin || debugBypass;
      }
    } catch (e) {
      debugPrint('AdminGate check failed: $e');
    }
    if (mounted) {
      setState(() {
        _allowed = allowed;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundIvory,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primaryOliveGreen)),
      );
    }
    if (!_allowed) {
      return const Scaffold(
        backgroundColor: AppTheme.primaryNavyBlue,
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'لا تملك صلاحية الوصول إلى لوحة الإشراف.',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return const AdminDashboardScreen();
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
        // A pending match awaits accept/reject; an active one opens the room.
        final matchRes = await Supabase.instance.client
            .from('matches')
            .select('id, match_percentage, ai_reasoning, expires_at, room_status, user1_id, user2_id')
            .or('user1_id.eq.$currentUserId,user2_id.eq.$currentUserId')
            .inFilter('room_status', ['pending', 'active'])
            .maybeSingle();

        if (matchRes != null) {
          if (matchRes['room_status'] == 'pending') {
            _safeRoute(MatchDecisionScreen(matchData: matchRes));
          } else {
            _safeRoute(FocusRoomScreen(matchData: matchRes));
          }
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
