import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../../core/utils/focus_room_format.dart';
import '../logic/message_send.dart';
import 'notification_bell.dart';

class FocusRoomScreen extends StatefulWidget {
  final Map<String, dynamic> matchData;

  const FocusRoomScreen({super.key, required this.matchData});

  @override
  State<FocusRoomScreen> createState() => _FocusRoomScreenState();
}

class _FocusRoomScreenState extends State<FocusRoomScreen> {
  final ApiService _api = ApiService();
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
  int _previousMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _currentMatchData = widget.matchData;
    _startTimer();
    _fetchPartnerData();
    _initMatchRealtimeEngine();

    // Stream created exactly once in initState (BRD §4.2 — no re-init flicker).
    _messagesStream = Supabase.instance.client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('match_id', _currentMatchData['id'])
        .order('created_at', ascending: true);
  }

  bool get _isExpired => isRoomExpired(
        parseTimestamp(_currentMatchData['expires_at'] as String?),
        _currentMatchData['room_status'] as String?,
        DateTime.now(),
      );

  void _initMatchRealtimeEngine() {
    final matchId = widget.matchData['id'];
    // Passive subscription: keep room status/expiry fresh. Matches are
    // read-only for clients (RLS) — no client-side writes here.
    _matchSubscription = Supabase.instance.client
        .from('matches')
        .stream(primaryKey: ['id'])
        .eq('id', matchId)
        .listen((events) {
      if (events.isNotEmpty && mounted) {
        setState(() => _currentMatchData = events.first);
        _startTimer();
      }
    });
  }

  Future<void> _fetchPartnerData() async {
    try {
      final matchId = widget.matchData['id'];
      // Minimised partner view: server-side function returns only safe display
      // columns (never questionnaire_answers / psychological_profile / is_admin).
      final result = await Supabase.instance.client
          .rpc('get_partner_profile', params: {'p_match_id': matchId});

      if (result is List && result.isNotEmpty) {
        if (mounted) {
          setState(() {
            _partnerProfile = Map<String, dynamic>.from(result.first as Map);
            _isLoadingPartner = false;
          });
        }
        return;
      }
      _setFallbackPartner();
    } catch (e) {
      debugPrint('Partner fetch error: $e');
      _setFallbackPartner();
    }
  }

  void _setFallbackPartner() {
    if (!mounted) return;
    setState(() {
      _partnerProfile = {'first_name': 'شريك', 'age': 'N/A', 'height': 'N/A', 'body_type': 'N/A'};
      _isLoadingPartner = false;
    });
  }

  void _startTimer() {
    _timer?.cancel();
    final expiresAt = parseTimestamp(_currentMatchData['expires_at'] as String?);
    if (expiresAt == null) {
      if (mounted) setState(() => _timeLeft = Duration.zero);
      return;
    }
    _updateTimer(expiresAt);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTimer(expiresAt));
  }

  void _updateTimer(DateTime expiresAt) {
    final left = timeLeftUntil(expiresAt, DateTime.now());
    if (mounted) setState(() => _timeLeft = left);
    if (left == Duration.zero) _timer?.cancel();
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

    if (_isExpired) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('انتهى وقت غرفة التركيز. لا يمكن إرسال رسائل جديدة.')),
        );
      }
      return;
    }

    // sender_id MUST be the authenticated session user (RLS: sender_id =
    // auth.uid()). No cached-id fallback — that would be an unauthenticated
    // insert and fail with 42501.
    final user = Supabase.instance.client.auth.currentUser;
    final req = buildMessageRequest(
      authUserId: user?.id,
      matchId: widget.matchData['id'] as String?,
      content: text,
    );
    if (req == null) {
      if (user == null && mounted) {
        _showSendError('انتهت الجلسة. الرجاء إعادة تسجيل الدخول ثم المحاولة.', canRetry: false);
      }
      return; // keep the typed text so nothing is lost
    }

    try {
      await Supabase.instance.client.from('messages').insert({
        'match_id': req.matchId,
        'sender_id': req.senderId,
        'content': req.content,
      });
      _chatController.clear(); // clear ONLY after a successful send
    } on PostgrestException catch (e) {
      // Surface the real Postgres error (e.g. 42501 RLS / 23503 FK) so failures
      // are diagnosable, and keep a retry path instead of a dead-end banner.
      debugPrint('Message send failed: code=${e.code} message=${e.message}');
      if (mounted) {
        _showSendError(
          'تعذّر إرسال الرسالة${e.code != null && e.code!.isNotEmpty ? ' (رمز ${e.code})' : ''}. الرجاء إعادة المحاولة.',
          canRetry: true,
        );
      }
    } catch (e) {
      debugPrint('Message send failed: $e');
      if (mounted) {
        _showSendError('تعذّر إرسال الرسالة. تحقق من اتصالك ثم أعد المحاولة.', canRetry: true);
      }
    }
  }

  void _showSendError(String message, {required bool canRetry}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 6),
        action: canRetry
            ? SnackBarAction(
                label: 'إعادة المحاولة',
                textColor: Colors.white,
                onPressed: _sendMessage,
              )
            : null,
      ),
    );
  }

  void _showCounselorAdviceBottomSheet(BuildContext context) {
    // Create the stream once (broadcast) so sheet rebuilds don't restart it.
    final adviceStream =
        _api.streamCounselorAdvice(_currentMatchData['id']).asBroadcastStream();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.primaryNavyBlue,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return StreamBuilder<String>(
              stream: adviceStream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                          const SizedBox(height: 16),
                          Text(
                            'تعذر الاتصال بالمستشار الذكي:\n${snapshot.error}',
                            style: const TextStyle(color: Colors.redAccent, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final advice = snapshot.data ?? '';
                final isDone = snapshot.connectionState == ConnectionState.done;

                // Before the first chunk arrives, show the retrieval animation.
                if (advice.isEmpty && !isDone) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Color(0xFFD4AF37)),
                          SizedBox(height: 24),
                          Text(
                            'جاري تحليل أنماط التواصل وبناء التوصيات الزوجية...',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24.0),
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Row(
                      children: [
                        Icon(Icons.stars, color: Color(0xFFD4AF37), size: 28),
                        SizedBox(width: 12),
                        Text(
                          'نصيحة المستشار الأسري الذكي',
                          style: TextStyle(color: Color(0xFFD4AF37), fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Text(
                        advice.isEmpty ? 'لا توجد نصيحة حالية.' : advice,
                        style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.8),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    if (!isDone) ...[
                      const SizedBox(height: 16),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD4AF37)),
                          ),
                          SizedBox(width: 8),
                          Text('يكتب المستشار...',
                              style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 32),
                    ElevatedButton(
                      onPressed: isDone ? () => Navigator.pop(context) : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryOliveGreen,
                        disabledBackgroundColor: Colors.grey.withValues(alpha: 0.3),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('فهمت النصيحة',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final percentage = _currentMatchData['match_percentage'] ?? 0;
    final reasoning = _currentMatchData['ai_reasoning'] ?? 'لم يتم استخراج سبب';
    final prefsStringId = _currentMatchData['user1_id'] ?? '';
    final currentUserId = Supabase.instance.client.auth.currentUser?.id ?? prefsStringId;
    final expired = _isExpired;

    return Scaffold(
      backgroundColor: AppTheme.primaryNavyBlue,
      appBar: AppBar(
        title: Text(
          _isLoadingPartner
              ? 'يتم الاتصال...'
              : (_partnerProfile != null
                  ? 'شريكك: ${_partnerProfile!['first_name']?.toString() ?? 'مجهول'}'
                  : 'تم العثور على توافق روحي'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppTheme.backgroundIvory,
        actions: const [NotificationBell()],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Timer header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              color: (expired ? Colors.redAccent : AppTheme.primaryOliveGreen).withValues(alpha: 0.2),
              child: Column(
                children: [
                  Text(
                    expired ? 'انتهى وقت التعارف المبدئي' : 'الوقت المتبقي للتعارف المبدئي',
                    style: const TextStyle(color: AppTheme.backgroundBeige, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    expired ? '00:00:00' : formatCountdown(_timeLeft),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),

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
                                          Text('$percentage%',
                                              style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
                                          const Text('نسبة التوافق',
                                              style: TextStyle(color: AppTheme.primaryOliveGreen, fontSize: 14)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const Center(
                                  child: Text('تم ربط التوافق الروحي بنجاح',
                                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                      textAlign: TextAlign.center),
                                ),
                                const SizedBox(height: 16),
                                if (_partnerProfile != null) _buildPartnerProfileButton(context),
                                const SizedBox(height: 32),
                                _buildReasoningCard(reasoning),
                                const SizedBox(height: 32),
                                _buildCounselorCard(expired),
                                const SizedBox(height: 32),
                              ],
                            ),
                          ),
                        ),
                        _buildMessagesSliver(currentUserId),
                      ],
                    ),
            ),

            _buildComposer(expired),
          ],
        ),
      ),
    );
  }

  Widget _buildPartnerProfileButton(BuildContext context) {
    return Center(
      child: ElevatedButton.icon(
        icon: const Icon(Icons.person, color: AppTheme.primaryNavyBlue),
        label: const Text('📄 عرض الملف الشخصي الكامل',
            style: TextStyle(color: AppTheme.primaryNavyBlue, fontWeight: FontWeight.bold, fontSize: 16)),
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
                  Center(
                      child: Text('ملف ${_partnerProfile!['first_name']?.toString() ?? 'الشريك'} الكامل',
                          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 32),
                  const Text('المعلومات الأساسية',
                      style: TextStyle(color: AppTheme.primaryOliveGreen, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _chip('الحالة الاجتماعية: ${_partnerProfile!['marital_status']?.toString() ?? 'غير محدد'}'),
                    _chip('العمر: ${_partnerProfile!['age']?.toString() ?? 'غير محدد'} سنة'),
                    _chip('المدينة: ${_partnerProfile!['city']?.toString() ?? 'غير محدد'}'),
                  ]),
                  const SizedBox(height: 32),
                  const Text('المواصفات الشكلية',
                      style: TextStyle(color: AppTheme.primaryOliveGreen, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    _chip('الطول: ${_partnerProfile!['height']?.toString() ?? 'غير محدد'} سم'),
                    _chip('بنية الجسم: ${_partnerProfile!['body_type']?.toString() ?? 'غير محدد'}'),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _chip(String label) => Chip(
        label: Text(label, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        side: BorderSide.none,
      );

  Widget _buildReasoningCard(Object reasoning) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.psychology, color: AppTheme.primaryOliveGreen),
            SizedBox(width: 8),
            Text('بصيرة التوافق',
                style: TextStyle(color: AppTheme.primaryOliveGreen, fontSize: 18, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 16),
          Text('$reasoning',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 16, height: 1.8),
              textAlign: TextAlign.right),
        ],
      ),
    );
  }

  Widget _buildCounselorCard(bool expired) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFFD4AF37).withValues(alpha: 0.15), Colors.white.withValues(alpha: 0.02)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD4AF37).withValues(alpha: 0.4), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(children: [
            Icon(Icons.stars, color: Color(0xFFD4AF37), size: 28),
            SizedBox(width: 12),
            Text('المستشار الذكي ما بعد الزواج',
                style: TextStyle(color: Color(0xFFD4AF37), fontSize: 18, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 12),
          Text(
            expired
                ? 'انتهت صلاحية الغرفة، لم يعد بإمكانك طلب نصيحة المستشار.'
                : 'استخرج نصيحة تواصل ذهبية مخصصة من الذكاء الاصطناعي بناءً على تحليل ملفاتكما النفسية مجتمعة.',
            style: TextStyle(color: AppTheme.backgroundBeige.withValues(alpha: 0.8), fontSize: 14, height: 1.6),
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            icon: const Icon(Icons.psychology, color: AppTheme.primaryNavyBlue),
            label: const Text('الحصول على النصيحة الذكية',
                style: TextStyle(color: AppTheme.primaryNavyBlue, fontWeight: FontWeight.bold, fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              disabledBackgroundColor: Colors.grey.withValues(alpha: 0.3),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: expired ? null : () => _showCounselorAdviceBottomSheet(context),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesSliver(Object currentUserId) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _messagesStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const SliverToBoxAdapter(
            child: Center(child: CircularProgressIndicator(color: AppTheme.primaryOliveGreen)),
          );
        }

        final messages = snapshot.data ?? [];

        if (messages.length > _previousMessageCount) {
          _previousMessageCount = messages.length;
          final matchId = _currentMatchData['id'] as String;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Active-chat suppression scoped to THIS match + read receipts.
            _api.markMatchNotificationsAsRead(matchId);
            _api.markMessagesAsRead(matchId);
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          });
        }

        if (messages.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Center(
                child: Text('اسأل بصدق، الحوار مسجل ومؤقت...',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14)),
              ),
            ),
          );
        }

        return SliverPadding(
          padding: const EdgeInsets.only(bottom: 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _buildBubble(messages[index], currentUserId),
              childCount: messages.length,
            ),
          ),
        );
      },
    );
  }

  Widget _buildBubble(Map<String, dynamic> msg, Object currentUserId) {
    final isMe = msg['sender_id'] == currentUserId;
    final createdAt = parseTimestamp(msg['created_at'] as String?);
    final timeStr = createdAt != null ? formatArabicTime(createdAt) : '';

    return Align(
      alignment: isMe ? Alignment.centerLeft : Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.start : CrossAxisAlignment.end,
          children: [
            Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isMe ? AppTheme.primaryOliveGreen : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isMe ? Radius.zero : const Radius.circular(16),
                  bottomRight: isMe ? const Radius.circular(16) : Radius.zero,
                ),
              ),
              child: Text(msg['content'] ?? '',
                  style: TextStyle(color: isMe ? Colors.white : Colors.white.withValues(alpha: 0.9), fontSize: 16, height: 1.4)),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(timeStr, style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 10)),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(Icons.done_all,
                        size: 14,
                        color: (msg['is_read'] ?? false)
                            ? AppTheme.primaryOliveGreen
                            : Colors.white.withValues(alpha: 0.4)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer(bool expired) {
    if (expired) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        color: AppTheme.primaryNavyBlue,
        child: SafeArea(
          top: false,
          child: Text(
            'انتهى وقت غرفة التركيز. المحادثة مغلقة الآن.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(color: AppTheme.primaryNavyBlue),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _chatController,
                focusNode: _chatFocusNode,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) {
                  _sendMessage();
                  _chatFocusNode.requestFocus();
                },
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'اكتب رسالة بصدق...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.1),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
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
            ),
          ],
        ),
      ),
    );
  }
}
