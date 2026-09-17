import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'report_staus_detail.dart';
import '../config/api_config.dart';
import '../missing/missing_list.dart';
import '../missing/missing_detail.dart';

class ReportStatusTab extends StatefulWidget {
  const ReportStatusTab({super.key});

  @override
  State<ReportStatusTab> createState() => ReportStatusTabState();
}

class ReportStatusTabState extends State<ReportStatusTab> {
  void refresh() => _fetchStatusList();
  List<dynamic> _statusList = [];

  // ✅ 관리자 / 비회원 상태
  bool isAdmin = false;
  bool isGuest = false;
  bool _guestChecked = false;
  int _selectedFilter = 0; // 0=전체 1=접수중 2=확인중 3=신고완료

  // ✅ 비회원 신고 현황 조회 입력값
  final TextEditingController _guestNameCtrl = TextEditingController();
  final TextEditingController _guestPhone1Ctrl =
      TextEditingController(text: "010");
  final TextEditingController _guestPhone2Ctrl = TextEditingController();
  final TextEditingController _guestPhone3Ctrl = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    _fetchStatusList();
  }

  @override
  void dispose() {
    _guestNameCtrl.dispose();
    _guestPhone1Ctrl.dispose();
    _guestPhone2Ctrl.dispose();
    _guestPhone3Ctrl.dispose();
    super.dispose();
  }

  // 🔥 API 호출 + 데이터 변환
  Future<void> _fetchStatusList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("access") ?? "";
      final role = prefs.getString("role") ?? "";
      final bool guest = prefs.getBool("isGuest") ?? token.isEmpty;
      final bool admin = role == "admin";

      if (!mounted) return;

      setState(() {
        isGuest = guest;
        isAdmin = admin;
      });

      // ✅ 비회원이면 바로 조회하지 않고 입력 폼 표시
      if (guest) {
        return;
      }

      final url = admin
          ? Uri.parse("${ApiConfig.baseUrl}/case/reports/admin/")
          : Uri.parse("${ApiConfig.baseUrl}/case/my-reports/");

      final response = await http.get(
        url,
        headers: {
          "Authorization": "Bearer $token",
        },
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final List data = decoded is Map
            ? (decoded['results'] as List? ?? [])
            : (decoded as List? ?? []);

        if (!mounted) return;

        setState(() {
          _statusList = data.map((item) {
            final Map<String, dynamic> caseItem =
                Map<String, dynamic>.from(item as Map);

            final dynamic rawPayload = caseItem["payload"];
            final Map<String, dynamic> payload = rawPayload is Map
                ? Map<String, dynamic>.from(rawPayload)
                : {};

            final photos = caseItem["photo_items"] ?? caseItem["missing_person_photos"] ?? caseItem["photos"];
            final imageUrl = _extractFirstImageUrl(photos);

            final reporterName =
                caseItem["reporter_name"]?.toString() ??
                payload["reporter_name"]?.toString() ??
                "신고자 정보 없음";

            return {
              "id": caseItem["id"] ?? caseItem["case_id"],
              "case_id": caseItem["case_id"] ?? caseItem["id"],
              "type_code": caseItem["type_code"],
              "payload": payload,
              "photos": photos,
              "raw": caseItem,
              "name": payload["name"]?.toString() ??
                  caseItem["reported_missing_name"]?.toString() ??
                  "이름 없음",
              "date": _formatDate(
                caseItem["occr_date"]?.toString() ??
                caseItem["created_at"]?.toString(),
              ),
              "location": caseItem["occr_location"]?.toString() ??
                  payload["occurred_location"]?.toString() ??
                  "위치 없음",
              "status": _convertStatus(
                caseItem["status"]?.toString() ?? "received",
              ),
              "image": imageUrl,
              "reporter_name": reporterName,
            };
          }).toList();
        });

        // 좌표 형태 위치를 주소로 변환
        _geocodeListLocations();
      } else {
        debugPrint("❌ API 실패: ${response.statusCode}");
        debugPrint("❌ 응답 바디: ${utf8.decode(response.bodyBytes)}");
      }
    } catch (e) {
      debugPrint("❌ 에러 발생: $e");
    }
  }

  // msspsn_idntfccd 추출 헬퍼
  String? _extractMissingSeq(Map<String, dynamic> data) {
    // 직접 필드
    for (final k in [
      'msspsn_idntfccd',
      'msspsnn_idntfccd',
      'missing_person_seq',
      'missing_seq',
    ]) {
      final v = data[k]?.toString();

      if (v != null &&
          v.isNotEmpty &&
          v != 'null') {
        return v;
      }
    }

    // 중첩 Map
    final mp = data['missing_person'];

    if (mp is Map) {
      for (final k in [
        'msspsn_idntfccd',
        'msspsnn_idntfccd',
        'seq',
        'id',
      ]) {
        final v = mp[k]?.toString();

        if (v != null &&
            v.isNotEmpty &&
            v != 'null') {
          return v;
        }
      }
    }

    // 사진 URL에서 추출
    for (final key in [
      'missing_person_photos',
      'missing_photos',
      'official_photos',
    ]) {
      final list = data[key];

      if (list is List && list.isNotEmpty) {
        final p = list.first;

        final url = (p is Map
                ? (p['url'] ??
                    p['image_url'] ??
                    p['image'] ??
                    p['photo'] ??
                    p['file'])
                : p)
            ?.toString() ??
            '';

        final m =
            RegExp(r'missing_persons/([^/]+)/')
                .firstMatch(url);

        if (m != null) {
          return m.group(1);
        }
      }
    }

    return null;
  }

  // 완료된 신고 → msspsn_idntfccd 추출 후 실종자 상세로 이동
  Future<void> _openCompletedCase(Map<String, dynamic> item) async {
    final raw = (item["raw"] as Map?)?.cast<String, dynamic>() ?? item;

    // 1) 이미 가진 데이터에서 추출
    String? missingSeq = _extractMissingSeq(raw);

    if (missingSeq != null && missingSeq.isNotEmpty) {
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => MissingDetailPage(missingSeq: missingSeq!),
        ));
      }
      return;
    }

    // 2) raw에 없으면 API 재조회
    final caseId = item["id"] ?? item["case_id"];
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString("access") ?? "";

    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/case/$caseId/case-detail/"),
        headers: {"Authorization": "Bearer $token"},
      );
      final body = utf8.decode(res.bodyBytes);

      if (!mounted) return;

      if (res.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        missingSeq = _extractMissingSeq(data);
        if (missingSeq != null && missingSeq.isNotEmpty) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => MissingDetailPage(missingSeq: missingSeq!),
          ));
          return;
        }
      }
      
    } catch (e) {
      debugPrint("완료 케이스 이동 실패: $e");
    }

    // 3) 끝내 못 찾으면 실종자 목록으로 fallback
    if (mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const MissingListPage()));
    }
  }

  Future<void> _fetchGuestReports() async {
    final name = _guestNameCtrl.text.trim();
    final phone =
        "${_guestPhone1Ctrl.text.trim()}${_guestPhone2Ctrl.text.trim()}${_guestPhone3Ctrl.text.trim()}";

    if (name.isEmpty ||
        _guestPhone1Ctrl.text.trim().isEmpty ||
        _guestPhone2Ctrl.text.trim().isEmpty ||
        _guestPhone3Ctrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("성명과 연락처를 모두 입력해 주세요.")),
      );
      return;
    }

    try {
      final response = await http.post(
        Uri.parse("${ApiConfig.baseUrl}/case/guest-history/"),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "reporter_name": name,
          "reporter_phone": phone,
        }),
      );

      debugPrint("비회원 신고 조회 응답 코드: ${response.statusCode}");
      debugPrint("비회원 신고 조회 응답 바디: ${utf8.decode(response.bodyBytes)}");

      if (!mounted) return;

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

        final List results = data["results"] ?? [];

        setState(() {
          _guestChecked = true;

          _statusList = results.map((item) {
            final Map<String, dynamic> caseItem =
                Map<String, dynamic>.from(item as Map);

            final Map<String, dynamic> feature =
                Map<String, dynamic>.from(caseItem["feature"] ?? {});

            final photos = caseItem["photo_items"] ?? caseItem["missing_person_photos"] ?? caseItem["photos"];
            final imageUrl = _extractFirstImageUrl(photos);

            final payload = {
              "name": caseItem["reported_missing_name"],
              "reporter_name": caseItem["reporter_name"],
              "reporter_phone": caseItem["reporter_phone"],
              "occurred_location": caseItem["occr_location"],
              "occurred_at": caseItem["occr_date"],
              "description": caseItem["description"],
              "physical": feature["physical"],
              "clothing": feature["clothing"],
              "health": feature["health"],
              "behavior": feature["behavior"],
              "etc": feature["etc"],
            };

            return {
              "id": caseItem["case_id"],
              "case_id": caseItem["case_id"],
              "type_code": caseItem["type_code"],
              "payload": payload,
              "photos": photos,

              // ✅ 비회원 상세 조회 분기용
              "is_guest_history": true,
              "reporter_name": caseItem["reporter_name"]?.toString() ?? name,
              "reporter_phone": caseItem["reporter_phone"]?.toString() ?? phone,

              "raw": {
                ...caseItem,
                "id": caseItem["case_id"],
                "payload": payload,

                // ✅ raw로 넘어가도 비회원 상세 조회 가능하게 넣기
                "is_guest_history": true,
                "reporter_name": caseItem["reporter_name"]?.toString() ?? name,
                "reporter_phone": caseItem["reporter_phone"]?.toString() ?? phone,
              },

              "name": caseItem["reported_missing_name"]?.toString() ?? "이름 없음",
              "date": _formatDate(
                caseItem["occr_date"]?.toString() ??
                caseItem["created_at"]?.toString(),
              ),
              "location": caseItem["occr_location"]?.toString() ?? "위치 없음",
              "status": _convertStatus(caseItem["status"]?.toString() ?? "received"),
              "image": imageUrl,
            };
          }).toList();
        });
      } else {
        final body = utf8.decode(response.bodyBytes);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("신고 내역을 조회할 수 없습니다. (${response.statusCode}) $body"),
          ),
        );
      }
    } catch (e) {
      debugPrint("비회원 신고 조회 에러: $e");

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("조회 중 오류가 발생했습니다.")),
      );
    }
  }

  // 목록의 location 필드가 "lat,lng" 좌표면 주소로 변환
  Future<void> _geocodeListLocations() async {
    for (int i = 0; i < _statusList.length; i++) {
      final loc = _statusList[i]["location"]?.toString() ?? "";
      final parts = loc.split(',');
      if (parts.length != 2) continue;
      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());
      if (lat == null || lng == null) continue;

      try {
        final res = await http.get(
          Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&accept-language=ko',
          ),
          headers: {'User-Agent': 'dasibom-app'},
        );
        if (!mounted) return;
        if (res.statusCode == 200) {
          final addr = (jsonDecode(res.body)['address'] as Map<String, dynamic>);
          final addrParts = <String>[
            (addr['city'] ?? addr['state'] ?? '') as String,
            (addr['city_district'] ?? addr['suburb'] ?? addr['quarter'] ?? addr['neighbourhood'] ?? '') as String,
            (addr['road'] ?? '') as String,
          ].where((s) => s.isNotEmpty).toList();
          final address = addrParts.join(' ');
          if (address.isNotEmpty) {
            setState(() => _statusList[i]["location"] = address);
          }
        }
      } catch (_) {}

      // Nominatim 1초 제한 준수
      await Future.delayed(const Duration(milliseconds: 1100));
    }
  }

  String? _extractFirstImageUrl(dynamic photos) {
    if (photos is! List || photos.isEmpty) return null;
    final first = photos[0];
    String? path;
    if (first is Map) {
      path = first["url"]?.toString()
          ?? first["image_url"]?.toString()
          ?? first["image"]?.toString()
          ?? first["photo"]?.toString()
          ?? first["file"]?.toString();
    } else if (first is String && first.isNotEmpty) {
      path = first;
    }
    if (path == null || path.isEmpty) return null;
    return path.startsWith("http") ? path : "${ApiConfig.mediaBaseUrl}$path";
  }

  List<dynamic> get _filteredList {
    if (_selectedFilter == 0) return _statusList;
    final targetStatus = _selectedFilter - 1;
    return _statusList.where((e) => e['status'] == targetStatus).toList();
  }

  // 🔄 상태 변환
  int _convertStatus(String status) {
    switch (status) {
      case "received":  return 0;
      case "reviewing": return 1;
      case "completed": return 2;
      case "rejected":  return 3;
      default:          return 0;
    }
  }

  // 🧾 날짜 포맷
  String _formatDate(String? date) {
    if (date == null || date.isEmpty) return "날짜 없음";
    try {
      final dt = DateTime.parse(date).toLocal();
      final y  = dt.year.toString();
      final m  = dt.month.toString().padLeft(2, '0');
      final d  = dt.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    } catch (_) {
      if (date.length >= 10) return date.substring(0, 10);
      return date;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isGuest && !_guestChecked) {
      return _buildGuestLookupForm();
    }

    final filtered = _filteredList;

    return Column(
      children: [
        _buildFilterBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchStatusList,
            child: filtered.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 120),
                      const Icon(Icons.folder_open_outlined, size: 54, color: Colors.black26),
                      const SizedBox(height: 14),
                      Center(
                        child: Text(
                          isGuest ? "조회된 신고 내역이 없습니다" : "신고 내역이 없습니다",
                          style: const TextStyle(fontSize: 15, color: Colors.black45),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _buildStatusCard(item);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    const labels = ['전체', '접수중', '확인중', '신고완료'];
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

  // --- 🧩 카드 UI ---
  Widget _buildGuestLookupForm() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFDF9EB),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 42, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 상단 아이콘
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.manage_search_rounded,
                color: Color(0xFFF2C94C),
                size: 38,
              ),
            ),

            const SizedBox(height: 22),

            const Text(
              "신고 현황 조회",
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Color(0xFF3A2A1A),
                letterSpacing: -0.8,
              ),
            ),

            const SizedBox(height: 14),

            const Text(
              "비회원으로 신고하신 경우\n신고 시 입력한 정보를 입력해 주세요.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFF777777),
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 34),

            // 입력 카드
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE8E0D2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGuestNameRow(),

                  const SizedBox(height: 22),

                  _buildGuestPhoneRow(),

                  const SizedBox(height: 28),

                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _fetchGuestReports,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFDF60),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        "조회하기",
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7D6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Color(0xFF8A6D1D),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "신고 당시 입력한 성명과 연락처가 일치해야 신고 현황을 조회할 수 있습니다.",
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF7A6A3A),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuestNameRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(
              Icons.person_outline_rounded,
              size: 18,
              color: Color(0xFF3A2A1A),
            ),
            SizedBox(width: 6),
            Text(
              "성명",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: Color(0xFF3A2A1A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _guestNameCtrl,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            hintText: "신고자 이름을 입력해 주세요",
            hintStyle: const TextStyle(
              fontSize: 14,
              color: Color(0xFFB0B0B0),
            ),
            filled: true,
            fillColor: const Color(0xFFFFFCF3),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 15,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE5DDCB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(
                color: Color(0xFFF2C94C),
                width: 1.8,
              ),
            ),
          ),
        ),
      ],
    );
  }

Widget _buildGuestPhoneRow() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Row(
        children: [
          Icon(
            Icons.phone_iphone_rounded,
            size: 18,
            color: Color(0xFF3A2A1A),
          ),
          SizedBox(width: 6),
          Text(
            "연락처",
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: Color(0xFF3A2A1A),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),

      Row(
        children: [
          SizedBox(
            width: 82,
            child: _buildPhoneInput(_guestPhone1Ctrl, "010"),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              "-",
              style: TextStyle(
                color: Color(0xFF777777),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: _buildPhoneInput(_guestPhone2Ctrl, "0000"),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              "-",
              style: TextStyle(
                color: Color(0xFF777777),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: _buildPhoneInput(_guestPhone3Ctrl, "0000"),
          ),
        ],
      ),
    ],
  );
}

  Widget _buildPhoneInput(
    TextEditingController controller,
    String hint,
  ) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.phone,
      textAlign: TextAlign.center,
      maxLength: 4,
      decoration: InputDecoration(
        counterText: "",
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 14,
          color: Color(0xFFB0B0B0),
        ),
        filled: true,
        fillColor: const Color(0xFFFFFCF3),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 15,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFE5DDCB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: Color(0xFFF2C94C),
            width: 1.8,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(Map<String, dynamic> item) {
    final bool isRejected  = item['status'] == 3;
    final bool isCompleted = item['status'] == 2;

    double progress = item['status'] == 0
        ? 0.05
        : item['status'] == 1
            ? 0.5
            : item['status'] == 2
                ? 1.0
                : 0.0;

    return GestureDetector(
      onTap: () async {
        // 신고 완료 케이스는 실종자 상세 페이지로 바로 이동
        if (isCompleted) {
          await _openCompletedCase(item);
          return;
        }

        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReportCaseDetailPage(
              caseData: isGuest ? item : (item["raw"] ?? item),
            ),
          ),
        );

        if (!mounted) return;
        _fetchStatusList();
        if (result == "completed") {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MissingListPage()),
          );
        }
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
          borderRadius: BorderRadius.circular(15),
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
                    Text("신고가 거절되었습니다",
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
                    Text("신고가 완료되었습니다",
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
                // 이미지
                Column(
                  children: [
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 100,
                            height: 100,
                            color: Colors.white,
                            child: item['image'] != null
                                ? ColorFiltered(
                                    colorFilter: isRejected
                                        ? const ColorFilter.matrix([
                                            0.2126, 0.7152, 0.0722, 0, 0,
                                            0.2126, 0.7152, 0.0722, 0, 0,
                                            0.2126, 0.7152, 0.0722, 0, 0,
                                            0,      0,      0,      1, 0,
                                          ])
                                        : const ColorFilter.mode(
                                            Colors.transparent,
                                            BlendMode.multiply,
                                          ),
                                    child: Image.network(
                                      item['image'],
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) =>
                                          const Icon(Icons.person, size: 50),
                                    ),
                                  )
                                : const Icon(Icons.person, size: 50),
                          ),
                        ),
                        if (isRejected)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Center(
                                child: Icon(Icons.block, color: Colors.red, size: 36),
                              ),
                            ),
                          ),
                      ],
                    ),

                    // ✅ 관리자일 때만 신고자 이름 표시
                    if (isAdmin) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: 100,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              "신고자",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.black45,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item["reporter_name"] ?? "정보 없음",
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
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: 16),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildInfoRow("실종자 이름", item['name']),
                      _buildInfoRow("실종 일시", item['date']),
                      _buildInfoRow("실종 위치", item['location']),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            _BlinkingProgressBar(
                status: item['status'], progress: progress),
          ],
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
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold)),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 2),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(value,
                style:
                    const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
        ],
      ),
    );
  }
}

class _BlinkingProgressBar extends StatefulWidget {
  final int status;
  final double progress;
  const _BlinkingProgressBar({required this.status, required this.progress});

  @override
  State<_BlinkingProgressBar> createState() => _BlinkingProgressBarState();
}

class _BlinkingProgressBarState extends State<_BlinkingProgressBar> {
  bool _visible = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.status == 0) {
      _timer = Timer.periodic(const Duration(milliseconds: 800), (_) {
        if (mounted) setState(() => _visible = !_visible);
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
            Text(
              "거절됨",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade600,
              ),
            ),
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
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFDE14C)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _statusText("접수중", widget.status >= 0),
            _statusText("확인중", widget.status >= 1),
            _statusText("신고 완료", widget.status >= 2),
          ],
        ),
      ],
    );
  }

  Widget _statusText(String text, bool isActive) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
        color: isActive ? Colors.black : Colors.grey,
      ),
    );
  }
}