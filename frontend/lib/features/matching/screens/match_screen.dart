import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/models/match_result.dart';
import '../../../core/services/api_service.dart';
import 'chat_room_screen.dart';

class MatchScreen extends StatefulWidget {
  final String userId;

  const MatchScreen({super.key, required this.userId});

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> with SingleTickerProviderStateMixin {
  late Future<Map<String, dynamic>> _matchFuture;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _matchFuture = ApiService().fetchMatchAnalysis();
    
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryNavyBlue, // Dark, elegant background
      appBar: AppBar(
        title: const Text("نتيجة التطابق"),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        foregroundColor: AppTheme.backgroundIvory,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FutureBuilder<Map<String, dynamic>>(
                future: _matchFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return SizedBox(
                      height: MediaQuery.of(context).size.height * 0.7,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ScaleTransition(
                            scale: _pulseAnimation,
                            child: const Icon(Icons.favorite, color: AppTheme.primaryOliveGreen, size: 80),
                          ),
                          const SizedBox(height: 32),
                          const Text(
                            "جاري تحليل توافق الأرواح بالذكاء الاصطناعي...",
                            style: TextStyle(
                              fontSize: 20, 
                              color: AppTheme.backgroundIvory, 
                              fontWeight: FontWeight.bold
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  } else if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        "حدث خطأ استثنائي أثناء المطابقة:\n${snapshot.error}", 
                        style: const TextStyle(color: Colors.redAccent, fontSize: 18),
                        textAlign: TextAlign.center,
                      ),
                    );
                  } else if (snapshot.hasData) {
                    final data = snapshot.data!;
                    final int score = data['score'] ?? 0;
                    final List<dynamic> strengths = data['strengths'] ?? [];
                    final List<dynamic> challenges = data['challenges'] ?? [];
                    final String quote = data['quote'] ?? 'لم تتم صياغة الخلاصة';

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Circular Indicator
                        Center(
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppTheme.primaryNavyBlue,
                              border: Border.all(color: AppTheme.primaryOliveGreen, width: 8),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryOliveGreen.withOpacity(0.3),
                                  blurRadius: 30,
                                  spreadRadius: 10,
                                )
                              ],
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "$score%",
                                    style: const TextStyle(
                                      fontSize: 56,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.backgroundIvory,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    "نسبة التوافق",
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: AppTheme.backgroundBeige,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 48),
                        
                        // Poetic Summary Card
                        Card(
                          color: AppTheme.backgroundIvory,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                          elevation: 4,
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              children: [
                                const Icon(Icons.format_quote_rounded, color: AppTheme.primaryOliveGreen, size: 48),
                                const SizedBox(height: 16),
                                Text(
                                  quote,
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: AppTheme.primaryNavyBlue,
                                    height: 1.8,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 18,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        
                        // Strengths
                        if (strengths.isNotEmpty) ...[
                          const Text(
                            "نقاط التوافق الجوهرية:",
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.backgroundIvory),
                          ),
                          const SizedBox(height: 16),
                          ...strengths.map((s) => Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.check_circle, color: AppTheme.primaryOliveGreen, size: 24),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(s.toString(), style: const TextStyle(color: AppTheme.backgroundBeige, fontSize: 16, height: 1.5)),
                                ),
                              ],
                            ),
                          )),
                          const SizedBox(height: 32),
                        ],
                        
                        // Frictions
                        if (challenges.isNotEmpty) ...[
                          const Text(
                            "تحديات نفسية محتملة:",
                            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.backgroundIvory),
                          ),
                          const SizedBox(height: 16),
                          ...challenges.map((f) => Padding(
                            padding: const EdgeInsets.only(bottom: 12.0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.info_outline, color: Colors.orangeAccent, size: 24),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(f.toString(), style: const TextStyle(color: AppTheme.backgroundBeige, fontSize: 16, height: 1.5)),
                                ),
                              ],
                            ),
                          )),
                          const SizedBox(height: 32),
                        ],
                      ],
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              
              // Ephemeral Chat Call-To-Action Block
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavyBlue,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFD4AF37).withOpacity(0.5), width: 1.5), // Subtle gold accent
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFD4AF37).withOpacity(0.1),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Friction/Seriousness Badge
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("⏳", style: TextStyle(fontSize: 28)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            "لضمان الجدية التامة، المحادثة ستكون نصية فقط ومحكومة بـ 72 ساعة تغلق بعدها تلقائياً.",
                            style: TextStyle(
                              color: AppTheme.backgroundIvory.withOpacity(0.9), 
                              fontSize: 15, 
                              height: 1.7,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    
                    // Primary Luxurious Button
                    ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ChatRoomScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4AF37), // Luxurious Gold
                        foregroundColor: AppTheme.primaryNavyBlue,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 8,
                        minimumSize: const Size(double.infinity, 60),
                      ),
                      child: const Text(
                        "طلب بدء التعارف النصي", 
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
        ), // ConstrainedBox
        ), // Center
      ),
    );
  }
}
