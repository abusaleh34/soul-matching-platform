import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';

class FocusRoomScreen extends StatefulWidget {
  final Map<String, dynamic> matchData;

  const FocusRoomScreen({super.key, required this.matchData});

  @override
  State<FocusRoomScreen> createState() => _FocusRoomScreenState();
}

class _FocusRoomScreenState extends State<FocusRoomScreen> {
  Timer? _timer;
  Duration _timeLeft = Duration.zero;
  final TextEditingController _chatController = TextEditingController();
  final FocusNode _chatFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  
  Map<String, dynamic>? _partnerProfile;
  late Map<String, dynamic> _currentMatchData;
  StreamSubscription? _matchSubscription;
  bool _isLoadingPartner = true;
  late final Stream<List<Map<String, dynamic>>> _messagesStream;

  @override
  void initState() {
    super.initState();
    _currentMatchData = widget.matchData;
    _startTimer();
    _fetchPartnerData();
    _initMatchRealtimeEngine();
    
    // Extracted Stream to cleanly prevent infinite initialization build loops
    _messagesStream = Supabase.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('match_id', _currentMatchData['id'])
        .order('created_at', ascending: true);
  }
  
  void _initMatchRealtimeEngine() {
    final matchId = widget.matchData['id'];
    _matchSubscription = Supabase.instance.client
        .from('matches')
        .stream(primaryKey: ['id'])
        .eq('id', matchId)
        .listen((events) {
           if (events.isNotEmpty) {
             final updatedMatch = events.first;
             
             // Detect extension safely!
             final oldExtCount = _currentMatchData['extension_count'] ?? 0;
             final newExtCount = updatedMatch['extension_count'] ?? 0;
             
             if (newExtCount > oldExtCount && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم تمديد الغرفة بنجاح لـ 24 ساعة إضافية!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    backgroundColor: AppTheme.primaryOliveGreen,
                  )
                );
             }
             
             if (mounted) {
               setState(() {
                 _currentMatchData = updatedMatch;
               });
               _startTimer(); // Recalculate ticks
             }
           }
        });
  }

  Future<void> _fetchPartnerData() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser!.id;
      final matchId = widget.matchData['id'];

      final matchRecord = await Supabase.instance.client
          .from('matches')
          .select('*')
          .eq('id', matchId)
          .maybeSingle();

      if (matchRecord == null) {
        print('--- DEBUG: MATCH RECORD NOT FOUND IN DB! ---');
        if (mounted) {
           setState(() {
             _partnerProfile = {'first_name': 'شريك', 'age': 'N/A', 'height': 'N/A', 'body_type': 'N/A'};
             _isLoadingPartner = false;
           });
        }
        return;
      }

      print('--- DEBUG MATCH RECORD MAP: $matchRecord ---');
      print('--- DEBUG CURRENT USER ID: $currentUserId ---');

      final partnerId = currentUserId == matchRecord['user1_id'] 
          ? matchRecord['user2_id'] 
          : matchRecord['user1_id'];

      if (partnerId == null) {
        print('--- DEBUG: STILL NULL! currentUserId did not match user1_id or user2_id. ---');
        if (mounted) {
           setState(() {
             _partnerProfile = {'first_name': 'شريك', 'age': 'N/A', 'height': 'N/A', 'body_type': 'N/A'};
             _isLoadingPartner = false;
           });
        }
        return;
      }

      final response = await Supabase.instance.client
          .from('profiles')
          .select('*')
          .eq('id', partnerId)
          .maybeSingle();

      if (response == null) {
        print('DEBUG: No profile found for partnerId: $partnerId');
        if (mounted) {
           setState(() {
             _partnerProfile = {'first_name': 'شريك', 'age': 'N/A', 'height': 'N/A', 'body_type': 'N/A'};
             _isLoadingPartner = false;
           });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _partnerProfile = response;
          _isLoadingPartner = false;
        });
      }
    } catch (e) {
       print("FATAL RLS/FETCH ERROR: $e");
       if (mounted) {
          setState(() {
            _partnerProfile = {'first_name': 'شريك', 'age': 'N/A', 'height': 'N/A', 'body_type': 'N/A'};
            _isLoadingPartner = false;
          });
       }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    final expiresAtStr = _currentMatchData['expires_at'] as String?;
    if (expiresAtStr != null) {
      final expiresAt = DateTime.parse(expiresAtStr).toLocal();
      _updateTimer(expiresAt);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _updateTimer(expiresAt);
      });
    } else {
      if (mounted) setState(() => _timeLeft = Duration.zero);
    }
  }

  void _updateTimer(DateTime expiresAt) {
    final now = DateTime.now();
    if (now.isBefore(expiresAt)) {
      if (mounted) setState(() => _timeLeft = expiresAt.difference(now));
    } else {
      if (mounted) setState(() => _timeLeft = Duration.zero);
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _chatController.dispose();
    _chatFocusNode.dispose();
    _scrollController.dispose();
    _matchSubscription?.cancel();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    final matchId = widget.matchData['id'];
    final prefs = await SharedPreferences.getInstance();
    final localId = prefs.getString('current_user_id');
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? localId;
    if (currentUserId == null) return;

    _chatController.clear();

    try {
      await Supabase.instance.client.from('messages').insert({
        'match_id': matchId,
        'sender_id': currentUserId,
        'content': text,
      });
      
      // Update timer securely triggering the countdown natively strictly to 24 hours
      if (_currentMatchData['expires_at'] == null) {
         final newExpiresAt = DateTime.now().toUtc().add(const Duration(hours: 24)).toIso8601String();
         await Supabase.instance.client.from('matches').update({
             'expires_at': newExpiresAt
         }).eq('id', matchId);
      }
      
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الإرسال: $e', style: const TextStyle(fontWeight: FontWeight.bold))));
      }
    }
  }
  
  Future<void> _onExtendPressed() async {
    final prefs = await SharedPreferences.getInstance();
    final localId = prefs.getString('current_user_id');
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? localId;
    if (currentUserId == null) return;
    
    final isUser1 = _currentMatchData['user1_id'] == currentUserId;
    
    final updateData = isUser1 
        ? {'user1_wants_extension': true} 
        : {'user2_wants_extension': true};

    try {
      await Supabase.instance.client
          .from('matches')
          .update(updateData)
          .eq('id', _currentMatchData['id']);
          
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم إرسال طلب التمديد. ننتظر موافقة الطرف الآخر.", style: TextStyle(fontWeight: FontWeight.bold)),
            backgroundColor: AppTheme.primaryNavyBlue,
          )
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("فشل تقديم الطلب: $e", style: const TextStyle(fontWeight: FontWeight.bold)))
        );
      }
    }
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds";
  }

  @override
  Widget build(BuildContext context) {
    final percentage = _currentMatchData['match_percentage'] ?? 0;
    final reasoning = _currentMatchData['ai_reasoning'] ?? 'لم يتم استخراج سبب';
    final int extensionCount = _currentMatchData['extension_count'] ?? 0;
    
    final prefsStringId = _currentMatchData['user1_id'] ?? ''; // Safe local proxy map
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? prefsStringId; 
    
    // We already know safely routing to this screen guarantees we are either user1 or user2 reliably 
    final isUser1 = _currentMatchData['user1_id'] == currentUserId;
    final bool iHaveRequested = isUser1 
        ? (_currentMatchData['user1_wants_extension'] ?? false)
        : (_currentMatchData['user2_wants_extension'] ?? false);
    
    final partnerIdentity = _isLoadingPartner 
       ? "جاري التحميل..." 
       : (_partnerProfile != null ? "${_partnerProfile!['first_name'] ?? 'شريك'}" : "شريك مجهول");

    return Scaffold(
      backgroundColor: AppTheme.primaryNavyBlue,
      appBar: AppBar(
        title: Text(
            _isLoadingPartner ? "يتم الاتصال..." : (_partnerProfile != null ? "شريكك: ${_partnerProfile!['first_name']?.toString() ?? 'مجهول'}" : "تم العثور على توافق روحي"), 
            style: const TextStyle(fontWeight: FontWeight.bold)
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppTheme.backgroundIvory,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Max Extension Warning Horizon
            if (extensionCount >= 2)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                color: Colors.redAccent.withOpacity(0.2),
                child: const Text("هذا هو اليوم الأخير. حان وقت القرار.", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              
            // 1. Timer Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              color: AppTheme.primaryOliveGreen.withOpacity(0.2),
              child: Column(
                children: [
                  const Text(
                    "الوقت المتبقي للتعارف المبدئي",
                    style: TextStyle(color: AppTheme.backgroundBeige, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatDuration(_timeLeft),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Sleek Extension Button logic injected right above the barrier ONLY under 5 minutes
                  if (extensionCount < 2 && !iHaveRequested && _timeLeft.inMinutes <= 5)
                    TextButton.icon(
                      onPressed: _onExtendPressed,
                      icon: const Icon(Icons.more_time, color: Colors.white),
                      label: const Text("طلب تمديد المحادثة", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.1),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    )
                  else if (extensionCount < 2 && iHaveRequested)
                    const Text("طلب التمديد مُرسل... ننتظر الموافقة", style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),

            // 2. Scrollable Body
            Expanded(
              child: _isLoadingPartner 
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryOliveGreen))
                : CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: AppTheme.primaryOliveGreen, width: 4),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      "$percentage%",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 40,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Text(
                                      "نسبة التوافق",
                                      style: TextStyle(
                                        color: AppTheme.primaryOliveGreen,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          Center(
                            child: Text(
                              _isLoadingPartner 
                                 ? "جاري التحميل..." 
                                 : (_partnerProfile != null ? "تم ربط التوافق الروحي بنجاح" : "شريك مجهول"),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_partnerProfile != null)
                             Center(
                               child: ElevatedButton.icon(
                                  icon: const Icon(Icons.person, color: AppTheme.primaryNavyBlue),
                                  label: const Text("📄 عرض الملف الشخصي الكامل", style: TextStyle(color: AppTheme.primaryNavyBlue, fontWeight: FontWeight.bold, fontSize: 16)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.backgroundIvory,
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  ),
                                  onPressed: () {
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: AppTheme.primaryNavyBlue,
                                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                                      builder: (context) => Padding(
                                        padding: const EdgeInsets.only(left: 24.0, right: 24.0, top: 32.0, bottom: 48.0),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Center(child: Text("ملف ${_partnerProfile!['first_name']?.toString() ?? 'الشريك'} الكامل", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
                                            const SizedBox(height: 32),
                                            
                                            const Text("المعلومات الأساسية", style: TextStyle(color: AppTheme.primaryOliveGreen, fontSize: 18, fontWeight: FontWeight.bold)),
                                            const SizedBox(height: 16),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                Chip(label: Text("الحالة الاجتماعية: ${_partnerProfile!['marital_status']?.toString() ?? 'غير محدد'}", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: Colors.white, side: BorderSide.none),
                                                Chip(label: Text("العمر: ${_partnerProfile!['age']?.toString() ?? 'غير محدد'} سنة", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: Colors.white, side: BorderSide.none),
                                                Chip(label: Text("المدينة: ${_partnerProfile!['city']?.toString() ?? 'غير محدد'}", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: Colors.white, side: BorderSide.none),
                                              ],
                                            ),
                                            
                                            const SizedBox(height: 32),
                                            
                                            const Text("المواصفات الشكلية", style: TextStyle(color: AppTheme.primaryOliveGreen, fontSize: 18, fontWeight: FontWeight.bold)),
                                            const SizedBox(height: 16),
                                            Wrap(
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: [
                                                Chip(label: Text("الطول: ${_partnerProfile!['height']?.toString() ?? 'غير محدد'} سم", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: Colors.white, side: BorderSide.none),
                                                Chip(label: Text("بنية الجسم: ${_partnerProfile!['body_type']?.toString() ?? 'غير محدد'}", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), backgroundColor: Colors.white, side: BorderSide.none),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }
                               )
                             ),
                          const SizedBox(height: 32),

                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                )
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: const [
                                    Icon(Icons.psychology, color: AppTheme.primaryOliveGreen),
                                    SizedBox(width: 8),
                                    Text(
                                      "بصيرة التوافق",
                                      style: TextStyle(
                                        color: AppTheme.primaryOliveGreen,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  reasoning,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 16,
                                    height: 1.8,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                  
                  StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _messagesStream,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const SliverToBoxAdapter(
                            child: Center(child: CircularProgressIndicator(color: AppTheme.primaryOliveGreen)),
                          );
                        }
                        
                        final messages = snapshot.data ?? [];
                        if (messages.isEmpty) {
                          return SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Center(
                                child: Text(
                                  "ასأل بصدق، الحوار مسجل ومؤقت...",
                                  style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
                                ),
                              ),
                            ),
                          );
                        }
                        
                        return SliverPadding(
                          padding: const EdgeInsets.only(bottom: 24),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final msg = messages[index];
                                final isMe = msg['sender_id'] == currentUserId;
                                
                                return Align(
                                  alignment: isMe ? Alignment.centerLeft : Alignment.centerRight,
                                  child: Container(
                                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                                    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isMe ? AppTheme.primaryOliveGreen : Colors.white.withOpacity(0.1),
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(16),
                                        topRight: const Radius.circular(16),
                                        bottomLeft: isMe ? const Radius.circular(0) : const Radius.circular(16),
                                        bottomRight: isMe ? const Radius.circular(16) : const Radius.circular(0),
                                      ),
                                    ),
                                    child: Text(
                                      msg['content'] ?? '',
                                      style: TextStyle(
                                        color: isMe ? Colors.white : Colors.white.withOpacity(0.9), 
                                        fontSize: 16,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                );
                              },
                              childCount: messages.length,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),

            Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primaryNavyBlue,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    )
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _chatController,
                          focusNode: _chatFocusNode,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (text) {
                            _sendMessage();
                            _chatFocusNode.requestFocus();
                          },
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: "اكتب رسالة بصدق...",
                            hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.1),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      CircleAvatar(
                        backgroundColor: AppTheme.primaryOliveGreen,
                        radius: 24,
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white, size: 20),
                          onPressed: _sendMessage,
                        ),
                      )
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
