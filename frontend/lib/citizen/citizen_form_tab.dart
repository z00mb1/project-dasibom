import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:geolocator/geolocator.dart';

import '../config/api_config.dart';

class CitizenFormTab extends StatefulWidget {
  final String? initialName;
  final int? initialGender;
  final String? initialPhotoUrl;
  final String? initialMissingSeq;
  final VoidCallback? onSuccess;

  const CitizenFormTab({
    this.initialName,
    this.initialGender,
    this.initialPhotoUrl,
    this.initialMissingSeq,
    this.onSuccess,
    super.key,
  });

  @override
  State<CitizenFormTab> createState() => _CitizenFormTabState();
}

class _CitizenFormTabState extends State<CitizenFormTab> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _charCtrl = TextEditingController();
  final TextEditingController _locCtrl = TextEditingController();
  final TextEditingController _clothCtrl = TextEditingController();
  final TextEditingController _reporterNameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _reporterRrnFrontCtrl = TextEditingController();
  final TextEditingController _reporterRrnBackCtrl = TextEditingController();
  final TextEditingController _detailLocCtrl = TextEditingController();
  final TextEditingController _etcCtrl = TextEditingController();
  String? _verificationId;

  bool isLoggedIn = false;
  String _loggedInName = "";
  String _loggedInPhone = "";

  bool _isUnknownReporterRRN = false;

  DateTime _selectedDateTime = DateTime.now();
  int _selectedGender = -1;
  bool _isAgreed = false;
  bool _serviceAgree = false;
  bool _locationAgree = false;
  bool _privacyAgree = false;
  bool _isAdmin = false;
  bool _isSubmitting = false;
  bool _isGettingLocation = false;
  final bool _isEditMode = false;
  int _currentStatus = 0;
  int _timerSeconds = 0;
  Timer? _timer;
  bool _isVerified = false;
  File? _selectedImage;

  final Color _lightYellow = const Color(0xFFFDF9EB);
  final Color _lightPink = const Color(0xFFFAEEF0);

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
    if (widget.initialName != null) _nameCtrl.text = widget.initialName!;
    if (widget.initialGender != null) _selectedGender = widget.initialGender!;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _nameCtrl.dispose();
    _charCtrl.dispose();
    _locCtrl.dispose();
    _clothCtrl.dispose();
    _reporterNameCtrl.dispose();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _reporterRrnFrontCtrl.dispose();
    _reporterRrnBackCtrl.dispose();
    _detailLocCtrl.dispose();
    _etcCtrl.dispose();
    super.dispose();
  }

  void _selectDateAndTime() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      locale: const Locale('ko', 'KR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFFDE14C),
              onPrimary: Colors.black,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      if (!mounted) return;
      showModalBottomSheet(
        context: context,
        builder: (BuildContext context) {
          return Container(
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
                      const Text("발견 시간 설정",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text("완료"),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.time,
                    onDateTimeChanged: (DateTime newTime) {
                      setState(() {
                        _selectedDateTime = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                          newTime.hour,
                          newTime.minute,
                        );
                      });
                    },
                    initialDateTime: _selectedDateTime,
                    use24hFormat: false,
                  ),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access');
    final role = prefs.getString('role');
    final isGuest = prefs.getBool('isGuest') ?? true;

    if (!mounted) return;
    setState(() => _isAdmin = role == 'admin');

    if (isGuest || token == null || token.isEmpty) {
      setState(() {
        isLoggedIn = false;
        _loggedInName = "";
        _loggedInPhone = "";
      });
      return;
    }

    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/userauth/me/"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final person = data["person"] as Map? ?? {};
        setState(() {
          isLoggedIn = true;
          _loggedInName = person["name"]?.toString() ?? "";
          _loggedInPhone = person["phone"]?.toString() ?? "";
          _reporterNameCtrl.text = _loggedInName;
          _phoneCtrl.text = _loggedInPhone;
          _isVerified = true;
        });
      } else {
        setState(() => isLoggedIn = false);
      }
    } catch (e) {
      debugPrint("시민제보 사용자 정보 로드 실패: $e");
      if (mounted) setState(() => isLoggedIn = false);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _timerSeconds = 180);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timerSeconds == 0) {
        timer.cancel();
      } else {
        if (!mounted) return;
        setState(() => _timerSeconds--);
      }
    });
  }

  Future<void> _sendSMS() async {
    String phoneNumber = _phoneCtrl.text.trim();
    if (phoneNumber.isEmpty) {
      _showMessage("전화번호를 입력해 주세요.");
      return;
    }
    if (phoneNumber.startsWith("0")) {
      phoneNumber = "+82${phoneNumber.substring(1)}";
    }
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (PhoneAuthCredential credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
        },
        verificationFailed: (e) {
          if (!mounted) return;
          _showMessage("인증 실패: ${e.message}");
        },
        codeSent: (String verificationId, int? token) {
          if (!mounted) return;
          setState(() => _verificationId = verificationId);
          _showMessage("인증번호가 발송되었습니다.");
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage("인증번호 발송 중 오류가 발생했습니다.");
    }
  }

  Future<void> _verifyCode() async {
    if (_verificationId == null) {
      _showMessage("먼저 인증번호를 전송해 주세요.");
      return;
    }
    if (_codeCtrl.text.trim().isEmpty) {
      _showMessage("인증번호를 입력해 주세요.");
      return;
    }
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _codeCtrl.text.trim(),
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      if (!mounted) return;
      setState(() => _isVerified = true);
      _showMessage("인증이 완료되었습니다.");
    } catch (e) {
      if (!mounted) return;
      _showMessage("인증번호가 올바르지 않습니다.");
    }
  }

  void _openAgreementSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            bool allChecked =
                _serviceAgree && _locationAgree && _privacyAgree;
            return Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "이용약관 동의",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  ListTile(
                    leading: Icon(
                      allChecked
                          ? Icons.check_circle
                          : Icons.circle_outlined,
                      color: const Color(0xFFFF8A8A),
                    ),
                    title: const Text("약관 전체 동의"),
                    onTap: () {
                      setModalState(() {
                        _serviceAgree = !allChecked;
                        _locationAgree = !allChecked;
                        _privacyAgree = !allChecked;
                      });
                    },
                  ),
                  const Divider(),
                  _buildAgreementItem(
                    "서비스 이용약관 (필수)",
                    _serviceAgree,
                    () => setModalState(() => _serviceAgree = !_serviceAgree),
                  ),
                  _buildAgreementItem(
                    "위치기반 서비스 이용약관 (필수)",
                    _locationAgree,
                    () =>
                        setModalState(() => _locationAgree = !_locationAgree),
                  ),
                  _buildAgreementItem(
                    "개인정보 처리방침 (필수)",
                    _privacyAgree,
                    () => setModalState(() => _privacyAgree = !_privacyAgree),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_serviceAgree &&
                              _locationAgree &&
                              _privacyAgree)
                          ? () {
                              setState(() => _isAgreed = true);
                              Navigator.pop(context);
                            }
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8A8A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text("확인",
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAgreementItem(
      String title, bool value, VoidCallback onTap) {
    return ListTile(
      leading: Icon(
        value ? Icons.check_circle : Icons.circle_outlined,
        color: const Color(0xFFFF8A8A),
      ),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  bool _validateTipperInfo() {
    if (!_isAgreed) {
      _showMessage("이용약관에 동의해주세요.");
      return false;
    }
    if (isLoggedIn) return true;

    if (_reporterNameCtrl.text.trim().isEmpty) {
      _showMessage("제보자 이름을 입력해주세요.");
      return false;
    }
    if (!_isUnknownReporterRRN &&
        (_reporterRrnFrontCtrl.text.trim().isEmpty ||
            _reporterRrnBackCtrl.text.trim().isEmpty)) {
      _showMessage("제보자 주민번호를 입력해주세요.");
      return false;
    }
    if (_phoneCtrl.text.trim().isEmpty) {
      _showMessage("제보자 전화번호를 입력해주세요.");
      return false;
    }
    if (!_isVerified) {
      _showMessage("전화번호 인증을 완료해주세요.");
      return false;
    }
    return true;
  }

  Future<void> _submitCitizenTip() async {
    if (_isSubmitting) return;

    // ── validation (isSubmitting 세팅 전) ────────────────────────────────
    if (!_validateTipperInfo()) return;

    if (_nameCtrl.text.trim().isEmpty) {
      _showMessage("제보 대상 실종자 이름을 입력해주세요.");
      return;
    }
    if (_selectedGender == -1) {
      _showMessage("성별 정보가 없습니다.");
      return;
    }
    if (_locCtrl.text.trim().isEmpty) {
      _showMessage("목격 장소를 주소 검색으로 선택해주세요.");
      return;
    }
    if (_detailLocCtrl.text.trim().length < 2) {
      _showMessage("상세 위치를 조금 더 구체적으로 입력해주세요.");
      return;
    }
    if (_charCtrl.text.trim().isEmpty) {
      _showMessage("신체 특징을 입력해주세요.");
      return;
    }
    if (_clothCtrl.text.trim().isEmpty) {
      _showMessage("인상착의를 입력해주세요.");
      return;
    }

    // ── 모든 검증 통과 후에만 잠금 ──────────────────────────────────────
    setState(() { _isSubmitting = true; });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("access");

      final uri = Uri.parse("${ApiConfig.baseUrl}/report/tip/");
      final request = http.MultipartRequest("POST", uri);

      if (isLoggedIn && token != null && token.isNotEmpty) {
        request.headers["Authorization"] = "Bearer $token";
      }

      request.fields["missing_name"] = _nameCtrl.text.trim();

      if (widget.initialMissingSeq != null &&
          widget.initialMissingSeq!.trim().isNotEmpty) {
        request.fields["missing_seq"] =
            widget.initialMissingSeq!.trim();
      }

      request.fields["gender"] =
          _selectedGender == 0 ? "male" : "female";

      request.fields["gender"] = _selectedGender == 0 ? "male" : "female";
      request.fields["found_datetime"] = _selectedDateTime.toIso8601String();
      request.fields["physical"] = _charCtrl.text.trim();
      request.fields["clothing"] = _clothCtrl.text.trim();
      request.fields["health"] = "";
      request.fields["behavior"] = "";
      request.fields["found_location"] =
          "${_locCtrl.text.trim()} ${_detailLocCtrl.text.trim()}";

      request.fields["etc"] = _etcCtrl.text.trim();

      if (isLoggedIn) {
        request.fields["reporter_name"] = _loggedInName;
        request.fields["reporter_phone"] = _loggedInPhone;
        request.fields["is_guest_report"] = "false";
      } else {
        request.fields["reporter_name"] = _reporterNameCtrl.text.trim();
        request.fields["reporter_phone"] = _phoneCtrl.text.trim();
        request.fields["reporter_resident_front"] =
            _isUnknownReporterRRN ? "" : _reporterRrnFrontCtrl.text.trim();
        request.fields["reporter_resident_back"] =
            _isUnknownReporterRRN ? "" : _reporterRrnBackCtrl.text.trim();
        request.fields["is_guest_report"] = "true";
      }

      if (_selectedImage != null) {
        final bytes = await _selectedImage!.readAsBytes();
        final ext = _selectedImage!.path.split('.').last.toLowerCase();
        final mime = ext == 'png' ? 'png' : 'jpeg';
        request.files.add(
          http.MultipartFile.fromBytes(
            "photo",
            bytes,
            filename: "photo.$mime",
            contentType: MediaType("image", mime),
          ),
        );
      }

      final response = await request.send();
      final body = await response.stream.bytesToString();

      debugPrint("시민제보 응답 코드: ${response.statusCode}");
      debugPrint("시민제보 응답 바디: $body");

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        _showMessage("제보가 정상적으로 접수되었습니다.");
        widget.onSuccess?.call();
      } else {
        _showMessage("제보 실패: $body");
      }
        } catch (e) {
          debugPrint("시민제보 전송 오류: $e");
          _showMessage("제보 중 오류가 발생했습니다.");
        } finally {
          if (mounted) {
            setState(() {
              _isSubmitting = false;
            });
          }
        }
      }

  @override
  Widget build(BuildContext context) {
    final bool canSubmit = isLoggedIn ? _isAgreed : (_isAgreed && _isVerified);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("실종자 정보",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  const Text(
                    "실종자 사진",
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  _buildProfilePhotoBox(),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInputLabel("이름"),
                    _buildTextFieldBox(
                      controller: _nameCtrl,
                      height: 40,
                      color: _lightYellow,
                      isReadOnly: widget.initialName != null,
                    ),
                    const SizedBox(height: 16),
                    _buildInputLabel("성별"),
                    _buildGenderSelection(),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          _buildInputLabel("발견 일시"),
          GestureDetector(
            onTap: _selectDateAndTime,
            child: Container(
              width: double.infinity,
              height: 40,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: _lightYellow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                DateFormat('yyyy년 MM월 dd일 a hh시 mm분', 'ko_KR')
                    .format(_selectedDateTime),
                style: const TextStyle(color: Colors.black87),
              ),
            ),
          ),
          const SizedBox(height: 20),

          _buildInputLabel("신체 특징"),
          _buildTextFieldBox(
            controller: _charCtrl,
            height: 100,
            color: _lightYellow,
            hint: "Ex) 코 옆에 점이 있었어요, 엄지 손가락에 흉터가 있었어요",
          ),
          const SizedBox(height: 20),

          _buildAddressSearchInput(),

          const SizedBox(height: 20),

          _buildInputLabel("인상착의"),
          _buildTextFieldBox(
            controller: _clothCtrl,
            height: 100,
            color: _lightYellow,
            hint: "Ex) 빨간 목도리를 착용하고 있었어요, 검은 바지를 입고 있었어요",
          ),

          const SizedBox(height: 20),

          _buildInputLabel("기타 참고 사항"),
          _buildTextFieldBox(
            controller: _etcCtrl,
            height: 100,
            color: _lightYellow,
            hint: "예: 주변을 두리번거림, 혼자 이동 중, 특정 방향으로 걸어감",
          ),

          const SizedBox(height: 32),

          _buildInputLabel("목격 사진"),
          _buildPhotoUploadBox(),

          const SizedBox(height: 20),

          _buildTipperSection(),
          const SizedBox(height: 32),

          if (_isAdmin && _isEditMode) ...[
            _buildAdminStatusSection(),
            const SizedBox(height: 24),
          ],

          _buildActionButton(
            text: _isSubmitting ? "제보 접수 중..." : "제보하기",
            color: canSubmit && !_isSubmitting
                ? const Color(0xFFFF8A8A)
                : Colors.grey.shade300,
            textColor: Colors.white,
            onPressed: canSubmit && !_isSubmitting
                ? _submitCitizenTip
                : () {
                    if (!_isAgreed) {
                      _showMessage("이용약관에 동의해주세요.");
                      return;
                    }
                    if (!isLoggedIn && !_isVerified) {
                      _showMessage("전화번호 인증을 완료해주세요.");
                      return;
                    }
                  },
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ── 제보자 정보 섹션 ──────────────────────────────────────────────────────

  Widget _buildTipperSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "제보자 정보",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFAFA),
            borderRadius: BorderRadius.circular(16),
          ),
          child: isLoggedIn
              ? _buildLoggedInTipperInfo()
              : _buildGuestTipperForm(),
        ),
      ],
    );
  }

  Widget _buildLoggedInTipperInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.verified, color: Color(0xFFFF8A8A), size: 18),
                SizedBox(width: 6),
                Text(
                  "로그인된 사용자 정보",
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                ),
              ],
            ),
            GestureDetector(
              onTap: _openAgreementSheet,
              child: Row(
                children: [
                  Icon(
                    _isAgreed ? Icons.check_circle : Icons.circle_outlined,
                    size: 18,
                    color: const Color(0xFFFF8A8A),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    "이용약관 동의",
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildInputLabel("제보자 이름"),
        _buildReadOnlyBox(_loggedInName.isNotEmpty ? _loggedInName : "이름 없음"),
        const SizedBox(height: 14),
        _buildInputLabel("제보자 전화번호"),
        _buildReadOnlyBox(
            _loggedInPhone.isNotEmpty ? _loggedInPhone : "전화번호 없음"),
      ],
    );
  }

  Widget _buildGuestTipperForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              "비회원 제보자 정보",
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            GestureDetector(
              onTap: _openAgreementSheet,
              child: Row(
                children: [
                  Icon(
                    _isAgreed ? Icons.check_circle : Icons.circle_outlined,
                    size: 18,
                    color: const Color(0xFFFF8A8A),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    "이용약관 동의 (필수)",
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        _buildInputLabel("제보자 이름"),
        _buildTextFieldBox(
            controller: _reporterNameCtrl,
            height: 40,
            color: _lightPink,
            hint: "제보자 이름"),
        const SizedBox(height: 16),

        Row(
          children: [
            _buildInputLabel("주민번호"),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(
                  () => _isUnknownReporterRRN = !_isUnknownReporterRRN),
              child: Row(
                children: [
                  Icon(
                    _isUnknownReporterRRN
                        ? Icons.check_circle
                        : Icons.circle_outlined,
                    size: 16,
                    color: Colors.black54,
                  ),
                  const SizedBox(width: 4),
                  const Text("알 수 없음", style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AbsorbPointer(
          absorbing: _isUnknownReporterRRN,
          child: Opacity(
            opacity: _isUnknownReporterRRN ? 0.45 : 1,
            child: Row(
              children: [
                Expanded(
                  child: _buildTextFieldBox(
                      controller: _reporterRrnFrontCtrl,
                      height: 40,
                      color: _lightPink,
                      hint: "앞자리"),
                ),
                const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text("-")),
                Expanded(
                  child: _buildTextFieldBox(
                      controller: _reporterRrnBackCtrl,
                      height: 40,
                      color: _lightPink,
                      hint: "뒷자리"),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        _buildInputLabel("제보자 전화번호"),
        Row(
          children: [
            Expanded(
              child: _buildTextFieldBox(
                  controller: _phoneCtrl,
                  height: 40,
                  color: _lightPink,
                  hint: "01012345678"),
            ),
            const SizedBox(width: 10),
            _buildSmallWhiteButton(
              _timerSeconds > 0 ? "재전송 (${_timerSeconds}s)" : "인증번호전송",
              onTap: _timerSeconds > 0
                  ? null
                  : () {
                      _startTimer();
                      _sendSMS();
                    },
            ),
          ],
        ),
        const SizedBox(height: 16),

        _buildInputLabel("인증번호"),
        Row(
          children: [
            Expanded(
              child: _buildTextFieldBox(
                  controller: _codeCtrl,
                  height: 40,
                  color: _lightPink,
                  hint: "인증번호 입력"),
            ),
            const SizedBox(width: 10),
            _buildSmallWhiteButton(
              _isVerified ? "✔ 인증완료" : "확인",
              onTap: _isVerified ? null : _verifyCode,
            ),
          ],
        ),
      ],
    );
  }

  // ── 헬퍼 위젯 ────────────────────────────────────────────────────────────

  Widget _buildInputLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.black87)),
    );
  }

  Widget _buildReadOnlyBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: const TextStyle(fontSize: 14, color: Colors.black87)),
    );
  }

  Widget _buildSmallWhiteButton(String text, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: onTap == null ? Colors.grey.shade200 : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          text,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.black87),
        ),
      ),
    );
  }

  Widget _buildTextFieldBox({
    TextEditingController? controller,
    required double height,
    required Color color,
    String? hint,
    Color? textColor,
    bool isReadOnly = false,
  }) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: controller,
        enabled: !isReadOnly,
        readOnly: isReadOnly,
        maxLines: height > 50 ? null : 1,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          hintStyle: TextStyle(color: textColor ?? Colors.grey.shade400),
        ),
      ),
    );
  }
  Widget _buildAddressSearchInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInputLabel("발생 위치"),

        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _openAddressSearch,
                child: AbsorbPointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: _lightYellow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: TextField(
                      controller: _locCtrl,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: "주소 검색으로 발생 위치를 선택하세요",
                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                        suffixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _isGettingLocation ? null : _getCurrentLocation,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: _lightYellow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _isGettingLocation
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.my_location, size: 18, color: Colors.black54),
                          SizedBox(width: 6),
                          Text(
                            "현재 위치",
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _lightYellow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: _detailLocCtrl,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: "상세 위치 예: 학교 정문 앞, 역 2번 출구 근처",
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
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
              _locCtrl.text = address;
            });
          },
        ),
      ),
    );
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isGettingLocation = true);
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showMessage("위치 권한이 거부되었습니다.");
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showMessage("위치 권한이 영구적으로 거부되었습니다. 설정에서 허용해주세요.");
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      final response = await http.get(
        Uri.parse(
          "https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${position.latitude}&lon=${position.longitude}&accept-language=ko",
        ),
        headers: {"User-Agent": "dasibom-app"},
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final addr = data["address"] as Map<String, dynamic>;
        final parts = <String>[
          (addr["city"] ?? addr["state"] ?? "") as String,
          (addr["city_district"] ?? addr["suburb"] ?? addr["quarter"] ?? addr["neighbourhood"] ?? "") as String,
          (addr["road"] ?? "") as String,
        ].where((s) => s.isNotEmpty).toList();
        setState(() => _locCtrl.text = parts.join(" "));
      } else {
        _showMessage("현재 위치를 주소로 변환하지 못했습니다.");
      }
    } catch (e) {
      if (mounted) _showMessage("현재 위치를 가져오지 못했습니다.");
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  Widget _buildPhotoUploadBox() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _showImagePickerOptions,
          child: Container(
            width: 130,
            height: 170,
            decoration: BoxDecoration(
              color: _lightPink,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFC1C1)),
            ),
            child: _selectedImage != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _selectedImage!,
                      fit: BoxFit.cover,
                    ),
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_a_photo, size: 36, color: Colors.black54),
                      SizedBox(height: 8),
                      Text(
                        "사진 첨부",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "선택사항",
                        style: TextStyle(fontSize: 11, color: Colors.black45),
                      ),
                    ],
                  ),
          ),
        ),

        const SizedBox(width: 14),

        Expanded(
          child: Container(
            height: 170,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFAFA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFE0E0)),
            ),
            child: _selectedImage == null
                ? const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "목격 사진 안내",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        "사진은 필수가 아니에요.\n목격 당시 사진이 있는 경우에만 첨부해 주세요.",
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: Colors.black54,
                        ),
                      ),
                      Spacer(),
                      Row(
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.black38),
                          SizedBox(width: 5),
                          Text(
                            "미첨부 상태",
                            style: TextStyle(fontSize: 11, color: Colors.black38),
                          ),
                        ],
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "사진이 첨부되었어요",
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "선택한 사진이 제보와 함께 전송됩니다.",
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: Colors.black54,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        height: 36,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _selectedImage = null;
                            });
                          },
                          icon: const Icon(Icons.delete_outline, size: 16),
                          label: const Text("사진 삭제"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Color(0xFFFFC1C1)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfilePhotoBox() {
    return Container(
      width: 130,
      height: 170,
      decoration: BoxDecoration(
        color: _lightYellow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: widget.initialPhotoUrl != null && widget.initialPhotoUrl!.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                widget.initialPhotoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.person, size: 45),
              ),
            )
          : const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person, size: 40, color: Colors.black54),
                SizedBox(height: 8),
                Text(
                  "프로필 사진 없음",
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
    );
  }

  Widget _buildGenderSelection() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
          color: _lightYellow, borderRadius: BorderRadius.circular(8)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildGenderRadio(title: "남자", index: 0),
          _buildGenderRadio(title: "여자", index: 1),
        ],
      ),
    );
  }

  Widget _buildGenderRadio({required String title, required int index}) {
    final isSelected = _selectedGender == index;
    return GestureDetector(
      onTap: widget.initialGender != null
          ? null
          : () => setState(() => _selectedGender = index),
      child: Row(
        children: [
          Text(title),
          const SizedBox(width: 8),
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? Colors.blueGrey : Colors.grey.shade300,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showImagePickerOptions() async {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text("카메라"),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo),
                title: const Text("갤러리"),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked != null) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  Widget _buildAdminStatusSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF9EB),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("접수 상태 변경",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(
            children: [
              _statusBox(0, "접수 중"),
              const SizedBox(width: 10),
              _statusBox(1, "확인 중"),
              const SizedBox(width: 10),
              _statusBox(2, "등록 완료"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBox(int index, String label) {
    bool isSelected = _currentStatus == index;
    return Expanded(
      child: GestureDetector(
        onTap: _isEditMode ? () => setState(() => _currentStatus = index) : null,
        child: Opacity(
          opacity: _isEditMode ? 1.0 : 0.5,
          child: Container(
            height: 70,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFFDE14C)
                  : const Color(0xFFFFFBE6),
              borderRadius: BorderRadius.circular(12),
              border: isSelected
                  ? Border.all(color: Colors.orangeAccent, width: 2)
                  : null,
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? Colors.black : Colors.black54,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required String text,
    required Color color,
    required VoidCallback? onPressed,
    Color textColor = Colors.black87,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          elevation: 1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(
          text,
          style: TextStyle(
              color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
    );
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.black87,
        duration: const Duration(seconds: 2),
      ),
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
