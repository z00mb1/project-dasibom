import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../citizen/citizen_form_tab.dart' show AddressSearchPage;
import '../config/api_config.dart';
import '../missing/edit_missing_detail.dart';
import 'package:http/http.dart' as http;

class ReportCaseDetailPage extends StatefulWidget {
  final Map<String, dynamic> caseData;
  const ReportCaseDetailPage({super.key, required this.caseData});

  @override
  State<ReportCaseDetailPage> createState() => _ReportCaseDetailPageState();
}

class _ReportCaseDetailPageState extends State<ReportCaseDetailPage> {
  Map<String, dynamic>? _detail;
  bool _isLoading = true;
  bool _isEditing = false;
  int _selectedPhotoIndex = 0;
  int _status = 0;
  int _originalStatus = 0; // 수정 시작 전 상태 저장 (취소 시 복원용)
  bool isAdmin = false;
  String _typeCode = "";
  List<File> _newImages = [];
  List<int> _deletedPhotoIds = [];
  List<Map<String, dynamic>> _displayPhotos = [];
  Map<String, dynamic>? _missingInfoFull;
  bool get _isGuestHistory =>
    widget.caseData["is_guest_history"] == true;

  // 제보(tip) 편집 컨트롤러
  final _physicalCtrl      = TextEditingController();
  final _behaviorCtrl      = TextEditingController();
  final _healthCtrl        = TextEditingController();
  final _clothingCtrl      = TextEditingController();
  final _etcCtrl           = TextEditingController();
  final _foundLocationCtrl = TextEditingController();

  // 신고(missing) 편집 컨트롤러
  final _nameCtrl           = TextEditingController();
  final _ageCtrl            = TextEditingController();
  final _occLocationCtrl    = TextEditingController();
  final _occDetailLocCtrl   = TextEditingController();
  final _occDateCtrl        = TextEditingController();
  String   _selectedGender    = '';
  DateTime? _selectedOccurredAt;

  final Color _pointColor = const Color(0xFFFDE14C);

  @override
  void initState() {
    super.initState();
    _loadUser();
    _fetchDetail();
  }

  @override
  void dispose() {
    _physicalCtrl.dispose();
    _behaviorCtrl.dispose();
    _healthCtrl.dispose();
    _clothingCtrl.dispose();
    _etcCtrl.dispose();
    _foundLocationCtrl.dispose();
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _occLocationCtrl.dispose();
    _occDetailLocCtrl.dispose();
    _occDateCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => isAdmin = prefs.getString("role") == "admin");
  }

  // ── GET /dasibom/case/{id}/case-detail/ ──────────────────────────────
  Future<void> _fetchDetail() async {
    try {
      final caseId = widget.caseData["id"] ?? widget.caseData["case_id"];

      final bool isGuestHistory =
          widget.caseData["is_guest_history"] == true;

      late http.Response res;

      if (isGuestHistory) {
        final reporterName =
            widget.caseData["reporter_name"]?.toString() ??
            widget.caseData["payload"]?["reporter_name"]?.toString() ??
            "";

        final reporterPhone =
            widget.caseData["reporter_phone"]?.toString() ??
            widget.caseData["payload"]?["reporter_phone"]?.toString() ??
            "";

        res = await http.post(
          Uri.parse("${ApiConfig.baseUrl}/case/$caseId/guest-detail/"),
          headers: {
            "Content-Type": "application/json",
          },
          body: jsonEncode({
            "reporter_name": reporterName,
            "reporter_phone": reporterPhone,
          }),
        );
      } else {
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString("access") ?? "";

        res = await http.get(
          Uri.parse("${ApiConfig.baseUrl}/case/$caseId/case-detail/"),
          headers: {
            "Authorization": "Bearer $token",
          },
        );
      }

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        _parseDetail(data);
      } else {
        setState(() => _isLoading = false);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "상세 정보를 불러올 수 없습니다. (${res.statusCode}) ${utf8.decode(res.bodyBytes)}",
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint("case-detail 에러: $e");

      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _parseDetail(Map<String, dynamic> data) {
final typeCode   = data["type_code"]?.toString() ?? "tip";
    _typeCode        = typeCode;
    final reporter   = (data["reporter"] as Map?)   ?? {};

    List<dynamic> asList(String key) {
      final v = data[key];
      return (v is List) ? v.where((e) => e != null).toList() : [];
    }

    String resolveImgUrl(dynamic raw) {
      final s = raw?.toString() ?? '';
      if (s.isEmpty) return '';
      return s.startsWith('http') ? s : '${ApiConfig.mediaBaseUrl}$s';
    }

    Map<String, dynamic> normalizePhoto(dynamic p) {
      if (p is Map) {
        final m = Map<String, dynamic>.from(p);
        final rawUrl = m['url'] ?? m['image_url'] ?? m['image'] ?? m['photo'] ?? m['file'];
        m['image'] = resolveImgUrl(rawUrl);
        return m;
      }
      return {'image': resolveImgUrl(p), 'photo_type': null};
    }

    // 파일명 기준 중복 제거 (서버가 같은 파일을 다른 폴더에 복사 저장하기 때문)
    String filename(String url) {
      try { return Uri.parse(url).pathSegments.last; } catch (_) { return url; }
    }

    final seen = <String>{};
    final rawPhotos = <Map<String, dynamic>>[];

    // photo_items 우선 (부모 사진 포함 전체), 그 다음 photos
    for (final key in ["photo_items", "photos"]) {
      for (final p in asList(key)) {
        final norm = normalizePhoto(p);
        final url = norm['image'] as String;
        if (url.isNotEmpty && seen.add(filename(url))) rawPhotos.add(norm);
      }
    }

    // 공식 사진 중 파일명이 새로운 것만 추가 (AI 몽타주 등)
    for (final key in ["missing_person_photos", "missing_photos", "official_photos"]) {
      for (final p in asList(key)) {
        final norm = normalizePhoto(p);
        final url = norm['image'] as String;
        if (url.isNotEmpty && seen.add(filename(url))) rawPhotos.add(norm);
      }
    }

    // parent_photos: {"parent1_face": url, "parent2_face": url} 형태
    final parentMap = data['parent_photos'];
    if (parentMap is Map) {
      parentMap.forEach((k, v) {
        final url = resolveImgUrl(v);
        if (url.isNotEmpty && seen.add(filename(url))) {
          rawPhotos.add({'photo_type': k.toString(), 'image': url, 'url': url});
        }
      });
    }

    _displayPhotos = rawPhotos;
    final categories = (data["categories"] as Map?) ?? {};

    final reporterName =
        reporter["name"]?.toString() ??
        data["reporter_name"]?.toString() ??
        widget.caseData["reporter_name"]?.toString() ??
        widget.caseData["payload"]?["reporter_name"]?.toString() ??
        "정보 없음";

    final reporterPhone =
        reporter["phone"]?.toString() ??
        data["reporter_phone"]?.toString() ??
        widget.caseData["reporter_phone"]?.toString() ??
        widget.caseData["payload"]?["reporter_phone"]?.toString() ??
        "정보 없음";

    String typeLabel, name, loc, date, gender, ageMissing;

    if (typeCode == "missing") {
      typeLabel = "실종 신고";
      final info = (data["missing_info"] as Map?) ?? {};
      name       = info["name"]?.toString()              ?? "이름 없음";
      gender     = _genderLabel(info["gender"]?.toString() ?? "");
      ageMissing = info["age_at_missing"] != null         ? "${info["age_at_missing"]}세" : "-";
      loc        = info["occurred_location"]?.toString() ?? "위치 정보 없음";
      date       = _formatDateTime(info["occurred_at"]?.toString());

      // missing categories → List
      _physicalCtrl.text = _listToText(categories["신체 특징"]);
      _clothingCtrl.text = _listToText(categories["착의 사항"]);
      _healthCtrl.text   = _listToText(categories["건강·장애 정보"]);
      _etcCtrl.text      = _listToText(categories["기타 참고 사항"]);
      _behaviorCtrl.text = "";

      _nameCtrl.text        = name;
      _ageCtrl.text         = info["age_at_missing"]?.toString() ?? "";
      _occLocationCtrl.text = loc;
      _occDateCtrl.text     = info["occurred_at"]?.toString() ?? "";
      _selectedGender       = info["gender"]?.toString() ?? "";
      final rawOccAt        = info["occurred_at"]?.toString();
      if (rawOccAt != null && rawOccAt.isNotEmpty) {
        try { _selectedOccurredAt = DateTime.parse(rawOccAt).toLocal(); } catch (_) {}
      }
    } else {
      // tip
      typeLabel = "상세 제보";
      final info = (data["tip_info"] as Map?) ?? {};
      name       = info["missing_name"]?.toString()    ?? "이름 없음";
      gender     = "정보 없음";
      ageMissing = "-";
      loc        = info["found_location"]?.toString()  ?? "위치 정보 없음";
      date       = _formatDateTime(
          info["found_datetime"]?.toString() ?? data["created_at"]?.toString());

      // tip categories → String | null
      _physicalCtrl.text      = categories["신체 특징"]?.toString()    ?? "";
      _clothingCtrl.text      = categories["착의 사항"]?.toString()    ?? "";
      _healthCtrl.text        = categories["건강·장애 정보"]?.toString() ?? "";
      _behaviorCtrl.text      = categories["성격·행동 특성"]?.toString() ?? "";
      _etcCtrl.text           = categories["기타 참고 사항"]?.toString() ?? "";
      _foundLocationCtrl.text = info["found_location"]?.toString()    ?? "";
    }

    final missingPersonId = data["missing_person_id"]?.toString() ??
        (data["missing_info"] as Map?)?["id"]?.toString() ??
        (data["missing_person"] as Map?)?["id"]?.toString();

    _missingInfoFull = data["missing_info"] as Map<String, dynamic>?;

    setState(() {
      _detail = {
        "type":              typeLabel,
        "name":              name,
        "gender":            gender,
        "age_missing":       ageMissing,
        "loc":               loc,
        "date":              date,
        "reporter_name":     reporterName,
        "reporter_phone":    reporterPhone,
        "feature":           _physicalCtrl.text.isNotEmpty ? _physicalCtrl.text : "내용 없음",
        "behavior":          _behaviorCtrl.text.isNotEmpty ? _behaviorCtrl.text : "내용 없음",
        "health":            _healthCtrl.text.isNotEmpty   ? _healthCtrl.text   : "내용 없음",
        "clothing":          _clothingCtrl.text.isNotEmpty ? _clothingCtrl.text : "내용 없음",
        "etc":               _etcCtrl.text.isNotEmpty      ? _etcCtrl.text      : "내용 없음",
        "photos":            rawPhotos,
        "missing_person_id": missingPersonId,
      };
      _status         = _convertStatus(data["status"]?.toString() ?? "received");
      _originalStatus = _status;
      _isLoading = false;
    });

    // 좌표면 주소로 변환
    _resolveLocIfCoords(loc);
  }

  // "lat,lng" 형태면 역지오코딩 후 _detail["loc"] 업데이트
  Future<void> _resolveLocIfCoords(String loc) async {
    final parts = loc.split(',');
    if (parts.length != 2) return;
    final lat = double.tryParse(parts[0].trim());
    final lng = double.tryParse(parts[1].trim());
    if (lat == null || lng == null) return;
    final address = await _coordsToAddress(lat, lng);
    if (!mounted || address.isEmpty) return;
    setState(() {
      _detail?["loc"] = address;
      _occLocationCtrl.text = address;
      _foundLocationCtrl.text = address;
    });
  }

  static Future<String> _coordsToAddress(double lat, double lng) async {
    try {
      final res = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&accept-language=ko',
        ),
        headers: {'User-Agent': 'dasibom-app'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final addr = data['address'] as Map<String, dynamic>;
        final parts = <String>[
          (addr['city'] ?? addr['state'] ?? '') as String,
          (addr['city_district'] ?? addr['suburb'] ?? addr['quarter'] ?? addr['neighbourhood'] ?? '') as String,
          (addr['road'] ?? '') as String,
        ].where((s) => s.isNotEmpty).toList();
        return parts.join(' ');
      }
    } catch (_) {}
    return '';
  }

  String _genderLabel(String g) {
    switch (g.toLowerCase()) {
      case "male":   return "남성";
      case "female": return "여성";
      default:       return g.isEmpty ? "정보 없음" : g;
    }
  }

  String _listToText(dynamic val) {
    if (val == null) return "";
    if (val is List) return val.map((e) => e.toString()).join(", ");
    return val.toString();
  }

  // ── 수정완료: 내용 저장 + 상태 변경을 독립적으로 처리 ───────────────────
  Future<void> _onEdit() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (!mounted) return;

      final token = prefs.getString("access");

      if (token == null || token.isEmpty) {
        debugPrint("토큰 없음");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("로그인이 필요합니다.")),
        );
        return;
      }

      final caseId = widget.caseData["id"] ?? widget.caseData["case_id"];

      final int targetStatus = _status;
      final bool statusChanged = isAdmin && targetStatus != _originalStatus;
      final bool canEditContent = isAdmin || _originalStatus == 0;

      bool contentOk = true;

      if (canEditContent) {
        contentOk = await _saveContent(token, caseId, refreshAfterSave: false);

        if (!mounted) return;

        if (!contentOk) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("내용 수정 실패로 상태 변경을 중단했습니다.")),
          );
          return;
        }
      }

      if (statusChanged) {
        await _applyStatusChange(token, caseId, targetStatus);
        return;
      }

      if (!mounted) return;

      setState(() {
        _isEditing = false;
        _newImages = [];
        _deletedPhotoIds = [];
      });

      await _fetchDetail();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("수정이 완료되었습니다.")),
      );
    } catch (e) {
      debugPrint("에러: $e");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("네트워크 오류가 발생했습니다.")),
      );
    }
  }

  Future<bool> _saveContent(
    String token,
    dynamic caseId, {
    bool refreshAfterSave = true,
  }) async {
    try {
      final String editUrl = "${ApiConfig.baseUrl}/case/$caseId/update-case/";
      debugPrint("수정 요청 typeCode: $_typeCode");
      debugPrint("수정 요청 caseId: $caseId");
      debugPrint("수정 요청 URL: $editUrl");

      final request = http.MultipartRequest("PATCH", Uri.parse(editUrl));
      request.headers["Authorization"] = "Bearer $token";

      // ✅ 공통 사진 삭제
      // delete_photos는 백엔드 구현에 따라 반복 key 또는 JSON 문자열 방식이 필요할 수 있음.
      // 우선 문서 예시처럼 반복 key 방식으로 보내되, http MultipartRequest의 fields는 Map이라
      // 같은 key 반복 저장이 안 될 수 있어 아래에서는 문자열 배열 형태도 같이 대비.
      if (_deletedPhotoIds.isNotEmpty) {
        request.fields["delete_photos"] = jsonEncode(_deletedPhotoIds);
      }

      // ✅ 새 사진 추가
      for (final img in _newImages) {
        request.files.add(
          await http.MultipartFile.fromPath("new_photos", img.path),
        );
      }

      if (_typeCode == "tip") {
        // ✅ 제보 수정 필드
        request.fields["found_location"] = _foundLocationCtrl.text;
        request.fields["physical"] = _physicalCtrl.text;
        request.fields["clothing"] = _clothingCtrl.text;
        request.fields["health"] = _healthCtrl.text;
        request.fields["behavior"] = _behaviorCtrl.text;
        request.fields["etc"] = _etcCtrl.text;
        request.fields["reported_missing_name"] = _nameCtrl.text;

        // 현재 화면에 found_datetime 편집 UI가 없으므로 기존 날짜를 그대로 보낼 수 없으면 생략
        // 필요하면 _foundDateCtrl 따로 만들어서 보내야 함.
      } else if (_typeCode == "missing" || _typeCode == "report") {
        request.fields["name"] = _nameCtrl.text;
        if (_ageCtrl.text.trim().isNotEmpty) {
          request.fields["age_at_missing"] =
              int.tryParse(_ageCtrl.text)?.toString() ?? _ageCtrl.text;
        }
        if (_selectedGender.isNotEmpty) {
          request.fields["gender"] = _selectedGender;
        }
        final detail = _occDetailLocCtrl.text.trim();
        request.fields["occurred_location"] = detail.isNotEmpty
            ? "${_occLocationCtrl.text.trim()} $detail"
            : _occLocationCtrl.text.trim();
        request.fields["occurred_at"] = _selectedOccurredAt != null
            ? _selectedOccurredAt!.toIso8601String()
            : _occDateCtrl.text;
        request.fields["physical"] = _physicalCtrl.text;
        request.fields["clothing"] = _clothingCtrl.text;
        request.fields["health"] = _healthCtrl.text;
        request.fields["description"] = _etcCtrl.text;
      }

      final streamed = await request.send();
      final body = await streamed.stream.bytesToString();

      debugPrint("내용 수정 응답 코드: ${streamed.statusCode}");
      debugPrint("내용 수정 응답 바디: $body");

      if (!mounted) return false;

      if (streamed.statusCode == 200) {
        if (refreshAfterSave) {
          await _fetchDetail();
        }

        if (!mounted) return true;

        setState(() {
          _newImages = [];
          _deletedPhotoIds = [];
        });

        return true;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("내용 수정에 실패했습니다. (${streamed.statusCode}) $body")),
        );
        return false;
      }
    } catch (e) {
      debugPrint("내용 수정 에러: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("내용 수정 중 오류가 발생했습니다.")),
        );
      }
      return false;
    }
  }

  Future<void> _applyStatusChange(String token, dynamic caseId, int targetStatus) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    try {
      final res = await http.patch(
        Uri.parse("${ApiConfig.baseUrl}/case/$caseId/update-status/"),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "status": _statusToString(targetStatus),
        }),
      );

      debugPrint("상태 변경 응답 코드: ${res.statusCode}");
      debugPrint("상태 변경 응답 바디: ${utf8.decode(res.bodyBytes)}");

      if (!mounted) return;

      if (res.statusCode == 200) {
        _originalStatus = targetStatus;

        setState(() {
          _status = targetStatus;
          _isEditing = false;
          _newImages = [];
          _deletedPhotoIds = [];
        });

        if (targetStatus == 1) {
          await _fetchDetail();
          if (!mounted) return;
          messenger.showSnackBar(
            const SnackBar(content: Text("상태가 '확인 중'으로 변경되었습니다.")),
          );
        } else if (targetStatus == 2) {
          messenger.showSnackBar(
            const SnackBar(content: Text("공식 실종자 목록에 등록되었습니다.")),
          );
          nav.pop("completed");
        } else if (targetStatus == 3) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text("수정 완료 및 제보가 거절되었습니다."),
              backgroundColor: Colors.red,
            ),
          );
          nav.pop("rejected");
        } else {
          messenger.showSnackBar(
            const SnackBar(content: Text("수정이 완료되었습니다.")),
          );
        }
      } else {
        setState(() {
          _status = _originalStatus;
        });

        messenger.showSnackBar(
          SnackBar(
            content: Text("상태 변경 실패: ${res.statusCode} ${utf8.decode(res.bodyBytes)}"),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _status = _originalStatus;
      });

      debugPrint("상태 변경 실패: $e");
      messenger.showSnackBar(
        const SnackBar(content: Text("상태 변경 중 오류가 발생했습니다.")),
      );
    }
  }

  // ── 상태 변환 ──────────────────────────────────────────────────────────
  int _convertStatus(String s) {
    switch (s) {
      case "received":  return 0;
      case "reviewing": return 1;
      case "completed": return 2;
      case "rejected":  return 3;
      default:          return 0;
    }
  }

  String _statusToString(int s) {
    switch (s) {
      case 0: return "received";
      case 1: return "reviewing";
      case 2: return "completed";
      case 3: return "rejected";
      default: return "received";
    }
  }

  void _openAddressSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddressSearchPage(
          onSelected: (address) {
            setState(() => _occLocationCtrl.text = address);
          },
        ),
      ),
    );
  }

  void _selectOccurredDate() async {
    final initial = _selectedOccurredAt ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      locale: const Locale('ko', 'KR'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFFFDE14C),
            onPrimary: Colors.black,
            onSurface: Colors.black,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;

    setState(() {
      _selectedOccurredAt = DateTime(
        picked.year, picked.month, picked.day,
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
                initialDateTime: _selectedOccurredAt ?? initial,
                use24hFormat: false,
                onDateTimeChanged: (t) => setState(() {
                  _selectedOccurredAt = DateTime(
                    picked.year, picked.month, picked.day,
                    t.hour, t.minute,
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _newImages.add(File(picked.path)));
    }
  }

  void _deleteServerPhoto(int index) {
    setState(() {
      final id = _displayPhotos[index]["id"];
      if (id != null) _deletedPhotoIds.add(id as int);
      _displayPhotos.removeAt(index);
      final total = _displayPhotos.length + _newImages.length;
      if (_selectedPhotoIndex >= total && _selectedPhotoIndex > 0) {
        _selectedPhotoIndex--;
      }
    });
  }

  void _deleteNewPhoto(int newIndex) {
    setState(() {
      _newImages.removeAt(newIndex);
      final total = _displayPhotos.length + _newImages.length;
      if (_selectedPhotoIndex >= total && _selectedPhotoIndex > 0) {
        _selectedPhotoIndex--;
      }
    });
  }

  // ── 관리자 상태 선택 (UI만 반영, 실제 API는 수정완료 시 호출) ────────────
  void _updateStatus(int newStatus) {
    setState(() => _status = newStatus);
  }

  // ── 유틸 ───────────────────────────────────────────────────────────────
  String _formatDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return "정보 없음";
    try {
      final dt    = DateTime.parse(raw);
      final ampm  = dt.hour < 12 ? "오전" : "오후";
      final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      return "${dt.year}년 ${dt.month}월 ${dt.day}일 $ampm $hour12시 ${dt.minute.toString().padLeft(2, '0')}분";
    } catch (_) {
      return raw;
    }
  }

  // ── build ──────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF9EB),
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _detail == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.cloud_off, size: 48, color: Colors.black38),
                      const SizedBox(height: 12),
                      const Text("정보를 불러올 수 없습니다"),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _fetchDetail,
                        child: const Text("다시 시도"),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  if (_status == 3) _buildRejectedBanner(),
                  _buildPhotoSection(),
                  const SizedBox(height: 20),
                  _buildGridInfo(),
                  const SizedBox(height: 10),
                  if (_typeCode == "missing" && _isEditing)
                    _buildDatePicker()
                  else
                    _buildEditableLongInfo(
                      "실종 발생 일시",
                      _detail!["date"],
                      _occDateCtrl,
                    ),
                  if (_typeCode == "missing" && _isEditing)
                    _buildAddressEditField()
                  else
                    _buildEditableLongInfo(
                      _typeCode == "missing" ? "발생 장소" : "발견 장소",
                      _detail!["loc"],
                      _typeCode == "missing" ? _occLocationCtrl : _foundLocationCtrl,
                    ),
                  const SizedBox(height: 6),
                  _buildFeatureBox("신체 특징",    _detail!["feature"],  _physicalCtrl),
                  if (_typeCode == "tip")
                    _buildFeatureBox("성격·행동 특성", _detail!["behavior"], _behaviorCtrl),
                  _buildFeatureBox("건강·장애 정보", _detail!["health"],   _healthCtrl),
                  _buildFeatureBox("착의 사항",    _detail!["clothing"], _clothingCtrl),
                  _buildFeatureBox("기타 참고 사항", _detail!["etc"],      _etcCtrl),
                  const SizedBox(height: 20),
                  _buildReporterSection(),
                  if (isAdmin) ...[
                    const SizedBox(height: 40),
                    const Divider(thickness: 2, color: Colors.black12),
                    const SizedBox(height: 20),
                    AbsorbPointer(
                      absorbing: !_isEditing,
                      child: Opacity(
                        opacity: _isEditing ? 1.0 : 0.35,
                        child: _buildAdminStatusSection(),
                      ),
                    ),
                    if (!_isEditing)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          "수정 모드일 때 상태 변경이 가능합니다.",
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                  const SizedBox(height: 30),
                  _buildBottomButton(),
                ],
              ),
            ),
    );
  }

  // ── 위젯 ───────────────────────────────────────────────────────────────
  Widget _buildRejectedBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(Icons.cancel_outlined, color: Colors.red.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "이 신고는 거절되었습니다.",
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _resolveUrl(String raw) =>
      raw.startsWith('http') ? raw : '${ApiConfig.mediaBaseUrl}$raw';

  String _photoTypeLabel(String? pType) {
    switch (pType) {
      case 'face':         return '실종자 정면';
      case 'full_body':    return '실종자 전신';
      case 'left_side':    return '실종자 왼쪽';
      case 'right_side':   return '실종자 오른쪽';
      case 'person':       return '실종자 사진';
      case 'parent1_face': return '부모님 사진 1';
      case 'parent2_face': return '부모님 사진 2';
      default:             return '첨부 사진';
    }
  }

  Widget _buildPhotoSection() {
    final totalCount = _displayPhotos.length + _newImages.length;
    final safeIndex = _selectedPhotoIndex.clamp(0, totalCount == 0 ? 0 : totalCount - 1);

    // 미리보기 이미지
    Widget previewChild;
    if (totalCount > 0) {
      if (safeIndex < _displayPhotos.length) {
        final url = _resolveUrl(_displayPhotos[safeIndex]["image"]?.toString() ?? '');
        previewChild = url.isNotEmpty
            ? Image.network(url, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.person, size: 50, color: Colors.white54))
            : const Icon(Icons.person, size: 50, color: Colors.white54);
      } else {
        previewChild = Image.file(_newImages[safeIndex - _displayPhotos.length], fit: BoxFit.cover);
      }
    } else {
      previewChild = const Icon(Icons.person, size: 50, color: Colors.white54);
    }

    final selectedPhoto = safeIndex < _displayPhotos.length ? _displayPhotos[safeIndex] : null;
    final previewLabel = selectedPhoto != null
        ? _photoTypeLabel(selectedPhoto['photo_type']?.toString())
        : safeIndex >= _displayPhotos.length ? '새 사진' : '첨부 사진';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 왼쪽: 큰 미리보기 ──
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 140,
                height: 170,
                color: const Color(0xFFD9E2F3),
                child: previewChild,
              ),
            ),
            Positioned(
              top: 5, left: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  previewLabel,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 14),
        // ── 오른쪽: 썸네일 Wrap ──
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('첨부 사진', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (totalCount == 0 && !_isEditing)
                const Text('첨부된 사진이 없습니다.',
                    style: TextStyle(color: Colors.black45, fontSize: 13))
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    // 서버 사진
                    ..._displayPhotos.asMap().entries.map((e) {
                      final i = e.key;
                      final url = _resolveUrl(e.value["image"]?.toString() ?? '');
                      return _buildThumbnail(
                        index: i,
                        label: _photoTypeLabel(e.value['photo_type']?.toString()),
                        child: url.isNotEmpty
                            ? Image.network(url, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.person, size: 24))
                            : const Icon(Icons.person, size: 24),
                        onDelete: _isEditing ? () => _deleteServerPhoto(i) : null,
                      );
                    }),
                    // 새로 추가한 사진
                    ..._newImages.asMap().entries.map((e) {
                      final i = _displayPhotos.length + e.key;
                      return _buildThumbnail(
                        index: i,
                        label: '새 사진',
                        child: Image.file(e.value, fit: BoxFit.cover),
                        onDelete: _isEditing ? () => _deleteNewPhoto(e.key) : null,
                      );
                    }),
                    // 추가 버튼 (수정 모드)
                    if (_isEditing)
                      GestureDetector(
                        onTap: _addPhoto,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.black12),
                          ),
                          child: const Icon(Icons.add, size: 24, color: Colors.black54),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThumbnail({
    required int index,
    required Widget child,
    String? label,
    VoidCallback? onDelete,
  }) {
    final selected = _selectedPhotoIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedPhotoIndex = index),
      child: Stack(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade300,
              border: Border.all(
                color: selected ? Colors.blue : Colors.transparent,
                width: 2,
              ),
            ),
            child: ClipOval(child: child),
          ),
          if (onDelete != null)
            Positioned(
              top: 0, right: 0,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 16, height: 16,
                  decoration: const BoxDecoration(
                      color: Colors.black54, shape: BoxShape.circle),
                  child: const Icon(Icons.close, size: 10, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGridInfo() {
    final editing = _isEditing && _typeCode == "missing";
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildEditableField("이름", _nameCtrl)),
            const SizedBox(width: 10),
            if (_typeCode == "missing")
              Expanded(child: _buildEditableField("실종 당시 나이", _ageCtrl,
                  keyboardType: TextInputType.number))
            else
              Expanded(child: _buildSmallBox("성별", _detail!["gender"])),
          ],
        ),
        if (_typeCode == "missing") ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: editing
                  ? Border.all(color: const Color(0xFFFDE14C), width: 2)
                  : null,
            ),
            child: editing
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("성별",
                          style: TextStyle(fontSize: 12, color: Colors.black54)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _genderOption("남성", "male"),
                          const SizedBox(width: 10),
                          _genderOption("여성", "female"),
                        ],
                      ),
                    ],
                  )
                : Text("성별 : ${_detail!["gender"]}",
                    style: const TextStyle(fontSize: 13)),
          ),
        ],
      ],
    );
  }

  Widget _genderOption(String label, String value) {
    final isSelected = _selectedGender == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedGender = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFDE14C) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: const Color(0xFFF0C800), width: 1.5)
              : Border.all(color: Colors.black12),
        ),
        child: Text(label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            )),
      ),
    );
  }

  Widget _buildAddressEditField() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFDE14C), width: 2),
          ),
          child: GestureDetector(
            onTap: _openAddressSearch,
            child: AbsorbPointer(
              child: TextField(
                controller: _occLocationCtrl,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: "주소 검색으로 발생 위치를 선택하세요",
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                  labelText: "발생 장소",
                  suffixIcon: Icon(Icons.search, size: 20),
                ),
              ),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFDE14C), width: 2),
          ),
          child: TextField(
            controller: _occDetailLocCtrl,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: "세부 주소 예: 학교 정문 앞, 역 2번 출구 근처",
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker() {
    String display;
    if (_selectedOccurredAt != null) {
      final dt = _selectedOccurredAt!;
      final ampm = dt.hour < 12 ? "오전" : "오후";
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      display = "${dt.year}년 ${dt.month.toString().padLeft(2,'0')}월 "
          "${dt.day.toString().padLeft(2,'0')}일 $ampm $h시 "
          "${dt.minute.toString().padLeft(2,'0')}분";
    } else {
      display = _detail!["date"];
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFDE14C), width: 2),
      ),
      child: GestureDetector(
        onTap: _selectOccurredDate,
        child: Row(
          children: [
            Expanded(
              child: Text("실종 발생 일시 : $display",
                  style: const TextStyle(fontSize: 14)),
            ),
            const Icon(Icons.edit_calendar_outlined,
                size: 18, color: Colors.black45),
          ],
        ),
      ),
    );
  }

  Widget _buildEditableField(String label, TextEditingController ctrl,
      {TextInputType? keyboardType}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: _isEditing
            ? Border.all(color: const Color(0xFFFDE14C), width: 2)
            : null,
      ),
      child: _isEditing
          ? TextField(
              controller: ctrl,
              keyboardType: keyboardType,
              decoration: InputDecoration(
                labelText: label,
                border: InputBorder.none,
              ),
            )
          : Text("$label : ${ctrl.text.isNotEmpty ? ctrl.text : '-'}"),
    );
  }

  Widget _buildFeatureBox(
      String title, String content, TextEditingController ctrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 80),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: _isEditing
                ? Border.all(color: const Color(0xFFFDE14C), width: 2)
                : Border.all(color: Colors.transparent, width: 2),
          ),
          child: _isEditing
              ? TextField(
                  controller: ctrl,
                  maxLines: null,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                  decoration:
                      const InputDecoration.collapsed(hintText: "내용을 입력하세요"),
                )
              : Text(content,
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildReporterSection() {
    final nameLabel  = _typeCode == "tip" ? "제보자 이름"   : "신고자 이름";
    final phoneLabel = _typeCode == "tip" ? "제보자 전화번호" : "신고자 전화번호";
    final sectionLabel = _typeCode == "tip" ? "제보자 정보" : "신고자 정보";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(sectionLabel,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
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
              Text(nameLabel),
              const SizedBox(height: 8),
              _pinkBox(_detail!["reporter_name"]),
              const SizedBox(height: 16),
              Text(phoneLabel),
              const SizedBox(height: 8),
              _pinkBox(_detail!["reporter_phone"]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAdminStatusSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          Row(
            children: const [
              Icon(Icons.admin_panel_settings, color: Colors.blueGrey),
              SizedBox(width: 8),
              Text("관리자 전용: 신고 상태 변경",
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey)),
            ],
          ),
          const SizedBox(height: 20),
          Row(children: [
            _statusBtn("접수 중",  0),
            _statusBtn("확인 중",  1),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _statusBtn("등록 완료", 2),
            _statusBtn("거절됨",   3),
          ]),
        ],
      ),
    );
  }

  Widget _statusBtn(String label, int idx) {
    final active      = _status == idx;
    final isReject    = idx == 3;
    final activeColor = isReject ? const Color(0xFFFFCDD2) : _pointColor;
    final textColor   = (active && isReject) ? Colors.red.shade800 : Colors.black;

    return Expanded(
      child: GestureDetector(
        onTap: () => _updateStatus(idx),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: active ? activeColor : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: (active && isReject)
                ? Border.all(color: Colors.red, width: 1.5)
                : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context)),
      title: GestureDetector(
        onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
        child: Image.asset('assets/images/dasibom_logo.png',
            height: 40,
            errorBuilder: (c, e, s) =>
                const Icon(Icons.favorite, color: Colors.amber)),
      ),
      centerTitle: true,
    );
  }

  Widget _buildSmallBox(String label, String val) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(10)),
        child: Text("$label : $val"),
      );

  Widget _buildEditableLongInfo(
    String label,
    String val,
    TextEditingController ctrl,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: _isEditing
            ? Border.all(color: const Color(0xFFFDE14C), width: 2)
            : Border.all(color: Colors.transparent, width: 2),
      ),
      child: _isEditing
          ? TextField(
              controller: ctrl,
              maxLines: 1,
              decoration: InputDecoration(
                labelText: label,
                border: InputBorder.none,
                hintText: "내용을 입력하세요",
              ),
            )
          : Text("$label : $val"),
    );
  }

  Widget _buildBottomButton() {
     if (_isGuestHistory) return const SizedBox.shrink();

    // 완료된 신고 → 실종자 프로필 수정하기 버튼 (관리자 제외)
   if (_status == 2 && _typeCode == "missing" && !_isEditing) {
    final mpId = _detail?["missing_person_id"]?.toString() ?? '';

    return InkWell(
      onTap: () {
        if (mpId.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("실종자 수정 ID를 확인할 수 없습니다."),
            ),
          );
          return;
        }

        debugPrint("✅ completed missing 수정");
        debugPrint("✅ missing_person_id = $mpId");

        final fullDetail = <String, dynamic>{
          ...?_missingInfoFull,
          "id": mpId,
        };

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EditMissingPage(
              detail: fullDetail,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Text(
            "실종자 프로필 수정하기",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF2E7D32),
            ),
          ),
        ),
      ),
    );
  }

    // 접수중(0)이 아니면 일반 사용자는 수정 불가
    if (_status != 0 && !isAdmin) return const SizedBox.shrink();

    if (_isEditing) {
      return Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                setState(() {
                  _isEditing = false;
                  _status = _originalStatus;
                  _newImages = [];
                  _deletedPhotoIds = [];
                  _displayPhotos = ((_detail?["photos"] as List?) ?? [])
                      .map<Map<String, dynamic>>((p) => p is Map
                          ? Map<String, dynamic>.from(p)
                          : {"image": p.toString()})
                      .toList();
                });
                // 컨트롤러·상태를 원본으로 복원
                _nameCtrl.text        = _detail?["name"] ?? "";
                _ageCtrl.text         = _detail?["age_missing"]
                    ?.toString().replaceAll("세", "") ?? "";
                _occLocationCtrl.text = _detail?["loc"] ?? "";
                _occDetailLocCtrl.text = "";
                final rawOccAt = _occDateCtrl.text;
                if (rawOccAt.isNotEmpty) {
                  try {
                    _selectedOccurredAt = DateTime.parse(rawOccAt).toLocal();
                  } catch (_) {}
                }
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black12),
                ),
                child: const Center(
                  child: Text("취소",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.black54)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: InkWell(
              onTap: _onEdit,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: const Color(0xFFFDE14C),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text("수정완료",
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return InkWell(
      onTap: () => setState(() {
        _originalStatus = _status; // 수정 시작 시점의 상태 저장
        _isEditing = true;
      }),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1BE),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Text("수정하기",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      ),
    );
  }

  Widget _pinkBox(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEEE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text, style: const TextStyle(fontSize: 14)),
    );
  }
}
