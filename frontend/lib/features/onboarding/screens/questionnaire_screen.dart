import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/api_service.dart';
import '../../matching/screens/match_screen.dart';
import 'waiting_screen.dart';

class QuestionnaireScreen extends StatefulWidget {
  final String profileId;
  const QuestionnaireScreen({super.key, required this.profileId});

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  final int _totalPages = 4;
  
  // Store structured answers from Choice Questions
  final Map<String, String> _choices = {};

  // Store unstructured answers from Text Questions
  final Map<String, TextEditingController> _textControllers = {
    'q4': TextEditingController(),
    'q5': TextEditingController(),
    'q6': TextEditingController(),
    'q7': TextEditingController(),
    'q8': TextEditingController(),
    'q9': TextEditingController(),
    'q12': TextEditingController(),
  };

  @override
  void dispose() {
    _pageController.dispose();
    for (var controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool _canProceed() {
    List<String> requiredQuestions = [];
    if (_currentPage == 0) requiredQuestions = ['q1', 'q2', 'q3'];
    else if (_currentPage == 1) requiredQuestions = ['q4', 'q5', 'q6'];
    else if (_currentPage == 2) requiredQuestions = ['q7', 'q8', 'q9'];
    else if (_currentPage == 3) requiredQuestions = ['q10', 'q11', 'q12'];

    for (var qId in requiredQuestions) {
      if (_textControllers.containsKey(qId)) {
        if (_textControllers[qId]!.text.trim().length < 30) {
          return false;
        }
      } else {
        if (!_choices.containsKey(qId)) {
          return false;
        }
      }
    }
    return true;
  }

  bool _validateCurrentPage() {
    return _canProceed();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Tajawal')),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _nextPage() {
    if (!_validateCurrentPage()) return;
    
    // Merge TextFields into unified Answers Map
    _textControllers.forEach((key, controller) {
      if (controller.text.trim().isNotEmpty) {
        _choices[key] = controller.text.trim();
      }
    });

    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    } else {
      _finishQuestionnaire();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _finishQuestionnaire() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: AppTheme.backgroundIvory,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppTheme.primaryOliveGreen),
                const SizedBox(height: 32),
                Text(
                  "جاري دراسة الأجوبة\nومعالجة الاستبيان النفسي...",
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppTheme.primaryOliveGreen,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );

    // Logging Unified Output Prior to Network
    print("--- Final Unified Psychological Extract ---");
    _choices.forEach((key, value) {
      print("$key: $value");
    });
    
    final apiService = ApiService();
    final success = await apiService.submitQuestionnaire(_choices);

    if (mounted) {
      Navigator.pop(context); // Dismiss loading overlay
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم تشفير الاستبيان وإرساله بنجاح!", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Tajawal')),
            backgroundColor: AppTheme.primaryOliveGreen,
          )
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => WaitingScreen(profileId: widget.profileId),
          ),
        );
      } else {
        _showError("حدث خطأ أثناء مزامنة الاستبيان النفسي مع السحابة.");
      }
    }
  }

  Widget _buildChoiceQuestion(String id, String questionText, List<String> options) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            questionText,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryNavyBlue),
          ),
          const SizedBox(height: 16),
          ...options.map((option) {
            final isSelected = _choices[id] == option;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: InkWell(
                onTap: () {
                  setState(() {
                    _choices[id] = option;
                  });
                },
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                  decoration: BoxDecoration(
                    color: isSelected ? AppTheme.primaryOliveGreen : AppTheme.backgroundIvory,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? AppTheme.primaryOliveGreen : AppTheme.primaryNavyBlue.withOpacity(0.15),
                      width: 1.5,
                    ),
                    boxShadow: isSelected ? [
                      BoxShadow(color: AppTheme.primaryOliveGreen.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))
                    ] : [],
                  ),
                  child: Text(
                    option,
                    style: TextStyle(
                      fontSize: 16,
                      color: isSelected ? Colors.white : AppTheme.primaryNavyBlue,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTextQuestion(String id, String questionText, {int maxLines = 4}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            questionText,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryNavyBlue),
          ),
          const SizedBox(height: 16),
          TextFormField(
            autovalidateMode: AutovalidateMode.onUserInteraction,
            controller: _textControllers[id],
            maxLines: maxLines,
            style: const TextStyle(color: AppTheme.primaryNavyBlue, fontSize: 16),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: "اكتب إجابتك هنا بصدق وتفصيل...",
              hintStyle: TextStyle(color: AppTheme.primaryNavyBlue.withOpacity(0.4)),
              filled: true,
              fillColor: AppTheme.backgroundIvory,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: AppTheme.primaryNavyBlue.withOpacity(0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppTheme.primaryOliveGreen, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.redAccent, width: 2),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Colors.redAccent, width: 2),
              ),
              errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            validator: (v) {
              if (v == null || v.trim().length < 30) {
                return "يرجى كتابة إجابة مفصلة تعبر عنك (لا تقل عن 30 حرفاً)";
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPage1() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "نمط الحياة والأسلوب",
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppTheme.primaryOliveGreen),
          ),
          const SizedBox(height: 12),
          const Text(
            "أسئلة سريعة حول تفضيلاتك في العيش",
            style: TextStyle(fontSize: 16, color: AppTheme.primaryNavyBlue),
          ),
          const SizedBox(height: 48),
          _buildChoiceQuestion(
            'q1',
            "صف عطلة نهاية الأسبوع المثالية بالنسبة لك:",
            [
              "الراحة والهدوء في المنزل.",
              "مغامرات وأنشطة خارجية متنوعة.",
              "تجمعات اجتماعية وزيارات عائلية متقاربة."
            ],
          ),
          _buildChoiceQuestion(
            'q2',
            "ما هو أقرب أسلوب لك في الإدارة المالية؟",
            [
              "وضع ميزانية صارمة والالتزام الدقيق بها.",
              "إنفاق مرن يعتمد على الاحتياجات والرفاهية.",
              "ميل للادخار والاستثمار المفرط للوصول للأمان السريع."
            ],
          ),
          _buildChoiceQuestion(
            'q3',
            "ما مدى أهمية الانخراط المستمر مع العائلة الممتدة؟",
            [
              "مهم جداً (تواصل يومي وزيارات متقاربة).",
              "متوسط (زيارات مرنة وتواصل متوازن).",
              "نادر (أفضل الاستقلالية القصوى والحدود الصارمة)."
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPage2() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "الذكاء العاطفي",
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppTheme.primaryOliveGreen),
          ),
          const SizedBox(height: 12),
          const Text(
            "أسئلة تطلب إجابات حرة، تعكس العمق الداخلي للروح",
            style: TextStyle(fontSize: 16, color: AppTheme.primaryNavyBlue),
          ),
          const SizedBox(height: 48),
          _buildTextQuestion('q4', "عند حدوث خلاف حاد، هل تفضل الصمت المؤقت أم النقاش الفوري؟ ولماذا؟"),
          _buildTextQuestion('q5', "كيف تقوم عادةً بمعالجة وتلقي النقد البناء من الموثوقين حولك؟"),
          _buildTextQuestion('q6', "صف موقفاً من الماضي اضطررت فيه لتقديم تنازل مهم لأجل علاقة أو شخص. كيف شعرت حينها؟"),
        ],
      ),
    );
  }

  Widget _buildPage3() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "القيم والتربية",
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppTheme.primaryOliveGreen),
          ),
          const SizedBox(height: 12),
          const Text(
            "أسئلة تعكس بوصلة المبادئ وأساسيات إنشاء عائلة المستقبل",
            style: TextStyle(fontSize: 16, color: AppTheme.primaryNavyBlue),
          ),
          const SizedBox(height: 48),
          _buildTextQuestion('q7', "ما هما القيمتان الأساسيتان اللتان لا تتنازل عن غرسها في أبنائك بالمستقبل؟"),
          _buildTextQuestion('q8', "لو اختلفت بشدة مع شريك حياتك حول قرار تربوي مصيري، كيف ستسعى للحل؟"),
          _buildTextQuestion('q9', "في الحياة اليومية العملية، ما هو المفهوم الحقيقي لـ 'الولاء والإخلاص' بالنسبة لك شخصيًا؟", maxLines: 5),
        ],
      ),
    );
  }

  Widget _buildPage4() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "المحددات والخطوط الحمراء",
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: AppTheme.primaryOliveGreen),
          ),
          const SizedBox(height: 12),
          const Text(
            "الأسئلة الختامية لحسم الفوارق الجوهرية (التعقيبات الحاسمة)",
            style: TextStyle(fontSize: 16, color: AppTheme.primaryNavyBlue),
          ),
          const SizedBox(height: 48),
          _buildChoiceQuestion(
            'q10',
            "ما هو مستوى طموحك المهني؟",
            [
              "طموح عالٍ جداً، ومستعد للعمل الطويل أو التضحية ببعض الوقت الأسري للنجاح.",
              "متوازن، أعطي العمل والأسرة مقادير عادلة.",
              "أميل للراحة والاستقرار ولست مولعاً بالسباقات المهنية الحادة."
            ],
          ),
          _buildChoiceQuestion(
            'q11',
            "ما مدى تحملك لفترات البعد الجغرافي الطويلة في حال تطلّب العمل ذلك للمستقبل؟",
            [
              "تحمل عالٍ، المهم التخطيط للمستقبل.",
              "تحمل منخفض، لا أفضل التباعد المستمر.",
              "مرفوض تماماً، أريد الاستقرار التام (الخط الأحمر)."
            ],
          ),
          _buildTextQuestion('q12', "أخيراً، ما هو التوقع الوحيـد وغير القابل للتفاوض أو الإعذار الذي تتطلبه في شريك حياتك؟", maxLines: 5),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundBeige,
      appBar: AppBar(
        title: const Text("الميثاق النفسي"),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppTheme.primaryNavyBlue,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
          children: [
            // Linear Progress Indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
              child: AnimatedProgressBar(
                progress: (_currentPage + 1) / _totalPages,
              ),
            ),
            
            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // Disable swipe to enforce logical validation checks
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                children: [
                  _buildPage1(),
                  _buildPage2(),
                  _buildPage3(),
                  _buildPage4(),
                ],
              ),
            ),
            
            // Bottom Action Bar
            Container(
              padding: const EdgeInsets.all(24.0),
              decoration: BoxDecoration(
                color: AppTheme.backgroundIvory,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    offset: const Offset(0, -6),
                    blurRadius: 20,
                  )
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_currentPage > 0)
                    TextButton(
                      onPressed: _previousPage,
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryNavyBlue,
                        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      child: const Text("رجوع"),
                    )
                  else
                    const SizedBox.shrink(),
                  
                  ElevatedButton(
                    onPressed: _canProceed() ? _nextPage : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryOliveGreen,
                      disabledBackgroundColor: Colors.grey.withOpacity(0.3),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    child: Text(
                      _currentPage == _totalPages - 1 ? "حفظ الميثاق والمطابقة" : "التالي",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ), // ConstrainedBox
      ), // Center
    );
  }
}

// Custom animated progress bar
class AnimatedProgressBar extends StatelessWidget {
  final double progress;

  const AnimatedProgressBar({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: constraints.maxWidth,
          height: 10,
          decoration: BoxDecoration(
            color: AppTheme.backgroundIvory,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.fastOutSlowIn,
                width: constraints.maxWidth * progress,
                decoration: BoxDecoration(
                  color: AppTheme.primaryOliveGreen,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
