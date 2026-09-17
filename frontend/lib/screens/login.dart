import 'package:flutter/material.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:logger/logger.dart'; // ✅ [추가] 로거 패키지 임포트
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'signup.dart';
import '../home/home.dart';
import '../guardian/guardian.dart';
import '../main.dart' show EmergencyService;

import '../config/api_config.dart';

// ✅ [추가] 로거 인스턴스 생성 (PrettyPrinter로 가독성 향상)
var logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0, // 불필요한 스택 트레이스 제거
    errorMethodCount: 5, // 에러 발생 시 스택 트레이스 표시
    lineLength: 50, // 줄바꿈 너비
    colors: true, // 색상 적용
    printEmojis: true, // 이모지 적용
  ),
);

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool _isLoading = false;

  // ... (일반 로그인 _login 함수는 기존과 동일하므로 생략 가능, 필요시 동일하게 logger 적용) ...
  
  Future<void> _login() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      _showMessage("아이디와 비밀번호를 입력해주세요.");
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final res = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/userauth/login/'),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"email": email, "password": password}),
          )
          .timeout(const Duration(seconds: 5));

      if (!mounted) return;

      if (res.statusCode == 200) {
        logger.i("일반 로그인 성공");

        final data = jsonDecode(res.body);
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString("access", data["access"]);
        await prefs.setString("refresh", data["refresh"] ?? "");
        await prefs.setBool("isLoggedIn", true);
        await prefs.setBool("isGuest", false);
        await prefs.setString("role", data["user"]?["role"] ?? "guest");

        debugPrint("🔥 저장된 role: ${data["user"]?["role"]}");
        debugPrint("🔥 저장된 isGuest: ${prefs.getBool('isGuest')}");
        debugPrint("🔥 저장된 isLoggedIn: ${prefs.getBool('isLoggedIn')}");

        if (!mounted) return;
        setState(() => _isLoading = false);

        // 🚀 [수정] 권한(Role)에 따른 페이지 이동 분기
        final role = data["user"]?["role"];

        if (!mounted) return;

        if (role == "guardian") {
          // 1️⃣ 권한이 'guardian'인 경우 -> 보호자 전용 페이지
          logger.i("보호자 권한으로 로그인: GuardianPage로 이동");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const GuardianPage()),
          );
        } else if (role == "admin" || role == "citizen" || role == "guest") {
          // 2️⃣ 관리자(admin), 일반시민(citizen), 게스트(guest) -> 메인 대시보드
          logger.i("$role 권한으로 로그인: HomeDashboard로 이동");
          if (role == "admin") EmergencyService.instance.startIfAdmin();
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeDashboard(isGuest: false)),
          );
        } else {
          // 3️⃣ 예외 처리 (정의되지 않은 권한일 경우 기본 홈으로)
          logger.w("알 수 없는 권한($role): 기본 홈으로 이동");
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeDashboard(isGuest: true)),
          );
        }
      } else {
        logger.w("로그인 실패: ${res.statusCode} / ${res.body}");
        _showMessage("로그인 실패");
        setState(() => _isLoading = false);
      }
    } on TimeoutException {
      logger.w("⏱ 서버 타임아웃");
      _showMessage("서버 응답이 없습니다. 네트워크를 확인해주세요.");
      if (mounted) setState(() => _isLoading = false);
    } catch (e, stackTrace) {
      logger.e("로그인 에러", error: e, stackTrace: stackTrace);
      _showMessage("오류 발생");
      if (mounted) setState(() => _isLoading = false);
    }
  }


  // ======================================================
  // 🔥 (2) 카카오 로그인 (수정된 부분)
  // ======================================================
  Future<void> _kakaoLogin() async {
    try {
      OAuthToken token;
      if (await isKakaoTalkInstalled()) {
        token = await UserApi.instance.loginWithKakaoTalk();
      } else {
        token = await UserApi.instance.loginWithKakaoAccount();
      }

      final accessToken = token.accessToken;
      
      // ✅ [추가] 토큰 획득 로그 (디버깅용)
      logger.d("카카오 액세스 토큰 획득 성공");

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/userauth/kakao-login/'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"access": accessToken}),
      )
      .timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        throw TimeoutException("서버 응답 시간이 너무 오래 걸립니다.");
      },
    );

      // 🔴 [수정된 부분] 기존 print 문 제거 및 Logger 적용
      // print("STATUS: ${response.statusCode}"); // 삭제
      // print("RAW: ${response.body}"); // 삭제
      
      logger.d(
        "카카오 로그인 서버 응답\n"
        "Status: ${response.statusCode}\n"
        "Body: ${response.body}"
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        logger.i("카카오 로그인 최종 성공"); // ✅ Info 레벨 로그
        _showMessage("카카오 로그인 성공!");

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeDashboard()),
        );
      } else {
        logger.w("서버 응답 오류: ${response.body}"); // ✅ Warning 레벨 로그
        _showMessage("서버 오류: ${response.body}");
      }
    } catch (e, stackTrace) {
      // ✅ [변경] 에러와 스택 트레이스를 함께 기록하여 디버깅 용이성 확보
      logger.e("카카오 로그인 프로세스 실패", error: e, stackTrace: stackTrace);
      _showMessage("카카오 로그인 실패: $e");
    }
  }

  void _showMessage(String msg) {
    if (!mounted) return; // 비동기 처리 후 안전장치 추가
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }
  
  // ... (나머지 build 및 UI 코드는 기존과 동일) ...
  @override
  Widget build(BuildContext context) {
      return Scaffold(
          // (기존 UI 코드 그대로 사용)
          backgroundColor: Colors.white,
          body: SafeArea(
              child: Center(
                  child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                              Image.asset('assets/images/dasibom_logo.png', height: 120),
                              const SizedBox(height: 40),
                              TextField(
                                  controller: emailController,
                                  decoration: _input("아이디"),
                              ),
                              const SizedBox(height: 20),
                              TextField(
                                  controller: passwordController,
                                  obscureText: true,
                                  decoration: _input("비밀번호"),
                              ),
                              const SizedBox(height: 30),
                              SizedBox(
                                  width: double.infinity,
                                  height: 55,
                                  child: ElevatedButton(
                                      onPressed: _isLoading ? null : _login,
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFFCF6D6),
                                          shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                          ),
                                          elevation: 1,
                                      ),
                                      child: _isLoading
                                          ? const CircularProgressIndicator(color: Colors.black)
                                          : const Text(
                                              '로그인',
                                              style: TextStyle(
                                                  color: Colors.black87,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.bold,
                                              ),
                                          ),
                                  ),
                              ),
                              const SizedBox(height: 30),
                              _signupAndFindPw(context),
                              const SizedBox(height: 30),
                              Divider(color: const Color.fromARGB(255, 0, 0, 0)),
                              const SizedBox(height: 25),
                             OutlinedButton(
                               onPressed: () {
                                  _enterGuestMode();
                               },

                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 50),
                                  side: const BorderSide(color: Colors.black),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  foregroundColor: Colors.black,
                                ),
                                child: const Text(
                                  '다시봄 비회원 로그인',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 15),
                                SizedBox(
                                  width: double.infinity,
                                  child: GestureDetector(
                                    onTap: _kakaoLogin,   // ← 카카오 로그인 실행
                                    child: Image.asset(
                                      'assets/icons/kakao_logo2.png', // ← 니가 올린 그 이미지
                                      fit: BoxFit.contain,
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

  InputDecoration _input(String text) {
    return InputDecoration(
      hintText: text,
      hintStyle: TextStyle(color: Colors.grey.shade400),
      filled: true,
      fillColor: const Color(0xFFFFFAE8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 15, vertical: 18),
    );
  }

  Widget _signupAndFindPw(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(width: 1, height: 16, color: Colors.black38),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SignupPage()),
                ),
                child: const Text("회원가입",
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
              GestureDetector(
                onTap: () {
                  // TODO: 비밀번호 찾기
                },
                child: const Text("비밀번호 찾기",
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _enterGuestMode() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool('isGuest', true);
    await prefs.setBool('isLoggedIn', false);
    await prefs.setString('role', 'guest');

    if (!mounted) return;

    _goToGuestHome(); // 👉 Navigator 따로 호출
  }

  void _goToGuestHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const HomeDashboard(isGuest: true),
      ),
    );
  }
}