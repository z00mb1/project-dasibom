import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'citizen_status_detail.dart';

class CitizenStatusTab extends StatefulWidget {
  const CitizenStatusTab({super.key});

  @override
  State<CitizenStatusTab> createState() => CitizenStatusTabState();
}

class CitizenStatusTabState extends State<CitizenStatusTab> {
  bool _isLoading = false;
  // ignore: prefer_final_fields
  bool _isAdmin = false;
  bool _isLoggedIn = false;
  List<Map<String, dynamic>> _tips = [];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() => _fetchMyTips();

  Future<void> _fetchMyTips() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access') ?? '';
    final role = prefs.getString('role') ?? '';
    final isAdmin = role == 'admin';

    if (token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoggedIn = false;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoggedIn = true;
      _isLoading = true;
      _isAdmin = isAdmin;
    });

    try {
      final response = await http.get(
        Uri.parse(
          isAdmin
              ? '${ApiConfig.baseUrl}/case/tips/admin/'
              : '${ApiConfig.baseUrl}/case/my-tips/',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final List<dynamic> rawList = decoded is List
            ? decoded
            : (decoded['results'] is List ? decoded['results'] : []);

        setState(() {
          _tips = rawList
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _tips = [];
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('제보 목록 조회 오류: $e');
      if (!mounted) return;
      setState(() {
        _tips = [];
        _isLoading = false;
      });
    }
  }

  int _statusToStep(String status) {
    switch (status) {
      case 'received':
        return 1;
      case 'reviewing':
        return 2;
      case 'completed':
        return 3;
      default:
        return 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!_isLoggedIn) {
      return const Center(
        child: Text(
          '제보 현황은 로그인 후 확인할 수 있습니다.',
          style: TextStyle(color: Colors.black45),
        ),
      );
    }

    if (_tips.isEmpty) {
      return const Center(
        child: Text(
          '제출한 제보가 없습니다.',
          style: TextStyle(color: Colors.black45),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _tips.length,
        itemBuilder: (context, index) => _buildTipCard(_tips[index]),
      ),
    );
  }

  Widget _buildTipCard(Map<String, dynamic> tip) {
    final status = tip['status']?.toString() ?? 'received';
    final step = _statusToStep(status);

    final name = tip['missing_name']?.toString() ??
        tip['reported_missing_name']?.toString() ??
        '알 수 없음';

    final location = tip['found_location']?.toString() ??
        tip['occr_location']?.toString() ??
        '';

    final rawDate = tip['found_datetime']?.toString() ??
        tip['occr_date']?.toString() ??
        tip['created_at']?.toString() ??
        '';

    // 실종자 공식 프로필 사진 — main_photo(제보자 첨부)는 사용하지 않음
    final rawPhoto = tip['missing_profile_photo']?.toString() ??
        tip['missing_photo']?.toString() ??
        tip['missing_face_photo']?.toString();
    final photoUrl = (rawPhoto != null && rawPhoto.isNotEmpty)
        ? (rawPhoto.startsWith('http')
            ? rawPhoto
            : '${ApiConfig.mediaBaseUrl}$rawPhoto')
        : null;

    String dateStr = rawDate;
    try {
      final dt = DateTime.parse(rawDate).toLocal();
      dateStr = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {}

    final isRejected  = status == 'rejected';
    final isCompleted = status == 'completed';

    return GestureDetector(
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CitizenStatusDetailPage(tipData: tip),
          ),
        );
        refresh();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isRejected
              ? const Color(0xFFFFEBEE)
              : isCompleted
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFFDF9EB),
          borderRadius: BorderRadius.circular(16),
          border: isRejected
              ? Border.all(color: Colors.red.shade200, width: 1.5)
              : isCompleted
                  ? Border.all(color: Colors.green.shade200, width: 1.5)
                  : null,
        ),
        child: Column(
          children: [
            if (isRejected)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cancel_outlined, color: Colors.red.shade700, size: 16),
                    const SizedBox(width: 6),
                    Text('제보가 거절되었습니다',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        )),
                  ],
                ),
              ),
            if (isCompleted)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline, color: Colors.green.shade700, size: 16),
                    const SizedBox(width: 6),
                    Text('제보가 완료되었습니다',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        )),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 120,
                        height: 120,
                        color: const Color(0xFFD4DAF0),
                        child: photoUrl != null && photoUrl.isNotEmpty
                            ? Image.network(
                                photoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.person,
                                  size: 50,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.person,
                                size: 50,
                                color: Colors.white,
                              ),
                      ),
                    ),

                    // ✅ 관리자일 때만 신고자 미니 박스 표시
                    if (_isAdmin) ...[
                      const SizedBox(height: 8),
                      _buildReporterMiniBox(tip),
                    ],
                  ],
                ),

                const SizedBox(width: 16),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow('실종자 이름', name),
                      const SizedBox(height: 8),
                      _buildInfoRow('제보 일자', dateStr),
                      const SizedBox(height: 8),
                      _buildInfoRow('발견한 위치', location),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            _buildStatusBar(step, status),
          ],
        ),
      ),
    );
  }

  Widget _buildReporterMiniBox(Map<String, dynamic> tip) {
    final reporterName =
        tip['reporter_name']?.toString().trim().isNotEmpty == true
            ? tip['reporter_name'].toString()
            : '정보 없음';

    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          const Text(
            '제보자',
            style: TextStyle(
              fontSize: 10,
              color: Colors.black45,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            reporterName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.black87)),
        const SizedBox(height: 3),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F1D6),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            content,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBar(int step, String status) {
    if (status == 'rejected') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.remove_circle_outline, color: Colors.red.shade400, size: 16),
            const SizedBox(width: 6),
            Text('거절됨',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade600,
                )),
          ],
        ),
      );
    }

    final widthFactor = step == 1 ? 0.1 : step == 2 ? 0.5 : 1.0;

    return Column(
      children: [
        Stack(
          children: [
            Container(
              height: 10,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            FractionallySizedBox(
              widthFactor: widthFactor,
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  color: const Color(0xFFFDE14C),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('접수 중',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
            Text('확인 중',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
            Text('제보 완료',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87)),
          ],
        ),
      ],
    );
  }
}
