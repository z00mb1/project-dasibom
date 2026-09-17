import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../citizen/citizen_form_tab.dart' show AddressSearchPage;
import '../config/api_config.dart';
import 'package:http/http.dart' as http;

class CitizenStatusDetailPage extends StatefulWidget {
  final Map<String, dynamic> tipData;
  const CitizenStatusDetailPage({super.key, required this.tipData});

  @override
  State<CitizenStatusDetailPage> createState() =>
      _CitizenStatusDetailPageState();
}

class _CitizenStatusDetailPageState extends State<CitizenStatusDetailPage> {
  Map<String, dynamic>? _detail;
  bool _isLoading = true;
  bool _isEditing = false;
  bool _canEdit = false;
  int _selectedPhotoIndex = 0;
  int _status = 0;
  int _originalStatus = 0;
  bool isAdmin = false;
  String _typeCode = "";
  List<File> _newImages = [];
  List<int> _deletedPhotoIds = [];
  List<Map<String, dynamic>> _displayPhotos = [];
  List<Map<String, dynamic>> _missingPersonPhotos = [];
  bool get _isGuestHistory => widget.tipData["is_guest_history"] == true;

  // 제보(tip) 편집 컨트롤러
  final _physicalCtrl      = TextEditingController();
  final _clothingCtrl      = TextEditingController();
  final _etcCtrl           = TextEditingController();
  final _foundLocationCtrl = TextEditingController();

  // 신고(missing) / 제보(tip) 공통 편집 컨트롤러
  final _nameCtrl           = TextEditingController();
  final _ageCtrl            = TextEditingController();
  final _occLocationCtrl    = TextEditingController();
  final _occDetailLocCtrl   = TextEditingController();
  final _occDateCtrl        = TextEditingController();
  final _foundDetailLocCtrl = TextEditingController();
  String    _selectedGender    = '';
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
    _clothingCtrl.dispose();
    _etcCtrl.dispose();
    _foundLocationCtrl.dispose();
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _occLocationCtrl.dispose();
    _occDetailLocCtrl.dispose();
    _occDateCtrl.dispose();
    _foundDetailLocCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => isAdmin = prefs.getString("role") == "admin");
  }

  Future<void> _fetchDetail() async {
    try {
      final caseId = widget.tipData["id"] ?? widget.tipData["case_id"];
      final bool isGuestHistory = widget.tipData["is_guest_history"] == true;

      late http.Response res;

      if (isGuestHistory) {
        final reporterName =
            widget.tipData["reporter_name"]?.toString() ??
            widget.tipData["payload"]?["reporter_name"]?.toString() ?? "";
        final reporterPhone =
            widget.tipData["reporter_phone"]?.toString() ??
            widget.tipData["payload"]?["reporter_phone"]?.toString() ?? "";

        res = await http.post(
          Uri.parse("${ApiConfig.baseUrl}/case/$caseId/guest-detail/"),
          headers: {"Content-Type": "application/json"},
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
          headers: {"Authorization": "Bearer $token"},
        );
      }

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        _parseDetail(data);
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "상세 정보를 불러올 수 없습니다. (${res.statusCode}) ${utf8.decode(res.bodyBytes)}"),
        ));
      }
    } catch (e) {
      debugPrint("case-detail 에러: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _parseDetail(Map<String, dynamic> data) {
    final typeCode =
        data["type_code"]?.toString().trim().toLowerCase() ?? "";

    if (typeCode != "missing" && typeCode != "tip") {
      setState(() {
        _isLoading = false;
        _detail = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("신고·제보 유형을 확인할 수 없습니다."),
        ),
      );
      return;
    }

    _typeCode = typeCode;

    final rawPermissions = data["permissions"];

    final Map<String, dynamic> permissions =
        rawPermissions is Map
            ? Map<String, dynamic>.from(rawPermissions)
            : <String, dynamic>{};

    _canEdit = permissions["can_edit"] == true;
    final reporter   = (data["reporter"] as Map?) ?? {};
    final photos = (data["photo_items"] as List?) ??
        (data["photos"] as List?) ?? [];

    _displayPhotos = photos
        .map<Map<String, dynamic>>((p) {
          if (p is Map) {
            final m = Map<String, dynamic>.from(p);
            m['image'] = m['url'] ?? m['image_url'] ?? m['photo'] ?? m['file'] ?? m['image'];
            return m;
          }
          return {"image": p.toString()};
        })
        .toList();

    // 실종자 공식 등록 사진 (관리자 비교용)
    final officialRaw = (data["missing_photos"] as List?) ??
        (data["missing_person_photos"] as List?) ??
        (data["official_photos"] as List?) ?? [];
    _missingPersonPhotos = officialRaw
        .map<Map<String, dynamic>>((p) =>
            p is Map ? Map<String, dynamic>.from(p) : {"image": p.toString()})
        .toList();

    final categories = (data["categories"] as Map?) ?? {};

    final reporterName =
        reporter["name"]?.toString() ??
        data["reporter_name"]?.toString() ??
        widget.tipData["reporter_name"]?.toString() ??
        widget.tipData["payload"]?["reporter_name"]?.toString() ?? "정보 없음";

    final reporterPhone =
        reporter["phone"]?.toString() ??
        data["reporter_phone"]?.toString() ??
        widget.tipData["reporter_phone"]?.toString() ??
        widget.tipData["payload"]?["reporter_phone"]?.toString() ?? "정보 없음";

    String typeLabel, name, loc, date, gender, ageMissing;

    if (typeCode == "missing") {
      typeLabel = "실종 신고";
      final info = (data["missing_info"] as Map?) ?? {};
      name       = info["name"]?.toString()              ?? "이름 없음";
      gender     = _genderLabel(info["gender"]?.toString() ?? "");
      ageMissing = info["age_at_missing"] != null ? "${info["age_at_missing"]}세" : "-";
      loc        = info["occurred_location"]?.toString() ?? "위치 정보 없음";
      date       = _formatDateTime(info["occurred_at"]?.toString());

      _physicalCtrl.text = _listToText(categories["신체 특징"]);
      _clothingCtrl.text = _listToText(categories["착의 사항"]);
      _etcCtrl.text      = _listToText(categories["기타 참고 사항"]);

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
      typeLabel = "상세 제보";

      final info = (data["tip_info"] as Map?) ?? {};

      name = info["missing_name"]?.toString() ?? "이름 없음";
      gender = _genderLabel(info["gender"]?.toString());
      ageMissing = "-";

      loc = info["found_location"]?.toString() ?? "위치 정보 없음";

      date = _formatDateTime(info["found_datetime"]?.toString());

      _physicalCtrl.text = _listToText(categories["신체 특징"]);
      _clothingCtrl.text = _listToText(categories["착의 사항"]);
      _etcCtrl.text = _listToText(categories["기타 참고 사항"]);

      _foundLocationCtrl.text = loc;
      _nameCtrl.text = name;
      _selectedGender = info["gender"]?.toString() ?? "";

      final rawFoundAt = info["found_datetime"]?.toString();
      _occDateCtrl.text = rawFoundAt ?? "";

      if (rawFoundAt != null && rawFoundAt.isNotEmpty) {
        try {
          _selectedOccurredAt = DateTime.parse(rawFoundAt).toLocal();
        } catch (_) {}
      }
    }

    setState(() {
      _detail = {
        "type":           typeLabel,
        "name":           name,
        "gender":         gender,
        "age_missing":    ageMissing,
        "loc":            loc,
        "date":           date,
        "reporter_name":  reporterName,
        "reporter_phone": reporterPhone,
        "feature":        _physicalCtrl.text.isNotEmpty ? _physicalCtrl.text : "내용 없음",
        "clothing":       _clothingCtrl.text.isNotEmpty ? _clothingCtrl.text : "내용 없음",
        "etc":            _etcCtrl.text.isNotEmpty      ? _etcCtrl.text      : "내용 없음",
        "photos":         photos,
      };
      _status         = _convertStatus(data["status"]?.toString() ?? "received");
      _originalStatus = _status;
      _isLoading = false;
    });
  }

  String _genderLabel(String? g) {
    final value = g?.trim().toLowerCase() ?? "";

    switch (value) {
      case "male":
      case "m":
      case "남":
      case "남자":
      case "남성":
        return "남성";

      case "female":
      case "f":
      case "여":
      case "여자":
      case "여성":
        return "여성";

      default:
        return "정보 없음";
    }
  }

  String _listToText(dynamic val) {
    if (val == null) return "";
    if (val is List) return val.map((e) => e.toString()).join(", ");
    return val.toString();
  }

  // ── 수정완료 ─────────────────────────────────────────────────────────────
  Future<void> _onEdit() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final token = prefs.getString("access");

      if (token == null || token.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text("로그인이 필요합니다.")));
        return;
      }

      final caseId = widget.tipData["id"] ?? widget.tipData["case_id"];
      final int targetStatus = _status;
      final bool statusChanged = isAdmin && targetStatus != _originalStatus;
      // 일반 사용자는 백엔드의 can_edit 권한에 따라 수정 가능
      if (!isAdmin && !_canEdit) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("현재 상태에서는 수정할 수 없습니다."),
          ),
        );
        return;
      }

      final bool canEditContent = isAdmin || _originalStatus == 0 || _originalStatus == 2;

      bool contentOk = true;
      if (canEditContent) {
        contentOk = await _saveContent(token, caseId, refreshAfterSave: false);
        if (!mounted) return;
        if (!contentOk) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("내용 수정 실패로 상태 변경을 중단했습니다.")));
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("수정이 완료되었습니다.")));
    } catch (e) {
      debugPrint("에러: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("네트워크 오류가 발생했습니다.")));
    }
  }

  Future<bool> _saveContent(String token, dynamic caseId,
      {bool refreshAfterSave = true}) async {
    try {
      final request = http.MultipartRequest(
        "PATCH",
        Uri.parse("${ApiConfig.baseUrl}/case/$caseId/update-case/"),
      );
      request.headers["Authorization"] = "Bearer $token";

      if (_deletedPhotoIds.isNotEmpty) {
        request.fields["delete_photos"] = jsonEncode(_deletedPhotoIds);
      }
      for (final img in _newImages) {
        request.files
            .add(await http.MultipartFile.fromPath("new_photos", img.path));
      }

      if (_typeCode == "tip") {
        request.fields["reported_missing_name"] = _nameCtrl.text;
        if (_selectedGender.isNotEmpty) {
          request.fields["gender"] = _selectedGender;
        }
        final foundDetail = _foundDetailLocCtrl.text.trim();
        request.fields["found_location"] = foundDetail.isNotEmpty
            ? "${_foundLocationCtrl.text.trim()} $foundDetail"
            : _foundLocationCtrl.text.trim();
        if (_selectedOccurredAt != null) {
          request.fields["found_datetime"] =
              _selectedOccurredAt!.toIso8601String();
        } 
        request.fields["physical"]  = _physicalCtrl.text;
        request.fields["clothing"]  = _clothingCtrl.text;
        request.fields["etc"]       = _etcCtrl.text;
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
        if (_selectedOccurredAt != null) {
          request.fields["occurred_at"] =
              _selectedOccurredAt!.toIso8601String();
        }
        request.fields["physical"]    = _physicalCtrl.text;
        request.fields["clothing"]    = _clothingCtrl.text;
        request.fields["description"] = _etcCtrl.text;
      }

      final streamed = await request.send();
      final body = await streamed.stream.bytesToString();
      debugPrint("내용 수정 응답 코드: ${streamed.statusCode}");
      debugPrint("내용 수정 응답 바디: $body");

      if (!mounted) return false;

      if (streamed.statusCode == 200) {
        if (refreshAfterSave) await _fetchDetail();
        if (!mounted) return true;
        setState(() {
          _newImages = [];
          _deletedPhotoIds = [];
        });
        return true;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("내용 수정에 실패했습니다. (${streamed.statusCode}) $body")));
        return false;
      }
    } catch (e) {
      debugPrint("내용 수정 에러: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("내용 수정 중 오류가 발생했습니다.")));
      }
      return false;
    }
  }

  Future<void> _applyStatusChange(
      String token, dynamic caseId, int targetStatus) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final res = await http.patch(
        Uri.parse("${ApiConfig.baseUrl}/case/$caseId/update-status/"),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode({"status": _statusToString(targetStatus)}),
      );

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
              const SnackBar(content: Text("상태가 '확인 중'으로 변경되었습니다.")));
        } else if (targetStatus == 2) {
          nav.pop("completed");
        } else if (targetStatus == 3) {
          messenger.showSnackBar(const SnackBar(
              content: Text("수정 완료 및 제보가 거절되었습니다."),
              backgroundColor: Colors.red));
          nav.pop("rejected");
        } else {
          messenger
              .showSnackBar(const SnackBar(content: Text("수정이 완료되었습니다.")));
        }
      } else {
        setState(() => _status = _originalStatus);
        messenger.showSnackBar(SnackBar(
            content: Text(
                "상태 변경 실패: ${res.statusCode} ${utf8.decode(res.bodyBytes)}")));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = _originalStatus);
      debugPrint("상태 변경 실패: $e");
      messenger.showSnackBar(
          const SnackBar(content: Text("상태 변경 중 오류가 발생했습니다.")));
    }
  }

  // ── 상태 변환 ─────────────────────────────────────────────────────────────
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

  void _updateStatus(int newStatus) => setState(() => _status = newStatus);

  // ── 주소 검색 ─────────────────────────────────────────────────────────────
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

  // ── 발생 일시 선택 ─────────────────────────────────────────────────────────
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
          initial.hour, initial.minute);
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
                      child: const Text("완료")),
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
                      t.hour, t.minute);
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 발견 장소 주소 검색 (tip) ────────────────────────────────────────────
  void _openFoundAddressSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddressSearchPage(
          onSelected: (address) {
            setState(() => _foundLocationCtrl.text = address);
          },
        ),
      ),
    );
  }

  // ── 사진 수정 ─────────────────────────────────────────────────────────────
  Future<void> _addPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) setState(() => _newImages.add(File(picked.path)));
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

  // ── 유틸 ─────────────────────────────────────────────────────────────────
  String _resolveUrl(String raw) =>
      raw.startsWith('http') ? raw : '${ApiConfig.mediaBaseUrl}$raw';

  String _formatDateTime(String? raw) {
    if (raw == null || raw.isEmpty) return "정보 없음";

    try {
      final value = raw.trim();

      DateTime dt;

      final dotPattern = RegExp(
        r'^(\d{4})\.(\d{1,2})\.(\d{1,2})\s+(\d{1,2}):(\d{1,2})',
      );

      final match = dotPattern.firstMatch(value);

      if (match != null) {
        dt = DateTime(
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
          int.parse(match.group(4)!),
          int.parse(match.group(5)!),
        );
      } else {
        dt = DateTime.parse(value).toLocal();
      }

      final ampm = dt.hour < 12 ? "오전" : "오후";
      final displayHour = dt.hour < 12 ? dt.hour : dt.hour - 12;

      return "${dt.year}년 ${dt.month}월 ${dt.day}일 "
          "$ampm $displayHour시 ${dt.minute}분";
    } catch (_) {
      return raw;
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────
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
                  if (_isEditing)
                    _buildDatePicker()
                  else
                    _buildEditableLongInfo(
                      _typeCode == "missing" ? "실종 발생 일시" : "발견 일시",
                      _detail!["date"],
                      _occDateCtrl,
                    ),
                  if (_isEditing)
                    (_typeCode == "missing"
                        ? _buildAddressEditField()
                        : _buildFoundAddressEditField())
                  else
                    _buildEditableLongInfo(
                      _typeCode == "missing" ? "발생 장소" : "발견 장소",
                      _detail!["loc"],
                      _typeCode == "missing"
                          ? _occLocationCtrl
                          : _foundLocationCtrl,
                    ),
                  const SizedBox(height: 6),
                  _buildFeatureBox("신체 특징",     _detail!["feature"],  _physicalCtrl),
                  if (_typeCode == "tip")
                  _buildFeatureBox("착의 사항",     _detail!["clothing"], _clothingCtrl),
                  _buildFeatureBox("기타 참고 사항", _detail!["etc"],      _etcCtrl),
                  const SizedBox(height: 20),
                  _buildReporterSection(),
                  if (isAdmin) ...[
                    const SizedBox(height: 20),
                    _buildPhotoComparisonSection(),
                    const SizedBox(height: 20),
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

  // ── 위젯 ─────────────────────────────────────────────────────────────────
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
                  fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection() {
    final totalCount = _displayPhotos.length + _newImages.length;
    final safeIndex =
        _selectedPhotoIndex.clamp(0, totalCount == 0 ? 0 : totalCount - 1);

    Widget previewChild;
    if (totalCount > 0) {
      if (safeIndex < _displayPhotos.length) {
        final url = _resolveUrl(
            _displayPhotos[safeIndex]["image"]?.toString() ?? '');
        previewChild = Image.network(url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.person, size: 50, color: Colors.white));
      } else {
        final newIdx = safeIndex - _displayPhotos.length;
        previewChild = Image.file(_newImages[newIdx], fit: BoxFit.cover);
      }
    } else {
      previewChild = const Icon(Icons.person, size: 50, color: Colors.white);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 140,
                height: 160,
                color: const Color(0xFFD9E2F3),
                child: previewChild,
              ),
            ),
            Positioned(
              top: 5,
              left: 5,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                color: Colors.white.withValues(alpha: 0.8),
                child: Text(_detail!["type"],
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("첨부 사진",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._displayPhotos.asMap().entries.map((e) {
                    final i = e.key;
                    final url = _resolveUrl(
                        e.value["image"]?.toString() ?? '');
                    return _buildThumbnail(
                      index: i,
                      child: Image.network(url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.person, size: 20)),
                      onDelete:
                          _isEditing ? () => _deleteServerPhoto(i) : null,
                    );
                  }),
                  ..._newImages.asMap().entries.map((e) {
                    final i = _displayPhotos.length + e.key;
                    return _buildThumbnail(
                      index: i,
                      child: Image.file(e.value, fit: BoxFit.cover),
                      onDelete:
                          _isEditing ? () => _deleteNewPhoto(e.key) : null,
                    );
                  }),
                  if (_isEditing)
                    GestureDetector(
                      onTap: _addPhoto,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black12),
                        ),
                        child: const Icon(Icons.add,
                            size: 20, color: Colors.black54),
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
    VoidCallback? onDelete,
  }) {
    final isSelected = _selectedPhotoIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedPhotoIndex = index),
      child: Stack(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade300,
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFFDE14C)
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: ClipOval(child: child),
          ),
          if (onDelete != null)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 10, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGridInfo() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildEditableField("이름", _nameCtrl)),
            const SizedBox(width: 10),
            if (_typeCode == "missing")
              Expanded(
                  child: _buildEditableField("실종 당시 나이", _ageCtrl,
                      keyboardType: TextInputType.number))
            else
              // tip 타입: 성별 수정 가능
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: _isEditing
                        ? Border.all(color: _pointColor, width: 2)
                        : null,
                  ),
                  child: _isEditing
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("성별",
                                style: TextStyle(
                                    fontSize: 12, color: Colors.black54)),
                            const SizedBox(height: 8),
                            Row(children: [
                              _genderOption("남성", "male"),
                              const SizedBox(width: 8),
                              _genderOption("여성", "female"),
                            ]),
                          ],
                        )
                      : Text("성별 : ${_detail!["gender"]}",
                          style: const TextStyle(fontSize: 13)),
                ),
              ),
          ],
        ),
        // missing 타입: 성별 별도 행
        if (_typeCode == "missing") ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: _isEditing
                  ? Border.all(color: _pointColor, width: 2)
                  : null,
            ),
            child: _isEditing
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("성별",
                          style: TextStyle(
                              fontSize: 12, color: Colors.black54)),
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
          color: isSelected ? _pointColor : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: const Color(0xFFF0C800), width: 1.5)
              : Border.all(color: Colors.black12),
        ),
        child: Text(label,
            style: TextStyle(
              fontWeight:
                  isSelected ? FontWeight.bold : FontWeight.normal,
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
            border: Border.all(color: _pointColor, width: 2),
          ),
          child: GestureDetector(
            onTap: _openAddressSearch,
            child: AbsorbPointer(
              child: TextField(
                controller: _occLocationCtrl,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: "주소 검색으로 발생 위치를 선택하세요",
                  hintStyle:
                      TextStyle(fontSize: 13, color: Colors.grey),
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
            border: Border.all(color: _pointColor, width: 2),
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

  Widget _buildFoundAddressEditField() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _pointColor, width: 2),
          ),
          child: GestureDetector(
            onTap: _openFoundAddressSearch,
            child: AbsorbPointer(
              child: TextField(
                controller: _foundLocationCtrl,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: "주소 검색으로 발견 위치를 선택하세요",
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                  labelText: "발견 장소",
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
            border: Border.all(color: _pointColor, width: 2),
          ),
          child: TextField(
            controller: _foundDetailLocCtrl,
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
      final h = dt.hour < 12 ? dt.hour : dt.hour - 12;

      display = "${dt.year}년 ${dt.month}월 ${dt.day}일 "
          "$ampm $h시 ${dt.minute}분";
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
        border: Border.all(color: _pointColor, width: 2),
      ),
      child: GestureDetector(
        onTap: _selectOccurredDate,
        child: Row(
          children: [
            Expanded(
              child: Text(
                "${_typeCode == 'missing' ? '실종 발생 일시' : '발견 일시'} : $display",
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const Icon(
              Icons.edit_calendar_outlined,
              size: 18,
              color: Colors.black45,
            ),
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
            ? Border.all(color: _pointColor, width: 2)
            : null,
      ),
      child: _isEditing
          ? TextField(
              controller: ctrl,
              keyboardType: keyboardType,
              decoration: InputDecoration(
                  labelText: label, border: InputBorder.none),
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
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16)),
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
                ? Border.all(color: _pointColor, width: 2)
                : Border.all(color: Colors.transparent, width: 2),
          ),
          child: _isEditing
              ? TextField(
                  controller: ctrl,
                  maxLines: null,
                  style: const TextStyle(
                      fontSize: 13, color: Colors.black87),
                  decoration: const InputDecoration.collapsed(
                      hintText: "내용을 입력하세요"),
                )
              : Text(content,
                  style: const TextStyle(
                      color: Colors.grey, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildPhotoComparisonSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.compare, color: Colors.blueGrey.shade600, size: 18),
              const SizedBox(width: 6),
              Text(
                '사진 비교',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.blueGrey.shade700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '관리자 전용',
                  style: TextStyle(fontSize: 10, color: Colors.blueGrey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            '실종자 등록 사진',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
          ),
          const SizedBox(height: 8),
          _buildPhotoRow(_missingPersonPhotos, isOfficial: true),
          const SizedBox(height: 16),
          const Text(
            '제보 첨부 사진',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
          ),
          const SizedBox(height: 8),
          _buildPhotoRow(_displayPhotos, isOfficial: false),
        ],
      ),
    );
  }

  Widget _buildPhotoRow(List<Map<String, dynamic>> photos,
      {required bool isOfficial}) {
    if (photos.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black12),
        ),
        child: const Text('사진이 없습니다.',
            style: TextStyle(color: Colors.black45, fontSize: 12)),
      );
    }

    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: photos.length,
        itemBuilder: (context, i) {
          final p = photos[i];
          final raw = p["url"]?.toString() ??
              p["image_url"]?.toString() ??
              p["image"]?.toString() ??
              '';
          final url = raw.startsWith('http')
              ? raw
              : raw.isNotEmpty
                  ? '${ApiConfig.mediaBaseUrl}$raw'
                  : '';
          return GestureDetector(
            onTap: () => showDialog(
              context: context,
              builder: (_) => Dialog(
                backgroundColor: Colors.black,
                insetPadding: const EdgeInsets.all(12),
                child: url.isNotEmpty
                    ? Image.network(url, fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image, color: Colors.white, size: 60))
                    : const Icon(Icons.image_not_supported,
                        color: Colors.white, size: 60),
              ),
            ),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.grey.shade200,
              ),
              clipBehavior: Clip.antiAlias,
              child: url.isNotEmpty
                  ? Image.network(url, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image, color: Colors.black26))
                  : const Icon(Icons.image_not_supported,
                      color: Colors.black26),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReporterSection() {
    final nameLabel    = _typeCode == "tip" ? "제보자 이름"    : "신고자 이름";
    final phoneLabel   = _typeCode == "tip" ? "제보자 전화번호" : "신고자 전화번호";
    final sectionLabel = _typeCode == "tip" ? "제보자 정보"    : "신고자 정보";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(sectionLabel,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold)),
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
          const Row(
            children: [
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
            _statusBtn("접수 중", 0),
            _statusBtn("확인 중", 1),
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
    final textColor   =
        (active && isReject) ? Colors.red.shade800 : Colors.black;

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
            child: Text(label,
                style: TextStyle(
                  fontWeight:
                      active ? FontWeight.bold : FontWeight.normal,
                  color: textColor,
                )),
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
            ? Border.all(color: _pointColor, width: 2)
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
    if (_isGuestHistory) {
      return const SizedBox.shrink();
    }

    if (!isAdmin && !_canEdit) {
      return const SizedBox.shrink();
    }
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
                  _displayPhotos = ((_detail?["photo_items"] as List?)
                      ?? (_detail?["photos"] as List?) ?? [])
                      .map<Map<String, dynamic>>((p) {
                        if (p is Map) {
                          final m = Map<String, dynamic>.from(p);
                          m['image'] = m['url'] ?? m['image_url'] ?? m['photo'] ?? m['file'] ?? m['image'];
                          return m;
                        }
                        return {"image": p.toString()};
                      }).toList();
                });
                _nameCtrl.text        = _detail?["name"] ?? "";
                _ageCtrl.text         = _detail?["age_missing"]
                        ?.toString().replaceAll("세", "") ?? "";
                _occLocationCtrl.text = _detail?["loc"] ?? "";
                _occDetailLocCtrl.text = "";
                _foundDetailLocCtrl.text = "";
                final rawOccAt = _occDateCtrl.text;
                if (rawOccAt.isNotEmpty) {
                  try {
                    _selectedOccurredAt =
                        DateTime.parse(rawOccAt).toLocal();
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
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return InkWell(
      onTap: () => setState(() {
        _originalStatus = _status;
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
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16)),
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
