import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

class GuardianProtectedProfilePage extends StatefulWidget {
  final int registerId;

  const GuardianProtectedProfilePage({
    super.key,
    required this.registerId,
  });

  @override
  State<GuardianProtectedProfilePage> createState() =>
      _GuardianProtectedProfilePageState();
}

class _GuardianProtectedProfilePageState
    extends State<GuardianProtectedProfilePage> {
  bool _isLoading = true;
  bool _isAdmin = false;
  Map<String, dynamic>? _profile;
  int _selectedPhotoIndex = 0;

  @override
  void initState() {
    super.initState();
    _fetchProtectedProfile();
  }

  Future<void> _fetchProtectedProfile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access') ?? '';
      final role = prefs.getString('role') ?? '';
      final isAdmin = role == 'admin';
      debugPrint('👮 guardian_protected_profile role=$role, isAdmin=$isAdmin');

      if (token.isEmpty) {
        if (!mounted) return;

        setState(() {
          _isLoading = false;
          _profile = null;
        });
        return;
      }

      final response = await http
          .get(
            Uri.parse(
              '${ApiConfig.baseUrl}/prevention-registrations/${widget.registerId}/',
            ),
            headers: {
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 8));

      final responseBody = utf8.decode(response.bodyBytes);

      debugPrint('피보호자 예방등록 상세 코드: ${response.statusCode}');

      if (!mounted) return;

      if (response.statusCode == 200) {
        final detail = jsonDecode(responseBody) as Map<String, dynamic>;
        debugPrint('🔑 device 필드: ${detail['device']}');

        setState(() {
          _profile = detail;
          _isAdmin = isAdmin;
          _selectedPhotoIndex = 0;
          _isLoading = false;
        });
      } else {
        setState(() {
          _profile = null;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('피보호자 상세 프로필 조회 에러: $e');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _profile = null;
      });
    }
  }

  String _badgeSerial(dynamic device) {
    if (device is Map) {
      for (final key in ['device_uid', 'device_code', 'uid', 'code', 'serial']) {
        final v = device[key]?.toString().trim();
        if (v != null && v.isNotEmpty && v != 'null') return v;
      }
    }
    return '정보 없음';
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
      case '남성':
      case '남자':
        return '남자';

      case 'female':
      case 'f':
      case '여':
      case '여성':
      case '여자':
        return '여자';

      default:
        return text.isEmpty ? '정보 없음' : value.toString();
    }
  }

  String _formatRrn(dynamic front, dynamic back) {
    final f = front?.toString().trim() ?? '';
    final b = back?.toString().trim() ?? '';

    if (f.isEmpty && b.isEmpty) return '정보 없음';
    if (f.isEmpty) return '- $b';
    if (b.isEmpty) return '$f -';

    return '$f - $b';
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;

    return Scaffold(
      backgroundColor: const Color(0xFFFDF9EB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
          child: Image.asset(
            'assets/images/dasibom_logo.png',
            height: 40,
            errorBuilder: (c, e, s) =>
                const Icon(Icons.favorite, color: Colors.amber),
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : profile == null
              ? _buildEmptyView()
              : RefreshIndicator(
                  onRefresh: _fetchProtectedProfile,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildPhotoSection(profile),
                        const SizedBox(height: 20),
                        _buildSection(
                          title: '등록 대상자 정보',
                          children: [
                            Row(children: [
                              Expanded(child: _readOnlyBox('이름', _display(profile['name']))),
                              const SizedBox(width: 10),
                              Expanded(child: _readOnlyBox('성별', _formatGender(profile['gender']))),
                            ]),
                            _readOnlyBox('전화번호', _display(profile['phone'])),
                            _readOnlyBox('주소', _display(profile['address'])),
                            _readOnlyBox('자주 가는 장소', _display(profile['frequent_place'])),
                            _readOnlyBox('기타 참고사항', _display(profile['note'])),
                            _readOnlyBox('주민등록번호',
                                _formatRrn(profile['rrn_front'], profile['rrn_back'])),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _buildSection(
                          title: '신체 및 특징 정보',
                          children: [
                            Row(children: [
                              Expanded(child: _readOnlyBox('키', _display(profile['height']))),
                              const SizedBox(width: 10),
                              Expanded(child: _readOnlyBox('몸무게', _display(profile['weight']))),
                            ]),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(child: _readOnlyBox('체격', _display(profile['body_type']))),
                              const SizedBox(width: 10),
                              Expanded(child: _readOnlyBox('얼굴형', _display(profile['face_type']))),
                            ]),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(child: _readOnlyBox('두발 색상', _display(profile['hair_color']))),
                              const SizedBox(width: 10),
                              Expanded(child: _readOnlyBox('두발 형태', _display(profile['hair_style']))),
                            ]),
                            const SizedBox(height: 10),
                            Row(children: [
                              Expanded(child: _readOnlyBox('혈액형', _display(profile['blood_type']))),
                              const SizedBox(width: 10),
                              Expanded(child: _readOnlyBox('눈동자 색', _display(profile['eye_color']))),
                            ]),
                            const SizedBox(height: 10),
                            _readOnlyBox('신체 특징', _display(profile['physical_feature'])),
                            _readOnlyBox('건강 정보', _display(profile['health_info'])),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _buildSection(
                          title: '보호자 정보',
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFAFA),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _readOnlyPinkBox(
                                    '보호자 이름',
                                    _display(profile['guardian_name']),
                                  ),
                                  const SizedBox(height: 16),
                                  _readOnlyPinkBox(
                                    '보호자 전화번호',
                                    _display(profile['guardian_phone']),
                                  ),
                                  const SizedBox(height: 16),
                                  _readOnlyPinkBox(
                                    '보호자 주민등록번호',
                                    _formatRrn(
                                      profile['guardian_rrn_front'],
                                      profile['guardian_rrn_back'],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (_isAdmin) ...[
                          const SizedBox(height: 20),
                          _buildSection(
                            title: '뱃지 정보 (관리자)',
                            children: [
                              _readOnlyBox(
                                '뱃지 일련번호',
                                _badgeSerial(profile['device']),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              );
            }

  Widget _readOnlyPinkBox(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 12,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEEEE),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyView() {
    return RefreshIndicator(
      onRefresh: _fetchProtectedProfile,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 160),
          Icon(Icons.person_search_outlined, size: 64, color: Colors.black26),
          SizedBox(height: 16),
          Center(
            child: Text(
              '등록된 피보호자 예방등록 정보가 없습니다.',
              style: TextStyle(fontSize: 15, color: Colors.black54, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection(Map<String, dynamic> data) {
    final photos = data['photo_items'] ?? data['photos'];

    final List<Map<String, dynamic>> photoList = photos is List
        ? photos.map<Map<String, dynamic>>((p) {
            if (p is Map) {
              final m = Map<String, dynamic>.from(p);
              // url(Cloudinary) → image 우선 적용
              m['image'] = m['url'] ?? m['image_url'] ?? m['photo'] ?? m['file'] ?? m['image'];
              return m;
            }
            return {'image': p.toString()};
          }).toList()
        : [];

    final mainPhoto = data['main_photo']?.toString() ?? '';

    if (photoList.isEmpty && mainPhoto.isNotEmpty) {
      photoList.add({
        'image_url': mainPhoto,
        'image': mainPhoto,
        'photo_type': 'face',
        'validation_status': null,
        'validation_message': '대표 사진',
      });
    }

    final totalCount = photoList.length;

    final safeIndex = _selectedPhotoIndex.clamp(
      0,
      totalCount == 0 ? 0 : totalCount - 1,
    );

    final selectedPhoto =
        totalCount > 0 ? photoList[safeIndex] : null;

    final selectedUrl =
        selectedPhoto == null ? '' : _photoUrl(selectedPhoto);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 140,
                height: 170,
                color: const Color(0xFFD9E2F3),
                child: selectedUrl.isNotEmpty
                    ? Image.network(
                        selectedUrl,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        errorBuilder: (_, __, ___) {
                          return const Icon(
                            Icons.person,
                            size: 50,
                            color: Colors.white,
                          );
                        },
                      )
                    : const Icon(
                        Icons.person,
                        size: 50,
                        color: Colors.white,
                      ),
              ),
            ),
            Positioned(
              top: 5,
              left: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  selectedPhoto == null
                      ? '사진'
                      : _photoTypeLabel(
                          selectedPhoto['photo_type']?.toString(),
                        ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '등록 사진',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (totalCount == 0)
                const Text(
                  '첨부된 사진이 없습니다.',
                  style: TextStyle(
                    color: Colors.black45,
                    fontSize: 13,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: photoList.asMap().entries.map((entry) {
                    final index = entry.key;
                    final photo = entry.value;
                    final url = _photoUrl(photo);
                    final validationStatus =
                        photo['validation_status']?.toString();

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedPhotoIndex = index;
                        });
                      },
                      child: Stack(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey.shade300,
                              border: Border.all(
                                color: _selectedPhotoIndex == index
                                    ? Colors.blue
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: ClipOval(
                              child: url.isNotEmpty
                                  ? Image.network(
                                      url,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) {
                                        return const Icon(
                                          Icons.person,
                                          size: 20,
                                        );
                                      },
                                    )
                                  : const Icon(
                                      Icons.person,
                                      size: 20,
                                    ),
                            ),
                          ),
                          if (validationStatus != null)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  color: _validationColor(validationStatus),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              if (selectedPhoto != null) ...[
                const SizedBox(height: 12),
                _buildValidationMessage(selectedPhoto),
              ],
            ],
          ),
        ),
      ],
    );
  }

  String _photoUrl(Map<String, dynamic> photo) {
    for (final key in ['url', 'image_url', 'image', 'photo', 'file']) {
      final v = photo[key]?.toString() ?? '';
      if (v.isEmpty) continue;
      if (v.startsWith('http')) return v;
      return '${ApiConfig.mediaBaseUrl}${v.startsWith('/') ? v : '/$v'}';
    }
    return '';
  }

String _photoTypeLabel(String? type) {
  switch (type) {
    case 'face':
      return '정면';
    case 'full_body':
      return '전신';
    case 'left_side':
      return '왼쪽 측면';
    case 'right_side':
      return '오른쪽 측면';
    case 'parent1_face':
      return '가족 1';
    case 'parent2_face':
      return '가족 2';
    default:
      return '사진';
  }
}

String _validationLabel(String? status) {
  switch (status) {
    case 'valid':
      return '정상';
    case 'warning':
      return '경고';
    case 'invalid':
      return '부적합';
    case 'error':
      return '오류';
    default:
      return '미검사';
  }
}

Color _validationColor(String? status) {
  switch (status) {
    case 'valid':
      return Colors.green;
    case 'warning':
      return Colors.orange;
    case 'invalid':
    case 'error':
      return Colors.red;
    default:
      return Colors.grey;
  }
}

  Widget _buildValidationMessage(Map<String, dynamic> photo) {
    final status = photo['validation_status']?.toString();

    final message = _display(
      photo['validation_message'],
      fallback: '사진 검증 정보가 없습니다.',
    );

    final confidence = photo['validation_confidence'];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${_validationLabel(status)} · $message'
        '${confidence == null ? '' : ' · 신뢰도 $confidence'}',
        style: TextStyle(
          fontSize: 12,
          color: _validationColor(status),
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _readOnlyBox(String label, String value) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$label : $value',
        style: const TextStyle(
          fontSize: 14,
          color: Colors.black87,
        ),
      ),
    );
  }
}