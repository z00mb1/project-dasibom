import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart'; // 🚀 추가
import '../config/api_config.dart';
import 'login.dart';
import '../help/help_page.dart';
// import 'inquiry.dart'; // 문의하기 임시 숨김

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late Future<Map<String, dynamic>> _userProfileFuture;

  @override
  void initState() {
    super.initState();
    _userProfileFuture = _fetchUserProfile();
  }

  Future<Map<String, dynamic>> _fetchUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 🚀 [수정 1] 로그인 페이지에서 'access'로 저장했으므로 똑같이 'access'로 불러옴
    final String? token = prefs.getString('access'); 
    final bool isGuest = prefs.getBool('isGuest') ?? false;

    // 🚀 [수정 2] 비회원이면 서버에 묻지도 말고 즉시 기본값 반환 (401 방지)
    if (isGuest || token == null || token.isEmpty) {
      debugPrint("ℹ️ 비회원 모드: API 호출을 생략합니다.");
      return {
        "email": "로그인이 필요합니다",
        "role": "GUEST",
        "person": {"name": "비회원 사용자", "phone": "-"}
      };
    }

    final url = Uri.parse("${ApiConfig.baseUrl}/userauth/me/"); 
    try {
      final response = await http.get(url, headers: {
        // 🚀 [수정 3] Bearer 한 칸 띄우고 토큰 전송
        'Authorization': 'Bearer $token', 
        'Content-Type': 'application/json',
      });

      debugPrint("📡 서버 응답 코드: ${response.statusCode}");

      if (response.statusCode == 200) {
        return jsonDecode(utf8.decode(response.bodyBytes));
      } else {
        debugPrint("❌ 서버 에러 응답: ${response.body}");
        throw Exception("데이터 로드 실패");
      }
    } catch (e) {
      debugPrint("🚨 네트워크 오류: $e");
      return {
        "email": "오류 발생",
        "role": "ERROR",
        "person": {"name": "연결 확인 필요", "phone": "-"}
      };
    }
  }

  Future<void> _handleLogout() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access');

    try {
      // ✅ 1. 서버 로그아웃 요청
      if (token != null) {
        final res = await http.post(
          Uri.parse("${ApiConfig.baseUrl}/userauth/logout/"),
          headers: {
            "Authorization": "Bearer $token",
            "Content-Type": "application/json",
          },
        );

        debugPrint("🔥 로그아웃 응답: ${res.statusCode}");
        debugPrint("🔥 body: ${res.body}");
      }
    } catch (e) {
      debugPrint("❌ 로그아웃 API 실패: $e");
    }

    // ✅ 2. 로컬 토큰 삭제 (🔥 핵심)
    await prefs.remove('access');   // 🔥 수정
    await prefs.remove('refresh');  // 🔥 수정

    await prefs.setBool('isLoggedIn', false);
    await prefs.setBool('isGuest', false);
    await prefs.setString('role', 'guest'); // ✅ 추가
    await prefs.remove('role'); // ✅ 또는 이걸로

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const Login()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("설정", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _userProfileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFFF2C2)));
          }

          final user = snapshot.data!;
          // 🚀 계층 구조 접근: user['person']
          final person = user['person'] ?? {}; 

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDF9EB),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 30,
                        backgroundColor: Color(0xFFFAEEF0),
                        child: Icon(Icons.person, color: Colors.black54, size: 35),
                      ),
                      const SizedBox(width: 15),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 🚀 데이터 파싱 수정
                          Text(person['name'] ?? '이름 없음', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(user['email'] ?? '이메일 없음', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                          const SizedBox(height: 2),
                          Text("권한: ${user['role']}", style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                ListTile(
                  leading: const Icon(Icons.phone_android, color: Colors.black87),
                  title: Text("연락처: ${person['phone'] ?? '없음'}", style: const TextStyle(fontSize: 14)),
                ),
                /*
                _buildSettingTile(Icons.notifications_none, "알림 설정"),
                _buildSettingTile(Icons.lock_outline, "비밀번호 변경"),
                */
                const Divider(height: 32),
                _buildSectionLabel('고객지원'),
                ListTile(
                  leading: const Icon(Icons.help_outline, color: Colors.black87),
                  title: const Text('도움말', style: TextStyle(fontSize: 14)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HelpPage()),
                  ),
                ),
                // 문의하기 (임시 숨김)
                // ListTile(
                //   leading: const Icon(Icons.help_outline, color: Colors.black87),
                //   title: const Text("문의하기", style: TextStyle(fontSize: 14)),
                //   trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                //   onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InquiryPage())),
                // ),
                const Divider(height: 40),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: const Text("로그아웃", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  onTap: () => _showLogoutDialog(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 2),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500, letterSpacing: 0.3),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("로그아웃"),
        content: const Text("정말 로그아웃 하시겠습니까?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소", style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: _handleLogout, child: const Text("확인", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }
}