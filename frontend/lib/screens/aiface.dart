import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class AIFacePage extends StatefulWidget {
  final String? caseId;
  final String? missingPersonId;
  final String? name;
  final String? gender;
  final List<String>? initialPhotoUrls;       // 실종자 사진 URL 목록
  final List<String>? initialParentPhotoUrls; // 부모님 사진 URL 목록 (최대 2장)

  const AIFacePage({
    super.key,
    this.caseId,
    this.missingPersonId,
    this.name,
    this.gender,
    this.initialPhotoUrls,
    this.initialParentPhotoUrls,
  });

  @override
  State<AIFacePage> createState() => _AIFacePageState();
}

class _AIFacePageState extends State<AIFacePage> {

  final List<File> _images = [];        // 실종자 사진 (서버 다운로드 + 직접 추가)
  final List<File?> _parentPhotos = [null, null]; // 부모님 사진 (선택)
  int? _selectedIndex;
  bool _isGenerated = false;
  bool _isLoading = false;
  bool _isLoadingPhotos = false;        // 초기 사진 로딩 중

  String? _resultImgUrl;
  int? _montageId;
  bool _isResultImageLoaded = false;

  double? _identityScore;
  int? _calibratedTarget;
  bool? _ageWarning;

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _ageCtrl = TextEditingController();
  final TextEditingController _targetAgeCtrl = TextEditingController();

  int _selectedGender = 0;

  static const _parentPhotoLabels = ['부모님 사진 1', '부모님 사진 2'];

  @override
  void initState() {
    super.initState();
    if (widget.name != null) _nameCtrl.text = widget.name!;
    if (widget.gender != null) {
      final g = widget.gender!.trim().toLowerCase();
      if (g == '여자' || g == '여성' || g == 'f' || g == 'female') {
        _selectedGender = 1;
      }
    }
    if (widget.initialPhotoUrls != null && widget.initialPhotoUrls!.isNotEmpty) {
      _loadInitialPhotos(widget.initialPhotoUrls!);
    }
    if (widget.initialParentPhotoUrls != null && widget.initialParentPhotoUrls!.isNotEmpty) {
      _loadInitialParentPhotos(widget.initialParentPhotoUrls!);
    }
  }

  // 실종자 사진 URL → _images
  Future<void> _loadInitialPhotos(List<String> urls) async {
    setState(() => _isLoadingPhotos = true);
    for (int i = 0; i < urls.length; i++) {
      try {
        final url = urls[i].startsWith('http')
            ? urls[i]
            : '${ApiConfig.mediaBaseUrl}${urls[i]}';
        final res = await http.get(Uri.parse(url));
        if (res.statusCode == 200) {
          final ext = url.contains('.png') ? 'png' : 'jpg';
          final tmp = File(
            '${Directory.systemTemp.path}/aiface_init_${i}_${DateTime.now().millisecondsSinceEpoch}.$ext',
          );
          await tmp.writeAsBytes(res.bodyBytes);
          if (mounted) {
            setState(() {
              _images.add(tmp);
              _selectedIndex ??= 0;
            });
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _isLoadingPhotos = false);
  }

  // 부모님 사진 URL → _parentPhotos (최대 2장)
  Future<void> _loadInitialParentPhotos(List<String> urls) async {
    for (int i = 0; i < urls.length && i < _parentPhotos.length; i++) {
      try {
        final url = urls[i].startsWith('http')
            ? urls[i]
            : '${ApiConfig.mediaBaseUrl}${urls[i]}';
        final res = await http.get(Uri.parse(url));
        if (res.statusCode == 200) {
          final ext = url.contains('.png') ? 'png' : 'jpg';
          final tmp = File(
            '${Directory.systemTemp.path}/aiface_parent_${i}_${DateTime.now().millisecondsSinceEpoch}.$ext',
          );
          await tmp.writeAsBytes(res.bodyBytes);
          if (mounted) setState(() => _parentPhotos[i] = tmp);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = const Color(0xFFFFFCF5);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _topBar(),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 서버 사진 로딩 중 배너
                    if (_isLoadingPhotos) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF9DE),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          children: [
                            SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54)),
                            SizedBox(width: 10),
                            Text('실종자 사진 불러오는 중...', style: TextStyle(fontSize: 13, color: Colors.black54)),
                          ],
                        ),
                      ),
                    ],

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _uploadArea(),
                        const SizedBox(width: 18),
                        Expanded(child: _imageGrid()),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // 부모님 참고 사진 섹션 (선택)
                    _buildParentPhotoSection(),

                    const SizedBox(height: 18),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _nameField()),
                        const SizedBox(width: 14),
                        Expanded(child: _gender()),
                      ],
                    ),

                    const SizedBox(height: 14),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _ageInput("선택된 사진 당시 나이", _ageCtrl)),
                        const SizedBox(width: 14),
                        Expanded(child: _ageInput("몽타주 생성할 나이", _targetAgeCtrl)),
                      ],
                    ),

                    const SizedBox(height: 32),

                    if (!_isGenerated) _generateBtn(),

                    if (_isGenerated) ...[
                      const SizedBox(height: 28),
                      const Divider(
                        color: Color(0xFF777777),
                        thickness: 0.8,
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        "결과 분석",
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _resultSection(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 🔥 상단 바
  Widget _topBar() {
    return Container(
      height: 66,
      decoration: const BoxDecoration(
        color: Color(0xFFFFFCF5),
        border: Border(
          bottom: BorderSide(
            color: Color(0xFF999999),
            width: 0.8,
          ),
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(
                Icons.arrow_back_ios_new,
                size: 30,
                color: Colors.black,
              ),
            ),
          ),

          GestureDetector(
            onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
            child: Image.asset(
              'assets/images/dasibom_logo.png',
              height: 42,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.favorite_border,
                size: 34,
                color: Color(0xFFE8C96A),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 🔥 업로드 박스
  Widget _uploadArea() {
    final previewImage = _previewImage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "AI 몽타주 생성",
          style: TextStyle(
            fontSize: 14,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 6),

        GestureDetector(
          onTap: _showImagePickerOptions,
          child: Container(
            width: 152,
            height: 208,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(
                color: Colors.black,
                width: 0.8,
              ),
              borderRadius: BorderRadius.circular(7),
            ),
            child: previewImage == null
                ? const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add,
                        size: 42,
                        color: Colors.black,
                      ),
                      SizedBox(height: 26),
                      Text(
                        "사진을 등록해 주세요!",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          previewImage,
                          fit: BoxFit.cover,
                        ),

                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 7),
                            color: Colors.black.withValues(alpha: 0.45),
                            child: const Text(
                              "선택된 사진",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  // ── 부모님 참고 사진 섹션 ──────────────────────────────────────
  Widget _buildParentPhotoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('부모님 참고 사진', style: TextStyle(fontSize: 14, color: Colors.black)),
            const SizedBox(width: 6),
            Text('(선택)', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'AI 몽타주 정확도 향상을 위해 부모님 정면 사진을 등록할 수 있습니다.',
          style: TextStyle(fontSize: 11, color: Colors.black45),
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(2, (i) {
            final photo = _parentPhotos[i];
            return Expanded(
              child: GestureDetector(
                onTap: () => _pickParentPhoto(i),
                child: Container(
                  height: 90,
                  margin: EdgeInsets.only(right: i == 0 ? 8 : 0),
                  decoration: BoxDecoration(
                    color: photo != null ? null : const Color(0xFFFAEEF0),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: photo != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(fit: StackFit.expand, children: [
                            Image.file(photo, fit: BoxFit.cover),
                            Positioned(
                              left: 0, right: 0, bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                color: Colors.black.withValues(alpha: 0.45),
                                child: Text(
                                  _parentPhotoLabels[i],
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 4, right: 4,
                              child: GestureDetector(
                                onTap: () => setState(() => _parentPhotos[i] = null),
                                child: Container(
                                  width: 18, height: 18,
                                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                  child: const Icon(Icons.close, size: 12, color: Colors.white),
                                ),
                              ),
                            ),
                          ]),
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.add, size: 22, color: Colors.black38),
                            const SizedBox(height: 4),
                            Text(_parentPhotoLabels[i],
                                style: const TextStyle(fontSize: 10, color: Colors.black38, fontWeight: FontWeight.bold)),
                          ],
                        ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Future<void> _pickParentPhoto(int index) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.camera_alt), title: const Text('카메라'),
                onTap: () => Navigator.pop(context, ImageSource.camera)),
            ListTile(leading: const Icon(Icons.photo), title: const Text('갤러리'),
                onTap: () => Navigator.pop(context, ImageSource.gallery)),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked != null && mounted) {
      setState(() => _parentPhotos[index] = File(picked.path));
    }
  }

  void _showImagePickerOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text("카메라"),
                onTap: () => _pickImage(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo),
                title: const Text("갤러리"),
                onTap: () => _pickImage(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.folder),
                title: const Text("파일"),
                onTap: () => _pickImage(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
  }
  
  File? get _previewImage {
    if (_images.isEmpty) return null;

    final index = _selectedIndex != null && _selectedIndex! < _images.length
        ? _selectedIndex!
        : 0;

    return _images[index];
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);

    if (picked != null) {
      setState(() {
        _images.add(File(picked.path));

        // 새로 등록한 사진을 바로 대표 사진으로 표시
        _selectedIndex = _images.length - 1;
      });
    }

    if (!mounted) return;

    Navigator.pop(context);
  }

  /// 🔥 이미지 리스트
  Widget _imageGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "실종자 사진 목록",
          style: TextStyle(
            fontSize: 14,
            color: Colors.black,
          ),
        ),

        const SizedBox(height: 10),

        if (_images.isEmpty)
          const SizedBox(
            height: 208,
            child: Center(
              child: Text(
                "사진을 등록하면\n목록에 표시됩니다",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: Color(0xFF9A9A9A),
                ),
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _images.length > 9 ? 9 : _images.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1,
            ),
            itemBuilder: (_, i) {
              final isSelected = _selectedIndex == i;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedIndex = i;
                  });
                },
                child: Center(
                  child: Container(
                    width: 58,
                    height: 58,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF5F7DFF)
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: ClipOval(
                      child: Image.file(
                        _images[i],
                        width: 54,
                        height: 54,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _nameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "이름",
          style: TextStyle(fontSize: 14, color: Colors.black),
        ),
        const SizedBox(height: 7),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: widget.name != null
                ? const Color(0xFFF0F0F0)
                : const Color(0xFFFFF9DE),
            borderRadius: BorderRadius.circular(8),
          ),
          child: widget.name != null
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.name!,
                    style: const TextStyle(fontSize: 14, color: Colors.black54),
                  ),
                )
              : TextField(
                  controller: _nameCtrl,
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.only(bottom: 12),
                  ),
                ),
        ),
      ],
    );
  }

  /// 🔥 성별 선택
  Widget _gender() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "성별",
          style: TextStyle(
            fontSize: 14,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 7),

        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF9DE),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _genderText("남자", 0),
              const SizedBox(width: 10),
              _genderText("여자", 1),
            ],
          ),
        ),
      ],
    );
  }

  Widget _genderText(String text, int val) {
    final selected = _selectedGender == val;

    return GestureDetector(
      onTap: null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFE27A) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFFE0B800) : const Color(0xFFE0E0E0),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? Colors.black : Colors.black54,
          ),
        ),
      ),
    );
  }

  /// 🔥 나이 입력
  Widget _ageInput(String label, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 7),

        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF9DE),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 13),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                "세",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _requestMontageGenerate() async {
    if (widget.caseId == null && widget.missingPersonId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("연결할 신고/제보 또는 실종자 ID가 필요합니다")),
      );
      return;
    }

    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("사진을 먼저 등록해 주세요")),
      );
      return;
    }

    final selectedFile = _selectedIndex != null && _selectedIndex! < _images.length
        ? _images[_selectedIndex!]
        : _images.first;

    final sourceAgeText = _ageCtrl.text.trim();
    final targetAgeText = _targetAgeCtrl.text.trim();

    if (sourceAgeText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("사진 당시 나이를 입력해 주세요")),
      );
      return;
    }

    if (targetAgeText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("몽타주 생성할 나이를 입력해 주세요")),
      );
      return;
    }

    final sourceAge = int.tryParse(sourceAgeText);
    final targetAge = int.tryParse(targetAgeText);

    if (sourceAge == null || targetAge == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("나이는 숫자로 입력해 주세요")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _isGenerated = false;
      _resultImgUrl = null;
      _montageId = null;
      _isResultImageLoaded = false;

      _identityScore = null;
      _calibratedTarget = null;
      _ageWarning = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      if (!mounted) return;

      final accessToken = prefs.getString("access");

      if (accessToken == null || accessToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("관리자 로그인이 필요합니다")),
        );

        setState(() {
          _isLoading = false;
        });
        return;
      }

      final uri = Uri.parse("${ApiConfig.baseUrl}/montage/generate/");
      final request = http.MultipartRequest("POST", uri);

      request.headers["Authorization"] = "Bearer $accessToken";

      if (widget.caseId != null && widget.caseId!.isNotEmpty) {
        request.fields["case_id"] = widget.caseId!;
      }

      if (widget.missingPersonId != null && widget.missingPersonId!.isNotEmpty) {
        request.fields["missing_person_id"] = widget.missingPersonId!;
      }

      request.fields["source_age"] = sourceAge.toString();
      request.fields["target_age"] = targetAge.toString();
      request.fields["gender"] = _selectedGender == 0 ? "M" : "F";
      request.fields["ethnicity"] = "korean";

      request.files.add(
        await http.MultipartFile.fromPath("image", selectedFile.path),
      );

      // 부모님 참고 사진 (선택)
      for (int i = 0; i < _parentPhotos.length; i++) {
        final pf = _parentPhotos[i];
        if (pf == null) continue;
        request.files.add(
          await http.MultipartFile.fromPath(
            'parent_photos',
            pf.path,
            filename: 'parent_photo_$i.jpg',
          ),
        );
      }

      if (!mounted) return;

      final streamedResponse = await request.send();

      if (!mounted) return;

      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      final decodedText = utf8.decode(response.bodyBytes);

      if (response.statusCode == 201) {
        final Map<String, dynamic> data = jsonDecode(decodedText);

        setState(() {
          _montageId = data["montage_id"];
          _resultImgUrl = data["result_img_url"];

          _identityScore =
              double.tryParse(data["identity_score"]?.toString() ?? '');

          _calibratedTarget =
              int.tryParse(data["calibrated_target"]?.toString() ?? '');

          _ageWarning =
              data["age_warning"]?.toString().toLowerCase() == 'true';

          _isGenerated = true;
          _isResultImageLoaded = false;
        });

        debugPrint('AI 몽타주 응답: $data');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("몽타주 생성 실패: $decodedText")),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("AI 몽타주 요청 중 오류 발생: $e")),
      );
    }

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _applyMontage() async {
    if (_montageId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("등록할 몽타주가 없습니다")),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString("access");

      if (accessToken == null || accessToken.isEmpty) {
        if (!mounted) return;
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("관리자 로그인이 필요합니다")),
        );
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final uri = Uri.parse(
        "${ApiConfig.baseUrl}/montage/$_montageId/apply/",
      );

      final response = await http.patch(
        uri,
        headers: {
          "Authorization": "Bearer $accessToken",
          "Content-Type": "application/json",
        },
        body: jsonEncode({}),
      );

      final decodedText = utf8.decode(response.bodyBytes);

      debugPrint("🔥 montage apply status: ${response.statusCode}");
      debugPrint("🔥 montage apply body: $decodedText");

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 204) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("AI 몽타주가 상세 프로필에 등록되었습니다")),
        );

        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("AI 몽타주 등록 실패: $decodedText")),
        );
      }
    } catch (e) {
      debugPrint("❌ AI 몽타주 등록 오류: $e");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("AI 몽타주 등록 중 오류 발생: $e")),
      );
    }

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });
  }

  /// 🔥 생성 버튼
  Widget _generateBtn() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        width: double.infinity,
        height: 38,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            elevation: 0,
            backgroundColor: const Color(0xFFFFF1B8),
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: _isLoading ? null : _requestMontageGenerate,
          child: Text(
            _isLoading ? "생성 중..." : "AI 몽타주 생성하기",
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  /// 🔥 결과 영역
  Widget _resultSection() {
    return Center(
      child: Column(
        children: [
          Container(
            width: 140,
            height: 140,
            color: const Color(0xFFDCE4FF),
            child: _resultImgUrl != null
                ? Image.network(
                    _resultImgUrl!,
                    fit: BoxFit.cover,

                    // 이미지가 실제로 다 로딩되기 전까지 로딩 표시
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) {
                        if (!_isResultImageLoaded) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() {
                                _isResultImageLoaded = true;
                              });
                            }
                          });
                        }

                        return child;
                      }

                      return const Center(
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                          ),
                        ),
                      );
                    },

                    errorBuilder: (_, __, ___) {
                      return const Icon(
                        Icons.broken_image_outlined,
                        size: 70,
                        color: Colors.black,
                      );
                    },
                  )
                : const Icon(
                    Icons.person,
                    size: 70,
                    color: Colors.black,
                  ),
          ),

          // 이미지 로딩 완료 전에는 이름/나이/버튼 전부 숨김
          if (_isResultImageLoaded) ...[
            const SizedBox(height: 22),

            Text(
              "${_nameCtrl.text.trim().isEmpty ? '대상자' : _nameCtrl.text.trim()} / ${_targetAgeCtrl.text.trim()}세",
              style: const TextStyle(
                fontSize: 22,
                color: Colors.black,
              ),
            ),

            if (_calibratedTarget != null) ...[
              const SizedBox(height: 10),
              Text(
                'AI 실제 적용 나이: $_calibratedTarget세',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                ),
              ),
            ],

            if (_ageWarning == true) ...[
              const SizedBox(height: 12),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '요청 나이 구간에서는 생성 정확도가 다소 낮아질 수 있습니다.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],

            if (_identityScore != null) ...[
              const SizedBox(height: 18),

              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '정체성 유사도 ${(_identityScore! * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              LinearProgressIndicator(
                value: _identityScore!.clamp(0.0, 1.0),
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
            ],

            if (_montageId != null) ...[
              const SizedBox(height: 8),
              Text(
                "Montage ID: $_montageId",
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF777777),
                ),
              ),
            ],

            const SizedBox(height: 34),

            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: const Color(0xFFFFF4F4),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _isLoading ? null : _requestMontageGenerate,
                      child: const Text(
                        "이미지 재생성",
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 18),

                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: const Color(0xFFFFF1B8),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: _montageId == null || _isLoading
                          ? null
                          : _applyMontage,
                      child: const Text(
                        "등록하기",
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}