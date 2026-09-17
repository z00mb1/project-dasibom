import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';

import '../screens/aiface.dart';

class EditMissingPage extends StatefulWidget {
  final Map<String, dynamic>? detail;
  const EditMissingPage({super.key, required this.detail});

  @override
  State<EditMissingPage> createState() => _EditMissingPageState();
}

class _EditMissingPageState extends State<EditMissingPage> {
  List<Map<String, dynamic>> _images = [];
  final List<File> _newImages = [];
  final List<String> _deletedPhotoPaths = [];
  int _selectedPhotoIndex = 0;

  final Color _bgYellow = const Color(0xFFFDF9EB);
  final Color _bgPink = const Color(0xFFFAEEF0);

  late TextEditingController nameCtrl, ageCtrl, locationCtrl;
  Map<String, TextEditingController> categoryCtrls = {};

  String _selectedGender = '';
  DateTime? _selectedDateTime;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final d = widget.detail ?? {};

    // 모든 사진 필드 합산 (URL 기준 중복 제거)
    String photoUrl(dynamic p) {
      if (p is Map) {
        return (p['url'] ?? p['image_url'] ?? p['image'] ?? p['photo'] ?? p['file'])?.toString() ?? '';
      }
      return p?.toString() ?? '';
    }

    final seen = <String>{};
    final allPhotos = <Map<String, dynamic>>[];
    for (final key in ['photo_items', 'photos', 'missing_person_photos', 'missing_photos', 'official_photos']) {
      for (final p in (d[key] as List?) ?? []) {
        final url = photoUrl(p);
        if (url.isNotEmpty && seen.add(url)) {
          final m = p is Map ? Map<String, dynamic>.from(p) : <String, dynamic>{};
          m['image'] = url;
          allPhotos.add(m);
        }
      }
    }
    // parent_photos: {"parent1_face": url, "parent2_face": url}
    final parentMap = d['parent_photos'];
    if (parentMap is Map) {
      parentMap.forEach((k, v) {
        final url = v?.toString() ?? '';
        if (url.isNotEmpty && seen.add(url)) {
          allPhotos.add({'photo_type': k.toString(), 'image': url, 'url': url});
        }
      });
    }
    _images = allPhotos;

    nameCtrl = TextEditingController(text: d["name"] ?? "");
    ageCtrl = TextEditingController(
        text: d["age_at_missing"]?.toString() ?? d["current_age"]?.toString() ?? "");
    locationCtrl = TextEditingController(text: d["occurred_location"] ?? "");

    _selectedGender = d["gender"]?.toString() ?? '';

    final occurredAt = d["occurred_at"]?.toString();
    if (occurredAt != null && occurredAt.isNotEmpty) {
      try {
        _selectedDateTime = DateTime.parse(occurredAt).toLocal();
      } catch (_) {}
    }

    final cats = d["categories"] as Map<String, dynamic>?;
    for (var key in [
      "신체 특징",
      "성격·행동 특성",
      "건강·장애 정보",
      "착의·외형 정보",
      "기타 참고 사항",
    ]) {
      final raw = cats?[key];
      String initialText = '';
      if (raw is List) {
        final seen = <String>{};
        final deduped = <String>[];
        for (final item in raw) {
          final s = item?.toString().trim() ?? '';
          if (s.isNotEmpty && seen.add(s)) deduped.add(s);
        }
        initialText = deduped.join('\n');
      } else if (raw is String && raw.trim().isNotEmpty) {
        initialText = raw.trim();
      }
      categoryCtrls[key] = TextEditingController(text: initialText);
    }
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    ageCtrl.dispose();
    locationCtrl.dispose();
    for (final ctrl in categoryCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _selectDateAndTime() async {
    final initial = _selectedDateTime ?? DateTime.now();
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      locale: const Locale('ko', 'KR'),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFFFDE14C),
            onPrimary: Colors.black,
            onSurface: Colors.black,
          ),
        ),
        child: child!,
      ),
    );

    if (pickedDate == null || !mounted) return;

    setState(() {
      _selectedDateTime = DateTime(
        pickedDate.year, pickedDate.month, pickedDate.day,
        initial.hour, initial.minute,
      );
    });

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        height: 300,
        color: Colors.white,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              color: Colors.grey.shade100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("실종 발생 시간",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("완료"),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                initialDateTime: _selectedDateTime ?? initial,
                use24hFormat: false,
                onDateTimeChanged: (DateTime t) {
                  setState(() {
                    _selectedDateTime = DateTime(
                      pickedDate.year, pickedDate.month, pickedDate.day,
                      t.hour, t.minute,
                    );
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final ampm = dt.hour < 12 ? "오전" : "오후";
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    return "${dt.year}년 ${dt.month.toString().padLeft(2, '0')}월 "
        "${dt.day.toString().padLeft(2, '0')}일 $ampm $h시 "
        "${dt.minute.toString().padLeft(2, '0')}분";
  }

  Future<void> _updateData() async {
    setState(() => _isLoading = true);

    try {
      final rawId  = widget.detail?["id"]?.toString().trim() ?? '';
      final rawSeq = widget.detail?["msspsn_idntfccd"]?.toString().trim() ?? '';
      final id = rawId.isNotEmpty ? rawId : rawSeq;
      if (id.isEmpty) {
        _showMessage("수정할 실종자 ID가 없습니다.");
        return;
      }

      debugPrint('✏️ [edit] id=$id url=${ApiConfig.baseUrl}/missingperson/$id/edit/');

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("access");

      final request = http.MultipartRequest(
        "PATCH",
        Uri.parse("${ApiConfig.baseUrl}/missingperson/$id/edit/"),
      );
      request.headers["Authorization"] = "Bearer $token";

      request.fields["name"] = nameCtrl.text.trim();
      final age = ageCtrl.text.trim();
      if (age.isNotEmpty) {
        request.fields["age_at_missing"] = int.tryParse(age)?.toString() ?? age;
      }
      request.fields["occurred_location"] = locationCtrl.text.trim();

      if (_selectedGender.isNotEmpty) {
        request.fields["gender"] = _selectedGender;
      }
      if (_selectedDateTime != null) {
        request.fields["occurred_at"] = _selectedDateTime!.toIso8601String();
      }

      const categoryFieldMap = {
        "신체 특징":     "physical",
        "성격·행동 특성": "behavior",
        "건강·장애 정보": "health",
        "착의·외형 정보": "clothing",
        "기타 참고 사항": "description",
      };
      categoryCtrls.forEach((key, ctrl) {
        final fieldName = categoryFieldMap[key] ?? key;
        request.fields[fieldName] = ctrl.text.trim();
      });

      if (_deletedPhotoPaths.isNotEmpty) {
        request.fields["delete_photos"] = jsonEncode(_deletedPhotoPaths);
      }

      for (final image in _newImages) {
        request.files.add(
          await http.MultipartFile.fromPath('new_photos', image.path),
        );
      }

      final res = await request.send()
          .timeout(const Duration(seconds: 30));

      final body = await res.stream.bytesToString()
          .timeout(const Duration(seconds: 30));
      debugPrint('✏️ [edit] ${res.statusCode} $body');

      if (!mounted) return;

      if (res.statusCode == 200 || res.statusCode == 204) {
        _showMessage("수정이 완료되었습니다.");
        Navigator.pop(context, true);
      } else {
        _showMessage("수정 실패 (${res.statusCode}): $body");
      }
    } catch (e) {
      debugPrint('✏️ [edit] 에러: $e');
      if (mounted) _showMessage("에러 발생: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _newImages.add(File(picked.path));
        _images.add({"image": picked.path});
      });
    }
  }

  void _deletePhoto(int index) {
    setState(() {
      final img = _images[index];
      final photoPath = img["path"]?.toString() ?? '';
      if (photoPath.isNotEmpty) {
        _deletedPhotoPaths.add(photoPath);
      } else {
        final imgUrl = img["image"]?.toString() ?? img["url"]?.toString() ?? '';
        _newImages.removeWhere((f) => f.path == imgUrl);
      }
      _images.removeAt(index);
      if (_selectedPhotoIndex >= _images.length && _selectedPhotoIndex > 0) {
        _selectedPhotoIndex--;
      }
    });
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── 사진 섹션 ─────────────────────────────────────────────────────────────
  Widget _buildPhotoSection() {
    String? selectedUrl;
    if (_images.isNotEmpty && _selectedPhotoIndex < _images.length) {
      selectedUrl = _images[_selectedPhotoIndex]["image"]?.toString();
    }

    Widget previewChild;
    if (selectedUrl != null && selectedUrl.isNotEmpty) {
      previewChild = selectedUrl.startsWith('http')
          ? Image.network(selectedUrl, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, size: 40, color: Colors.black26))
          : Image.file(File(selectedUrl), fit: BoxFit.cover);
    } else {
      previewChild = const Icon(Icons.person, size: 50, color: Colors.white);
    }

    return _buildCard("사진", [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 왼쪽 큰 프리뷰
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 120,
              height: 150,
              color: const Color(0xFFD4DAF0),
              child: previewChild,
            ),
          ),
          const SizedBox(width: 12),
          // 오른쪽 썸네일
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._images.asMap().entries.map((entry) {
                  final i = entry.key;
                  final imgUrl = entry.value["image"]?.toString() ?? '';
                  final isSelected = i == _selectedPhotoIndex;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedPhotoIndex = i),
                    child: Stack(
                      children: [
                        Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected
                                ? Border.all(
                                    color: const Color(0xFFFDE14C), width: 2.5)
                                : Border.all(color: Colors.black12),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: imgUrl.startsWith('http')
                                ? Image.network(imgUrl, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.broken_image,
                                        size: 20))
                                : Image.file(File(imgUrl), fit: BoxFit.cover),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => _deletePhoto(i),
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close,
                                  size: 11, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                // 추가 버튼
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    width: 62,
                    height: 62,
                    decoration: BoxDecoration(
                      color: _bgYellow,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: const Icon(Icons.add, color: Colors.black45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ]);
  }

  // ── build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8DE),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text("정보 수정",
            style:
                TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildPhotoSection(),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              height: 45,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AIFacePage(
                        missingPersonId: widget.detail?['id']?.toString(),
                        name: widget.detail?['name'] as String?,
                        gender: widget.detail?['gender_display'] as String? ??
                            widget.detail?['gender'] as String?,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEDE7F6), elevation: 0),
                child: const Text("AI 이미지 생성하기",
                    style: TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),

            const SizedBox(height: 16),

            _buildCard("인적 정보", [
              _buildField("이름", nameCtrl),
              _buildField("실종 당시 나이", ageCtrl,
                  keyboardType: TextInputType.number),
              const Text("성별",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              _buildGenderSelection(),
              const SizedBox(height: 10),
            ]),

            const SizedBox(height: 16),

            _buildCard("실종 정보", [
              const Text("실종 발생 일시",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: _selectDateAndTime,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: _bgYellow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedDateTime != null
                              ? _formatDateTime(_selectedDateTime!)
                              : widget.detail?["occurred_display"] ??
                                  "날짜를 선택하세요",
                          style: const TextStyle(color: Colors.black87),
                        ),
                      ),
                      const Icon(Icons.edit_calendar_outlined,
                          size: 18, color: Colors.black45),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _buildField("발생 장소", locationCtrl),
            ]),

            const SizedBox(height: 16),

            _buildCard("신체 특징", [
              _buildFieldMulti(categoryCtrls["신체 특징"]!),
            ]),

            const SizedBox(height: 16),

            _buildCard("건강·장애 정보", [
              _buildFieldMulti(categoryCtrls["건강·장애 정보"]!),
            ]),

            const SizedBox(height: 16),

            _buildCard("착의 사항", [
              _buildFieldMulti(categoryCtrls["착의·외형 정보"]!),
            ]),

            const SizedBox(height: 16),

            _buildCard("기타 참고 사항", [
              _buildFieldMulti(categoryCtrls["기타 참고 사항"]!),
            ]),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _updateData,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFF2C2), elevation: 0),
                child: _isLoading
                    ? const CircularProgressIndicator()
                    : const Text("수정 완료",
                        style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // ── 헬퍼 위젯 ─────────────────────────────────────────────────────────────
  Widget _buildGenderSelection() {
    return Row(
      children: [
        _buildGenderOption("남성", "male"),
        const SizedBox(width: 12),
        _buildGenderOption("여성", "female"),
      ],
    );
  }

  Widget _buildGenderOption(String label, String value) {
    final isSelected = _selectedGender == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedGender = value),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFDE14C) : _bgYellow,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: const Color(0xFFF0C800), width: 1.5)
              : Border.all(color: Colors.black12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight:
                isSelected ? FontWeight.bold : FontWeight.normal,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 2)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl,
      {TextInputType? keyboardType}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _bgYellow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: ctrl,
            keyboardType: keyboardType,
            decoration: const InputDecoration(border: InputBorder.none),
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildFieldMulti(TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _bgPink,
          borderRadius: BorderRadius.circular(8),
        ),
        child: TextField(
          controller: ctrl,
          maxLines: 4,
          decoration: const InputDecoration(border: InputBorder.none),
        ),
      ),
    );
  }
}
