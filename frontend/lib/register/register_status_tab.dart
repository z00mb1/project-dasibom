import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'register_staus_detail.dart';

import '../config/api_config.dart';

class RegisterStatusTab extends StatefulWidget {
  const RegisterStatusTab({super.key});

  @override
  State<RegisterStatusTab> createState() => RegisterStatusTabState();
}

class RegisterStatusTabState extends State<RegisterStatusTab> {
  void refresh() => _fetchList();

  List<Map<String, dynamic>> _statusList = [];
  bool _isLoading = false;
  bool _isLoggedIn = true;
  bool _isAdmin = false;
  int _selectedFilter = 0; // 0=전체 1=접수중 2=확인중 3=등록완료

  @override
  void initState() {
    super.initState();
    _fetchList();
  }

  Future<void> _fetchList() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access') ?? '';
    final role = prefs.getString('role') ?? '';
    final isGuest = prefs.getBool('isGuest') ?? token.isEmpty;

    if (!mounted) return;

    if (isGuest || token.isEmpty) {
      setState(() {
        _isLoggedIn = false;
        _isLoading = false;
        _statusList = [];
      });
      return;
    }

    setState(() {
      _isLoggedIn = true;
      _isLoading = true;
      _isAdmin = role == 'admin';
    });

    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/prevention-registrations/'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));

        final List rawList = decoded is List
            ? decoded
            : (decoded is Map && decoded['results'] is List
                ? decoded['results'] as List
                : []);
        setState(() {
          _statusList = rawList
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
      } else if (response.statusCode == 401) {
        setState(() {
          _isLoggedIn = false;
          _statusList = [];
        });
      } else {
        setState(() {
          _statusList = [];
        });

        debugPrint('예방등록 목록 조회 실패: ${response.statusCode}');
        debugPrint(utf8.decode(response.bodyBytes));
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _statusList = [];
      });

      debugPrint('예방등록 목록 조회 에러: $e');
    }

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> get _filteredList {
    if (_selectedFilter == 0) return _statusList;
    const statusMap = ['', 'received', 'reviewing', 'completed'];
    final target = statusMap[_selectedFilter];
    return _statusList.where((e) => e['status']?.toString() == target).toList();
  }

  int _convertStatus(String status) {
    switch (status) {
      case 'received':
        return 0;
      case 'reviewing':
        return 1;
      case 'completed':
        return 2;
      case 'rejected':
        return 3;
      default:
        return 0;
    }
  }

  String _formatDate(String? date) {
    if (date == null || date.isEmpty) return '0000-00-00';

    try {
      final parsed = DateTime.parse(date).toLocal();
      final y = parsed.year.toString().padLeft(4, '0');
      final m = parsed.month.toString().padLeft(2, '0');
      final d = parsed.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    } catch (_) {
      if (date.length >= 10) return date.substring(0, 10);
      return date;
    }
  }

  String _formatGender(String? gender) {
    if (gender == null || gender.isEmpty) return '성별 없음';

    switch (gender.toLowerCase()) {
      case 'male':
      case 'm':
      case '남':
      case '남성':
        return '남성';

      case 'female':
      case 'f':
      case '여':
      case '여성':
        return '여성';

      default:
        return gender;
    }
  }

  String _summaryText(dynamic summary) {
    if (summary is! Map) {
      return '사진 검증 정보 없음';
    }

    final total = summary['total'] ?? 0;
    final valid = summary['valid'] ?? 0;
    final warning = summary['warning'] ?? 0;
    final invalid = summary['invalid'] ?? 0;
    final error = summary['error'] ?? 0;

    return '사진 검증 : 총 $total장\n정상 $valid장  경고 $warning장  오류 ${invalid + error}장';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoggedIn) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 52, color: Colors.grey.shade300),
            const SizedBox(height: 14),
            const Text(
              '로그인 후 확인할 수 있습니다.',
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _filteredList;

    return Column(
      children: [
        _buildFilterBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchList,
            child: filtered.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Icon(Icons.folder_open_outlined, size: 54, color: Colors.black26),
                      SizedBox(height: 14),
                      Center(
                        child: Text(
                          '해당하는 예방등록 내역이 없습니다.',
                          style: TextStyle(fontSize: 15, color: Colors.black45),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return GestureDetector(
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RegisterDetailPage(registerId: item['id']),
                            ),
                          );
                          if (result == true) _fetchList();
                        },
                        child: _buildStatusCard(item),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    const labels = ['전체', '접수중', '확인중', '등록완료'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: List.generate(labels.length, (i) {
          final selected = _selectedFilter == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedFilter = i),
              child: Container(
                margin: EdgeInsets.only(left: i == 0 ? 0 : 6),
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFFFDE14C) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected ? const Color(0xFFFDE14C) : Colors.black12,
                  ),
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStatusCard(Map<String, dynamic> item) {
    final name = item['name']?.toString() ?? '이름 없음';
    final gender = _formatGender(item['gender']?.toString());
    final rawStatus = item['status']?.toString() ?? 'received';
    final status = _convertStatus(rawStatus);
    final dateText = _formatDate(item['created_at']?.toString());
    final mainPhoto = item['main_photo']?.toString();
    final rejectedReason = item['rejected_reason']?.toString();

    final double progress = status == 0
        ? 0.05
        : status == 1
            ? 0.5
            : status == 2
                ? 1.0
                : 0.0;

    final isRejected  = rawStatus == 'rejected';
    final isCompleted = rawStatus == 'completed';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isRejected
            ? const Color(0xFFFFEBEE)
            : isCompleted
                ? const Color(0xFFE8F5E9)
                : const Color(0xFFFDF9EB),
        borderRadius: BorderRadius.circular(18),
        border: isRejected
            ? Border.all(color: Colors.red.shade200, width: 1.5)
            : isCompleted
                ? Border.all(color: Colors.green.shade200, width: 1.5)
                : Border.all(color: const Color(0xFFEFE6C8), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
                  Text('신청이 거절되었습니다',
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
                  Text('등록이 완료되었습니다',
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
                  _buildPhotoBox(mainPhoto),
                  if (_isAdmin) ...[
                    const SizedBox(height: 8),
                    _buildApplicantMiniBox(item),
                  ],
                ],
              ),
              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('등록 대상자', name),
                    _buildInfoRow('성별', gender),
                    _buildInfoRow('등록일', dateText),
                    _buildInlinePhotoValidationBox(item['photo_validation_summary']),
                  ],
                ),
              ),
            ],
          ),

          if (rawStatus == 'rejected' && rejectedReason != null && rejectedReason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '거절 사유: $rejectedReason',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFD32F2F),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          _RegisterProgressBar(
            status: status,
            progress: progress,
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoBox(String? imageUrl) {
    const double photoBoxWidth = 105;
    const double photoBoxHeight = 140;

    return Container(
      width: photoBoxWidth,
      height: photoBoxHeight,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5DDCB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl == null || imageUrl.isEmpty
          ? const Icon(
              Icons.person_outline,
              size: 44,
              color: Color(0xFF4F6380),
            )
          : Image.network(
              imageUrl,
              width: photoBoxWidth,
              height: photoBoxHeight,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, __, ___) {
                return const Icon(
                  Icons.broken_image_outlined,
                  size: 38,
                  color: Colors.black26,
                );
              },
            ),
          );
        }

  Widget _buildApplicantMiniBox(Map<String, dynamic> item) {
    final applicantName =
        item['user_name']?.toString().trim().isNotEmpty == true
            ? item['user_name'].toString()
            : item['reporter_name']?.toString().trim().isNotEmpty == true
                ? item['reporter_name'].toString()
                : '정보 없음';

    return Container(
      width: 105,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          const Text(
            '신청자',
            style: TextStyle(
              fontSize: 10,
              color: Colors.black45,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            applicantName,
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

  Widget _buildInlinePhotoValidationBox(dynamic summary) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        _summaryText(summary),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 11,
          color: Colors.black54,
          height: 1.35,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegisterProgressBar extends StatefulWidget {
  final int status;
  final double progress;

  const _RegisterProgressBar({
    required this.status,
    required this.progress,
  });

  @override
  State<_RegisterProgressBar> createState() => _RegisterProgressBarState();
}

class _RegisterProgressBarState extends State<_RegisterProgressBar> {
  bool _visible = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    if (widget.status == 0) {
      _timer = Timer.periodic(const Duration(milliseconds: 800), (_) {
        if (mounted) {
          setState(() {
            _visible = !_visible;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.status == 3) {
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

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AnimatedOpacity(
            opacity: widget.status == 0 ? (_visible ? 1.0 : 0.2) : 1.0,
            duration: const Duration(milliseconds: 600),
            child: LinearProgressIndicator(
              value: widget.progress,
              minHeight: 10,
              backgroundColor: Colors.white,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFFDE14C),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _statusText('접수중', widget.status >= 0),
            _statusText('확인중', widget.status >= 1),
            _statusText('등록 완료', widget.status >= 2),
          ],
        ),
      ],
    );
  }

  Widget _statusText(String text, bool active) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: active ? FontWeight.bold : FontWeight.normal,
        color: active ? Colors.black87 : Colors.black38,
      ),
    );
  }
}