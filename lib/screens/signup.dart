// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';
import 'login.dart';

import '../config/api_config.dart';

var logger = Logger(printer: PrettyPrinter(methodCount: 0));

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();

  final idController = TextEditingController();
  final customDomainController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmController = TextEditingController();
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final codeController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String sex = '';
  String? selectedDomain;
  DateTime? selectedDate;

  bool agreeTerms = false;
  bool agreePrivacy = false;
  bool agreeMarketing = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? _verificationId;
  bool _isVerified = false;

  // ------------------------------------------------
  // 🔥 추가된 부분: 타이머 상태
  // ------------------------------------------------
  int _timerSeconds = 0;
  Timer? _timer;

  // 타이머 시작
  void _startTimer() {
    _timer?.cancel();

    setState(() => _timerSeconds = 180);

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timerSeconds == 0) {
        timer.cancel();
      } else {
        if (!mounted) return;
        setState(() => _timerSeconds--);
      }
    });
  }
  // 이메일 구성
  String get fullEmail {
    if (selectedDomain == null || idController.text.isEmpty) return '';
    if (selectedDomain == "직접 입력") {
      return "${idController.text}@${customDomainController.text}";
    }
    return "${idController.text}@$selectedDomain";
  }

  // 성별 변환
  String get normalizedSex {
    if (sex == "남성") return "male";
    if (sex == "여성") return "female";
    return "";
  }

  bool get _isFormValid {
    return fullEmail.contains("@") &&
        passwordController.text.isNotEmpty &&
        confirmController.text == passwordController.text &&
        nameController.text.isNotEmpty &&
        sex.isNotEmpty &&
        selectedDate != null &&
        phoneController.text.isNotEmpty &&
        _isVerified &&
        agreeTerms &&
        agreePrivacy;
  }

  void _refresh() => setState(() {});

  // -------------------------------------------------------
  // 🔥 (1) 인증번호 전송
  // -------------------------------------------------------
  Future<void> _sendVerificationCode() async {
    final cleaned = phoneController.text.replaceAll(RegExp(r'[^0-9]'), '');
    final phone = "+82$cleaned";

    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/phoneauth/request-code/'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"phone": phone}),
      );

      final result = jsonDecode(response.body);

      if (result["allowed"] == false) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result["message"] ?? "오늘 할당량 초과")),
        );
        return;
      }

      await _auth.verifyPhoneNumber(
        phoneNumber: phone,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (PhoneAuthCredential credential) async {
          await _auth.signInWithCredential(credential);
          if (!mounted) return;
          setState(() => _isVerified = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("전화번호 인증 자동 완료")),
          );
        },
        verificationFailed: (FirebaseAuthException e) {
          if (!mounted) return;
          logger.e("전화번호 인증 실패", error: e);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("인증 실패: ${e.message}")),
          );
        },

        // ---------------------------------------------------
        // 🔥 수정된 codeSent — 타이머 시작 포함
        // ---------------------------------------------------
        codeSent: (String verificationId, int? resendToken) {
          if (!mounted) return;

          setState(() {
            _verificationId = verificationId;   // 🔥🔥🔥 이 줄 추가
          });

          _startTimer();

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("인증번호가 전송되었습니다.")),
          );
        },

        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      logger.e("전화번호 인증 요청 중 에러", error: e);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("오류 발생: $e")),
      );
    }
  }

  // -------------------------------------------------------
  // 🔥 (2) 인증번호 확인
  // -------------------------------------------------------
  Future<void> _verifyCode() async {
    if (_verificationId == null) {
      debugPrint("verificationId null → 인증 불가"); // 🔥 추가
      return;
}

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: codeController.text.trim(),
      );

      await _auth.signInWithCredential(credential);

      if (!mounted) return; // ✅ 성공 시 체크
      setState(() {
        _isVerified = true;
        _timer?.cancel();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("인증 완료되었습니다.")),
      );
    } catch (e) {   // 🔥 여기 수정
        debugPrint("에러: $e");

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("에러: $e")),
        );
      }
  }

  // -------------------------------------------------------
  // 🔥 (3) 회원가입 요청
  // -------------------------------------------------------
  Future<void> _sendUserDataToBackend() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();

    if (!mounted) return; // 🔥 추가됨

    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Firebase 토큰을 가져올 수 없습니다.")),
      );
      return;
    }

    final body = jsonEncode({
      "email": fullEmail,
      "password": passwordController.text,
      "name": nameController.text,
      "birth":
          "${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}",
      "sex": normalizedSex,
      "phone": "+82${phoneController.text.trim()}",
    });

    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/userauth/firebase-signup/'),
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer $token",
      },
      body: body,
    );

    if (!mounted) return; // 🔥 추가됨 (context 사용 전)

    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("회원가입 완료!")),
      );

      final loginRes = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/userauth/login/'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": fullEmail,
          "password": passwordController.text,
        }),
      );

      if (!mounted) return; // 🔥 Navigator 전에 추가

      if (loginRes.statusCode == 200) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const Login()),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("로그인 실패: ${loginRes.body}")),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("회원가입 오류: ${res.body}")),
      );
    }
  } catch (e) {
    if (!mounted) return; // 🔥 추가됨
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("서버 오류: $e")),
    );
  }
}

  // =========================================================
  // 🔥 BUILD UI
  // =========================================================
  // =========================================================
// 🔥 BUILD UI — 전체 교체용
// =========================================================
@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),

              // 로고
              Center(
                child: Image.asset(
                  'assets/images/dasibom_logo.png',
                  height: 120,
                ),
              ),
              const SizedBox(height: 40),

              // ------------------------------
              // 이메일
              // ------------------------------
              _buildLabel("아이디(이메일 주소)"),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: idController,
                      onChanged: (_) => _refresh(),
                      decoration: _inputDecoration("아이디"),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text("@", style: TextStyle(fontSize: 18)),
                  ),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      items: const [
                        DropdownMenuItem(
                            value: "gmail.com", child: Text("gmail.com")),
                      DropdownMenuItem(
                            value: "naver.com", child: Text("naver.com")),
                        DropdownMenuItem(
                            value: "daum.net", child: Text("daum.net")),
                        DropdownMenuItem(
                            value: "직접 입력", child: Text("직접 입력")),
                      ],
                      initialValue: selectedDomain,
                      onChanged: (v) {
                        setState(() => selectedDomain = v);
                        _refresh();
                      },
                      decoration: _inputDecoration("도메인 선택"),
                    ),
                  ),
                ],
              ),

              if (selectedDomain == "직접 입력") ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: customDomainController,
                  onChanged: (_) => _refresh(),
                  decoration: _inputDecoration("직접 도메인 입력"),
                ),
              ],

              const SizedBox(height: 20),

              // ------------------------------
              // 비밀번호
              // ------------------------------
              _buildLabel("비밀번호"),
              _buildPasswordField(
                "비밀번호",
                passwordController,
                _obscurePassword,
                () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              const SizedBox(height: 20),

              // 비밀번호 확인
              _buildLabel("비밀번호 확인"),
              TextFormField(
                controller: confirmController,
                obscureText: _obscureConfirm,
                onChanged: (_) => _refresh(),
                decoration: _inputDecoration("비밀번호 재입력").copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                  errorText: confirmController.text.isNotEmpty &&
                          confirmController.text != passwordController.text
                      ? "비밀번호가 일치하지 않습니다."
                      : null,
                ),
              ),

              const SizedBox(height: 20),

              // ------------------------------
              // 이름 + 성별
              // ------------------------------
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel("이름"),
                        TextFormField(
                          controller: nameController,
                          onChanged: (_) => _refresh(),
                          decoration: _inputDecoration("이름"),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildSexSelector(),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ------------------------------
              // 생년월일
              // ------------------------------
              _buildLabel("생년월일"),
              _buildDatePickerField(),

              const SizedBox(height: 20),

              // ------------------------------
              // 전화번호 + 인증번호 전송
              // ------------------------------
              _buildLabel("휴대전화"),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: phoneController,
                      keyboardType: TextInputType.number,
                      onChanged: (_) {
                        final cleaned = phoneController.text
                            .replaceAll(RegExp(r'[^0-9]'), '');
                        phoneController.value = phoneController.value.copyWith(
                          text: cleaned,
                          selection: TextSelection.collapsed(
                            offset: cleaned.length,
                          ),
                        );
                        _refresh();
                      },
                      decoration: _inputDecoration("휴대전화번호(-제외)"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFDF7DC),
                        foregroundColor: Colors.black,
                      ),
                      onPressed:
                          _timerSeconds > 0 ? null : _sendVerificationCode,
                      child: Text(
                        _timerSeconds > 0
                            ? "재전송 (${_timerSeconds}s)"
                            : "인증번호 전송",
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ------------------------------
              // 인증번호 입력 + 확인
              // ------------------------------
              _buildLabel("인증번호 입력"),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: codeController,
                      enabled: !_isVerified,
                      decoration: _inputDecoration(
                        _isVerified ? "인증 완료됨" : "인증번호 입력",
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isVerified
                            ? Colors.greenAccent
                            : const Color(0xFFFDF7DC),
                        foregroundColor: Colors.black,
                      ),
                      onPressed: _isVerified ? null : _verifyCode,
                      child: Text(
                        _isVerified ? "✔ 인증 완료" : "인증 확인",
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 25),

              // ------------------------------
              // 약관
              // ------------------------------
              _buildLabel("약관 동의"),
              _buildAgreementItem(
                "이용약관 동의 (필수)",
                () => _showDialog(
                  "이용약관",
                  agreeTerms,
                  (v) => setState(() => agreeTerms = v),
                ),
                agreeTerms,
              ),
              _buildAgreementItem(
                "개인정보 취급방침 동의 (필수)",
                () => _showDialog(
                  "개인정보 취급방침",
                  agreePrivacy,
                  (v) => setState(() => agreePrivacy = v),
                ),
                agreePrivacy,
              ),
              _buildAgreementItem(
                "마케팅 정보 수신 (선택)",
                () => _showDialog(
                  "마케팅 정보 수신",
                  agreeMarketing,
                  (v) => setState(() => agreeMarketing = v),
                ),
                agreeMarketing,
              ),

              const SizedBox(height: 30),

              // ------------------------------
              // 가입 버튼
              // ------------------------------
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isFormValid ? _sendUserDataToBackend : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isFormValid
                        ? const Color(0xFFFDF7DC)
                        : Colors.grey.shade300,
                    foregroundColor: Colors.black,
                  ),
                  child: Text(
                    "가입하기",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _isFormValid ? Colors.black : Colors.black54,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  // =========================================================
  // HELPER UI
  // =========================================================

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.grey),
      filled: true,
      fillColor: const Color(0xFFFFFAE6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildPasswordField(String hint, TextEditingController controller,
      bool obscure, VoidCallback toggle) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      onChanged: (_) => _refresh(),
      decoration: _inputDecoration(hint).copyWith(
        suffixIcon: IconButton(
          icon: Icon(
              obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined),
          onPressed: toggle,
        ),
      ),
    );
  }
  
  Widget _buildSexSelector() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLabel("성별"),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildRadio("여성"),
              _buildRadio("남성"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRadio(String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Radio<String>(
          value: label,
          groupValue: sex,
          activeColor: Colors.black87,
          onChanged: (value) {
            setState(() => sex = value!);
          },
        ),
        Text(label, style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  Widget _buildDatePickerField() {
    return TextFormField(
      readOnly: true,
      decoration: _inputDecoration(
        selectedDate == null
            ? "YYYY-MM-DD"
            : "${selectedDate!.year}-${selectedDate!.month.toString().padLeft(2, '0')}-${selectedDate!.day.toString().padLeft(2, '0')}",
      ).copyWith(
        suffixIcon: IconButton(
          icon: const Icon(Icons.calendar_today_outlined,
              color: Colors.black54),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: selectedDate ?? DateTime(2000),
              firstDate: DateTime(1900),
              lastDate: DateTime.now(),
            );
            if (picked != null) {
              setState(() => selectedDate = picked);
              _refresh();
            }
          },
        ),
      ),
    );
  }

  Widget _buildAgreementItem(String title, VoidCallback onTap, bool value) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Checkbox(
                value: value,
                onChanged: (_) => onTap(),
                activeColor: const Color(0xFFFFD94C),
              ),
              Text(title, style: const TextStyle(fontSize: 14)),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.black54),
            onPressed: onTap,
          ),
        ],
      ),
    );
  }

  void _showDialog(
      String title, bool currentValue, ValueChanged<bool> onAgree) {
    showDialog(
      context: context,
      barrierDismissible: false,
      // 🔥 [수정됨] withOpacity(0.4) -> withValues(alpha: 0.4)
      // (Flutter 최신 버전 기준 권장 사항입니다. 에러가 나면 기존 withOpacity 유지)
      barrierColor: Colors.black.withValues(alpha: 0.4), 
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("약관 내용을 확인하시고 동의하셔야 진행할 수 있습니다.",
            style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("닫기", style: TextStyle(color: Colors.black54)),
          ),
          ElevatedButton(
            onPressed: () {
              onAgree(true);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD94C),
              foregroundColor: Colors.black,
            ),
            child: const Text("동의합니다"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel(); // 🔥 타이머 해제
    idController.dispose();
    customDomainController.dispose();
    passwordController.dispose();
    confirmController.dispose();
    nameController.dispose();
    phoneController.dispose();
    codeController.dispose();
    super.dispose();
  }
}
