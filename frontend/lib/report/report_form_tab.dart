import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async'; // ✅ 추가
import 'package:http/http.dart' as http; // ✅ 추가
import '../config/api_config.dart'; // ✅ 추가
import 'dart:io'; // ✅ File 타입 사용
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

class ReportFormTab extends StatefulWidget {
  final Function()? onSuccess; // 🔥 추가

  const ReportFormTab({
    super.key,
    this.onSuccess, // 🔥 추가
  });
  
  @override
  State<ReportFormTab> createState() => _ReportFormTabState();
}

class _ReportFormTabState extends State<ReportFormTab> {
  

  Widget _buildTextFieldBox({
    required TextEditingController controller,
    required double height,
    required Color color,
    String? hint,
  }) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(border: InputBorder.none, hintText: hint,),
      ),
    );
  }

  // 보호자 피보호자 선택
  bool _isGuardian = false;
  bool _showGuardianSelector = false;
  List<Map<String, dynamic>> _guardianProfiles = [];
  Map<String, dynamic>? _selectedGuardianProfile;

  // 뱃지 위치 자동완성
  bool _badgeLocationUsed = false;
  DateTime? _badgeLocationTimestamp;

  // 1. 수많은 컨트롤러들 (일부 생략, 필요시 추가)
  DateTime _selectedDateTime = DateTime.now();
  File? _selectedImage; // 실종자 대표 사진
  List<File> _personPhotos = []; // 실종자 사진 (선택, 최대 5장)
  List<File?> _parentPhotos = [null, null]; // 부모 정면 사진 2슬롯 (실종예방등록과 동일)

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _ageCtrl = TextEditingController();
  final TextEditingController _rrnFrontCtrl = TextEditingController();
  final TextEditingController _rrnBackCtrl = TextEditingController();
  final TextEditingController _reporterNameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();
  final TextEditingController _reporterRrnFrontCtrl = TextEditingController(); // ✅ 추가
  final TextEditingController _reporterRrnBackCtrl = TextEditingController();
  final TextEditingController _locCtrl = TextEditingController();   // ✅ 추가
  final TextEditingController _charCtrl = TextEditingController();  // ✅ 추가
  final TextEditingController _clothCtrl = TextEditingController(); // ✅ 추가
  final TextEditingController _descCtrl = TextEditingController();  // ✅ 추가 (신고 내용)
  final TextEditingController _detailLocCtrl = TextEditingController();
  bool _isGettingLocation = false;

  String? _verificationId;

  bool _isAgreed = false;
  int _timerSeconds = 0;
  Timer? _timer;
  bool _isVerified = false;
  bool isLoggedIn = false;
  String _loggedInName = "";
  String _loggedInPhone = "";
  bool _serviceAgree = false;
  bool _locationAgree = false;
  bool _privacyAgree = false;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final token   = prefs.getString('access');
    final isGuest = prefs.getBool('isGuest') ?? true;

    if (isGuest || token == null || token.isEmpty) {
      if (mounted) setState(() => isLoggedIn = false);
      return;
    }

    // SharedPreferences에서 role을 즉시 읽어 선택 화면을 바로 표시
    final savedRole = (prefs.getString('role') ?? '').toLowerCase();
    if (savedRole == 'guardian') {
      setState(() {
        isLoggedIn = true;
        _isGuardian = true;
        _showGuardianSelector = true;
      });
      _loadGuardianProfiles(token);  // 비동기로 프로필 로드 (await 없이)
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
          isLoggedIn      = true;
          _loggedInName   = person["name"]?.toString()  ?? "";
          _loggedInPhone  = person["phone"]?.toString() ?? "";
          _reporterNameCtrl.text = _loggedInName;
          _phoneCtrl.text        = _loggedInPhone;
        });
      } else {
        if (!_isGuardian) setState(() => isLoggedIn = false);
      }
    } catch (e) {
      debugPrint("사용자 정보 로드 실패: $e");
    }
  }

  Future<void> _loadGuardianProfiles(String token) async {
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/person/my-wards/simple/"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final List rawList = decoded is List
            ? decoded
            : decoded is Map && decoded['results'] is List
                ? decoded['results'] as List
                : [];
        final profiles = rawList.map<Map<String, dynamic>>((e) {
          final item = Map<String, dynamic>.from(e as Map);
          final person = item['missing_person'] is Map
              ? Map<String, dynamic>.from(item['missing_person'])
              : item['protected_person'] is Map
                  ? Map<String, dynamic>.from(item['protected_person'])
                  : item['person'] is Map
                      ? Map<String, dynamic>.from(item['person'])
                      : <String, dynamic>{};
          final merged = {...item, ...person};
          return merged;
        }).toList();
        setState(() {
          _guardianProfiles = profiles;
          // 이미 프로필 선택 완료된 경우 selector 다시 켜지지 않도록
          if (_selectedGuardianProfile == null) {
            _showGuardianSelector = profiles.isNotEmpty;
          }
        });
      } else {
        debugPrint("🔍 피보호자 API 실패: ${res.statusCode} - ${res.body}");
      }
    } catch (e) {
      debugPrint("피보호자 목록 로드 실패: $e");
    }
  }

  void _selectGuardianProfile(Map<String, dynamic> profile) {
    final name = profile['name']?.toString() ?? '';
    final genderRaw = (profile['gender'] ?? '')?.toString().toLowerCase() ?? '';
    final isFemale = genderRaw == 'female' || genderRaw == 'f'
        || genderRaw == '여' || genderRaw == '여성' || genderRaw == '여자';
    final ageStr = (profile['age'] ?? profile['current_age'])?.toString() ?? '';

    final descParts = <String>[
      profile['note']?.toString() ?? '',
      profile['physical_feature']?.toString() ?? '',
      profile['health_info']?.toString() ?? '',
    ].where((s) => s.isNotEmpty).toList();

    _nameCtrl.text = name;
    _ageCtrl.text = ageStr;
    _descCtrl.text = descParts.join(', ');

    // category_label이 있으면 바로 사용
    final categoryLabel = profile['category_label']?.toString() ?? '';
    final validTargets = [
      "정상아동(18세 미만)", "지적장애인", "시설보호무연고자", "치매질환자",
      "지적 장애인(18세 미만)", "가출인", "지적장애인(18세 이상)", "불상(기타)"
    ];
    final resolvedCategory = validTargets.contains(categoryLabel)
        ? categoryLabel
        : _selectedTarget;

    setState(() {
      _selectedGender = isFemale ? 1 : 0;
      _selectedHeight   = _mapHeight(profile['height']?.toString() ?? '');
      _selectedWeight   = _mapWeight(profile['weight']?.toString() ?? '');
      _selectedBody     = _mapBodyType(profile['body_type']?.toString() ?? '');
      _selectedFace     = _mapFaceType(profile['face_type']?.toString() ?? '');
      _selectedHairCol  = _mapHairColor(profile['hair_color']?.toString() ?? '');
      _selectedHairType = _mapHairStyle(profile['hair_style']?.toString() ?? '');
      _selectedGuardianProfile = profile;
      _showGuardianSelector = false;
      _selectedTarget = resolvedCategory;
    });

    // latest_location: Map이면 address 우선 사용, 없으면 lat/lng 역지오코딩
    final latestLoc = profile['latest_location'];
    if (latestLoc is Map) {
      final address = latestLoc['address']?.toString().trim() ?? '';
      if (address.isNotEmpty && address != 'null') {
        final rawTs = latestLoc['timestamp']?.toString() ?? '';
        setState(() {
          _locCtrl.text = address;
          _badgeLocationUsed = true;
          try {
            _badgeLocationTimestamp =
                rawTs.isNotEmpty ? DateTime.parse(rawTs).toLocal() : null;
          } catch (_) {
            _badgeLocationTimestamp = null;
          }
        });
      } else {
        final lat = latestLoc['lat'];
        final lng = latestLoc['lng'];
        if (lat != null && lng != null) {
          _fillLocationFromString('$lat,$lng');
        }
      }
    } else {
      final deviceCode = _getDeviceCode(profile);
      if (deviceCode != null) {
        _fetchBadgeLocationForReport(deviceCode);
      }
    }

    // 사진 URL 다운로드 (main_photo 우선, 없으면 photo)
    final photoUrl = profile['main_photo']?.toString().isNotEmpty == true
        ? profile['main_photo'].toString()
        : profile['photo']?.toString() ?? '';
    if (photoUrl.isNotEmpty) {
      _downloadAndSetPhoto(photoUrl);
    }

    // 주민번호: prevention_registration_id로 상세 API 호출 (rrn_front/back만 사용)
    final regId = profile['prevention_registration_id'];
    if (regId != null) {
      _fetchRrnFromRegistration(regId.toString(), skipCategory: categoryLabel.isNotEmpty);
    }
  }

  String? _getDeviceCode(Map<String, dynamic> profile) {
    final device = profile['device'];
    if (device is Map) {
      for (final key in ['device_uid', 'device_code', 'uid', 'code']) {
        final v = device[key]?.toString().trim();
        if (v != null && v.isNotEmpty && v != 'null') return v;
      }
    }
    for (final key in ['device_code', 'deviceCode', 'badge_code', 'gps_device_code', 'device_uid']) {
      final v = profile[key]?.toString().trim();
      if (v != null && v.isNotEmpty && v != 'null') return v;
    }
    return null;
  }

  Future<void> _fetchBadgeLocationForReport(String deviceCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access') ?? '';
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/gps/latest/?device_code=${Uri.encodeComponent(deviceCode)}'),
        headers: {if (token.isNotEmpty) 'Authorization': 'Bearer $token'},
      );
      if (!mounted || res.statusCode != 200) return;

      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) return;

      final lat = double.tryParse((decoded['lat'] ?? decoded['latitude'])?.toString() ?? '');
      final lng = double.tryParse((decoded['lng'] ?? decoded['longitude'])?.toString() ?? '');
      if (lat == null || lng == null) return;

      final rawTs = decoded['timestamp']?.toString()
          ?? decoded['created_at']?.toString()
          ?? decoded['recorded_at']?.toString()
          ?? '';
      DateTime timestamp;
      try {
        timestamp = rawTs.isNotEmpty ? DateTime.parse(rawTs).toLocal() : DateTime.now();
      } catch (_) {
        timestamp = DateTime.now();
      }

      // 역지오코딩
      final geoRes = await http.get(
        Uri.parse('https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&accept-language=ko'),
        headers: {'User-Agent': 'dasibom-app'},
      );
      if (!mounted) return;

      String address = '';
      if (geoRes.statusCode == 200) {
        final geoData = jsonDecode(geoRes.body);
        final addr = geoData['address'] as Map<String, dynamic>;
        final parts = <String>[
          (addr['city'] ?? addr['state'] ?? '') as String,
          (addr['city_district'] ?? addr['suburb'] ?? addr['quarter'] ?? addr['neighbourhood'] ?? '') as String,
          (addr['road'] ?? '') as String,
        ].where((s) => s.isNotEmpty).toList();
        address = parts.join(' ');
      }

      if (address.isNotEmpty && mounted) {
        setState(() {
          _locCtrl.text = address;
          _badgeLocationUsed = true;
          _badgeLocationTimestamp = timestamp;
        });
      }
    } catch (e) {
      debugPrint('뱃지 위치 조회 실패: $e');
    }
  }

  Future<void> _fillLocationFromString(String value) async {
    debugPrint('★★★ [location] _fillLocationFromString 호출: "$value"');
    final parts = value.split(',');
    if (parts.length == 2) {
      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());
      if (lat != null && lng != null) {
        try {
          final geoRes = await http.get(
            Uri.parse(
              'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&accept-language=ko',
            ),
            headers: {'User-Agent': 'dasibom-app'},
          );
          if (!mounted) return;
          debugPrint('★★★ [location] Nominatim 코드: ${geoRes.statusCode}');
          if (geoRes.statusCode == 200) {
            final geoData = jsonDecode(geoRes.body);
            debugPrint('★★★ [location] Nominatim 응답: ${geoData['display_name']}');
            final addr = geoData['address'] as Map<String, dynamic>;
            final addrParts = <String>[
              (addr['city'] ?? addr['state'] ?? '') as String,
              (addr['city_district'] ?? addr['suburb'] ?? addr['quarter'] ?? addr['neighbourhood'] ?? '') as String,
              (addr['road'] ?? '') as String,
            ].where((s) => s.isNotEmpty).toList();
            final address = addrParts.join(' ');
            if (address.isNotEmpty) {
              setState(() => _locCtrl.text = address);
              return;
            }
          }
        } catch (_) {}
        // 역지오코딩 실패 시 필드를 비워둠 (좌표 원문 노출 방지)
        return;
      }
    }
    // 좌표가 아닌 주소 문자열이면 바로 사용
    if (mounted) setState(() => _locCtrl.text = value);
  }

  String _formatBadgeTimestamp() {
    final ts = _badgeLocationTimestamp;
    if (ts == null) return '';
    return '${ts.year}.${ts.month.toString().padLeft(2, '0')}.${ts.day.toString().padLeft(2, '0')} '
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';
  }

  bool _isBadgeLocationOld() {
    final ts = _badgeLocationTimestamp;
    if (ts == null) return false;
    return DateTime.now().difference(ts).inMinutes > 30;
  }

  String _badgeTimeAgoStr() {
    final ts = _badgeLocationTimestamp;
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    if (h > 0) return '$h시간 $m분';
    return '$m분';
  }

  Future<void> _downloadAndSetPhoto(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final ext = url.contains('.png') ? 'png' : 'jpg';
        final tmpDir = await getTemporaryDirectory();
        final tempFile = File(
          '${tmpDir.path}/ward_photo_${DateTime.now().millisecondsSinceEpoch}.$ext',
        );
        await tempFile.writeAsBytes(response.bodyBytes);
        if (mounted) setState(() => _selectedImage = tempFile);
      }
    } catch (e) {
      debugPrint('사진 다운로드 실패: $e');
    }
  }

  Future<File?> _downloadPhotoToFile(String url, String suffix) async {
    try {
      final fullUrl = url.startsWith('http') ? url : '${ApiConfig.baseUrl}$url';
      final response = await http.get(Uri.parse(fullUrl));
      if (response.statusCode != 200) return null;
      final ext = url.contains('.png') ? 'png' : 'jpg';
      final tmpDir = await getTemporaryDirectory();
      final tempFile = File(
        '${tmpDir.path}/reg_photo_${suffix}_${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await tempFile.writeAsBytes(response.bodyBytes);
      return tempFile;
    } catch (e) {
      debugPrint('사진 다운로드 실패($suffix): $e');
      return null;
    }
  }

  String _extractPhotoUrl(Map<String, dynamic> photo) {
    for (final key in ['url', 'image_url', 'image', 'photo', 'file']) {
      final v = photo[key]?.toString() ?? '';
      if (v.isNotEmpty && v != 'null') return v;
    }
    return '';
  }

  Future<void> _fetchRrnFromRegistration(String regId, {bool skipCategory = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access');
      if (token == null) return;
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/prevention-registrations/$regId/'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final front    = data['rrn_front']?.toString() ?? '';
        final back     = data['rrn_back']?.toString()  ?? '';
        final category = data['category']?.toString()  ?? '';

        final validTargets = [
          "정상아동(18세 미만)", "지적장애인", "시설보호무연고자", "치매질환자",
          "지적 장애인(18세 미만)", "가출인", "지적장애인(18세 이상)", "불상(기타)"
        ];

        setState(() {
          if (front.isNotEmpty || back.isNotEmpty) {
            _rrnFrontCtrl.text = front;
            _rrnBackCtrl.text  = back;
          }
          if (!skipCategory && category.isNotEmpty && validTargets.contains(category)) {
            _selectedTarget = category;
          }
        });

        // ── 등록된 사진 불러오기 ──
        final rawPhotos = (data['photo_items'] as List?) ?? (data['photos'] as List?) ?? [];
        final List<File> personFiles = [];
        File? parent1File;
        File? parent2File;

        for (final p in rawPhotos) {
          if (p is! Map) continue;
          final photo = Map<String, dynamic>.from(p);
          final photoType = photo['photo_type']?.toString() ?? '';
          final url = _extractPhotoUrl(photo);
          if (url.isEmpty) continue;

          if (['full_body', 'face', 'left_side', 'right_side'].contains(photoType)) {
            if (personFiles.length < 5) {
              final f = await _downloadPhotoToFile(url, 'person_$photoType');
              if (f != null) personFiles.add(f);
            }
          } else if (photoType == 'parent1_face') {
            parent1File = await _downloadPhotoToFile(url, 'parent1');
          } else if (photoType == 'parent2_face') {
            parent2File = await _downloadPhotoToFile(url, 'parent2');
          }
        }

        if (!mounted) return;
        setState(() {
          if (personFiles.isNotEmpty) _personPhotos = personFiles;
          if (parent1File != null) _parentPhotos[0] = parent1File;
          if (parent2File != null) _parentPhotos[1] = parent2File;
        });
      }
    } catch (e) {
      debugPrint('주민번호 조회 실패: $e');
    }
  }

  String _mapHeight(String v) {
    if (v.isEmpty) return '알 수 없음';
    const opts = ['140cm 미만', '140~150cm', '150~160cm', '160~170cm', '170~180cm', '180cm 이상'];
    if (opts.contains(v)) return v;
    if (v.contains('150cm 미만') || (v.contains('140') && !v.contains('150'))) return '140cm 미만';
    if (v.contains('160cm대') || (v.contains('150') && v.contains('160'))) return '150~160cm';
    if (v.contains('170cm대') || (v.contains('160') && v.contains('170'))) return '160~170cm';
    if (v.contains('180')) return '170~180cm';
    return '알 수 없음';
  }

  String _mapWeight(String v) {
    if (v.isEmpty) return '알 수 없음';
    const opts = ['40kg대', '50kg대', '60kg대'];
    if (opts.contains(v)) return v;
    if (v.contains('40')) return '40kg대';
    if (v.contains('50')) return '50kg대';
    if (v.contains('60')) return '60kg대';
    return '알 수 없음';
  }

  String _mapBodyType(String v) {
    if (v.isEmpty) return '알 수 없음';
    const opts = ['알 수 없음', '비만', '건장', '보통', '왜소', '특이체형', '기타'];
    if (opts.contains(v)) return v;
    if (v.contains('마른') || v.contains('왜소')) return '왜소';
    if (v.contains('비만') || v.contains('뚱') || v.contains('통통')) return '비만';
    if (v.contains('건장') || v.contains('근육')) return '건장';
    if (v.contains('보통')) return '보통';
    return '알 수 없음';
  }

  String _mapFaceType(String v) {
    if (v.isEmpty) return '알 수 없음';
    const opts = ['알 수 없음', '삼각형', '역삼각형', '계란형', '사각형', '둥근형', '갸름한형', '기타'];
    if (opts.contains(v)) return v;
    if (v.contains('각진') || v.contains('사각')) return '사각형';
    if (v.contains('역삼각')) return '역삼각형';
    if (v.contains('삼각')) return '삼각형';
    if (v.contains('계란') || v.contains('달걀')) return '계란형';
    if (v.contains('둥근') || v.contains('원형')) return '둥근형';
    if (v.contains('갸름')) return '갸름한형';
    return '알 수 없음';
  }

  String _mapHairColor(String v) {
    if (v.isEmpty) return '알 수 없음';
    const opts = ['알 수 없음', '흑색', '백색', '반백', '갈색', '염색', '기타'];
    if (opts.contains(v)) return v;
    if (v.contains('검') || v.contains('흑')) return '흑색';
    if (v.contains('흰') || v.contains('백')) return '백색';
    if (v.contains('반백')) return '반백';
    if (v.contains('갈')) return '갈색';
    if (v.contains('염색')) return '염색';
    return '알 수 없음';
  }

  String _mapHairStyle(String v) {
    if (v.isEmpty) return '알 수 없음';
    const opts = ['알 수 없음', '삭발', '대머리', '긴머리', '곱슬긴머리', '단발머리', '커트머리', '스포츠형', '짧은머리(생머리)', '긴머리(생머리)', '짧은머리(퍼머)', '긴머리(퍼머)', '묶음머리', '기타'];
    if (opts.contains(v)) return v;
    if (v.contains('삭발')) return '삭발';
    if (v.contains('대머리')) return '대머리';
    if (v.contains('짧은') && v.contains('퍼머')) return '짧은머리(퍼머)';
    if (v.contains('긴') && v.contains('퍼머')) return '긴머리(퍼머)';
    if (v.contains('짧은') || v.contains('단발')) return '짧은머리(생머리)';
    if (v.contains('묶음')) return '묶음머리';
    if (v.contains('곱슬')) return '곱슬긴머리';
    if (v.contains('중간')) return '커트머리';
    if (v.contains('긴')) return '긴머리';
    if (v.contains('스포츠')) return '스포츠형';
    if (v.contains('커트')) return '커트머리';
    return '알 수 없음';
  }

  @override
  void dispose() {
    _timer?.cancel();
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _rrnFrontCtrl.dispose();
    _rrnBackCtrl.dispose();
    _reporterNameCtrl.dispose();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    _reporterRrnFrontCtrl.dispose();
    _reporterRrnBackCtrl.dispose();
    _locCtrl.dispose();   // ✅ 추가
    _charCtrl.dispose();  // ✅ 추가
    _clothCtrl.dispose(); // ✅ 추가
    _descCtrl.dispose();  // ✅ 추가
    _detailLocCtrl.dispose();
    super.dispose();
  }

  // 선택 값들
  int _selectedGender = 0; // 0: 남, 1: 여
  String _selectedTarget = "정상아동(18세 미만)";
  String _selectedBody = "알 수 없음";
  String _selectedFace = "알 수 없음";
  String _selectedHairCol = "알 수 없음";
  String _selectedHairType = "알 수 없음";
  String _selectedHeight = "알 수 없음";
  String _selectedWeight = "알 수 없음";

  final Color _bgYellow = const Color(0xFFFDF9EB);
  final Color _bgPink = const Color(0xFFFAEEF0);

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

  Widget _buildGuardianSelector() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('등록된 피보호자를 신고하시나요?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('피보호자를 선택하면 기본 정보가 자동으로 입력됩니다.', style: TextStyle(fontSize: 13, color: Colors.black54)),
          const SizedBox(height: 20),
          ..._guardianProfiles.map((profile) {
            final name = profile['name']?.toString() ?? '피보호자';
            final genderRaw = profile['gender']?.toString().toLowerCase() ?? '';
            final isFemale = genderRaw == 'female' || genderRaw == 'f' || genderRaw == '여' || genderRaw == '여성' || genderRaw == '여자';
            final age = profile['age'] ?? profile['current_age'];
            final ageStr = age != null ? '$age세' : '';
            return GestureDetector(
              onTap: () => _selectGuardianProfile(profile),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFCF0),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEFE0A0)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline, size: 32, color: Colors.black54),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          if (ageStr.isNotEmpty || genderRaw.isNotEmpty)
                            Text('${isFemale ? '여자' : '남자'}  $ageStr', style: const TextStyle(fontSize: 13, color: Colors.black54)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.black38),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              _resetForm();
              setState(() => _showGuardianSelector = false);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.black12),
              ),
              child: const Text('다른 실종자 신고하기', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Colors.black54)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showGuardianSelector) return _buildGuardianSelector();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 자동 입력 배너
          if (_selectedGuardianProfile != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF9DE),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEFE0A0)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 18, color: Color(0xFF9A7A00)),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('등록된 피보호자 정보에서 불러왔습니다.', style: TextStyle(fontSize: 13, color: Color(0xFF7A6000)))),
                  GestureDetector(
                    onTap: () {
                      _resetForm();
                      setState(() => _showGuardianSelector = _guardianProfiles.isNotEmpty);
                    },
                    child: const Text('변경', style: TextStyle(fontSize: 12, color: Color(0xFF9A7A00), fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
          // --- 실종자 정보 섹션 ---
          const Text("실종자 정보", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          _buildLabelInput("이름", _nameCtrl, "이름"),
          const SizedBox(height: 12),
          _buildLabelInput("실종 당시 나이", _ageCtrl, "실종 당시 나이"),
          const SizedBox(height: 16),
          _buildGenderSelector(), // 성별 선택
          const SizedBox(height: 20),
          
          // 주민번호 섹션
         _buildRRNSection(
            "주민번호",
            _rrnFrontCtrl,
            _rrnBackCtrl,
            _isUnknownRRN,
            (val) => setState(() => _isUnknownRRN = val!)
          ),
          const SizedBox(height: 20),

          // 발견 일시 (지난번 만든 달력+휠 로직 연결 지점)
          _buildLabelText("실종 일시"),
          GestureDetector(
            onTap: _pickDateTime,
            child: _buildFakeInput(
              () {
                final dt   = _selectedDateTime;
                final ampm = dt.hour < 12 ? '오전' : '오후';
                final h    = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
                final min  = dt.minute.toString().padLeft(2, '0');
                return '${dt.year}년 ${dt.month.toString().padLeft(2,'0')}월 '
                    '${dt.day.toString().padLeft(2,'0')}일 $ampm $h시 $min분';
              }(),
            ),
          ),
          
          const SizedBox(height: 30),

          _buildAddressSearchInput(),
                      
          const SizedBox(height: 30),
          
          // --- 대상 선택 (Grid 형태) ---
          const Text("대상", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          _buildTargetGrid(),
          const SizedBox(height: 30),

          // --- 상세 정보 (키, 몸무게 등 - 드롭다운 형태) ---
          Row(
            children: [
              Expanded(
                child: _buildDropdownRow(
                  "키",
                  ["알 수 없음", "140cm 미만", "140~150cm", "150~160cm", "160~170cm", "170~180cm", "180cm 이상"],
                  _selectedHeight,
                  (v) => setState(() => _selectedHeight = v!),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDropdownRow(
                  "몸무게",
                  ["알 수 없음", "40kg대", "50kg대", "60kg대"],
                  _selectedWeight,
                  (v) => setState(() => _selectedWeight = v!),
                ),
              ),
            ],
          ),

          // 체격 & 얼굴형
          Row(
            children: [
              Expanded(child: _buildDropdownField("체격", 
                ["알 수 없음", "비만", "건장", "보통", "왜소", "특이체형", "기타"], 
                _selectedBody, (v) => setState(() => _selectedBody = v!))),
              const SizedBox(width: 12),
              Expanded(child: _buildDropdownField("얼굴형", 
                ["알 수 없음", "삼각형", "역삼각형", "계란형", "사각형", "둥근형", "갸름한형", "기타"], 
                _selectedFace, (v) => setState(() => _selectedFace = v!))),
            ],
          ),

          // 두발 색상 & 두발 형태
          Row(
            children: [
              Expanded(child: _buildDropdownField("두발 색상", 
                ["알 수 없음", "흑색", "백색", "반백", "갈색", "염색", "기타"], 
                _selectedHairCol, (v) => setState(() => _selectedHairCol = v!))),
              const SizedBox(width: 12),
              Expanded(child: _buildDropdownField("두발 형태", 
                ["알 수 없음", "삭발", "대머리", "긴머리", "곱슬긴머리", "단발머리", "커트머리", "스포츠형", "짧은머리(생머리)", "긴머리(생머리)", "짧은머리(퍼머)", "긴머리(퍼머)", "묶음머리", "기타"], 
                _selectedHairType, (v) => setState(() => _selectedHairType = v!))),
            ],
          ),
        
          const SizedBox(height: 30),
          _buildLabelInput("신고 내용", _descCtrl, "남들과 구분되는 신체적 특징이나 버릇 등 특이사항을 입력해 주세요!", isLong: true),

          const SizedBox(height: 30),
          _buildReportPhotosSection(),

          const SizedBox(height: 40),
          _buildReporterSection(),
          
          const SizedBox(height: 40),
          
          // 1️⃣ [공통] 신고하기 버튼
          _buildActionButton(
            text: "신고하기",
            color: const Color(0xFFFAEEF0),
            onPressed: () {
              if (!_isAgreed) {
              _showMessage("약관에 동의해주세요.");
              return;
            }
              _submitReport();
            },
          )
        ],
      ),
    );
  }

  // 1. 인증번호 전송 함수
  Future<void> _sendSMS() async {
    String phoneNumber = _phoneCtrl.text.trim();

    // 🚀 [에러 해결 핵심] 번호가 비어있는지 확인
    if (phoneNumber.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("전화번호를 입력해 주세요.")),
      );
      return; // 👈 여기서 함수를 끝내서 Firebase 에러를 원천 차단합니다.
    }

    // 한국 번호 포맷 변경 (+8210...)
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
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("인증 실패: ${e.message}")));
        },
        codeSent: (String vid, int? token) {
          if (!mounted) return;
          setState(() => _verificationId = vid);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("인증번호가 발송되었습니다.")));
        },
        codeAutoRetrievalTimeout: (vid) => _verificationId = vid,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("발송 중 오류가 발생했습니다.")));
    }
  }

  // 2. 인증번호 확인 함수
  Future<void> _verifyCode() async {
    if (_verificationId == null) return;
    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _codeCtrl.text.trim(),
      );
      await FirebaseAuth.instance.signInWithCredential(credential);

      // 🚀 [추가] 비동기 작업 후 컨텍스트가 살아있는지 확인
      if (!mounted) return;
      setState(() => _isVerified = true);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("인증 성공!")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("번호가 틀렸습니다.")));
    }
  }

  Future<void> _submitReport() async {
    if (!_isAgreed) {
      _showMessage("개인정보 취급방침에 동의해주세요.");
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance(); // ✅ 한 번만
      final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
      final token = prefs.getString('access');

      // 필수값 체크
      if (_nameCtrl.text.isEmpty) {
        _showMessage("실종자 이름을 입력해주세요.");
        return;
      }

      if (_locCtrl.text.trim().isEmpty) {
        _showMessage("발생 위치를 주소 검색으로 선택해주세요.");
        return;
      }

      if (_detailLocCtrl.text.trim().length < 2) {
        _showMessage("상세 위치를 조금 더 구체적으로 입력해주세요.");
        return;
      }

      // 🔥 로그인 안 했을 때만 입력 요구
      if (!isLoggedIn) {
        if (_reporterNameCtrl.text.isEmpty || _phoneCtrl.text.isEmpty) {
          _showMessage("신고자 이름과 전화번호는 필수입니다.");
          return;
        }
      }

      final uri = Uri.parse("${ApiConfig.baseUrl}/report/register-missing/");
      final request = http.MultipartRequest("POST", uri);

      // 🔥 토큰은 로그인 상태일 때만 붙임
      if (token != null) {
        request.headers["Authorization"] = "Bearer $token";
      }

      // ✅ 실종자 정보
      request.fields["name"] = _nameCtrl.text;
      if (_ageCtrl.text.trim().isNotEmpty) {
        request.fields["age_at_missing"] = _ageCtrl.text.trim();
      }
      request.fields["gender"] = _selectedGender == 0 ? "male" : "female";
      if (!_isUnknownRRN) {
        if (_rrnFrontCtrl.text.isNotEmpty) request.fields["resident_front"] = _rrnFrontCtrl.text;
        if (_rrnBackCtrl.text.isNotEmpty)  request.fields["resident_back"]  = _rrnBackCtrl.text;
      }
      request.fields["occurred_at"] = _selectedDateTime.toIso8601String();
      request.fields["category"] = _selectedTarget;
      request.fields["occurred_location"] =
          "${_locCtrl.text.trim()} ${_detailLocCtrl.text.trim()}";
      if (_descCtrl.text.trim().isNotEmpty) {
        request.fields["description"] = _descCtrl.text.trim();
      }
      request.fields["height"]      = _selectedHeight;
      request.fields["weight"]      = _selectedWeight;
      request.fields["face_type"]   = _selectedFace;
      request.fields["hair_style"]  = _selectedHairType;
      request.fields["body_type"]   = _selectedBody;
      request.fields["hair_color"]  = _selectedHairCol;


      // ✅ 신고자 정보
      if (isLoggedIn) {
        request.fields["reporter_name"] = _loggedInName;
        request.fields["reporter_phone"] = _loggedInPhone;
      } else {
        request.fields["reporter_name"] = _reporterNameCtrl.text;
        request.fields["reporter_phone"] = _phoneCtrl.text;
      }

      // ✅ 실종자 다중 사진이 없을 때만 대표 사진을 fallback으로 전송
      if (_personPhotos.isEmpty && _selectedImage != null) {
        final bytes = await _selectedImage!.readAsBytes();
        final ext = _selectedImage!.path.split('.').last.toLowerCase();

        final mime = ext == 'png'
            ? 'png'
            : ext == 'gif'
                ? 'gif'
                : 'jpeg';

        request.files.add(
          http.MultipartFile.fromBytes(
            'photo',
            bytes,
            filename: 'photo.$mime',
            contentType: MediaType('image', mime),
          ),
        );
      }

      // ✅ 실종자 사진 여러 장
      // 백엔드: request.FILES.getlist("photo")
      for (int i = 0; i < _personPhotos.length; i++) {
        final bytes = await _personPhotos[i].readAsBytes();
        final ext = _personPhotos[i].path.split('.').last.toLowerCase();

        final mime = ext == 'png'
            ? 'png'
            : ext == 'gif'
                ? 'gif'
                : 'jpeg';

        request.files.add(
          http.MultipartFile.fromBytes(
            'photo',
            bytes,
            filename: 'person_photo_$i.$mime',
            contentType: MediaType('image', mime),
          ),
        );
      }

      // ✅ 부모님 정면 사진
      for (int i = 0; i < _parentPhotos.length; i++) {
        final f = _parentPhotos[i];
        if (f == null) continue;

        final bytes = await f.readAsBytes();
        final ext = f.path.split('.').last.toLowerCase();

        final mime = ext == 'png'
            ? 'png'
            : ext == 'gif'
                ? 'gif'
                : 'jpeg';

        final fieldName = i == 0
            ? 'parent1_face_photo'
            : 'parent2_face_photo';

        request.files.add(
          http.MultipartFile.fromBytes(
            fieldName,
            bytes,
            filename: i == 0
                ? 'parent1_face.$mime'
                : 'parent2_face.$mime',
            contentType: MediaType('image', mime),
          ),
        );
      }

      final response = await request.send();
      final resBody = await response.stream.bytesToString();

      debugPrint("🔥 [신고제출] status: ${response.statusCode}");
      debugPrint("🔥 [신고제출] body: $resBody");
      // 전송된 필드 목록 확인
      debugPrint("🔥 [신고제출] fields: ${request.fields.keys.toList()}");
      debugPrint("🔥 [신고제출] files: ${request.files.map((f) => '${f.field}=${f.filename}').toList()}");

      if (!mounted) return;

      if (response.statusCode == 201) {
        _showMessage("신고가 성공적으로 접수되었습니다.");
        if (!mounted) return;
        widget.onSuccess?.call();
      } else if (response.statusCode == 409) {
        // 유사 신고 존재 — 실제 신고 미등록
        String dupMsg = '유사한 신고가 이미 존재합니다.';
        try {
          final decoded = jsonDecode(resBody);
          if (decoded is Map) {
            dupMsg = decoded['error']?.toString() ?? dupMsg;
          }
        } catch (_) {}
        if (!mounted) return;
        _showMessage(dupMsg);
      } else {
        // 서버 오류 내용을 다이얼로그로 보여줌
        String errorMsg = resBody;
        try {
          final decoded = jsonDecode(resBody);
          if (decoded is Map) {
            errorMsg = decoded.entries
                .map((e) => '${e.key}: ${e.value}')
                .join('\n');
          }
        } catch (_) {}
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('신고 실패', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Text(errorMsg, style: const TextStyle(fontSize: 13)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      debugPrint("❌ 오류: $e");
      _showMessage("에러 발생");
    }
  }

  static const _parentPhotoLabels = ['부모님 정면 사진 1', '부모님 정면 사진 2'];

  Widget _buildReportPhotosSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 실종자 사진: 자유롭게 최대 5장
        Row(
          children: [
            const Text('실종자 사진', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Text('(선택, 최대 5장)', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ],
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              ..._personPhotos.asMap().entries.map((e) => Stack(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.grey[200],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(e.value, fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 10,
                    child: GestureDetector(
                      onTap: () => setState(() => _personPhotos.removeAt(e.key)),
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              )),
              if (_personPhotos.length < 5)
                GestureDetector(
                  onTap: _addPersonPhoto,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 28, color: Colors.grey[500]),
                        const SizedBox(height: 4),
                        Text('사진 추가', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 22),

        // 부모님 참고 사진: 실종예방등록과 동일한 2슬롯 방식
        Row(
          children: [
            const Text('부모님 참고 사진', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Text('(선택)', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'AI 몽타주 참고용으로 부모님 정면 사진을 선택 등록할 수 있습니다.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.95,
          children: List.generate(2, _buildParentPhotoBox),
        ),
      ],
    );
  }

  Widget _buildParentPhotoBox(int i) {
    final photo = _parentPhotos[i];
    return GestureDetector(
      onTap: () => _pickParentPhoto(i),
      child: Container(
        decoration: BoxDecoration(
          color: _bgPink,
          borderRadius: BorderRadius.circular(12),
        ),
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
                      child: Text(
                        _parentPhotoLabels[i],
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6, right: 6,
                    child: GestureDetector(
                      onTap: () => setState(() => _parentPhotos[i] = null),
                      child: Container(
                        width: 22, height: 22,
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
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

  Future<void> _addPersonPhoto() async {
    if (_personPhotos.length >= 5) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null && mounted) {
      setState(() => _personPhotos.add(File(picked.path)));
    }
  }

  static const Color _accentRed = Color(0xFFFF8A8A);

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

  Future<bool> _validateParentFaceAngle(File file) async {
    final detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true,
      ),
    );
    final faces = await detector.processImage(InputImage.fromFile(file));
    await detector.close();

    if (faces.isEmpty) {
      _showMessage('얼굴을 찾을 수 없습니다. 얼굴이 잘 보이는 사진을 선택해 주세요.');
      return false;
    }
    if (faces.length > 1) {
      return false;
    }
    final y = faces.first.headEulerAngleY ?? 0;
    if (y.abs() > 15) {
      _showMessage('정면 얼굴 사진을 올려 주세요.');
      return false;
    }
    return true;
  }

  Future<bool> _confirmUseAnyway(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
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

  Widget _parentGuideCheck(String text) => Padding(
    padding: const EdgeInsets.only(top: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.check_circle, size: 15, color: _accentRed),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12, height: 1.3, color: Colors.black87))),
    ]),
  );

  Widget _parentExampleImageBox() => Container(
    width: 150, height: 110,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE6E0D0)),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.asset(
        'assets/images/example_face/example_parent_front_face.png',
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.family_restroom, size: 36, color: Colors.black45),
            SizedBox(height: 8),
            Text('예시 이미지', style: TextStyle(fontSize: 12, color: Colors.black45)),
          ],
        ),
      ),
    ),
  );

  Future<void> _pickParentPhoto(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('부모님 정면 사진 등록 기준',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _parentExampleImageBox(),
              const SizedBox(height: 14),
              const Text(
                'AI 몽타주 참고용으로 부모님 얼굴이 정면으로 보이는 사진을 올려 주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.4, color: Colors.black87),
              ),
              const SizedBox(height: 12),
              _parentGuideCheck('정면을 바라보는 얼굴 사진이어야 합니다.'),
              _parentGuideCheck('얼굴이 흐릿하지 않아야 합니다.'),
              _parentGuideCheck('마스크, 모자, 선글라스 등 가림이 적어야 합니다.'),
              _parentGuideCheck('한 사람의 얼굴이 중심에 있는 사진을 권장합니다.'),
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
    final valid = await _validateParentFaceAngle(file);
    if (!valid) {
      final useAnyway = await _confirmUseAnyway('부모님 정면 사진으로 보기 어려울 수 있습니다.\n그래도 이 사진을 사용하시겠습니까?');
      if (!useAnyway) return;
    }
    if (mounted) setState(() => _parentPhotos[index] = file);
  }


  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime(2000),
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

    if (date == null || !mounted) return;

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
                  const Text('실종 시간 설정',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('완료'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                initialDateTime: _selectedDateTime,
                use24hFormat: false,
                onDateTimeChanged: (t) => setState(() {
                  _selectedDateTime = DateTime(
                    date.year, date.month, date.day,
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

  // --- 🧩 조립용 부품 위젯들 ---

  Widget _buildLabelText(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
  );

  Widget _buildFakeInput(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: BoxDecoration(color: _bgYellow, borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: const TextStyle(color: Colors.black87)),
  );

  Widget _buildLabelInput(String label, TextEditingController ctrl, String hint, {bool isLong = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelText(label),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: _bgYellow, borderRadius: BorderRadius.circular(8)),
          child: TextField(
            controller: ctrl,
            maxLines: isLong ? 5 : 1,
            decoration: InputDecoration(border: InputBorder.none, hintText: hint, hintStyle: const TextStyle(fontSize: 13, color: Colors.grey)),
          ),
        ),
      ],
    );
  }

  Widget _buildAddressSearchInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelText("발생 위치"),

        // ✅ 여기로 뱃지 위치 배너 이동
        if (_badgeLocationUsed) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFB0CFF0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.location_on,
                      size: 14,
                      color: Color(0xFF2D6A9F),
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Text(
                        '최근 뱃지 위치 불러옴',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2D6A9F),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => setState(() {
                        _badgeLocationUsed = false;
                        _badgeLocationTimestamp = null;
                      }),
                      child: const Text(
                        '위치 수정',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF2D6A9F),
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '마지막 확인: ${_formatBadgeTimestamp()}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                  ),
                ),
                if (_isBadgeLocationOld()) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '마지막 위치가 ${_badgeTimeAgoStr()} 전 정보입니다.\n'
                          '실제 실종 위치와 다를 수 있으니 확인해 주세요.',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.orange,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 8),
        ],

        // ✅ 주소 검색 + 현재 위치 버튼
        Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: _openAddressSearch,
                child: AbsorbPointer(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: _bgYellow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: TextField(
                      controller: _locCtrl,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: "주소 검색으로 발생 위치를 선택하세요",
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
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
                  color: _bgYellow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _isGettingLocation
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black54,
                        ),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.my_location,
                            size: 18,
                            color: Colors.black54,
                          ),
                          SizedBox(width: 6),
                          Text(
                            "현재 위치",
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // ✅ 상세 위치
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _bgYellow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: _detailLocCtrl,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: "상세 위치 예: 학교 정문 앞, 역 2번 출구 근처",
              hintStyle: TextStyle(
                fontSize: 13,
                color: Colors.grey,
              ),
            ),
          ),
        ),
      ],
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
        setState(() {
          _locCtrl.text = parts.join(" ");
          _badgeLocationUsed = false;
          _badgeLocationTimestamp = null;
        });
      } else {
        _showMessage("현재 위치를 주소로 변환하지 못했습니다.");
      }
    } catch (e) {
      if (mounted) _showMessage("현재 위치를 가져오지 못했습니다.");
    } finally {
      if (mounted) setState(() => _isGettingLocation = false);
    }
  }

  void _openAddressSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddressSearchPage(
          onSelected: (address) {
            setState(() {
              _locCtrl.text = address;
              _badgeLocationUsed = false;
              _badgeLocationTimestamp = null;
            });
          },
        ),
      ),
    );
  }


  Widget _buildGenderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelText("성별"),
        Row(
          children: [
            _genderBtn("남자", 0), const SizedBox(width: 10), _genderBtn("여자", 1),
          ],
        ),
      ],
    );
  }

  Widget _genderBtn(String title, int index) => Expanded(
    child: GestureDetector(
      onTap: () => setState(() => _selectedGender = index),
      child: Container(
        height: 45,
        decoration: BoxDecoration(
          color: _bgYellow, borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _selectedGender == index ? Colors.orange : Colors.transparent),
        ),
        child: Center(child: Text(title)),
      ),
    ),
  );

  bool _isUnknownRRN = false; // 실종자 주민번호 알 수 없음
  bool _isUnknownReporterRRN = false; // 신고자 주민번호 알 수 없음

// 🚀 [수정] 주민번호 섹션 (알 수 없음 기능 포함)
Widget _buildRRNSection(String label, TextEditingController f, TextEditingController b, bool isUnknown, Function(bool?) onToggle) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildLabelText(label),
          // 🔘 '알 수 없음' 체크박스
          Row(
            children: [
              Transform.scale(
                scale: 0.8,
                child: Checkbox(
                  value: isUnknown,
                  activeColor: Colors.black87,
                  onChanged: onToggle,
                ),
              ),
              const Text("알 수 없음", style: TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
      // 🚫 체크 시 입력을 막고 색상을 변경
      AbsorbPointer(
        absorbing: isUnknown,
        child: Opacity(
          opacity: isUnknown ? 0.5 : 1.0,
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isUnknown ? Colors.grey.shade200 : _bgYellow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: f,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(border: InputBorder.none, hintText: "앞자리"),
                  ),
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("-")),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: isUnknown ? Colors.grey.shade200 : _bgYellow,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: b,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(border: InputBorder.none, hintText: "뒷자리"),
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

  // 🚀 [추가] 신고자 정보 섹션 전체 (build 함수 하단에 배치)
  Widget _buildReporterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("신고자 정보", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFCF9F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: isLoggedIn
              ? _buildLoggedInReporterInfo()
              : _buildGuestReporterForm(),
        ),
      ],
    );
  }

  // ── 로그인 상태: 이름·전화번호 읽기 전용 표시 ──────────────────────────
  Widget _buildLoggedInReporterInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🔥 헤더 영역 (완전 핵심 UI 개선)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: const [
                Icon(Icons.verified, color: Colors.pink, size: 18),
                SizedBox(width: 6),
                Text(
                  "로그인된 사용자 정보",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),

            // 👉 오른쪽 상단 동의 영역
            Row(
              children: [
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
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 16),

        // 🔹 신고자 이름
        Row(
          children: [
            const Icon(Icons.person, size: 18, color: Color(0xFFFF8A8A)),
            const SizedBox(width: 6),
            _buildLabelText("신고자 이름"),
          ],
        ),
        const SizedBox(height: 6),
        _buildReadOnlyBox(
          _loggedInName.isNotEmpty ? _loggedInName : "이름 없음",
        ),

        const SizedBox(height: 12),

        // 🔹 신고자 전화번호
        Row(
          children: [
            const Icon(Icons.phone, size: 18, color: Color(0xFFFF8A8A)),
            const SizedBox(width: 6),
            _buildLabelText("신고자 전화번호"),
          ],
        ),
        const SizedBox(height: 6),
        _buildReadOnlyBox(
          _loggedInPhone.isNotEmpty ? _loggedInPhone : "전화번호 없음",
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildReadOnlyBox(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: const TextStyle(fontSize: 14, color: Colors.black87)),
      );

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
          bool allChecked = _serviceAgree && _locationAgree && _privacyAgree;

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

                /// 전체 동의
                ListTile(
                  leading: Icon(
                    allChecked ? Icons.check_circle : Icons.circle_outlined,
                    color: Color(0xFFFF8A8A),
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
                  () => setModalState(() => _locationAgree = !_locationAgree),
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
                    onPressed: (_serviceAgree && _locationAgree && _privacyAgree)
                        ? () {
                            setState(() {
                              _isAgreed = true;
                            });
                            Navigator.pop(context);
                          }
                        : null,
                    child: const Text("확인"),
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

Widget _buildAgreementItem(String title, bool value, VoidCallback onTap) {
  return ListTile(
    leading: Icon(
      value ? Icons.check_circle : Icons.circle_outlined,
      color: Color(0xFFFF8A8A),
    ),
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}

  // ── 비회원 상태: 기존 입력 폼 ──────────────────────────────────────────
  Widget _buildGuestReporterForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 신고자 이름 & 약관 영역
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabelText("신고자 이름"),
                  _buildTextFieldBox(
                    controller: _reporterNameCtrl,
                    height: 40,
                    color: _bgPink,
                  ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // 🔥 여기 삽입 (기존 개인정보 동의 자리)
                  GestureDetector(
                    onTap: _openAgreementSheet,
                    child: Row(
                      children: [
                        Icon(
                          _isAgreed ? Icons.check_circle : Icons.circle_outlined,
                          color: Color(0xFFFF8A8A),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          "이용약관 동의 (필수)",
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

              // 2. 주민번호 섹션 (시안 디자인 반영)
              Row(
                children: [
                  _buildLabelText("주민번호"),
                  const SizedBox(width: 10),
                  // '알 수 없음' 버튼 디자인
                  GestureDetector(
                    onTap: () => setState(() => _isUnknownReporterRRN = !_isUnknownReporterRRN),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFF2D5D9), borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        children: [
                          Icon(_isUnknownReporterRRN ? Icons.check_circle : Icons.circle_outlined, size: 14),
                          const SizedBox(width: 4),
                          const Text("알 수 없음", style: TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AbsorbPointer(
                absorbing: _isUnknownReporterRRN,
                child: Opacity(
                  opacity: _isUnknownReporterRRN ? 0.5 : 1.0,
                  child: Row(
                    children: [
                      Expanded(child: _buildTextFieldBox(controller: _reporterRrnFrontCtrl, height: 40, color: _bgPink, hint: "주민번호 앞자리")),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("-", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                      Expanded(child: _buildTextFieldBox(controller: _reporterRrnBackCtrl, height: 40, color: _bgPink, hint: "주민번호 뒷자리")),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 3. 전화번호 & 인증
              _buildLabelText("신고자 전화번호"),
              Row(
                children: [
                  Expanded(child: _buildTextFieldBox(controller: _phoneCtrl, height: 40, color: _bgPink)),
                  const SizedBox(width: 12),
                 // ✅ 수정
                  GestureDetector(
                    onTap: _timerSeconds > 0 ? null : () {
                      _startTimer();
                      _sendSMS();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _timerSeconds > 0 ? Colors.grey.shade300 : Colors.white,
                        borderRadius: BorderRadius.circular(25),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: Text(
                        _timerSeconds > 0 ? "재전송 (${_timerSeconds}s)" : "인증번호전송",
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              _buildLabelText("인증번호입력"),
              Row(
                children: [
                  Expanded(child: _buildTextFieldBox(controller: _codeCtrl, height: 40, color: _bgPink)),
                  const SizedBox(width: 12),
                  _buildSmallWhiteButton(
                    _isVerified ? "✔ 인증완료" : "확인",
                    onTap: _isVerified ? null : _verifyCode,
                  ),
                ],
              ),
        ],
      );
  }

  // 헬퍼: 시안의 흰색 타원형 버튼
  // 🚀 수정: 이름 변경 및 onTap(클릭) 기능 추가
  Widget _buildSmallWhiteButton(String text, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap, // 👈 버튼을 눌렀을 때 실행될 함수
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), 
              blurRadius: 4, 
              offset: const Offset(0, 2)
            )
          ],
        ),
        child: Text(
          text, 
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)
        ),
      ),
    );
  }

  Widget _buildTargetGrid() {
    final List<String> targets = [
      "정상아동(18세 미만)", "지적장애인",
      "시설보호무연고자", "치매질환자",
      "지적 장애인(18세 미만)", "가출인",
      "지적장애인(18세 이상)", "불상(기타)"
    ];

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 4.5,
      mainAxisSpacing: 0,
      crossAxisSpacing: 10,
      children: targets.map((t) => GestureDetector(
        onTap: () => setState(() => _selectedTarget = t),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 30,
              // 🚀 ignore 주석을 추가하여 최신 버전의 경고를 끕니다. 
              // 이 방식이 현재 가장 안전하고 확실하게 에러를 지우는 방법입니다.
              // ignore: deprecated_member_usea
              child: Radio<String>(
                value: t,
                // ignore: deprecated_member_use
                groupValue: _selectedTarget,
                activeColor: Colors.black87,
                // ignore: deprecated_member_use
                onChanged: (v) => setState(() => _selectedTarget = v!),
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
    );
  }

  Widget _buildDropdownRow(
    String label,
    List<String> items,
    String selectedValue,
    Function(String?) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelText(label),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _bgYellow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: selectedValue, // ✅ 상태 연결
              isExpanded: true,
              items: items
                  .map((i) => DropdownMenuItem(
                        value: i,
                        child: Text(i),
                      ))
                  .toList(),
              onChanged: onChanged, // ✅ 클릭 동작
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // 🚀 모든 상세 특징에 사용할 공용 드롭다운 위젯
  Widget _buildDropdownField(String label, List<String> items, String currentVal, Function(String?) onChange) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildLabelText(label),
        Container(
          width: double.infinity,
          height: 45,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(color: _bgYellow, borderRadius: BorderRadius.circular(8)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: currentVal,
              isExpanded: true,
              items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: onChange,
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // 🧩 공용 액션 버튼 빌더
  Widget _buildActionButton({required String text, required Color color, required VoidCallback onPressed, Color textColor = Colors.black87}) {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isAgreed 
              ? const Color(0xFFFF8A8A) 
              : Colors.grey,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: Text(text, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
    );
  }

  void _resetForm() {
    _nameCtrl.clear();
    _ageCtrl.clear();
    _rrnFrontCtrl.clear();
    _rrnBackCtrl.clear();
    _locCtrl.clear();
    _detailLocCtrl.clear();
    _descCtrl.clear();
    setState(() {
      _selectedGuardianProfile = null;
      _selectedGender   = 0;
      _selectedTarget   = "정상아동(18세 미만)";
      _selectedHeight   = "알 수 없음";
      _selectedWeight   = "알 수 없음";
      _selectedBody     = "알 수 없음";
      _selectedFace     = "알 수 없음";
      _selectedHairCol  = "알 수 없음";
      _selectedHairType = "알 수 없음";
      _selectedImage    = null;
      _personPhotos     = [];
      _parentPhotos     = [null, null];
      _selectedDateTime = DateTime.now();
      _badgeLocationUsed      = false;
      _badgeLocationTimestamp = null;
      _isUnknownRRN = false;
    });
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.black87));
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