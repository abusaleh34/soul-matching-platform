import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import '../../../core/theme/app_theme.dart';

class ChatRoomScreen extends StatefulWidget {
  const ChatRoomScreen({super.key});

  @override
  State<ChatRoomScreen> createState() => _ChatRoomScreenState();
}

class _ChatRoomScreenState extends State<ChatRoomScreen> with SingleTickerProviderStateMixin {
  // Developer Mock Toggle for Phase 13
  bool isFemale = false; // Toggle this to false to test the Male UX

  late Timer _timer;
  Duration _timeLeft = const Duration(hours: 71, minutes: 59, seconds: 59);
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Bridging Protocol Controllers
  final TextEditingController _waliPhoneController = TextEditingController();
  final TextEditingController _coverStoryController = TextEditingController();

  List<Map<String, dynamic>> messages = [
    {"text": "مرحباً، لفت انتباهي توافقنا العالي. هل يمكننا التحدث لتبادل بعض الأفكار الجوهرية؟", "isMe": false, "time": "10:00 م"},
    {"text": "أهلاً بك. نعم بالتأكيد، يسعدني ذلك.", "isMe": true, "time": "10:05 م"},
  ];

  final List<String> icebreakers = [
    "ما هو أهم مبدأ في حياتك؟",
    "كيف تقضي وقت فراغك عادة؟",
    "ما هو طموحك الأكبر في الحياة؟"
  ];

  @override
  void initState() {
    super.initState();
    _startTimer();
    
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft.inSeconds > 0) {
        setState(() {
          _timeLeft -= const Duration(seconds: 1);
        });
      } else {
        _timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _pulseController.dispose();
    _msgController.dispose();
    _scrollController.dispose();
    _waliPhoneController.dispose();
    _coverStoryController.dispose();
    super.dispose();
  }

  String formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  void _sendMessage() {
    if (_msgController.text.trim().isEmpty) return;
    setState(() {
      messages.add({
        "text": _msgController.text.trim(),
        "isMe": true,
        "time": "الآن",
      });
      _msgController.clear();
    });
    Future.delayed(const Duration(milliseconds: 100), () {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  // Phase 13: Bridging Protocol Handlers
  void _executeBridgingProtocol() {
    if (isFemale) {
      _showFemaleBridgingForm();
    } else {
      _showMaleStandbyModal();
    }
  }

  void _showFemaleBridgingForm() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.primaryNavyBlue,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Text(
                  "بيانات الخطوة الرسمية",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppTheme.backgroundIvory,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  "لضمان خصوصيتك الكبيرة وحفظ ماء الوجه، يرجى تزويد خاطبك بالبيانات التالية لتسهيل العملية.",
                  style: TextStyle(color: AppTheme.backgroundBeige.withOpacity(0.8), fontSize: 13, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                
                // Wali Phone Input
                TextField(
                  controller: _waliPhoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    labelText: "رقم ولي الأمر",
                    labelStyle: TextStyle(color: Colors.black.withOpacity(0.7), fontWeight: FontWeight.bold),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Cover Story Component
                TextField(
                  controller: _coverStoryController,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                  decoration: InputDecoration(
                    labelText: "طريقة التقدم المقترحة لعائلتك",
                    labelStyle: TextStyle(color: Colors.black.withOpacity(0.7), fontWeight: FontWeight.bold),
                    helperText: "(مثال: يفضل أن يخبرهم الخاطب أنه عرفنا عن طريق زميل عمل، أو إحدى القريبات...)",
                    helperMaxLines: 3,
                    helperStyle: const TextStyle(color: Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                ElevatedButton(
                  onPressed: () {
                    // Injecting Mock completion hook
                    Navigator.pop(context); // Close BottomSheet
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("تم الارسال بخصوصية وأمان تام للخاطب. وفقكم الله!", style: TextStyle(fontWeight: FontWeight.bold)),
                        backgroundColor: AppTheme.primaryOliveGreen,
                      )
                    );
                    Navigator.pop(context); // Return to Dash
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryOliveGreen,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text("اعتماد وإرسال للخاطب", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showMaleStandbyModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.primaryNavyBlue,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.shield, color: AppTheme.primaryOliveGreen, size: 64),
              const SizedBox(height: 24),
              const Text(
                "تم تسجيل موافقتك. ننتظر الآن من الطرف الآخر تزويدنا برقم ولي الأمر و (طريقة التقدم الأنسب لعائلتها) لضمان حفظ الخصوصية التامة. سيتم إشعارك فور وصولها.",
                style: TextStyle(
                  color: AppTheme.backgroundIvory, 
                  fontSize: 16, 
                  height: 1.8, 
                  fontWeight: FontWeight.bold
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context); // Close Modal
                  Navigator.pop(context); // Return to Dashboard Map
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryOliveGreen,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text("عودة للرئيسية", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // If Timer hits 0, trigger Phase 13 Gateway Lock organically
    bool isChatLocked = _timeLeft.inSeconds == 0;

    return Scaffold(
      backgroundColor: AppTheme.primaryNavyBlue,
      appBar: AppBar(
        title: Column(
          children: [
            const Text("شريك محتمل - توافق 88%", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.backgroundIvory)),
            const SizedBox(height: 4),
            GestureDetector(
              // DEV MODE TRIGGER: double tap timer to fast forward instantly
              onDoubleTap: () {
                setState(() {
                  _timeLeft = const Duration(seconds: 0);
                });
              },
              child: ScaleTransition(
                scale: _pulseAnimation,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer, size: 16, color: Colors.orangeAccent),
                    const SizedBox(width: 8),
                    Text(
                      isChatLocked ? "انتهى الوقت - الخطوة الرسمية" : formatDuration(_timeLeft),
                      style: const TextStyle(fontSize: 14, color: Colors.orangeAccent, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: AppTheme.primaryNavyBlue,
        elevation: 1,
        iconTheme: const IconThemeData(color: AppTheme.backgroundIvory),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: AppTheme.primaryOliveGreen.withOpacity(0.3), height: 1),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Internal strict warning banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              color: isChatLocked ? AppTheme.primaryOliveGreen.withOpacity(0.8) : Colors.black12,
              child: Text(
                isChatLocked 
                  ? "المحادثة مغلقة. يرجى البدء في تسجيل بيانات التقدم الرسمي."
                  : "تذكير: المحادثة نصية فقط ومراقبة آلياً لضمان الاحترام. ستُغلق نهائياً عند انتهاء العداد.",
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            
            // Messages List
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  final isMe = msg['isMe'] as bool;
                  return Align(
                    alignment: isMe ? Alignment.centerLeft : Alignment.centerRight,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.75,
                      ),
                      decoration: BoxDecoration(
                        color: isMe ? AppTheme.primaryOliveGreen : const Color(0xFF3B4254),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(16),
                          topRight: const Radius.circular(16),
                          bottomLeft: isMe ? Radius.zero : const Radius.circular(16),
                          bottomRight: isMe ? const Radius.circular(16) : Radius.zero,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg['text'],
                            style: const TextStyle(color: AppTheme.backgroundIvory, fontSize: 16, height: 1.5, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: Text(
                              msg['time'],
                              style: TextStyle(color: AppTheme.backgroundIvory.withOpacity(0.6), fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            if (!isChatLocked) ...[
              // Ice Breakers
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavyBlue,
                  border: Border(top: BorderSide(color: AppTheme.primaryOliveGreen.withOpacity(0.2))),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: icebreakers.map((chipText) {
                      return Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: ActionChip(
                          label: Text(chipText, style: const TextStyle(color: AppTheme.primaryNavyBlue, fontWeight: FontWeight.bold)),
                          backgroundColor: AppTheme.backgroundIvory,
                          elevation: 2,
                          onPressed: () {
                            setState(() {
                              if (_msgController.text.isNotEmpty) {
                                _msgController.text += " $chipText";
                              } else {
                                _msgController.text = chipText;
                              }
                            });
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

              // Input Area
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Color(0xFF2A3040),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B4254),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: TextField(
                          controller: _msgController,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            hintText: "اكتب رسالتك النبيلة هنا...",
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.primaryOliveGreen,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryOliveGreen.withOpacity(0.4),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send_rounded, color: AppTheme.backgroundIvory),
                        onPressed: _sendMessage,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Phase 13 Bridging CTA when locked
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: const BoxDecoration(
                  color: Color(0xFF2A3040),
                ),
                child: ElevatedButton(
                  onPressed: _executeBridgingProtocol,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37), // Luxury Gold
                    foregroundColor: AppTheme.primaryNavyBlue,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text("الانتقال للخطوة الرسمية", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
