import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../missing/missing_list.dart';
import '../map/map.dart';
import '../register/register.dart';
import '../report/report.dart';
import '../screens/login.dart';
import '../screens/notification.dart';

import '../config/api_config.dart';

import 'missing_ui.dart';
import '../screens/setting.dart';
import '../admin/admin_log_page.dart';

  class HomeDashboard extends StatefulWidget {
    final bool isGuest;
    const HomeDashboard({super.key, this.isGuest = false});

    @override
    State<HomeDashboard> createState() => _HomeDashboardState();
  }

  class _HomeDashboardState extends State<HomeDashboard> {
    late Future<List<MissingPerson>> recentFuture;
    late Future<List<MissingPerson>> longTermFuture;
    Timer? _autoRefreshTimer;
    bool _isAdmin = false;
    bool _hasUnreadNotification = false;

    @override
    void initState() {
      super.initState();
      _loadAllData();
      _loadUserRole();

      // 600초마다 자동 새로고침
      _autoRefreshTimer = Timer.periodic(const Duration(seconds: 600), (timer) {
        _loadAllData();
        _loadUnreadNotificationState();
      });
    }

    Future<void> _loadUserRole() async {
      final prefs = await SharedPreferences.getInstance();

      if (!mounted) return;

      final role = prefs.getString('role') ?? '';

      setState(() {
        _isAdmin = role == 'admin';
      });
    }

    Future<void> _loadUnreadNotificationState() async {
      final prefs = await SharedPreferences.getInstance();

      if (!mounted) return;

      setState(() {
        _hasUnreadNotification = prefs.getBool('hasUnreadNotification') ?? false;
      });
    }

    // 🚀 [추가] 데이터 로딩 로직 공통화
    void _loadAllData() {
      setState(() {
        recentFuture = fetchRecent();
        longTermFuture = fetchLongTerm();
      });
    }

    @override
    void dispose() {
      _autoRefreshTimer?.cancel();
      super.dispose();
    }

  Future<List<MissingPerson>> fetchRecent() async {
    final url = Uri.parse("${ApiConfig.baseUrl}/missingperson/recent/");
    final response = await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return [];
      return decoded.map<MissingPerson?>((e) {
        try { return MissingPerson.fromJson(e); } catch (_) { return null; }
      }).whereType<MissingPerson>().toList();
    }
    throw Exception("서버 오류 (${response.statusCode})");
  }

  Future<List<MissingPerson>> fetchLongTerm() async {
    final url = Uri.parse("${ApiConfig.baseUrl}/missingperson/long-term/");
    final response = await http.get(url).timeout(const Duration(seconds: 10));
    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return [];
      return decoded.map<MissingPerson?>((e) {
        try { return MissingPerson.fromJson(e); } catch (_) { return null; }
      }).whereType<MissingPerson>().toList();
    }
    throw Exception("서버 오류 (${response.statusCode})");
  }

  void _requireLogin(BuildContext context, Widget targetPage) {
    if (widget.isGuest) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text("로그인 필요", style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text("회원 전용 서비스입니다.\n로그인 화면으로 이동하시겠습니까?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("취소", style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushAndRemoveUntil(
                   context,
                   MaterialPageRoute(builder: (_) => const Login()),
                   (route) => false,
                );
              },
              child: const Text("확인", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => targetPage),
      );
    }
  }

  Future<void> _onNotificationPressed() async {
    if (widget.isGuest) {
      _requireLogin(context, const NotificationPage());
      return;
    }

    if (_isAdmin) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const AdminLogPage(),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const NotificationPage(),
      ),
    );

    if (!mounted) return;

    setState(() {
      _hasUnreadNotification = false;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasUnreadNotification', false);
  }
  
  @override
    Widget build(BuildContext context) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async => _loadAllData(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- 상단 헤더 영역 ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                     IconButton(
                        icon: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(Icons.notifications_none,
                                size: 28, color: Colors.black),
                            if (_hasUnreadNotification)
                              Positioned(
                                top: -1,
                                right: -1,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        onPressed: _onNotificationPressed,
                      ),
                      Image.asset('assets/images/dasibom_logo.png', height: 45),
                      
                      // 🚀 [수정] 톱니바퀴 버튼 클릭 시 설정 페이지로 이동
                      IconButton(
                        icon: const Icon(Icons.settings, size: 28),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => SettingsPage()),
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // --- 최근 실종자 섹션 ---
                  _buildFutureSection("최근 실종자", recentFuture),

                  const SizedBox(height: 10),

                  // --- 장기 실종자 섹션 ---
                  _buildFutureSection("장기 실종자", longTermFuture),

                  const SizedBox(height: 10),

                  _mainFunctionGrid(context),

                  const SizedBox(height: 35),

                  // --- 하단 긴급 전화 버튼들 ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _callButton(context, "112", "경찰"),
                      _callButton(context, "182", "실종아동센터"),
                      _callButton(context, "117", "신고상담센터"),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 🚀 [추가] 중복되는 FutureBuilder 구조를 하나로 합친 위젯 함수
    Widget _buildFutureSection(String title, Future<List<MissingPerson>> future) {
      return FutureBuilder<List<MissingPerson>>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator(color: Color(0xFFFFF2C2))),
            );
          }
          if (snapshot.hasError) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    GestureDetector(
                      onTap: _loadAllData,
                      child: const Row(
                        children: [
                          Icon(Icons.refresh, size: 14, color: Color(0xFFD4A800)),
                          SizedBox(width: 3),
                          Text('다시 시도', style: TextStyle(color: Color(0xFFD4A800), fontSize: 13, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 26),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF9E5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.cloud_off_outlined, size: 36, color: Colors.black38),
                      SizedBox(height: 8),
                      Text('서버에 연결할 수 없습니다', style: TextStyle(color: Colors.black45, fontSize: 13)),
                    ],
                  ),
                ),
              ],
            );
          }
          return MissingSection(
            title: title,
            list: snapshot.data ?? [],
          );
        },
      );
    }

  // 주요 기능 4개
  Widget _mainFunctionGrid(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.3,
        children: [
          _bigButton(
            'assets/icons/detail.png',
            "실종자 상세 정보",
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MissingListPage()),
            ),
          ),
          _bigButton(
            'assets/icons/map.png',
            "생활안전지도",
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MapPage()),
            ),
          ),
          _bigButton(
            'assets/icons/register.png',
            "실종예방등록",
            () {
              _requireLogin(context, const RegisterPage());
            },
          ),
          _bigButton(
            'assets/icons/report.png',
            "실종 신고",
            () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ReportPage(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _bigButton(String imagePath, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(1, 2),
            )
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Image.asset(
                  imagePath,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 5),
            Flexible(
              flex: 1,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 신고 전화 버튼
  Widget _callButton(BuildContext context, String number, String label) {
    return GestureDetector(
      onTap: () => _showCallDialog(context, number, label),
      child: Column(
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: const BoxDecoration(
              color: Color(0xFFFFF9E5),
              shape: BoxShape.circle,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.call, size: 32, color: Colors.black),
                const SizedBox(height: 6),
                Text(
                  number,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  void _showCallDialog(BuildContext context, String number, String label) {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "$number $label로\n통화하시겠습니까?",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 25),
                const Divider(height: 1),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          "취소",
                          style: TextStyle(
                            fontSize: 17,
                            color: Colors.blue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Container(width: 1, height: 50, color: Colors.grey),
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _makePhoneCall(number);
                        },
                        child: const Text(
                          "통화",
                          style: TextStyle(
                            fontSize: 17,
                            color: Colors.blue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _makePhoneCall(String number) async {
    final Uri url = Uri(scheme: "tel", path: number);

    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      debugPrint("전화 연결 실패");
    }
  }
}