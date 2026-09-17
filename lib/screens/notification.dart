import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../report/report.dart';
import '../register/register.dart';


class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  bool _isNotificationTab = true;
  bool _isGuardian = false;

  bool _isLoadingNotification = false;
  bool _isLoadingLocationLog = false;

  List<Map<String, dynamic>> notificationLogs = [];
  List<Map<String, dynamic>> locationLogs = [];

  @override
  void initState() {
    super.initState();
    _loadPageData();
  }

  Future<void> _loadPageData() async {
    await _loadUserRole();
    await _fetchNotificationLogs();

    if (_isGuardian) {
      await _fetchLocationLogs();
    }
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = (prefs.getString('role') ?? '').toLowerCase();

    debugPrint('현재 로그인 role: $role');

    if (!mounted) return;

    setState(() {
      _isGuardian = role == 'guardian';
    });
  }

  Future<void> _fetchLocationLogs() async {
    setState(() => _isLoadingLocationLog = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access') ?? '';

      if (token.isEmpty) {
        if (!mounted) return;
        setState(() { locationLogs = []; _isLoadingLocationLog = false; });
        return;
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/gps/history/'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final List<dynamic> rawList = decoded is List
            ? decoded
            : (decoded is Map && decoded['results'] is List)
                ? decoded['results']
                : [];

        final grouped = _groupLocationLogs(rawList);

        // 역지오코딩: 고유 lat/lng 쌍을 먼저 수집해 한 번씩만 요청
        final coordKeys = <String>{};
        for (final group in grouped) {
          for (final item in (group['items'] as List)) {
            final k = item['_coordKey'] as String? ?? '';
            if (k.isNotEmpty) coordKeys.add(k);
          }
        }

        final addressMap = <String, String>{};
        for (final key in coordKeys) {
          final parts = key.split(',');
          if (parts.length == 2) {
            final addr = await _reverseGeocode(parts[0], parts[1]);
            if (addr.isNotEmpty) addressMap[key] = addr;
            await Future.delayed(const Duration(milliseconds: 1100)); // Nominatim 초당 1회 제한
          }
        }

        // 주소로 교체
        for (final group in grouped) {
          for (final item in (group['items'] as List<Map<String, dynamic>>)) {
            final k = item['_coordKey'] as String? ?? '';
            if (addressMap.containsKey(k)) item['loc'] = addressMap[k]!;
            item.remove('_coordKey');
          }
        }

        if (!mounted) return;
        setState(() { locationLogs = grouped; _isLoadingLocationLog = false; });
      } else {
        if (!mounted) return;
        setState(() { locationLogs = []; _isLoadingLocationLog = false; });
      }
    } catch (e) {
      debugPrint('위치 로그 조회 에러: $e');
      if (!mounted) return;
      setState(() { locationLogs = []; _isLoadingLocationLog = false; });
    }
  }

  List<Map<String, dynamic>> _groupLocationLogs(List<dynamic> rawList) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final raw in rawList) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);

      final ts = item['timestamp']?.toString() ?? '';
      final dateKey = _formatDateKey(ts);
      grouped.putIfAbsent(dateKey, () => []);

      final lat = item['lat']?.toString() ?? '';
      final lng = item['lng']?.toString() ?? '';
      final coordKey = lat.isNotEmpty && lng.isNotEmpty ? '$lat,$lng' : '';
      final loc = coordKey.isNotEmpty ? '$lat, $lng' : '위치 정보 없음';

      grouped[dateKey]!.add({
        'title': item['ward_name']?.toString() ?? '피보호자',
        'loc': loc,
        '_coordKey': coordKey, // 역지오코딩 후 제거
        'time': _formatTime(ts),
      });
    }

    return grouped.entries.map((e) => {'date': e.key, 'items': e.value}).toList();
  }

  Future<String> _reverseGeocode(String lat, String lng) async {
    try {
      final res = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&accept-language=ko',
        ),
        headers: {'User-Agent': 'dasibom-app'},
      ).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final addr = body['display_name']?.toString() ?? '';
        if (addr.isNotEmpty) return addr;
      }
    } catch (e) {
      debugPrint('역지오코딩 실패($lat,$lng): $e');
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,

        // 뒤로가기: 이전 화면으로 이동
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: Colors.black,
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),

        title: GestureDetector(
          onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
          child: Image.asset(
            'assets/images/dasibom_logo.png',
            height: 40,
            errorBuilder: (c, e, s) =>
                const Icon(Icons.favorite, color: Colors.pink),
          ),
        ),
        centerTitle: true,
      ),
      body: _isGuardian
          ? Column(
              children: [
                _buildTabs(),
                Expanded(
                  child: _isNotificationTab
                      ? _buildNotificationLogList()
                      : _buildLocationLogList(),
                ),
              ],
            )
          : _buildNotificationLogList(),
    );
  }

  Future<void> _fetchNotificationLogs() async {
    setState(() {
      _isLoadingNotification = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access') ?? '';

      if (token.isEmpty) {
        if (!mounted) return;

        setState(() {
          notificationLogs = [];
          _isLoadingNotification = false;
        });

        return;
      }

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/notifications/'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (!mounted) return;

      debugPrint('알림 로그 조회 코드: ${response.statusCode}');
      final body = utf8.decode(response.bodyBytes);

      debugPrint('알림 API 실패: ${response.statusCode}');

      if (!body.trimLeft().startsWith('<!DOCTYPE html') &&
          !body.trimLeft().startsWith('<html')) {
        debugPrint(body.length > 300 ? body.substring(0, 300) : body);
      }

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));

        final List<dynamic> rawList;

        if (decoded is List) {
          rawList = decoded;
        } else if (decoded is Map && decoded['results'] is List) {
          rawList = decoded['results'];
        } else {
          rawList = [];
        }

        final grouped = _groupNotificationLogs(rawList);

        setState(() {
          notificationLogs = grouped;
          _isLoadingNotification = false;
        });
      } else {
        setState(() {
          notificationLogs = [];
          _isLoadingNotification = false;
        });
      }
    } catch (e) {
      debugPrint('알림 로그 조회 에러: $e');

      if (!mounted) return;

      setState(() {
        notificationLogs = [];
        _isLoadingNotification = false;
      });
    }
  }

  String _defaultNotificationTitle(String type) {
    switch (type) {
      case 'missing_report':
        return '실종 신고 알림';
      case 'citizen_tip':
        return '시민 제보 알림';
      case 'prevention':
        return '실종예방등록 알림';
      case 'status_changed':
        return '상태 변경 알림';
      case 'inquiry':
        return '새 문의 알림';
      default:
        return '알림';
    }
  }

  String _defaultNotificationMessage(String type, Map<String, dynamic> item) {
    final name = item['target_name']?.toString() ??
        item['name']?.toString() ??
        item['missing_name']?.toString() ??
        item['reported_missing_name']?.toString() ??
        '대상자';

    final status = item['status_label']?.toString() ??
        item['to_status_label']?.toString() ??
        item['status']?.toString() ??
        '';

    switch (type) {
      case 'missing_report':
        return '$name님의 실종 신고가 정상 접수되었습니다.';
      case 'citizen_tip':
        return '$name님 관련 시민 제보가 정상 접수되었습니다.';
      case 'prevention':
        return '$name님의 실종예방등록 상태를 확인해 주세요.';
      case 'status_changed':
        return status.isNotEmpty
            ? '$name님의 처리 상태가 $status(으)로 변경되었습니다.'
            : '$name님의 처리 상태가 변경되었습니다.';
      case 'inquiry':
        return '새로운 문의가 접수되었습니다. 확인해 주세요.';
      default:
        return '새로운 알림이 도착했습니다.';
    }
  }

  List<Map<String, dynamic>> _groupNotificationLogs(List<dynamic> rawList) {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final raw in rawList) {
      if (raw is! Map) continue;

      final item = Map<String, dynamic>.from(raw);

      final createdAt =
          item['created_at']?.toString() ??
          item['timestamp']?.toString() ??
          item['createdAt']?.toString() ??
          '';

      final dateKey = _formatDateKey(createdAt);

      grouped.putIfAbsent(dateKey, () => []);

      final type = item['type']?.toString() ??
    item['notification_type']?.toString() ??
    item['target_type']?.toString() ??
    '';

    final rawTitle = item['title']?.toString() ?? '';
    final rawMessage = item['message']?.toString() ??
        item['content']?.toString() ??
        item['body']?.toString() ??
        '';

    grouped[dateKey]!.add({
      'type': type,
      'target_type': item['target_type']?.toString() ?? '',
      'title': rawTitle.isNotEmpty
          ? rawTitle
          : _defaultNotificationTitle(type),
      'message': rawMessage.isNotEmpty
          ? rawMessage
          : _defaultNotificationMessage(type, item),
      'time': _formatTime(createdAt),
      'is_read': item['is_read'] ?? false,
    });
    }

    return grouped.entries.map((entry) {
      return {
        'date': entry.key,
        'items': entry.value,
      };
    }).toList();
  }


  String _formatDateKey(String raw) {
    if (raw.isEmpty) return '날짜 없음';

    try {
      final dt = DateTime.parse(raw).toLocal();
      final now = DateTime.now();

      final y = dt.year.toString();
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');

      final today =
          dt.year == now.year &&
          dt.month == now.month &&
          dt.day == now.day;

      return today ? '$y.$m.$d(오늘)' : '$y.$m.$d';
    } catch (_) {
      if (raw.length >= 10) return raw.substring(0, 10);
      return raw;
    }
  }

  String _formatTime(String raw) {
    if (raw.isEmpty) return '';

    try {
      final dt = DateTime.parse(raw).toLocal();
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return raw.length >= 16 ? raw.substring(11, 16) : raw;
    }
  }

  Widget _buildTabs() {
    return Row(
      children: [
        _tabItem(
          '알림',
          isSelected: _isNotificationTab,
          onTap: () {
            setState(() {
              _isNotificationTab = true;
            });
          },
        ),
        _tabItem(
          '위치 로그',
          isSelected: !_isNotificationTab,
          onTap: () {
            setState(() {
              _isNotificationTab = false;
            });
          },
        ),
      ],
    );
  }

  Widget _tabItem(String title, {required bool isSelected, required VoidCallback onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(title, style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.black : Colors.grey,
              )),
            ),
            if (isSelected) Container(height: 3, color: Colors.black),
          ],
        ),
      ),
    );
  }

  /*Widget _buildMoveCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFFDF9EB),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFFDF9EB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: Colors.black87,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Colors.black38,
            ),
          ],
        ),
      ),
    );
  }*/

  Widget _buildNotificationLogList() {
    if (_isLoadingNotification) {
      return const Center(child: CircularProgressIndicator());
    }

    if (notificationLogs.isEmpty) {
      return const Center(
        child: Text(
          '알림 내역이 없습니다.',
          style: TextStyle(color: Colors.black45),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchNotificationLogs,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        itemCount: notificationLogs.length,
        itemBuilder: (context, index) {
          return _buildNotificationLogGroup(notificationLogs[index]);
        },
      ),
    );
  }

Widget _buildNotificationLogGroup(Map<String, dynamic> group) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 8, top: 14, bottom: 10),
        child: Text(
          group['date'],
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      ...List.generate(group['items'].length, (index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildNotificationLogCard(group['items'][index]),
        );
      }),
    ],
  );
}

  void _navigateFromNotification(String type, String targetType) {
    switch (type) {
      case 'missing_report':
      case 'citizen_tip':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportPage(initialTabIndex: 1)));
        break;
      case 'prevention':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage(initialTabIndex: 1)));
        break;
      case 'status_changed':
        if (targetType == 'prevention') {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage(initialTabIndex: 1)));
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportPage(initialTabIndex: 1)));
        }
        break;
      default:
        break;
    }
  }

  Widget _buildNotificationLogCard(Map<String, dynamic> item) {
    final type = item['type']?.toString() ?? '';
    final targetType = item['target_type']?.toString() ?? '';
    final title = item['title']?.toString() ?? '알림';
    final message = item['message']?.toString() ?? '';
    final time = item['time']?.toString() ?? '';

    IconData icon;
    Color iconBgColor;
    Color iconColor;

    switch (type) {
      case 'missing_report':
        icon = Icons.assignment_outlined;
        iconBgColor = const Color(0xFFFFF8DE);
        iconColor = const Color(0xFF8A6D00);
        break;
      case 'citizen_tip':
        icon = Icons.edit_note;
        iconBgColor = const Color(0xFFE3F2FD);
        iconColor = const Color(0xFF1565C0);
        break;
      case 'prevention':
        icon = Icons.person_add_alt_1_outlined;
        iconBgColor = const Color(0xFFE8F5E9);
        iconColor = const Color(0xFF2E7D32);
        break;
      case 'inquiry':
        icon = Icons.help_outline;
        iconBgColor = const Color(0xFFFCE4E4);
        iconColor = const Color(0xFFC62828);
        break;
      default:
        icon = Icons.notifications_none;
        iconBgColor = const Color(0xFFF5F5F5);
        iconColor = Colors.black54;
    }

    return GestureDetector(
      onTap: () => _navigateFromNotification(type, targetType),
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFDF9EB),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Text(
                      time,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black38,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildLocationLogList() {
    if (_isLoadingLocationLog) {
      return const Center(child: CircularProgressIndicator());
    }

    if (locationLogs.isEmpty) {
      return const Center(
        child: Text(
          '피보호자 위치 로그가 없습니다.',
          style: TextStyle(color: Colors.black45, fontSize: 14),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchLocationLogs,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        itemCount: locationLogs.length,
        itemBuilder: (context, index) => _buildTimelineGroup(
          locationLogs[index],
          isFirstGroup: index == 0,
        ),
      ),
    );
  }

  Widget _buildTimelineGroup(
    Map<String, dynamic> group, {
    required bool isFirstGroup,
  }) {
    final items = (group['items'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 52, top: 10, bottom: 8),
          child: Text(
            group['date']?.toString() ?? '',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
        ),

        ...List.generate(items.length, (index) {
          final isLatest = isFirstGroup && index == 0;
          final isLast = index == items.length - 1;

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 48,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      Positioned(
                        top: 0,
                        bottom: isLast ? 22 : 0,
                        child: Container(
                          width: 4,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF1AE),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 31,
                        child: Container(
                          width: 21,
                          height: 21,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isLatest
                                ? const Color(0xFFFDE14C)
                                : const Color(0xFFD9D9D9),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildLocationLogCard(items[index]),
                  ),
                ),
              ],
            ),
          );
        }),

        const SizedBox(height: 14),
      ],
    );
  }

  Widget _buildLocationLogCard(Map<String, dynamic> item) {
    final title = item['title']?.toString() ?? '피보호자';
    final location = item['loc']?.toString() ?? '';
    final time = item['time']?.toString() ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFEDB3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
              ),
              if (time.isNotEmpty) ...[
                const SizedBox(width: 7),
                const Text('|', style: TextStyle(fontSize: 14, color: Colors.black54)),
                const SizedBox(width: 7),
                Text(time, style: const TextStyle(fontSize: 14, color: Colors.black87)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}