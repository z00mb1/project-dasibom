import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert'; // ✅ 추가
import '../citizen/citizen.dart';
import '../models/missing_list_model.dart';
import '../config/api_config.dart';
import '../config/utils.dart';
import 'package:url_launcher/url_launcher.dart'; // ✅ 추가
import 'package:shared_preferences/shared_preferences.dart';
import 'edit_missing_detail.dart';
import '../screens/aiface.dart';
// import '../screens/inquiry.dart'; // 문의하기 임시 숨김

class MissingDetailPage extends StatefulWidget {
  final MissingListPerson? person;
  final String? missingSeq; // msspsn_idntfccd 직접 전달 시 사용
  final bool isProtecting;

  const MissingDetailPage({
    super.key,
    this.person,
    this.missingSeq,
    this.isProtecting = false,
  }) : assert(person != null || missingSeq != null, 'person 또는 missingSeq 중 하나는 필수');

  @override
  State<MissingDetailPage> createState() => _MissingDetailPageState();
}

class _MissingDetailPageState extends State<MissingDetailPage> {
  Map<String, dynamic>? _detail; // 상세 API 데이터
  bool _isLoading = true;

  // missingSeq 우선, 없으면 person의 ID 사용
  String get _seq => widget.missingSeq ?? widget.person?.msspsnnIdntfccd ?? '';
  int _selectedPhotoIndex = 0; // ✅ 추가
  bool isLoggedIn = false; // 🔥 추가
  bool isAdmin = false;

  @override
  void initState() {
    super.initState();
    _fetchDetail();
    _loadUserInfo(); // 🔥 추가
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString("role");
    debugPrint("🔥 detail에서 읽은 role: $role"); // ✅ 추가
    debugPrint("🔥 detail에서 읽은 isLoggedIn: ${prefs.getBool('isLoggedIn')}"); // ✅ 추가
    setState(() {
      isLoggedIn = prefs.getBool("isLoggedIn") ?? false;
      isAdmin = role == "admin";
    });
  }

  // ✅ 수정
  Future<void> _fetchDetail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access') ?? '';
      final endpoint = widget.isProtecting
          ? "${ApiConfig.baseUrl}/protectedperson/$_seq/detail/"
          : "${ApiConfig.baseUrl}/missingperson/$_seq/detail/";
      final url = Uri.parse(endpoint);
      final response = await http.get(
        url,
        headers: token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {},
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        setState(() {
          _detail = decoded;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint("상세 조회 실패: $e");
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = const Color(0xFFFFF8DE);
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopBar(context),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 20),
                            _buildProfileSection(),
                            const SizedBox(height: 16),
                            _buildBasicInfoRow(),
                            const SizedBox(height: 16),
                            _buildSingleLineBox("실종 발생 일시 : ${_detail?['occurred_display'] ?? '-'}"),
                            const SizedBox(height: 12),
                            _buildSingleLineBox("발생 장소 : ${_detail?['occurred_location'] ?? '-'}"),
                            const SizedBox(height: 20),
                            _buildCategorySection("신체 특징"),
                            _buildCategorySection("성격·행동 특성"),
                            _buildCategorySection("건강·장애 정보"),
                            _buildCategorySection("착의·외형 정보"),
                            _buildCategorySection("기타 참고 사항"),
                            const SizedBox(height: 20),
                            _buildBottomButtons(context),
                            const SizedBox(height: 12),
                            // 문의하기 버튼 임시 숨김
                            // SizedBox(
                            //   width: double.infinity,
                            //   child: ElevatedButton.icon(
                            //     onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InquiryPage())),
                            //     icon: const Icon(Icons.help_outline, size: 18),
                            //     label: const Text("문의하기",
                            //         style: TextStyle(fontWeight: FontWeight.bold)),
                            //     style: ElevatedButton.styleFrom(
                            //       backgroundColor: const Color(0xFFF0F0F0),
                            //       foregroundColor: Colors.black87,
                            //       elevation: 0,
                            //       padding: const EdgeInsets.symmetric(vertical: 14),
                            //       shape: RoundedRectangleBorder(
                            //           borderRadius: BorderRadius.circular(10)),
                            //     ),
                            //   ),
                            // ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySection(String title) {
    final categories = _detail?['categories'] as Map<String, dynamic>?;
    final raw = categories?[title];

    final seen = <String>{};
    final itemList = <String>[];
    if (raw is List) {
      for (final item in raw) {
        final s = item?.toString().trim() ?? '';
        if (s.isNotEmpty && seen.add(s)) itemList.add(s);
      }
    } else if (raw is String && raw.trim().isNotEmpty) {
      itemList.add(raw.trim());
    }

    final text = itemList.isEmpty ? '작성된 정보가 없습니다.' : itemList.join('\n');
    return _buildMultiLineSection(title, text, isPlaceholder: itemList.isEmpty);
  }

  // --- 🎨 하위 위젯 빌더 함수들 ---

 Widget _buildTopBar(BuildContext context) {
    return Container(

      // 2. 상하좌우 약간의 여백을 주어 아이콘이 테두리에 붙지 않게 함
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), 
      
      // 3. 맨 아래쪽(bottom)에만 얇고 연한 회색 선을 긋기
      decoration: BoxDecoration(
        color: Colors.white, // decoration 안에 color를 넣어야 에러가 안 남
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade300, // 연한 회색 선
            width: 1.5, // 선 굵기
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back_ios_new, size: 28),
          ),
          GestureDetector(
            onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
            child: Image.asset("assets/images/dasibom_logo.png", height: 40,
                errorBuilder: (_, __, ___) => const Icon(Icons.favorite_border, color: Colors.pink, size: 30)),
          ),
          const SizedBox(width: 28),
        ],
      ),
    );
  }

  String _photoTypeLabel(String? type) {
    switch (type) {
      case 'face':         return '실종자 정면';
      case 'full_body':   return '실종자 전신';
      case 'parent1_face': return '부모님 사진 1';
      case 'parent2_face': return '부모님 사진 2';
      case 'ai_generated': return 'AI 몽타주';
      default:             return type ?? '사진';
    }
  }

  Widget _buildProfileSection() {
    final seen = <String>{};
    final photos = <dynamic>[];
    for (final key in ['photo_items', 'photos', 'missing_person_photos', 'missing_photos', 'official_photos']) {
      for (final p in (_detail?[key] as List<dynamic>?) ?? []) {
        final url = extractPhotoUrl(p) ?? '';
        if (url.isNotEmpty && seen.add(url)) photos.add(p);
      }
    }
    // parent_photos: {"parent1_face": url, "parent2_face": url} 형태
    final parentMap = _detail?['parent_photos'];
    if (parentMap is Map) {
      parentMap.forEach((k, v) {
        final url = v?.toString() ?? '';
        if (url.isNotEmpty && seen.add(url)) {
          photos.add({'photo_type': k.toString(), 'image': url, 'url': url});
        }
      });
    }

    final hasPhotos = photos.isNotEmpty;
    final safeIndex = _selectedPhotoIndex.clamp(0, hasPhotos ? photos.length - 1 : 0);

    final currentPhoto = hasPhotos ? extractPhotoUrl(photos[safeIndex]) : widget.person?.photo;
    final currentItem  = hasPhotos ? photos[safeIndex] : null;
    final isAI = currentItem is Map && currentItem['is_ai_generated'] == true;
    final selectedLabel = currentItem is Map
        ? _photoTypeLabel(currentItem['photo_type']?.toString())
        : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 메인 이미지 + 뱃지
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 14),
              width: 150,
              decoration: BoxDecoration(
                color: const Color(0xFFD4DAF0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black87, width: 1.5),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: currentPhoto != null && currentPhoto.isNotEmpty
                    ? Image.network(currentPhoto, fit: BoxFit.contain, width: 150)
                    : const SizedBox(
                        width: 150, height: 150,
                        child: Icon(Icons.person, size: 80, color: Colors.white),
                      ),
              ),
            ),
            // 카테고리 뱃지
            Positioned(
              top: 0, left: -5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFFCE4E4),
                  border: Border.all(color: Colors.black87),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.person?.category ?? _detail?['category_display']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ),
            // 사진 타입 레이블 (좌하단)
            if (selectedLabel != null)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Text(
                    isAI ? 'AI 몽타주' : selectedLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            // AI 뱃지 (우상단)
            if (isAI)
              Positioned(
                top: 0, right: -5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFC1D6),
                    border: Border.all(color: Colors.black87),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text("AI",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
          ],
        ),
        const SizedBox(width: 16),

        // 우측 썸네일 Wrap
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 14),
              if (isAI)
                const Text("*해당 이미지는 AI입니다",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (!hasPhotos)
                const Text('첨부된 사진이 없습니다.',
                    style: TextStyle(color: Colors.black45, fontSize: 13))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 10,
                  children: List.generate(photos.length, (i) {
                    final photoUrl = extractPhotoUrl(photos[i]);
                    final isSelected = i == safeIndex;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedPhotoIndex = i),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: Colors.blueAccent, width: 3)
                              : Border.all(color: Colors.grey.shade300),
                        ),
                        child: ClipOval(
                          child: photoUrl != null
                              ? Image.network(photoUrl, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.person, color: Colors.grey))
                              : const Icon(Icons.person, color: Colors.grey),
                        ),
                      ),
                    );
                  }),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBasicInfoRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
            ),
            child: Text("이름 : ${widget.person?.name ?? _detail?['name'] ?? ''}\n성별 : ${widget.person?.gender ?? _detail?['gender_display'] ?? ''}", style: TextStyle(height: 1.6, fontSize: 14)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
            ),
            child: Text("실종 당시 나이 : ${_detail?['age_at_missing'] ?? '-'}\n현재 나이 : ${_detail?['current_age'] ?? widget.person?.age ?? '-'}", style: TextStyle(height: 1.6, fontSize: 14)),
          ),
        ),
      ],
    );
  }

  Widget _buildSingleLineBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
      ),
      child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildMultiLineSection(String title, String text, {bool isPlaceholder = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 100),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2, offset: Offset(0, 1))],
            ),
            child: Text(
              text,
              style: TextStyle(
                color: isPlaceholder ? const Color(0xFFD3D3D3) : Colors.black87,
                fontSize: 13, height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButtons(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text("실종아동찾기센터"),
                      content: const Text("182로 전화하시겠습니까?"),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text("취소"),
                        ),
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final uri = Uri.parse("tel:182");
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri);
                            }
                          },
                          child: const Text("전화하기"),
                        ),
                      ],
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFAEEF0), // 연한 핑크 배경
                  foregroundColor: Colors.black87,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.call, size: 18), // 🔥 추가
                    SizedBox(width: 6),
                    Text(
                      "실종아동찾기센터",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CitizenPage(
                        targetName: widget.person?.name ?? _detail?['name']?.toString() ?? '',
                        targetGender: (widget.person?.gender ?? _detail?['gender_display']?.toString() ?? '') == "남자" ? 0 : 1,

                        targetPhotoUrl:
                            (_detail?['photos'] as List<dynamic>?)?.isNotEmpty == true
                                ? extractPhotoUrl(
                                    (_detail!['photos'] as List<dynamic>)[_selectedPhotoIndex],
                                  )
                                : widget.person?.photo,

                        targetMissingSeq:
                            _detail?['msspsn_idntfccd']?.toString() ?? _seq,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFAEEF0),
                  foregroundColor: Colors.black87,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.campaign, size: 18), // 🔥 추천 아이콘
                    SizedBox(width: 6),
                    Text(
                      "제보하기",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (isLoggedIn && isAdmin) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) {
                      // 실종자 사진 URL 수집 (부모 사진 제외)
                      final seenUrls = <String>{};
                      final photoUrls = <String>[];
                      for (final key in ['photo_items', 'photos', 'missing_person_photos', 'missing_photos', 'official_photos']) {
                        for (final p in (_detail?[key] as List?) ?? []) {
                          final url = extractPhotoUrl(p) ?? '';
                          if (url.isNotEmpty && seenUrls.add(url)) photoUrls.add(url);
                        }
                      }

                      // 부모님 사진 URL 수집 (parent_photos Map)
                      final parentUrls = <String>[];
                      final parentMap = _detail?['parent_photos'];
                      if (parentMap is Map) {
                        for (final k in ['parent1_face', 'parent2_face']) {
                          final url = parentMap[k]?.toString() ?? '';
                          if (url.isNotEmpty) parentUrls.add(url);
                        }
                      }

                      return AIFacePage(
                        missingPersonId: _detail?['id']?.toString(),
                        name: widget.person?.name ?? _detail?['name']?.toString() ?? '',
                        gender: widget.person?.gender ?? _detail?['gender_display']?.toString() ?? '',
                        initialPhotoUrls: photoUrls,
                        initialParentPhotoUrls: parentUrls.isNotEmpty ? parentUrls : null,
                      );
                    },
                  ),
                );
                if (result == true) {
                  _fetchDetail();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE3F2FD),
                foregroundColor: Colors.black87,
              ),
              child: const Text("AI 이미지 생성하기",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Builder(builder: (context) {
          final permissions = Map<String, dynamic>.from(
            _detail?['permissions'] as Map? ?? {},
          );
          final canEdit = permissions['can_edit'] == true;
          if (!canEdit) return const SizedBox.shrink();
          return Column(
            children: [
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditMissingPage(detail: _detail),
                      ),
                    );
                    if (result == true) _fetchDetail();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFF2C2),
                    foregroundColor: Colors.black87,
                  ),
                  child: const Text("수정하기",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}