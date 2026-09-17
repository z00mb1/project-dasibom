import 'dart:async';
import 'package:flutter/material.dart';
import '../screens/setting.dart';
import 'package:url_launcher/url_launcher.dart'; // ✅ 추가
import '../screens/notification.dart';
import '../missing/missing_list.dart';
import '../map/map.dart';
import '../register/register.dart';
import '../report/report.dart';
import '../register/register_staus_detail.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import 'guardian_location_map.dart';
import '../config/route_observer.dart';

class GuardianPage extends StatefulWidget {
  const GuardianPage({super.key});

  @override
  State<GuardianPage> createState() => _GuardianPageState();
}

class _GuardianPageState extends State<GuardianPage> with RouteAware {

  bool _isMainRouteActive = true;
  PageRoute<dynamic>? _currentRoute;

  final PageController _profilePageController = PageController();

  List<Map<String, dynamic>> _protectedProfiles = [];
  int _currentProfileIndex = 0;
  bool _isProfileLoading = true;
  bool _hasNewNotification = false;
  bool _hasSavedVisibleSelection = false;

  final Color _subBgColor = const Color(0xFFFDF9EB); // 메인 연노랑 배경
  final Color _cardBgColor = const Color(0xFFFEF9E4); // 카드 내부 연노랑
  final Set<int> _visibleProfileIds = {};

  @override
  void initState() {
    super.initState();
    _initAndLoad();
    _checkNewNotification();
  }

  Future<void> _initAndLoad() async {
    final prefs = await SharedPreferences.getInstance();

    final hasSavedSelection =
        prefs.containsKey('guardian_visible_profile_ids');

    final savedIds =
        prefs.getStringList('guardian_visible_profile_ids');

    debugPrint('★★★ [Guardian] initState - savedIds: $savedIds');

    _hasSavedVisibleSelection = hasSavedSelection;

    if (savedIds != null) {
      final ids = savedIds
          .map((s) => int.tryParse(s))
          .whereType<int>()
          .toSet();

      _visibleProfileIds
        ..clear()
        ..addAll(ids);
    }

    await _fetchProtectedProfiles();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _profilePageController.dispose();
    super.dispose();
  }

  @override
void didChangeDependencies() {
  super.didChangeDependencies();

  final route = ModalRoute.of(context);

  if (route is PageRoute<dynamic> && route != _currentRoute) {
    if (_currentRoute != null) {
      routeObserver.unsubscribe(this);
    }

    _currentRoute = route;
    routeObserver.subscribe(this, route);
  }
}

  @override
  void didPushNext() {
    setState(() {
      _isMainRouteActive = false;
    });

    debugPrint('메인 화면 이탈: 위치 추적 종료');
  }

  @override
  void didPopNext() {
    setState(() {
      _isMainRouteActive = true;
    });

    debugPrint('메인 화면 복귀: 위치 추적 재시작');
  }

  Future<void> _onRefresh() async {
    await _fetchProtectedProfiles();
  }

  Future<void> _fetchProtectedProfiles() async {
    setState(() {
      _isProfileLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access') ?? '';

      if (token.isEmpty) {
        if (!mounted) return;
        setState(() {
          _protectedProfiles = [];
          _isProfileLoading = false;
        });
        return;
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/person/my-wards/simple/'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      debugPrint('피보호자 목록 코드: ${response.statusCode}');

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));

        final List rawList = decoded is List
            ? decoded
            : decoded is Map && decoded['results'] is List
                ? decoded['results'] as List
                : [];

        final profiles = rawList.map<Map<String, dynamic>>((e) {
        final item = Map<String, dynamic>.from(e as Map);

        final person = item['missing_person'] is Map
            ? Map<String, dynamic>.from(item['missing_person'])
            : item['protected_person'] is Map
                ? Map<String, dynamic>.from(item['protected_person'])
                : item['person'] is Map
                    ? Map<String, dynamic>.from(item['person'])
                    : <String, dynamic>{};

        return {
          ...item,
          ...person,
          'id': item['id'],
          'register_id': item['prevention_registration_id'] ?? item['id'],
          'device_code': item['device_code'] ??
              person['device_code'] ??
              person['deviceCode'] ??
              person['badge_code'] ??
              person['gps_device_code'],
        };
      }).toList();

        // 현재 계정에 없는 ID는 visibleProfileIds에서 제거,
        // 새로 생긴 ID(재승인 등)는 자동으로 추가
        final validIds = profiles.map<int?>((p) {
          final idVal = p['register_id'] ?? p['id'];
          if (idVal == null) return null;
          return int.tryParse(idVal.toString());
        }).whereType<int>().toSet();

      bool needsSave = false;

      setState(() {
        _protectedProfiles = profiles;
        _currentProfileIndex = 0;
        _isProfileLoading = false;

        if (_hasSavedVisibleSelection) {
          // ✅ 이미 사용자가 선택한 기록이 있으면
          // 현재 존재하지 않는 ID만 제거하고 선택은 그대로 유지
          _visibleProfileIds.removeWhere(
            (id) => !validIds.contains(id),
          );
        } else {
          // ✅ 최초 실행일 때만 전체 피보호자를 기본 선택
          _visibleProfileIds
            ..clear()
            ..addAll(validIds);

          _hasSavedVisibleSelection = true;
          needsSave = true;
        }
      });

      if (needsSave) {
        final prefs = await SharedPreferences.getInstance();

        await prefs.setStringList(
          'guardian_visible_profile_ids',
          _visibleProfileIds
              .map((id) => id.toString())
              .toList(),
        );

        debugPrint(
          '★★★ [Guardian] 최초 기본 선택 저장: $_visibleProfileIds',
        );
      }
      } else {
        setState(() {
          _protectedProfiles = [];
          _isProfileLoading = false;
        });
      }
    } catch (e) {
      debugPrint('피보호자 목록 조회 에러: $e');

      if (!mounted) return;

      setState(() {
        _protectedProfiles = [];
        _isProfileLoading = false;
      });
    }
  }
  Future<void> _checkNewNotification() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access') ?? '';

      if (token.isEmpty) return;

      final savedLastSeenId = prefs.getInt('lastSeenLogId');

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/log/admin-timeline/'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (!mounted) return;
      if (response.statusCode != 200) return;

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is! List || decoded.isEmpty) return;

      final latest = decoded.first as Map<String, dynamic>;
      final latestId = int.tryParse(latest['id'].toString());

      if (latestId == null) return;

      setState(() {
        _hasNewNotification =
            savedLastSeenId != null && latestId > savedLastSeenId;
      });

      if (savedLastSeenId == null) {
        await prefs.setInt('lastSeenLogId', latestId);
      }
    } catch (e) {
      debugPrint('새 알림 확인 에러: $e');
    }
  }

  // 📞 1. 실제 전화 앱을 실행하는 함수
  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      debugPrint("전화를 걸 수 없습니다: $phoneNumber");
    }
  }

  // 💬 2. 확인 다이얼로그 띄우기 함수
  void _showCallDialog(String number, String label) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        backgroundColor: const Color(0xFFFEF9E4), // 👈 팁: 배경색을 카드와 맞추면 더 예쁩니다
        title: Text("$label ($number)", style: const TextStyle(fontWeight: FontWeight.bold)),
        content: const Text("해당 번호로 전화를 하시겠습니까?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("아니오", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _makePhoneCall(number);
            },
            child: const Text("예", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // 전체 배경은 화이트
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 10,
          ),
          child: Column(
            children: [
              _buildProfileCard(),
              const SizedBox(height: 20),
              if (_isMainRouteActive)
                GuardianLocationMap(
                  key: ValueKey(
                    _currentProfile?['id']
                    ?? _currentProfile?['register_id']
                    ?? _currentProfileIndex,
                  ),
                  profile: _currentProfile,
                  cardBgColor: _cardBgColor,
                )
              else
                const SizedBox.shrink(),
              const SizedBox(height: 20),
              _buildActionGrid(),
              const SizedBox(height: 30),
              _buildBottomCalls(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // 0️⃣ 상단 앱바
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: Icon(
          _hasNewNotification
              ? Icons.notifications
              : Icons.notifications_none,
          color: _hasNewNotification
              ? const Color(0xFFFBC02D)
              : Colors.black,
        ),
        onPressed: () async {
          final prefs = await SharedPreferences.getInstance();

          try {
            final token = prefs.getString('access') ?? '';

            final response = await http
                .get(
                  Uri.parse('${ApiConfig.baseUrl}/person/my-wards/simple/'),
                  headers: {
                    'Authorization': 'Bearer $token',
                  },
                )
                .timeout(const Duration(seconds: 8));

            if (response.statusCode == 200) {
              final decoded = jsonDecode(utf8.decode(response.bodyBytes));

              if (decoded is List && decoded.isNotEmpty) {
                final latest = decoded.first as Map<String, dynamic>;
                final latestId = int.tryParse(latest['id'].toString());

                if (latestId != null) {
                  await prefs.setInt('lastSeenLogId', latestId);
                }
              }
            }
          } catch (_) {}

          if (!mounted) return;

          setState(() {
            _hasNewNotification = false;
          });

          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationPage()),
          );

          _checkNewNotification();
        },
      ),
      title: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: GestureDetector(
          onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
          child: Image.asset(
            'assets/images/dasibom_logo.png',
            height: 45,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const SizedBox(width: 45, height: 45);
            },
          ),
        ),
      ),
      centerTitle: true,
      // 🚀 [수정] 설정 아이콘 클릭 시 설정 페이지로 이동
      actions: [
        IconButton(
          icon: const Icon(Icons.settings, color: Colors.black), 
          onPressed: () {
            // ✅ Navigator를 사용해 SettingsPage로 이동합니다.
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => SettingsPage()),
            );
          },
        )
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1.0),
        child: Container(color: Colors.grey.shade300, height: 1.0),
      ),
    );
  }

  // 1️⃣ 프로필 카드 (시안 스타일)
  Widget _buildProfileCard() {
    if (_isProfileLoading) {
      return Container(
        height: 190,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardBgColor,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_visibleProfiles.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cardBgColor,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const SizedBox(
          height: 140,
          child: Center(
            child: Text(
              '등록된 피보호자 정보가 없습니다.',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBgColor,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: 130,
            child: PageView.builder(
              controller: _profilePageController,
              itemCount: _visibleProfiles.length,
              onPageChanged: (index) {
                setState(() {
                  _currentProfileIndex = index;
                });
              },
              itemBuilder: (context, index) {
                final profile = _visibleProfiles[index];
                final imageUrl = _profileImageUrl(profile);
                final registerId = profile['register_id'] ?? profile['id'];

                return Stack(
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 120,
                            height: 120,
                            color: const Color(0xFFD9E2F3),
                            child: imageUrl.isNotEmpty
                                ? Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    alignment: Alignment.topCenter,
                                    errorBuilder: (_, __, ___) {
                                      return const Icon(
                                        Icons.person,
                                        size: 60,
                                        color: Colors.white,
                                      );
                                    },
                                  )
                                : const Icon(
                                    Icons.person,
                                    size: 60,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _profileText('이름:', _display(profile['name'])),
                              _profileText('성별:', _formatGender(profile['gender'])),
                              _profileText('나이:', _calculateAge(profile)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: IconButton(
                        icon: const Icon(
                          Icons.settings,
                          color: Colors.black87,
                          size: 24,
                        ),
                        onPressed: registerId == null
                            ? null
                            : () {
                                _showProfileOptionSheet(profile);
                              },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _buildProfileIndicator(),
        ],
      ),
    );
  }

  void _showProfileOptionSheet(Map<String, dynamic> profile) {
    final registerId = profile['register_id'] ?? profile['id'];

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFFEF9E4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 45,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                ListTile(
                  leading: const Icon(Icons.person_search_outlined),
                  title: const Text(
                    '피보호자 상세프로필 자세히 보기',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(context);

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RegisterDetailPage(
                          registerId: int.parse(registerId.toString()),
                        ),
                      ),
                    );
                  },
                ),

                const Divider(),

                ListTile(
                  leading: const Icon(Icons.checklist_outlined),
                  title: const Text(
                    '보여질 피보호자들 선택',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _showVisibleProfileSelectSheet();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showVisibleProfileSelectSheet() {
    final tempSelectedIds = Set<int>.from(_visibleProfileIds);

    if (tempSelectedIds.isEmpty) {
      for (final profile in _protectedProfiles) {
        final id = profile['register_id'] ?? profile['id'];
        if (id != null) {
          tempSelectedIds.add(int.parse(id.toString()));
        }
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFFEF9E4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 45,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),

                    const Text(
                      '보여질 피보호자 선택',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    ..._protectedProfiles.map((profile) {
                      final idValue = profile['register_id'] ?? profile['id'];
                      if (idValue == null) return const SizedBox.shrink();

                      final id = int.parse(idValue.toString());
                      final name = _display(profile['name']);
                      final isChecked = tempSelectedIds.contains(id);

                      return CheckboxListTile(
                        value: isChecked,
                        activeColor: Colors.black87,
                        title: Text(
                          name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${_formatGender(profile['gender'])} / ${_calculateAge(profile)}세',
                        ),
                        onChanged: (checked) {
                          modalSetState(() {
                            if (checked == true) {
                              tempSelectedIds.add(id);
                            } else {
                              tempSelectedIds.remove(id);
                            }
                          });
                        },
                      );
                    }),

                    const SizedBox(height: 12),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black87,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          setState(() {
                            _visibleProfileIds
                              ..clear()
                              ..addAll(tempSelectedIds);

                            _currentProfileIndex = 0;
                          });

                          final ids = tempSelectedIds.map((id) => id.toString()).toList();
                          debugPrint('★★★ [Guardian] 적용하기 저장: $ids');
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setStringList('guardian_visible_profile_ids', ids);
                          final check = prefs.getStringList('guardian_visible_profile_ids');
                          debugPrint('★★★ [Guardian] 저장 확인: $check');

                          if (context.mounted) Navigator.pop(context);
                        },
                        child: const Text(
                          '적용하기',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildProfileIndicator() {
    if (_visibleProfiles.length <= 1) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_visibleProfiles.length, (index) {
        final isActive = _currentProfileIndex == index;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 10 : 8,
          height: isActive ? 10 : 8,
          decoration: BoxDecoration(
            color: isActive ? Colors.black87 : Colors.black26,
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }

  Widget _profileText(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Text(value, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  // 3️⃣ 기능 그리드 (시안의 굵은 아이콘 반영)
  Widget _buildActionGrid() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: _subBgColor, borderRadius: BorderRadius.circular(15)),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 15,
        crossAxisSpacing: 15,
        childAspectRatio: 1.4,
        children: [
          _menuBtn(
            "실종자 상세 정보",
            'assets/icons/detail.png',
            const Color(0xFF333333),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MissingListPage()),
            ),
          ),
          _menuBtn(
            "생활안전지도",
            'assets/icons/map.png',
            const Color(0xFF333333),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MapPage()),
            ),
          ),
          _menuBtn(
            "실종예방등록",
            'assets/icons/register.png',
            const Color(0xFF333333),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const RegisterPage()),
            ),
          ),
          _menuBtn(
            "실종신고",
            'assets/icons/report.png',
            const Color(0xFF333333),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReportPage()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuBtn(
    String text,
    dynamic icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon is String)
              Image.asset(
                icon,
                width: 45,
                height: 45,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) {
                  return Icon(
                    Icons.image_not_supported_outlined,
                    size: 36,
                    color: color,
                  );
                },
              )
            else if (icon is IconData)
              Icon(
                icon,
                size: 36,
                color: color,
              ),

            const SizedBox(height: 10),

            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 4️⃣ 하단 전화 버튼 (시안 스타일)
  Widget _buildBottomCalls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _callItem("112", "경찰"),
        _callItem("182", "실종아동센터"),
        _callItem("117", "신고상담센터"),
      ],
    );
  }

  Widget _callItem(String number, String label) {
    return InkWell( // 👈 터치 이벤트 추가
      onTap: () => _showCallDialog(number, label), // 👈 클릭 시 다이얼로그 호출
      borderRadius: BorderRadius.circular(40),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(color: Color(0xFFFEF9E4), shape: BoxShape.circle),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.phone_enabled, size: 28),
                const SizedBox(height: 4),
                Text(number, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Map<String, dynamic>? get _currentProfile {
    final profiles = _visibleProfiles;

    if (profiles.isEmpty) return null;

    if (_currentProfileIndex < 0 ||
        _currentProfileIndex >= profiles.length) {
      return profiles.first;
    }

    return profiles[_currentProfileIndex];
  }

  String _display(dynamic value, {String fallback = '정보 없음'}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return fallback;
    return text;
  }

  String _formatGender(dynamic value) {
    final text = value?.toString().trim().toLowerCase() ?? '';

    switch (text) {
      case 'male':
      case 'm':
      case '남':
      case '남자':
      case '남성':
        return '남자';
      case 'female':
      case 'f':
      case '여':
      case '여자':
      case '여성':
        return '여자';
      default:
        return text.isEmpty ? '정보 없음' : value.toString();
    }
  }

  String _profileImageUrl(Map<String, dynamic> profile) {
    final mainPhoto = profile['main_photo']?.toString();

    if (mainPhoto != null && mainPhoto.isNotEmpty) {
      return mainPhoto.startsWith('http')
          ? mainPhoto
          : '${ApiConfig.mediaBaseUrl}$mainPhoto';
    }

    final photos = profile['photo_items'] ?? profile['photos'];

    if (photos is List && photos.isNotEmpty) {
      final first = photos.first;

      if (first is Map) {
        final imageUrl = first['image_url']?.toString();
        final image = first['image']?.toString();

        if (imageUrl != null && imageUrl.isNotEmpty) return imageUrl;
        if (image != null && image.isNotEmpty) {
          return image.startsWith('http')
              ? image
              : '${ApiConfig.mediaBaseUrl}$image';
        }
      }

      if (first is String && first.isNotEmpty) {
        return first.startsWith('http')
            ? first
            : '${ApiConfig.mediaBaseUrl}$first';
      }
    }

    return '';
  }

  String _calculateAge(Map<String, dynamic> profile) {
    final directAge = profile['current_age'] ?? profile['age'];
    if (directAge != null && directAge.toString().trim().isNotEmpty) {
      return directAge.toString();
    }

    final rrnFront = profile['rrn_front']?.toString().trim() ?? '';
    final rrnBack = profile['rrn_back']?.toString().trim() ?? '';

    if (rrnFront.length < 6 || rrnBack.isEmpty) {
      return '정보 없음';
    }

    try {
      final yy = int.parse(rrnFront.substring(0, 2));
      final mm = int.parse(rrnFront.substring(2, 4));
      final dd = int.parse(rrnFront.substring(4, 6));
      final genderCode = rrnBack.substring(0, 1);

      int birthYear;
      if (genderCode == '1' || genderCode == '2') {
        birthYear = 1900 + yy;
      } else if (genderCode == '3' || genderCode == '4') {
        birthYear = 2000 + yy;
      } else {
        return '정보 없음';
      }

      final today = DateTime.now();
      int age = today.year - birthYear;

      final birthdayThisYear = DateTime(today.year, mm, dd);
      if (today.isBefore(birthdayThisYear)) {
        age -= 1;
      }

      return age.toString();
    } catch (_) {
      return '정보 없음';
    }
  }
  List<Map<String, dynamic>> get _visibleProfiles {
    if (_visibleProfileIds.isEmpty) return _protectedProfiles;

    return _protectedProfiles.where((profile) {
      final id = profile['register_id'] ?? profile['id'];
      if (id == null) return false;

      return _visibleProfileIds.contains(int.parse(id.toString()));
    }).toList();
  }

}