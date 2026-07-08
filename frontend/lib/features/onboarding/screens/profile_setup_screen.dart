import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/data/saudi_cities.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'oath_screen.dart';
import 'welcome_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();

  // Core Data
  final TextEditingController _firstNameController = TextEditingController();
  String? _gender;
  String? _age;
  String? _height;
  String? _bodyType;
  
  // Partner Preferences
  String? _prefMinAge;
  String? _prefMaxAge;
  String? _prefMinHeight;
  String? _prefBodyType;
  String? _maritalStatus;
  String? _hasChildren; 
  String? _childrenLiving;
  String? _polygamyPref;
  String? _desiredWife; // Extra Smart Polygamy param
  String? _educationLevel;
  String? _employmentStatus;
  String? _smokingHabit;

  // City: self-declared from a fixed list (data minimisation — no geolocation,
  // no third-party geocode). Country is KSA-only per the product's target market.
  static const String _country = 'المملكة العربية السعودية';
  String? _selectedCity;

  // Options
  final List<String> _genders = ['ذكر', 'أنثى'];
  final List<String> _educationLevels = ['ثانوي', 'دبلوم', 'بكالوريوس', 'ماجستير', 'دكتوراه'];
  final List<String> _employmentStatuses = ['موظف حكومي', 'موظف قطاع خاص', 'صاحب عمل حر', 'طالب', 'باحث عن عمل', 'متقاعد'];
  final List<String> _yesNo = ['نعم', 'لا'];
  
  final List<String> _ages = List.generate(48, (i) => (18 + i).toString()); // 18 to 65
  final List<String> _heights = List.generate(81, (i) => (140 + i).toString()); // 140 to 220
  final List<String> _bodyTypes = ['نحيف', 'رياضي', 'متوسط', 'ممتلئ'];
  final List<String> _prefBodyTypes = ['نحيف', 'رياضي', 'متوسط', 'ممتلئ', 'لا يهم'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Supabase.instance.client.auth.currentUser == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("عذراً، الجلسة انتهت. الرجاء تسجيل الدخول مجدداً.", style: TextStyle(fontFamily: 'Tajawal', fontWeight: FontWeight.bold)),
            backgroundColor: Colors.redAccent,
          )
        );
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const WelcomeScreen()));
      }
    });
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    super.dispose();
  }

  List<String> get _maritalStatusOptions {
    if (_gender == 'أنثى') {
      return ['عزباء', 'مطلقة', 'أرملة'];
    } else if (_gender == 'ذكر') {
      return ['أعزب', 'مطلق', 'أرمل', 'متزوج'];
    }
    return [];
  }

  bool _isFormValid() {
    if (_selectedCity == null) return false;
    if (_gender == null) return false;
    if (_maritalStatus == null) return false;
    if (_educationLevel == null) return false;
    if (_employmentStatus == null) return false;
    if (_smokingHabit == null) return false;
    
    // Status specific
    bool isSingle = (_gender == 'ذكر' && _maritalStatus == 'أعزب') || (_gender == 'أنثى' && _maritalStatus == 'عزباء');
    if (!isSingle) {
      if (_hasChildren == null) return false;
      if (_hasChildren == 'نعم' && _childrenLiving == null) return false;
    }

    if (_gender == 'أنثى' && _polygamyPref == null) return false;
    if (_gender == 'ذكر' && _maritalStatus == 'متزوج' && _desiredWife == null) return false;

    if (_firstNameController.text.trim().isEmpty) return false;
    if (_age == null || _height == null || _bodyType == null) return false;
    if (_prefMinAge == null || _prefMaxAge == null || _prefMinHeight == null || _prefBodyType == null) return false;

    return true; 
  }

  Future<void> _submit() async {
    // Only proceed if the form passes internal Flutter validation
    if (_formKey.currentState?.validate() ?? false) {
      if (!_isFormValid()) return; // Protection

      final data = {
        "first_name": _firstNameController.text.trim(),
        "gender": _gender,
        "age": int.parse(_age!),
        "height": int.parse(_height!),
        "body_type": _bodyType,
        "pref_min_age": int.parse(_prefMinAge!),
        "pref_max_age": int.parse(_prefMaxAge!),
        "pref_min_height": int.parse(_prefMinHeight!),
        "pref_body_type": _prefBodyType,
        "marital_status": _maritalStatus,
        "has_children": _hasChildren == 'نعم',
        "children_living_with_user": _childrenLiving,
        "polygamy_preference": _gender == 'أنثى' ? _polygamyPref : _desiredWife,
        "country": _country,
        "city": _selectedCity,
        "location_verified": false,
        "education_level": _educationLevel,
        "employment_status": _employmentStatus,
        "smoking_habit": _smokingHabit,
        // account_status intentionally omitted: the DB defaults it to
        // 'pending' and RLS forbids clients from setting it (privilege guard).
      };

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator(color: AppTheme.primaryOliveGreen)),
      );

      try {
        final userId = Supabase.instance.client.auth.currentUser!.id;
        data['id'] = userId; // strictly link ID to the row

        await Supabase.instance.client.from('profiles').upsert(data);
        final String profileId = userId;
        
        // Anti-Amnesia Local Web Persistance Hook
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('current_user_id', profileId);

        if (!mounted) return;
        Navigator.of(context).pop(); 

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم حفظ البيانات في السحابة بنجاح!", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Tajawal')),
            backgroundColor: AppTheme.primaryOliveGreen,
          )
        );

        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => OathScreen(profileId: profileId)),
        );
      } catch (e) {
        if (!mounted) return;
        Navigator.of(context).pop();

        // Do not surface raw provider errors (may carry request/PII detail).
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تعذّر حفظ البيانات. الرجاء المحاولة مرة أخرى.", style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Tajawal')),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 4),
          )
        );
      }
    }
  }

  // UPDATED: High Contrast Core Strategy
  Widget _buildDropdown(String label, String? value, List<String> items, Function(String?) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: DropdownButtonFormField<String>(
        autovalidateMode: AutovalidateMode.onUserInteraction,
        initialValue: value,
        dropdownColor: Colors.white, 
        iconEnabledColor: Colors.black,
        style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.7), fontSize: 16, fontWeight: FontWeight.bold),
          filled: true,
          fillColor: Colors.white, // Absolute pure contrast
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppTheme.primaryOliveGreen, width: 3)),
          errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold),
        ),
        items: items.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
        onChanged: onChanged,
        validator: (v) => v == null ? "مطلوب" : null,
      ),
    );
  }

  // UPDATED: High Contrast Solid Validations
  Widget _buildTextField(String label, TextEditingController controller, {bool isNumber = false, bool isRequired = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: TextFormField(
        autovalidateMode: AutovalidateMode.onUserInteraction,
        controller: controller,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        inputFormatters: isNumber ? [FilteringTextInputFormatter.digitsOnly] : [],
        style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold), // CRITICAL QA MATCH
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.black.withValues(alpha: 0.7), fontSize: 16, fontWeight: FontWeight.bold),
          filled: true,
          fillColor: Colors.white, // SOLID WHITE CRITICAL MATCH
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppTheme.primaryOliveGreen, width: 3)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.redAccent, width: 2)),
          focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.redAccent, width: 2)),
          errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold), 
        ),
        validator: (v) {
          if (isRequired && (v == null || v.trim().isEmpty)) return "مطلوب";
          if (isNumber && v != null && v.trim().isNotEmpty) {
            final val = int.tryParse(v);
            if (val == null) return "أرقام فقط";
            if (label.contains("العمر") && (val < 18 || val > 85)) {
              return "العمر يجب أن يكون بين 18 و 85";
            }
            if (label.contains("الطول") && (val < 120 || val > 230)) {
              return "الطول غير منطقي";
            }
          }
          return null;
        },
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isSingle = (_gender == 'ذكر' && _maritalStatus == 'أعزب') || (_gender == 'أنثى' && _maritalStatus == 'عزباء');
    bool showPolygamyWoman = _gender == 'أنثى';
    bool showPolygamyMan = _gender == 'ذكر' && _maritalStatus == 'متزوج';

    return Scaffold(
      backgroundColor: AppTheme.primaryNavyBlue, 
      appBar: AppBar(
        title: const Text("الإعداد الجذري للملف", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppTheme.backgroundIvory,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: () => setState(() {}),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "الفلاتر الصارمة",
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.primaryOliveGreen),
                ),
                const SizedBox(height: 12),
                const Text(
                  "الصدق هنا هو أساس المطابقة الفعّالة والتصفية.",
                  style: TextStyle(fontSize: 16, color: AppTheme.backgroundBeige),
                ),
                const SizedBox(height: 48),

                const Text(
                  "البيانات الأساسية",
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 24),
                
                _buildTextField("الاسم الأول (باللغة العربية)", _firstNameController, isRequired: true),

                // 1. Gender 
                _buildDropdown("الجنس", _gender, _genders, (val) {
                  setState(() {
                    _gender = val;
                    _maritalStatus = null; 
                    _polygamyPref = null;
                    _desiredWife = null;
                    _hasChildren = null;
                    _childrenLiving = null;
                  });
                }),

                if (_gender != null) ...[
                  const SizedBox(height: 16),
                  const Text("مواصفاتي", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildDropdown("العمر", _age, _ages, (val) => setState(() => _age = val))),
                      const SizedBox(width: 16),
                      Expanded(child: _buildDropdown("الطول (سم)", _height, _heights, (val) => setState(() => _height = val))),
                    ],
                  ),
                  _buildDropdown("البنية الجسدية", _bodyType, _bodyTypes, (val) => setState(() => _bodyType = val)),
                  
                  const SizedBox(height: 24),
                  const Divider(color: Colors.white24, thickness: 1),
                  const SizedBox(height: 16),
                  
                  const Text("مواصفات الشريك المفضل", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildDropdown("العمر الأدنى", _prefMinAge, _ages, (val) => setState(() => _prefMinAge = val))),
                      const SizedBox(width: 16),
                      Expanded(child: _buildDropdown("العمر الأقصى", _prefMaxAge, _ages, (val) => setState(() => _prefMaxAge = val))),
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildDropdown("الطول الأدنى (سم)", _prefMinHeight, _heights, (val) => setState(() => _prefMinHeight = val))),
                      const SizedBox(width: 16),
                      Expanded(child: _buildDropdown("بنية الشريك", _prefBodyType, _prefBodyTypes, (val) => setState(() => _prefBodyType = val))),
                    ],
                  ),
                  
                  const SizedBox(height: 24),
                  const Divider(color: Colors.white24, thickness: 1),
                  const SizedBox(height: 24),

                  _buildDropdown("الحالة الاجتماعية", _maritalStatus, _maritalStatusOptions, (val) {
                    setState(() {
                      _maritalStatus = val;
                      if ((_gender == 'ذكر' && val == 'أعزب') || (_gender == 'أنثى' && val == 'عزباء')) {
                        _hasChildren = null;
                        _childrenLiving = null;
                      }
                      if (_gender == 'ذكر' && val != 'متزوج') {
                        _desiredWife = null;
                      }
                    });
                  }),

                  if (!isSingle && _maritalStatus != null) ...[
                    _buildDropdown("هل يوجد أطفال؟", _hasChildren, _yesNo, (val) {
                      setState(() {
                        _hasChildren = val;
                        if (val == 'لا') _childrenLiving = null;
                      });
                    }),
                    if (_hasChildren == 'نعم') 
                      _buildDropdown("مكان إقامة الأطفال:", _childrenLiving, ['معي تماماً', 'مع الطرف الآخر', 'مقسم / تناوب'], (val) => setState(() => _childrenLiving = val)),
                  ],

                  // SMART POLYGAMY LOGIC
                  if (showPolygamyWoman)
                    _buildDropdown("هل تقبلين التعدد؟ (الموافقة كزوجة ثانية)", _polygamyPref, _yesNo, (val) => setState(() => _polygamyPref = val)),
                  if (showPolygamyMan)
                    _buildDropdown("الزوجة المطلوبة؟", _desiredWife, ["الثانية", "الثالثة", "الرابعة"], (val) => setState(() => _desiredWife = val)),

                  _buildDropdown("المستوى التعليمي", _educationLevel, _educationLevels, (val) => setState(() => _educationLevel = val)),
                  _buildDropdown("الحالة الوظيفية", _employmentStatus, _employmentStatuses, (val) => setState(() => _employmentStatus = val)),
                  _buildDropdown("التدخين / الشيشة", _smokingHabit, _yesNo, (val) => setState(() => _smokingHabit = val)),

                  const SizedBox(height: 16),
                  const Text("المدينة (للمطابقة الجغرافية):", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 16),

                  _buildDropdown("اختر مدينتك", _selectedCity, saudiCities, (val) => setState(() => _selectedCity = val)),

                  const SizedBox(height: 56),

                  ElevatedButton(
                    onPressed: _isFormValid() ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryOliveGreen,
                      disabledBackgroundColor: Colors.grey.withValues(alpha: 0.3),
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text("المتابعة نحو الميثاق", style: TextStyle(fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 48),
                ],
              ],
            ),
          ),
          ), // ConstrainedBox
          ), // Center
        ),
      ),
    );
  }
}
