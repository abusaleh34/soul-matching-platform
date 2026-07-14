import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import 'focus_room_screen.dart';

/// B4: accept/reject a pending match before the room (and its 24h clock) opens.
/// Shows only the partner's SAFE projection (get_partner_profile RPC).
class MatchDecisionScreen extends StatefulWidget {
  final Map<String, dynamic> matchData;
  const MatchDecisionScreen({super.key, required this.matchData});

  @override
  State<MatchDecisionScreen> createState() => _MatchDecisionScreenState();
}

class _MatchDecisionScreenState extends State<MatchDecisionScreen> {
  Map<String, dynamic>? _partner;
  bool _loading = true;
  bool _busy = false;
  bool _decided = false; // this user has decided; waiting on the other
  StreamSubscription? _matchSub;

  String get _matchId => widget.matchData['id'] as String;

  @override
  void initState() {
    super.initState();
    _loadPartner();
    // Auto-advance when the room activates (partner accepts) or closes (reject).
    _matchSub = Supabase.instance.client
        .from('matches')
        .stream(primaryKey: ['id'])
        .eq('id', _matchId)
        .listen(_onMatchChange);
  }

  @override
  void dispose() {
    _matchSub?.cancel();
    super.dispose();
  }

  void _onMatchChange(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty || !mounted) return;
    final status = rows.first['room_status'];
    if (status == 'active') {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => FocusRoomScreen(matchData: rows.first)));
    } else if (status == 'closed' || status == 'expired') {
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _loadPartner() async {
    try {
      final rows = await Supabase.instance.client
          .rpc('get_partner_profile', params: {'p_match_id': _matchId});
      if (!mounted) return;
      setState(() {
        _partner = (rows is List && rows.isNotEmpty)
            ? Map<String, dynamic>.from(rows.first)
            : null;
        _loading = false;
      });
    } catch (e) {
      debugPrint('partner load failed: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _decide(String decision) async {
    setState(() => _busy = true);
    try {
      final res = await Supabase.instance.client
          .rpc('decide_match', params: {'p_match_id': _matchId, 'p_decision': decision});
      if (!mounted) return;
      if (decision == 'accepted') {
        if (res == 'active') {
          final m = await Supabase.instance.client
              .from('matches').select().eq('id', _matchId).maybeSingle();
          if (mounted && m != null) {
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => FocusRoomScreen(matchData: m)));
          }
        } else {
          setState(() => _decided = true); // waiting on the other party
        }
      } else {
        if (mounted) Navigator.pop(context); // rejected -> back to the hunt
      }
    } catch (e) {
      debugPrint('decide failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر تسجيل قرارك. حاول مجددًا.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = widget.matchData['match_percentage'];
    return Scaffold(
      backgroundColor: AppTheme.primaryNavyBlue,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('توافق جديد', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: _loading
                  ? const CircularProgressIndicator(color: AppTheme.primaryOliveGreen)
                  : _decided
                      ? _waitingForOther()
                      : _decisionUi(pct),
            ),
          ),
        ),
      ),
    );
  }

  Widget _waitingForOther() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.hourglass_top, color: AppTheme.primaryOliveGreen, size: 56),
          SizedBox(height: 20),
          Text('بانتظار قبول الطرف الآخر...',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
        ],
      );

  Widget _decisionUi(dynamic pct) {
    final name = _partner?['first_name']?.toString() ?? 'شريك محتمل';
    final age = _partner?['age']?.toString();
    final city = _partner?['city']?.toString();
    final line = [if (age != null) '$age سنة', ?city].join(' • ');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.favorite, color: AppTheme.primaryOliveGreen, size: 64),
        const SizedBox(height: 20),
        Text(name,
            style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center),
        if (line.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(line, style: const TextStyle(color: Colors.white70, fontSize: 18), textAlign: TextAlign.center),
        ],
        if (pct != null) ...[
          const SizedBox(height: 12),
          Text('نسبة التوافق: $pct%',
              style: const TextStyle(color: AppTheme.primaryOliveGreen, fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center),
        ],
        const SizedBox(height: 12),
        const Text('هل ترغب في فتح غرفة تركيز مع هذا الطرف؟',
            style: TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
        const SizedBox(height: 36),
        Semantics(
          button: true,
          label: 'قبول التوافق',
          child: ElevatedButton.icon(
            onPressed: _busy ? null : () => _decide('accepted'),
            icon: const Icon(Icons.check, color: Colors.white),
            label: const Text('قبول', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryOliveGreen,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Semantics(
          button: true,
          label: 'رفض التوافق',
          child: OutlinedButton.icon(
            onPressed: _busy ? null : () => _decide('rejected'),
            icon: const Icon(Icons.close, color: Colors.white70),
            label: const Text('رفض', style: TextStyle(fontSize: 18, color: Colors.white70)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ],
    );
  }
}
