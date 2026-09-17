import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config/api_config.dart';

enum PhotoRequirement {
  fullBody,
  frontFace,
  leftSideFace,
  rightSideFace,
  parentFrontFace,
}

class RegisterFormTab extends StatefulWidget {
  final VoidCallback? onSuccess;

  const RegisterFormTab({super.key, this.onSuccess});

  @override
  State<RegisterFormTab> createState() => _RegisterFormTabState();
}

class _RegisterFormTabState extends State<RegisterFormTab> {
  static const Color _bgColor   = Color(0xFFFFFCF5);
  static const Color _yellow    = Color(0xFFFDF9EB);
  static const Color _pink      = Color(0xFFFAEEF0);
  static const Color _accentRed = Color(0xFFFF8A8A);

  // 등록 대상자
  final _nameCtrl        = TextEditingController();
  final _rrnFrontCtrl    = TextEditingController();
  final _rrnBackCtrl     = TextEditingController();
  final _phoneCtrl       = TextEditingController();
  final _addressCtrl     = TextEditingController();
  final _placeCtrl       = TextEditingController();
  final _noteCtrl        = TextEditingController();
  final _bodyFeatureCtrl = TextEditingController();
  final _healthInfoCtrl  = TextEditingController();
  final TextEditingController _detailAddressCtrl = TextEditingController();

  // 보호자
  final _guardianNameCtrl     = TextEditingController();
  final _guardianRrnFrontCtrl = TextEditingController();
  final _guardianRrnBackCtrl  = TextEditingController();
  final _guardianPhoneCtrl    = TextEditingController();
  final _authCodeCtrl         = TextEditingController();

  // 로그인 상태
  bool   isLoggedIn     = false;
  String _loggedInName  = '';
  String _loggedInPhone = '';

  // 약관
  bool _isAgreed      = false;
  bool _serviceAgree  = false;
  bool _locationAgree = false;
  bool _privacyAgree  = false;

  // 인증
  bool    _isVerified   = false;
  bool    _isUnknownRRN = false;
  String? _verificationId;
  int     _timerSeconds = 0;
  Timer?  _timer;

  bool _isSubmitting = false;

  // 등록 대상 분류
  String _category = '정상아동(18세 미만)';
  static const _categoryOpts = [
    '정상아동(18세 미만)', '지적장애인',
    '시설보호무연고자', '치매질환자',
    '지적 장애인(18세 미만)', '가출인',
    '지적장애인(18세 이상)', '불상(기타)',
  ];

  // 신체 외형
  String _gender        = '남자';
  String _height        = '알 수 없음';
  String _weight        = '알 수 없음';
  String _bodyType      = '알 수 없음';
  String _faceShape     = '알 수 없음';
  String _hairColor     = '알 수 없음';
  String _hairStyle     = '알 수 없음';
  String _bloodType = '알 수 없음';
  String _eyeColor = '알 수 없음';

  // 사진
  final List<File?> _photos       = [null, null, null, null];
  final List<File?> _parentPhotos = [null, null];

  // 프론트 ML Kit 검증 결과 ('valid' / 'warning')
  final List<String?> _photoValidStatus  = [null, null, null, null];
  final List<String?> _parentValidStatus = [null, null];

  static const _photoLabels = ['전신 사진', '정면 얼굴 사진', '왼쪽 측면 사진', '오른쪽 측면 사진'];
  static const _photoGuideTexts = [
    '머리부터 발끝까지 전신이 보이는 사진을 올려 주세요.',
    '얼굴이 정면을 향하고 눈·코·입이 잘 보이는 사진을 올려 주세요.',
    '얼굴의 왼쪽 측면이 보이는 사진을 올려 주세요.',
    '얼굴의 오른쪽 측면이 보이는 사진을 올려 주세요.',
  ];
  static const _photoExampleAssets = [
    'assets/images/example_face/example_full_body.png',
    'assets/images/example_face/example_front_face.png',
    'assets/images/example_face/example_left_side_face.png',
    'assets/images/example_face/example_right_side_face.png',
  ];
  static const _parentPhotoLabels = ['부모님 정면 사진 1', '부모님 정면 사진 2'];

  // 드롭다운 옵션
  static const _heightOpts        = ['알 수 없음', '140cm 미만', '140~150cm', '150~160cm', '160~170cm', '170~180cm', '180cm 이상'];
  static const _weightOpts        = ['알 수 없음', '40kg대', '50kg대', '60kg대'];
  static const _bodyTypeOpts      = ['알 수 없음', '보통', '왜소', '비만', '건장', '특이체형', '기타'];
  static const _faceShapeOpts     = ['알 수 없음', '삼각형', '역삼각형', '계란형', '사각형', '둥근형', '갸름한형', '기타'];
  static const _hairColorOpts     = ['알 수 없음', '흑색', '백색', '반백', '갈색', '염색', '기타'];
  static const _hairStyleOpts     = ['알 수 없음', '삭발', '대머리', '긴머리', '곱슬긴머리', '단발머리', '커트머리', '스포츠형', '짧은머리(생머리)', '긴머리(생머리)', '짧은머리(퍼머)', '긴머리(퍼머)', '묶음머리', '기타'];
  static const _bloodTypeOpts = ['알 수 없음', 'A형', 'B형', 'O형', 'AB형'];
  static const _eyeColorOpts = ['알 수 없음', '검정', '갈색', '기타'];

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [
      _nameCtrl, _rrnFrontCtrl, _rrnBackCtrl, _phoneCtrl,
      _addressCtrl, _placeCtrl, _noteCtrl, _bodyFeatureCtrl, _healthInfoCtrl,
      _guardianNameCtrl, _guardianRrnFrontCtrl, _guardianRrnBackCtrl,
      _guardianPhoneCtrl, _authCodeCtrl, _detailAddressCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── 로그인 정보 ──────────────────────────────────────────────────────────
  Future<void> _loadUserInfo() async {
    final prefs   = await SharedPreferences.getInstance();
    final token   = prefs.getString('access');

    // 토큰이 없으면 비로그인
    if (token == null || token.isEmpty) {
      setState(() => isLoggedIn = false);
      return;
    }

    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/userauth/me/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        // person 키 → guardian 키 → 루트 순으로 시도
        final person = (body['person'] as Map?) ??
            (body['guardian'] as Map?) ??
            (body['user'] as Map?) ??
            body;
        setState(() {
          isLoggedIn     = true;
          _loggedInName  = person['name']?.toString()  ?? '';
          _loggedInPhone = person['phone']?.toString() ?? '';
          _isVerified    = true;
        });
      } else {
        debugPrint('userauth/me 실패: ${res.statusCode} ${utf8.decode(res.bodyBytes)}');
        setState(() => isLoggedIn = false);
      }
    } catch (e) {
      debugPrint('userauth/me 에러: $e');
      if (mounted) setState(() => isLoggedIn = false);
    }
  }

  // ── 약관 모달 ────────────────────────────────────────────────────────────
  void _openAgreementSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          final allChecked = _serviceAgree && _locationAgree && _privacyAgree;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('이용약관 동의',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                ListTile(
                  leading: Icon(allChecked ? Icons.check_circle : Icons.circle_outlined, color: _accentRed),
                  title: const Text('약관 전체 동의'),
                  onTap: () => setModal(() {
                    _serviceAgree  = !allChecked;
                    _locationAgree = !allChecked;
                    _privacyAgree  = !allChecked;
                  }),
                ),
                const Divider(),
                _agreementItem('서비스 이용약관 (필수)',         _serviceAgree,  () => setModal(() => _serviceAgree  = !_serviceAgree)),
                _agreementItem('위치기반 서비스 이용약관 (필수)', _locationAgree, () => setModal(() => _locationAgree = !_locationAgree)),
                _agreementItem('개인정보 처리방침 (필수)',         _privacyAgree,  () => setModal(() => _privacyAgree  = !_privacyAgree)),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: allChecked
                        ? () { setState(() => _isAgreed = true); Navigator.pop(ctx); }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentRed,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('확인', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _agreementItem(String title, bool value, VoidCallback onTap) {
    return ListTile(
      leading: Icon(value ? Icons.check_circle : Icons.circle_outlined, color: _accentRed),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  // ── SMS 인증 ─────────────────────────────────────────────────────────────
  void _startTimer() {
    _timer?.cancel();
    setState(() => _timerSeconds = 180);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_timerSeconds == 0) { t.cancel(); return; }
      if (!mounted) return;
      setState(() => _timerSeconds--);
    });
  }

  Future<void> _sendSMS() async {
    String phone = _guardianPhoneCtrl.text.trim();
    if (phone.isEmpty) { _toast('전화번호를 입력해 주세요.'); return; }
    if (phone.startsWith('0')) phone = '+82${phone.substring(1)}';
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phone,
        verificationCompleted: (c) async => FirebaseAuth.instance.signInWithCredential(c),
        verificationFailed: (e) { if (mounted) _toast('인증 실패: ${e.message}'); },
        codeSent: (id, _) {
          if (mounted) {
            setState(() => _verificationId = id);
            _toast('인증번호가 발송되었습니다.');
          }
        },
        codeAutoRetrievalTimeout: (id) => _verificationId = id,
      );
    } catch (_) {
      if (mounted) _toast('인증번호 발송 중 오류가 발생했습니다.');
    }
  }

  Future<void> _verifyCode() async {
    if (_verificationId == null) { _toast('먼저 인증번호를 전송해 주세요.'); return; }
    if (_authCodeCtrl.text.trim().isEmpty) { _toast('인증번호를 입력해 주세요.'); return; }
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _authCodeCtrl.text.trim(),
      );
      await FirebaseAuth.instance.signInWithCredential(cred);
      if (!mounted) return;
      setState(() => _isVerified = true);
      _toast('인증이 완료되었습니다.');
    } catch (_) {
      if (mounted) _toast('인증번호가 올바르지 않습니다.');
    }
  }

  // ── 사진 선택 + ML Kit 검증 ──────────────────────────────────────────────
  PhotoRequirement _requirementFor(int index) {
    switch (index) {
      case 0: return PhotoRequirement.fullBody;
      case 1: return PhotoRequirement.frontFace;
      case 2: return PhotoRequirement.leftSideFace;
      case 3: return PhotoRequirement.rightSideFace;
      default: return PhotoRequirement.frontFace;
    }
  }

  Future<ImageSource?> _pickSource() => showModalBottomSheet<ImageSource>(
    context: context,
    builder: (_) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(leading: const Icon(Icons.camera_alt), title: const Text('카메라'), onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo),      title: const Text('갤러리'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ],
      ),
    ),
  );

  Future<bool> _validateFaceAngle(File file, PhotoRequirement req) async {
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true,
      ),
    );
    final faces = await detector.processImage(InputImage.fromFile(file));
    await detector.close();

    if (faces.isEmpty) { _toast('얼굴을 찾을 수 없습니다. 얼굴이 잘 보이는 사진을 선택해 주세요.'); return false; }
    if (faces.length > 1) { return false; }

    final y = faces.first.headEulerAngleY ?? 0;
    switch (req) {
      case PhotoRequirement.frontFace:
      case PhotoRequirement.parentFrontFace:
        if (y.abs() <= 15) return true;
        _toast('정면 얼굴 사진을 올려 주세요.');
        return false;
      case PhotoRequirement.leftSideFace:
        if (y <= -25) return true;
        _toast('왼쪽 측면 얼굴 사진을 올려 주세요.');
        return false;
      case PhotoRequirement.rightSideFace:
        if (y >= 25) return true;
        _toast('오른쪽 측면 얼굴 사진을 올려 주세요.');
        return false;
      case PhotoRequirement.fullBody:
        return true;
    }
  }

  Future<bool> _confirmUseAnyway(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('사진 확인 필요', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        content: Text(message, style: const TextStyle(fontSize: 13, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('다시 선택')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accentRed, foregroundColor: Colors.white, elevation: 0),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('그래도 사용'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _openPhotoGuideAndPick(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${_photoLabels[index]} 등록 기준',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _exampleImageBox(
                assetPath: _photoExampleAssets[index],
                fallbackIcon: index == 0 ? Icons.accessibility_new : Icons.face_retouching_natural,
              ),
              const SizedBox(height: 14),
              Text(_photoGuideTexts[index],
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.black87)),
              const SizedBox(height: 12),
              _guideCheck('흐릿하지 않고 밝은 사진을 선택해 주세요.'),
              _guideCheck('얼굴 또는 신체가 가려지지 않은 사진을 선택해 주세요.'),
              if (index == 0) _guideCheck('머리부터 발끝까지 전신이 보이는 사진이어야 합니다.'),
              if (index == 1) _guideCheck('얼굴이 정면을 향한 사진이어야 합니다.'),
              if (index == 2) _guideCheck('왼쪽 측면 얼굴이 잘 보이는 사진이어야 합니다.'),
              if (index == 3) _guideCheck('오른쪽 측면 얼굴이 잘 보이는 사진이어야 합니다.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _accentRed, foregroundColor: Colors.white, elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('확인 후 선택'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final source = await _pickSource();
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    final file = File(picked.path);
    final req  = _requirementFor(index);
    String validStatus = 'valid';
    if (req != PhotoRequirement.fullBody) {
      final valid = await _validateFaceAngle(file, req);
      if (!valid) {
        final useAnyway = await _confirmUseAnyway('사진 기준과 다를 수 있습니다.\n그래도 이 사진을 사용하시겠습니까?');
        if (!useAnyway) return;
        validStatus = 'warning';
      }
    }
    setState(() {
      _photos[index] = file;
      _photoValidStatus[index] = validStatus;
    });
  }

  Future<void> _openParentPhotoGuideAndPick(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('부모님 정면 사진 등록 기준',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _exampleImageBox(assetPath: 'assets/images/example_face/example_parent_front_face.png', fallbackIcon: Icons.family_restroom),
              const SizedBox(height: 14),
              const Text(
                'AI 몽타주 참고용으로 부모님 얼굴이 정면으로 보이는 사진을 올려 주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.4, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              _guideCheck('정면을 바라보는 얼굴 사진이어야 합니다.'),
              _guideCheck('얼굴이 흐릿하지 않아야 합니다.'),
              _guideCheck('마스크, 모자, 선글라스 등 가림이 적어야 합니다.'),
              _guideCheck('한 사람의 얼굴이 중심에 있는 사진을 권장합니다.'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accentRed, foregroundColor: Colors.white, elevation: 0),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('확인 후 선택'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final source = await _pickSource();
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    final file  = File(picked.path);
    final valid = await _validateFaceAngle(file, PhotoRequirement.parentFrontFace);
    final parentStatus = valid ? 'valid' : 'warning';
    if (!valid) {
      final useAnyway = await _confirmUseAnyway('부모님 정면 사진으로 보기 어려울 수 있습니다.\n그래도 이 사진을 사용하시겠습니까?');
      if (!useAnyway) return;
    }
    setState(() {
      _parentPhotos[index] = file;
      _parentValidStatus[index] = parentStatus;
    });
  }

  // ── 제출 ─────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!isLoggedIn) {
      _toast('실종예방등록은 로그인 후 이용할 수 있습니다.');
      return;
    }

    if (!_isAgreed) {
      _toast('이용약관에 동의해주세요.');
      return;
    }

    if (_nameCtrl.text.trim().isEmpty) {
      _toast('등록 대상자 이름을 입력해주세요.');
      return;
    }

    // 백엔드에서 face_photo 정면 얼굴 검증을 하므로, 프론트에서도 최소 선택 여부는 확인
    if (_photos[1] == null) {
      _toast('정면 얼굴 사진을 등록해 주세요.');
      return;
    }

    if (_addressCtrl.text.trim().isEmpty) {
      _toast('거주지 주소를 주소 검색으로 선택해주세요.');
      return;
    }

    if (_detailAddressCtrl.text.trim().isEmpty) {
      _toast('상세 주소를 입력해주세요.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access');

    if (accessToken == null || accessToken.isEmpty) {
      _toast('로그인이 만료되었습니다. 다시 로그인해 주세요.');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/prevention-registrations/');

      final request = http.MultipartRequest('POST', uri);

      request.headers['Authorization'] = 'Bearer $accessToken';

      // 1) 등록 대상자 기본 인적사항
      request.fields['category'] = _category;
      request.fields['name'] = _nameCtrl.text.trim();
      request.fields['gender'] = _gender;
      request.fields['rrn_front'] = _rrnFrontCtrl.text.trim();
      request.fields['rrn_back'] = _rrnBackCtrl.text.trim();
      request.fields['phone'] = _phoneCtrl.text.trim();
      request.fields['address'] =
          '${_addressCtrl.text.trim()} ${_detailAddressCtrl.text.trim()}'.trim();
      request.fields['frequent_place'] = _placeCtrl.text.trim();
      request.fields['note'] = _noteCtrl.text.trim();

      // 2) 신체 정보
      request.fields['height'] = _height;
      request.fields['weight'] = _weight;
      request.fields['body_type'] = _bodyType;
      request.fields['face_type'] = _faceShape;
      request.fields['hair_color'] = _hairColor;
      request.fields['hair_style'] = _hairStyle;

      // 현재 UI에 혈액형/눈동자 색 입력칸이 없으면 일단 기본값 전송
      request.fields['blood_type'] = _bloodType;
      request.fields['eye_color'] = _eyeColor;

      // 3) 특징 및 건강 정보
      request.fields['physical_feature'] = _bodyFeatureCtrl.text.trim();
      request.fields['health_info'] = _healthInfoCtrl.text.trim();

      // 4) 보호자 정보
      // 로그인 상태에서는 내 정보가 보호자 정보로 들어가도록 처리
      request.fields['guardian_name'] = _loggedInName.isNotEmpty
          ? _loggedInName
          : _guardianNameCtrl.text.trim();

      request.fields['guardian_rrn_front'] = _isUnknownRRN
          ? ''
          : _guardianRrnFrontCtrl.text.trim();

      request.fields['guardian_rrn_back'] = _isUnknownRRN
          ? ''
          : _guardianRrnBackCtrl.text.trim();

      request.fields['guardian_phone'] = _loggedInPhone.isNotEmpty
          ? _loggedInPhone
          : _guardianPhoneCtrl.text.trim();

      // 6) 사진 정보
      // _photos[0] = 전신, _photos[1] = 정면 얼굴, _photos[2] = 왼쪽, _photos[3] = 오른쪽
      await _addFileIfExists(
        request: request,
        fieldName: 'full_body_photo',
        file: _photos[0],
      );

      await _addFileIfExists(
        request: request,
        fieldName: 'face_photo',
        file: _photos[1],
      );

      await _addFileIfExists(
        request: request,
        fieldName: 'left_side_photo',
        file: _photos[2],
      );

      await _addFileIfExists(
        request: request,
        fieldName: 'right_side_photo',
        file: _photos[3],
      );

      await _addFileIfExists(
        request: request,
        fieldName: 'parent1_face_photo',
        file: _parentPhotos[0],
      );

      await _addFileIfExists(
        request: request,
        fieldName: 'parent2_face_photo',
        file: _parentPhotos[1],
      );

      // 프론트 ML Kit 검증 결과 전송
      const photoFieldNames = [
        'full_body_photo',
        'face_photo',
        'left_side_photo',
        'right_side_photo',
      ];
      for (int i = 0; i < _photos.length; i++) {
        if (_photos[i] != null && _photoValidStatus[i] != null) {
          request.fields['${photoFieldNames[i]}_validation_status'] = _photoValidStatus[i]!;
        }
      }
      for (int i = 0; i < _parentPhotos.length; i++) {
        if (_parentPhotos[i] != null && _parentValidStatus[i] != null) {
          request.fields['parent${i + 1}_face_photo_validation_status'] = _parentValidStatus[i]!;
        }
      }

      // ✅ 실제 서버 전송 직전 확인 로그
      debugPrint('📤 전송 fields = ${request.fields}');
      debugPrint('📸 photo validation = $_photoValidStatus');
      debugPrint('👨‍👩‍👧 parent validation = $_parentValidStatus');

      final streamedResponse = await request.send();

      if (!mounted) return;

      final response = await http.Response.fromStream(streamedResponse);
      final responseText = utf8.decode(response.bodyBytes);

      if (response.statusCode == 200 || response.statusCode == 201) {
        _toast('실종예방 등록이 완료되었습니다.');
        widget.onSuccess?.call();
        return;
      }

      if (response.statusCode == 400) {
        final message = _extractErrorMessage(responseText);
        _toast(message);
        return;
      }

      if (response.statusCode == 401) {
        _toast('로그인이 만료되었습니다. 다시 로그인해 주세요.');
        return;
      }

      _toast('등록 실패: $responseText');
    } catch (e) {
      if (!mounted) return;
      _toast('실종예방 등록 중 오류가 발생했습니다: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _addFileIfExists({
    required http.MultipartRequest request,
    required String fieldName,
    required File? file,
  }) async {
    if (file == null) return;

    request.files.add(
      await http.MultipartFile.fromPath(
        fieldName,
        file.path,
      ),
    );
  }

  String _extractErrorMessage(String responseText) {
    try {
      final decoded = jsonDecode(responseText);

      if (decoded is Map<String, dynamic>) {
        return decoded['error']?.toString() ??
            decoded['message']?.toString() ??
            decoded['detail']?.toString() ??
            '등록에 실패했습니다.';
      }

      return '등록에 실패했습니다.';
    } catch (_) {
      return responseText.isNotEmpty ? responseText : '등록에 실패했습니다.';
    }
  }

  // ── build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final canSubmit = isLoggedIn && _isAgreed && !_isSubmitting;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('등록 대상자 기본 인적사항', Icons.person),
          const SizedBox(height: 16),

          Row(children: [
            Expanded(child: _label('이름')),
            const SizedBox(width: 12),
            Expanded(child: _label('성별')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _field(_nameCtrl, _yellow)),
            const SizedBox(width: 12),
            Expanded(child: _genderRow()),
          ]),
          const SizedBox(height: 14),

          _label('주민등록번호'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _field(_rrnFrontCtrl, _yellow, hint: '앞자리', isNumber: true)),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('-', style: TextStyle(fontSize: 18))),
            Expanded(child: _field(_rrnBackCtrl, _yellow, hint: '뒷자리', isNumber: true, obscure: true)),
          ]),
          const SizedBox(height: 14),

          _label('전화번호'),
          const SizedBox(height: 8),
          _field(_phoneCtrl, _yellow, hint: '01012345678', isNumber: true),
          const SizedBox(height: 14),

          _label('거주지 주소'),
          const SizedBox(height: 8),
          _buildAddressSearchField(),
          const SizedBox(height: 20),

          _label('대상'),
          const SizedBox(height: 8),
          _categoryGrid(),
          const SizedBox(height: 20),

          _label('평소 자주 다니는 곳'),
          const SizedBox(height: 8),
          _field(
            _placeCtrl,
            _yellow,
            hint: '예: 근처 공원, 시장, 복지관, 자주 가는 산책로',
          ),
          const SizedBox(height: 14),

          _label('기타 참고사항'),
          const SizedBox(height: 8),
          _field(_noteCtrl, _yellow, height: 80, hint: '참고사항을 입력해 주세요'),

          const SizedBox(height: 24),
          const Divider(color: Color(0xFFDDDDDD), thickness: 0.8),
          const SizedBox(height: 16),

          _sectionTitle('신체 및 외형 정보', Icons.accessibility_new),
          const SizedBox(height: 16),

          Row(children: [
            Expanded(child: _dropdown('키',     _height,   _heightOpts,   (v) => setState(() => _height   = v))),
            const SizedBox(width: 12),
            Expanded(child: _dropdown('몸무게', _weight,   _weightOpts,   (v) => setState(() => _weight   = v))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _dropdown('체격',   _bodyType, _bodyTypeOpts, (v) => setState(() => _bodyType = v))),
            const SizedBox(width: 12),
            Expanded(child: _dropdown('얼굴형', _faceShape, _faceShapeOpts, (v) => setState(() => _faceShape = v))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _dropdown('두발 색상', _hairColor, _hairColorOpts, (v) => setState(() => _hairColor = v))),
            const SizedBox(width: 12),
            Expanded(child: _dropdown('두발 형태', _hairStyle, _hairStyleOpts, (v) => setState(() => _hairStyle = v))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _dropdown(
                '혈액형',
                _bloodType,
                _bloodTypeOpts,
                (v) => setState(() => _bloodType = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _dropdown(
                '눈동자 색',
                _eyeColor,
                _eyeColorOpts,
                (v) => setState(() => _eyeColor = v),
              ),
            ),
          ]),
          const SizedBox(height: 14),

          _label('신체 특징'),
          const SizedBox(height: 8),
          _field(_bodyFeatureCtrl, _yellow, height: 90, hint: '신체 특징을 입력해 주세요'),
          const SizedBox(height: 14),

          _label('건강 정보'),
          const SizedBox(height: 8),
          _field(_healthInfoCtrl, _yellow, height: 90, hint: '건강 정보를 입력해 주세요'),

          const SizedBox(height: 24),
          const Divider(color: Color(0xFFDDDDDD), thickness: 0.8),
          const SizedBox(height: 16),

          _sectionTitle('사진 등록', Icons.photo_camera),
          const SizedBox(height: 8),
          const Text(
            '정확한 AI 분석을 위해 사진 유형에 맞는 이미지를 등록해 주세요.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.95,
            children: List.generate(4, _photoBox),
          ),

          const SizedBox(height: 22),
          _sectionTitle('부모님 참고 사진', Icons.family_restroom),
          const SizedBox(height: 8),
          const Text(
            'AI 몽타주 참고용으로 부모님 정면 사진을 선택 등록할 수 있습니다.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.95,
            children: List.generate(2, _parentPhotoBox),
          ),

          const SizedBox(height: 24),
          const Divider(color: Color(0xFFDDDDDD), thickness: 0.8),
          const SizedBox(height: 16),

          _guardianSection(),

          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: canSubmit
                  ? _submit
                  : () {
                      if (!isLoggedIn) {
                        _toast('실종예방등록은 로그인 후 이용할 수 있습니다.');
                      } else if (!_isAgreed) {
                        _toast('이용약관에 동의해주세요.');
                      } else if (_isSubmitting) {
                        _toast('등록 처리 중입니다.');
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: canSubmit ? _accentRed : Colors.grey.shade300,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(
                _isSubmitting ? '등록 중...' : '등록하기',
                style: TextStyle(
                  color: canSubmit ? Colors.white : Colors.black54,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ── 보호자 섹션 ──────────────────────────────────────────────────────────
  Widget _guardianSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('보호자 정보', Icons.shield),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFAFA),
            borderRadius: BorderRadius.circular(16),
          ),
          child: isLoggedIn ? _loggedInGuardian() : _guestGuardian(),
        ),
      ],
    );
  }

  Widget _loggedInGuardian() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(children: [
              Icon(Icons.verified, color: _accentRed, size: 18),
              SizedBox(width: 6),
              Text('로그인된 사용자 정보', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ]),
            _agreeToggle(),
          ],
        ),
        const SizedBox(height: 16),
        _label('보호자 이름'),
        const SizedBox(height: 8),
        _readOnlyBox(_loggedInName.isNotEmpty ? _loggedInName : '이름 없음'),
        const SizedBox(height: 14),
        _label('보호자 전화번호'),
        const SizedBox(height: 8),
        _readOnlyBox(_loggedInPhone.isNotEmpty ? _loggedInPhone : '전화번호 없음'),
      ],
    );
  }

  Widget _guestGuardian() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('보호자 정보 입력', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            _agreeToggle(required: true),
          ],
        ),
        const SizedBox(height: 16),

        _label('보호자 이름'),
        const SizedBox(height: 8),
        _field(_guardianNameCtrl, _pink, hint: '보호자 이름'),
        const SizedBox(height: 16),

        Row(children: [
          _label('주민번호'),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _isUnknownRRN = !_isUnknownRRN),
            child: Row(children: [
              Icon(_isUnknownRRN ? Icons.check_circle : Icons.circle_outlined, size: 16, color: Colors.black54),
              const SizedBox(width: 4),
              const Text('알 수 없음', style: TextStyle(fontSize: 12)),
            ]),
          ),
        ]),
        const SizedBox(height: 8),
        AbsorbPointer(
          absorbing: _isUnknownRRN,
          child: Opacity(
            opacity: _isUnknownRRN ? 0.45 : 1,
            child: Row(children: [
              Expanded(child: _field(_guardianRrnFrontCtrl, _pink, hint: '앞자리', isNumber: true)),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('-')),
              Expanded(child: _field(_guardianRrnBackCtrl, _pink, hint: '뒷자리', isNumber: true, obscure: true)),
            ]),
          ),
        ),
        const SizedBox(height: 16),

        _label('보호자 전화번호'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _field(_guardianPhoneCtrl, _pink, hint: '01012345678', isNumber: true)),
          const SizedBox(width: 10),
          _smallBtn(
            _timerSeconds > 0 ? '재전송 (${_timerSeconds}s)' : '인증번호전송',
            onTap: _timerSeconds > 0 ? null : () { _startTimer(); _sendSMS(); },
          ),
        ]),
        const SizedBox(height: 16),

        _label('인증번호'),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _field(_authCodeCtrl, _pink, hint: '인증번호 입력', isNumber: true)),
          const SizedBox(width: 10),
          _smallBtn(_isVerified ? '✔ 인증완료' : '확인', onTap: _isVerified ? null : _verifyCode),
        ]),
      ],
    );
  }

  Widget _agreeToggle({bool required = false}) {
    return GestureDetector(
      onTap: _openAgreementSheet,
      child: Row(children: [
        Icon(_isAgreed ? Icons.check_circle : Icons.circle_outlined, size: 18, color: _accentRed),
        const SizedBox(width: 4),
        Text(required ? '이용약관 동의 (필수)' : '이용약관 동의',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── 사진 박스 ─────────────────────────────────────────────────────────────
  Widget _photoBox(int i) {
    final photo = _photos[i];
    return GestureDetector(
      onTap: () => _openPhotoGuideAndPick(i),
      child: Container(
        decoration: BoxDecoration(color: _yellow, borderRadius: BorderRadius.circular(12)),
        child: photo != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(fit: StackFit.expand, children: [
                  Image.file(photo, fit: BoxFit.cover),
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      color: Colors.black.withValues(alpha: 0.45),
                      child: Text(_photoLabels[i], textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add, size: 34, color: Colors.black54),
                  const SizedBox(height: 8),
                  Text(_photoLabels[i], style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(i == 0 ? '전신 사진을 올려 주세요' : '유형에 맞는 사진을 올려 주세요',
                      style: const TextStyle(fontSize: 9, color: Color(0xFF777777))),
                ],
              ),
      ),
    );
  }

  Widget _parentPhotoBox(int i) {
    final photo = _parentPhotos[i];
    return GestureDetector(
      onTap: () => _openParentPhotoGuideAndPick(i),
      child: Container(
        decoration: BoxDecoration(color: _pink, borderRadius: BorderRadius.circular(12)),
        child: photo != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(fit: StackFit.expand, children: [
                  Image.file(photo, fit: BoxFit.cover),
                  Positioned(
                    left: 0, right: 0, bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      color: Colors.black.withValues(alpha: 0.45),
                      child: Text(_parentPhotoLabels[i], textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ]),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.add, size: 34, color: Colors.black54),
                  const SizedBox(height: 8),
                  Text(_parentPhotoLabels[i], style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('정면 사진만 등록', style: TextStyle(fontSize: 9, color: Color(0xFF777777))),
                ],
              ),
      ),
    );
  }

  // ── 헬퍼 위젯 ────────────────────────────────────────────────────────────
  Widget _buildAddressSearchField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _openAddressSearch,
          child: AbsorbPointer(
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _yellow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _addressCtrl,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: '주소 검색으로 거주지 주소를 선택하세요',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                  suffixIcon: const Icon(Icons.search, size: 20),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 10),

        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _yellow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: _detailAddressCtrl,
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: '상세 주소 예: 101동 302호, ○○요양원',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }

  void _openAddressSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddressSearchPage(
          onSelected: (address) {
            setState(() {
              _addressCtrl.text = address;
            });
          },
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(children: [
      Icon(icon, size: 16, color: const Color(0xFF4F6380)),
      const SizedBox(width: 6),
      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _label(String text) =>
      Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87));

  Widget _readOnlyBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFFF0F0F0), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: const TextStyle(fontSize: 14, color: Colors.black87)),
    );
  }

  Widget _field(TextEditingController ctrl, Color color, {
    double height = 40, String? hint, bool isNumber = false, bool obscure = false,
  }) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
      child: TextField(
        controller: ctrl,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        obscureText: obscure,
        maxLines: height > 50 ? null : 1,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          border: InputBorder.none, hintText: hint,
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        ),
      ),
    );
  }

  Widget _dropdown(String label, String value, List<String> opts, Function(String) onChange) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 8),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: _yellow, borderRadius: BorderRadius.circular(8)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value, isExpanded: true, iconSize: 18,
              style: const TextStyle(fontSize: 13, color: Colors.black),
              items: opts.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
              onChanged: (v) { if (v != null) onChange(v); },
            ),
          ),
        ),
      ],
    );
  }

  Widget _categoryGrid() {
    return RadioGroup<String>(
      groupValue: _category,
      onChanged: (v) { if (v != null) setState(() => _category = v); },
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        childAspectRatio: 4.5,
        mainAxisSpacing: 0,
        crossAxisSpacing: 10,
        children: _categoryOpts.map((t) => GestureDetector(
          onTap: () => setState(() => _category = t),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 30,
                child: Radio<String>(
                  value: t,
                  activeColor: Colors.black87,
                ),
              ),
              Flexible(
                child: Text(
                  t,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        )).toList(),
      ),
    );
  }

  Widget _genderRow() {
    return Container(
      height: 40,
      decoration: BoxDecoration(color: _yellow, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [_genderItem('남자'), _genderItem('여자')],
      ),
    );
  }

  Widget _genderItem(String value) {
    final selected = _gender == value;
    return GestureDetector(
      onTap: () => setState(() => _gender = value),
      child: Row(children: [
        Text(value, style: TextStyle(fontSize: 14, fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        const SizedBox(width: 6),
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(shape: BoxShape.circle, color: selected ? Colors.blueGrey : Colors.grey.shade300),
        ),
      ]),
    );
  }

  Widget _smallBtn(String text, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: onTap == null ? Colors.grey.shade200 : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
      ),
    );
  }

  Widget _exampleImageBox({required String assetPath, required IconData fallbackIcon}) {
    return Container(
      width: 150, height: 110,
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6E0D0)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset(assetPath, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(fallbackIcon, size: 36, color: Colors.black45),
                const SizedBox(height: 8),
                const Text('예시 이미지', style: TextStyle(fontSize: 12, color: Colors.black45)),
              ],
            )),
      ),
    );
  }

  Widget _guideCheck(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.check_circle, size: 15, color: _accentRed),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12, height: 1.3, color: Colors.black87))),
      ]),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.black87, duration: const Duration(seconds: 2)),
    );
  }
}

class AddressSearchPage extends StatefulWidget {
  final void Function(String address) onSelected;

  const AddressSearchPage({
    super.key,
    required this.onSelected,
  });

  @override
  State<AddressSearchPage> createState() => _AddressSearchPageState();
}

class _AddressSearchPageState extends State<AddressSearchPage> {
  late final WebViewController _controller;

  final String _html = '''
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<script src="https://t1.daumcdn.net/mapjsapi/bundle/postcode/prod/postcode.v2.js"></script>
</head>
<body style="margin:0;">
<div id="postcode" style="width:100%;height:100vh;"></div>
<script>
new daum.Postcode({
  oncomplete: function(data) {
    const address = data.roadAddress || data.jibunAddress;
    AddressChannel.postMessage(address);
  },
  width: '100%',
  height: '100%'
}).embed(document.getElementById('postcode'));
</script>
</body>
</html>
''';

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'AddressChannel',
        onMessageReceived: (message) {
          widget.onSelected(message.message);
          Navigator.pop(context);
        },
      )
      ..loadHtmlString(
        _html,
        baseUrl: 'https://t1.daumcdn.net',
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("주소 검색"),
        backgroundColor: Color(0xFFFFF8DE),
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}