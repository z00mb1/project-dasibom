import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../citizen/citizen_form_tab.dart' show AddressSearchPage;
import '../config/api_config.dart';

class RegisterDetailPage extends StatefulWidget {
  final int registerId;

  const RegisterDetailPage({
    super.key,
    required this.registerId,
  });

  @override
  State<RegisterDetailPage> createState() => _RegisterDetailPageState();
}

class _RegisterDetailPageState extends State<RegisterDetailPage> {
  final Color _pointColor = const Color(0xFFFDE14C);

  static const _heightOpts   = ['알 수 없음','140cm 미만','140~150cm','150~160cm','160~170cm','170~180cm','180cm 이상'];
  static const _weightOpts   = ['알 수 없음','40kg 미만','40~50kg','50~60kg','60~70kg','70~80kg','80kg 이상'];
  static const _bodyTypeOpts = ['알 수 없음','보통','마른 편','통통한 편','근육질'];
  static const _faceShapeOpts= ['알 수 없음','둥근형','타원형','각진형','긴형'];
  static const _hairColorOpts= ['알 수 없음','검은색','갈색','흰색/회색','금발','기타'];
  static const _hairStyleOpts= ['알 수 없음','짧은 머리','중간 머리','긴 머리','묶음','대머리'];
  static const _bloodTypeOpts= ['알 수 없음','A형','B형','O형','AB형'];
  static const _eyeColorOpts = ['알 수 없음','검정','갈색','기타'];
  static const _genderOpts   = ['남자', '여자'];

  Map<String, dynamic>? _detail;
  bool _isLoading = true;
  bool _isEditing = false;
  bool _isAdmin = false;
  int _selectedPhotoIndex = 0;
  int _status = 0;
  int _originalStatus = 0;

  List<Map<String, dynamic>> _newImages = [];
  List<int> _deletedPhotoIds = [];
  List<Map<String, dynamic>> _displayPhotos = [];

  final _nameCtrl = TextEditingController();
  final _genderCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _frequentPlaceCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _bodyTypeCtrl = TextEditingController();
  final _faceTypeCtrl = TextEditingController();
  final _hairColorCtrl = TextEditingController();
  final _hairStyleCtrl = TextEditingController();
  final _bloodTypeCtrl = TextEditingController();
  final _eyeColorCtrl = TextEditingController();
  final _physicalFeatureCtrl = TextEditingController();
  final _healthInfoCtrl = TextEditingController();

  final _guardianNameCtrl = TextEditingController();
  final _guardianPhoneCtrl = TextEditingController();
  final _addressDetailCtrl = TextEditingController();
  final _rrnFrontCtrl = TextEditingController();
  final _rrnBackCtrl = TextEditingController();
  final _guardianRrnFrontCtrl = TextEditingController();
  final _guardianRrnBackCtrl = TextEditingController();

  final TextEditingController _rejectedReasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _fetchDetail();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _genderCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _frequentPlaceCtrl.dispose();
    _noteCtrl.dispose();

    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _bodyTypeCtrl.dispose();
    _faceTypeCtrl.dispose();
    _hairColorCtrl.dispose();
    _hairStyleCtrl.dispose();
    _bloodTypeCtrl.dispose();
    _eyeColorCtrl.dispose();
    _physicalFeatureCtrl.dispose();
    _healthInfoCtrl.dispose();

    _guardianNameCtrl.dispose();
    _guardianPhoneCtrl.dispose();
    _addressDetailCtrl.dispose();
    _rrnFrontCtrl.dispose();
    _rrnBackCtrl.dispose();
    _guardianRrnFrontCtrl.dispose();
    _guardianRrnBackCtrl.dispose();

    _rejectedReasonCtrl.dispose();

    super.dispose();
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      _isAdmin = prefs.getString('role') == 'admin';
    });
  }

  Future<void> _fetchDetail() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access') ?? '';

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/prevention-registrations/${widget.registerId}/'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        _setDetail(decoded);
      } else {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '예방등록 상세 정보를 불러올 수 없습니다. (${response.statusCode})',
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('예방등록 상세 조회 에러: $e');

      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });
    }
  }

  void _setDetail(Map<String, dynamic> data) {
    _nameCtrl.text = _value(data['name']);
    _genderCtrl.text = _formatGenderForDisplay(data['gender']);
    _phoneCtrl.text = _value(data['phone']);
    _addressCtrl.text = _value(data['address']);
    _frequentPlaceCtrl.text = _value(data['frequent_place']);
    _noteCtrl.text = _value(data['note']);

    _heightCtrl.text = _value(data['height']);
    _weightCtrl.text = _value(data['weight']);
    _bodyTypeCtrl.text = _value(data['body_type']);
    _faceTypeCtrl.text = _value(data['face_type']);
    _hairColorCtrl.text = _value(data['hair_color']);
    _hairStyleCtrl.text = _value(data['hair_style']);
    _bloodTypeCtrl.text = _value(data['blood_type']);
    _eyeColorCtrl.text = _value(data['eye_color']);
    _physicalFeatureCtrl.text = _value(data['physical_feature']);
    _healthInfoCtrl.text = _value(data['health_info']);

    _guardianNameCtrl.text = _value(data['guardian_name']);
    _guardianPhoneCtrl.text = _value(data['guardian_phone']);
    _rrnFrontCtrl.text = _value(data['rrn_front']);
    _rrnBackCtrl.text = _value(data['rrn_back']);
    _guardianRrnFrontCtrl.text = _value(data['guardian_rrn_front']);
    _guardianRrnBackCtrl.text = _value(data['guardian_rrn_back']);

    _rejectedReasonCtrl.text = data['rejected_reason']?.toString() ?? '';

    final rawPhotos = (data['photo_items'] as List?) ??
    (data['photos'] as List?) ??
    [];

_displayPhotos = rawPhotos.map<Map<String, dynamic>>((p) {
  if (p is Map) {
    final m = Map<String, dynamic>.from(p);
    m['image'] = m['url'] ?? m['image_url'] ?? m['photo'] ?? m['file'] ?? m['image'];
    return m;
  }
  return {'image': p.toString()};
}).toList();

    final mainPhoto = data['main_photo']?.toString() ?? '';

    if (_displayPhotos.isEmpty && mainPhoto.isNotEmpty) {
      _displayPhotos = [
        {
          'id': null,
          'image_url': mainPhoto,
          'image': mainPhoto,
          'photo_type': 'face',
          'validation_status': null,
          'validation_message': '대표 사진',
        }
      ];
    }

    final statusInt = _convertStatus(data['status']?.toString() ?? 'received');

    setState(() {
      _detail = data;
      _selectedPhotoIndex = 0;
      _status = statusInt;
      _originalStatus = statusInt;
      _isLoading = false;
    });
  }

  String _value(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString();
    return text.isEmpty ? fallback : text;
  }

  String _formatGenderForDisplay(dynamic gender) {
    final text = gender?.toString().trim() ?? '';

    if (text.isEmpty) return '';

    switch (text.toLowerCase()) {
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
        return text;
    }
  }

  String _display(dynamic value, {String fallback = '정보 없음'}) {
    if (value == null) return fallback;
    final text = value.toString();
    return text.isEmpty ? fallback : text;
  }

  String _formatRrn(dynamic front, dynamic back) {
    final f = front?.toString().trim() ?? '';
    final b = back?.toString().trim() ?? '';

    if (f.isEmpty && b.isEmpty) {
      return '정보 없음';
    }

    if (f.isEmpty) {
      return '- $b';
    }

    if (b.isEmpty) {
      return '$f -';
    }

    return '$f - $b';
  }

  int _convertStatus(String status) {
    switch (status) {
      case 'received':
        return 0;
      case 'reviewing':
        return 1;
      case 'completed':
        return 2;
      case 'rejected':
        return 3;
      default:
        return 0;
    }
  }

  // 관리자: 모든 상태 수정 가능 / 보호자: 접수중(0) 또는 등록완료(2) 상태일 때 수정 가능
  bool get _canEdit => _isAdmin || _status == 0 || _status == 2;

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

  Future<void> _saveEdit() async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access') ?? '';

      if (!mounted) return;

      if (token.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('로그인이 필요합니다.')));
        return;
      }

      final int requestedStatus = _status;
      final int previousStatus = _originalStatus;

      final bool canEditContent = _isAdmin || _originalStatus == 0 || _originalStatus == 2;

      if (canEditContent) {
        final request = http.MultipartRequest(
          'PATCH',
          Uri.parse('${ApiConfig.baseUrl}/prevention-registrations/${widget.registerId}/'),
        );

        request.headers['Authorization'] = 'Bearer $token';
        request.fields['name'] = _nameCtrl.text;
        request.fields['gender'] = _genderCtrl.text;
        request.fields['phone'] = _phoneCtrl.text;
        final detailAddr = _addressDetailCtrl.text.trim();
        request.fields['address'] = detailAddr.isNotEmpty
            ? '${_addressCtrl.text.trim()} $detailAddr'
            : _addressCtrl.text.trim();
        request.fields['frequent_place'] = _frequentPlaceCtrl.text;
        request.fields['note'] = _noteCtrl.text;
        request.fields['height'] = _heightCtrl.text;
        request.fields['weight'] = _weightCtrl.text;
        request.fields['body_type'] = _bodyTypeCtrl.text;
        request.fields['face_type'] = _faceTypeCtrl.text;
        request.fields['hair_color'] = _hairColorCtrl.text;
        request.fields['hair_style'] = _hairStyleCtrl.text;
        request.fields['blood_type'] = _bloodTypeCtrl.text;
        request.fields['eye_color'] = _eyeColorCtrl.text;
        request.fields['physical_feature'] = _physicalFeatureCtrl.text;
        request.fields['health_info'] = _healthInfoCtrl.text;
        request.fields['guardian_name'] = _guardianNameCtrl.text;
        request.fields['guardian_phone'] = _guardianPhoneCtrl.text;
        request.fields['rrn_front'] = _rrnFrontCtrl.text;
        request.fields['rrn_back'] = _rrnBackCtrl.text;
        request.fields['guardian_rrn_front'] = _guardianRrnFrontCtrl.text;
        request.fields['guardian_rrn_back'] = _guardianRrnBackCtrl.text;
        if (_deletedPhotoIds.isNotEmpty) {
          request.fields['delete_photos'] = jsonEncode(_deletedPhotoIds);
        }
        for (final img in _newImages) {
          final file = img['file'] as File;
          final type = img['type'] as String;
          request.files.add(
            await http.MultipartFile.fromPath(type, file.path),
          );
        }

        final streamed = await request.send();
        final body = await streamed.stream.bytesToString();

        debugPrint('★★★ 예방등록 수정 코드: ${streamed.statusCode}');
        debugPrint('★★★ 예방등록 수정 바디: $body');

        if (!mounted) return;

        if (streamed.statusCode == 200) {
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          _setDetail(decoded);
          setState(() {
            _newImages = [];
            _deletedPhotoIds = [];
          });
          _addressDetailCtrl.text = '';

          if (_isAdmin && requestedStatus != previousStatus) {
            setState(() {
              _status = requestedStatus;
              _originalStatus = previousStatus;
            });
          }
        } else {
          messenger.showSnackBar(SnackBar(content: Text('수정 실패: $body')));
          return;
        }
      }

      if (!mounted) return;

      // 관리자이고 상태가 변경된 경우 상태 변경 API 별도 호출
      if (_isAdmin && requestedStatus != previousStatus) {
        setState(() {
          _status = requestedStatus;
          _originalStatus = previousStatus;
        });

        await _applyStatusChange(token);
        return;
      }

      setState(() => _isEditing = false);
      messenger.showSnackBar(const SnackBar(content: Text('예방등록 정보가 수정되었습니다.')));
    } catch (e) {
      debugPrint('예방등록 수정 에러: $e');
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('수정 중 오류가 발생했습니다.')));
    }
  }

  String _statusToString(int s) {
    switch (s) {
      case 0: return 'received';
      case 1: return 'reviewing';
      case 2: return 'completed';
      case 3: return 'rejected';
      default: return 'received';
    }
  }

  int _statusFromString(String? status) {
    switch (status) {
      case 'received':
        return 0;
      case 'reviewing':
        return 1;
      case 'completed':
        return 2;
      case 'rejected':
        return 3;
      default:
        return 0;
    }
  }

  void _updateStatus(int newStatus) => setState(() => _status = newStatus);

  Future<void> _applyStatusChange(String token) async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    final statusText = _statusToString(_status);

    final Map<String, dynamic> requestBody = {
      'status': statusText,
    };

    if (statusText == 'rejected') {
      final reason = _rejectedReasonCtrl.text.trim();

      if (reason.isNotEmpty) {
        requestBody['rejected_reason'] = reason;
      }
    }

    try {
      final res = await http.patch(
        Uri.parse(
          '${ApiConfig.baseUrl}/prevention-registrations/${widget.registerId}/admin-status/',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(requestBody),
      );

      final responseBody = utf8.decode(res.bodyBytes);

      debugPrint('상태 변경 요청 body: $requestBody');
      debugPrint('상태 변경 응답 코드: ${res.statusCode}');
      debugPrint(
        responseBody.length > 300
            ? '상태 변경 응답 바디: ${responseBody.substring(0, 300)}'
            : '상태 변경 응답 바디: $responseBody',
      );

      if (!mounted) return;

      if (res.statusCode == 200) {
        final decoded = jsonDecode(responseBody) as Map<String, dynamic>;

        setState(() {
          _status = _statusFromString(decoded['new_status']?.toString());
          _originalStatus = _status;
          _rejectedReasonCtrl.text =
              decoded['rejected_reason']?.toString() ?? '';
          _isEditing = false;
        });

        if (_status == 1) {
          messenger.showSnackBar(
            const SnackBar(content: Text("상태가 '확인 중'으로 변경되었습니다.")),
          );
          nav.pop(true);
        } else if (_status == 2) {
          messenger.showSnackBar(
            const SnackBar(content: Text('등록이 완료되었습니다.')),
          );
          nav.pop(true);
        } else if (_status == 3) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('신청이 거절되었습니다.'),
              backgroundColor: Colors.red,
            ),
          );
          nav.pop(true);
        } else {
          messenger.showSnackBar(
            const SnackBar(content: Text('수정이 완료되었습니다.')),
          );
          nav.pop(true);
        }
      } else {
        setState(() {
          _status = _originalStatus;
        });

        messenger.showSnackBar(
          SnackBar(content: Text(_extractErrorMessage(responseBody))),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _status = _originalStatus;
      });

      debugPrint('상태 변경 실패: $e');

      messenger.showSnackBar(
        const SnackBar(content: Text('상태 변경 중 오류가 발생했습니다.')),
      );
    }
  }

  String _extractErrorMessage(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);

      if (decoded is Map<String, dynamic>) {
        return decoded['error']?.toString() ??
            decoded['detail']?.toString() ??
            decoded['message']?.toString() ??
            '상태 변경에 실패했습니다.';
      }

      return '상태 변경에 실패했습니다.';
    } catch (_) {
      if (responseBody.trimLeft().startsWith('<!DOCTYPE html') ||
          responseBody.trimLeft().startsWith('<html')) {
        return '상태 변경 API 주소 또는 권한을 확인해 주세요.';
      }

      return responseBody.isNotEmpty ? responseBody : '상태 변경에 실패했습니다.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;

    return Scaffold(
      backgroundColor: const Color(0xFFFDF9EB),
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : detail == null
              ? const Center(child: Text('상세 정보가 없습니다.'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      if (detail['status'] == 'rejected')
                        _buildRejectedBanner(detail['rejected_reason']),

                      _buildPhotoSection(),
                      const SizedBox(height: 20),

                      _buildTargetInfoSection(),
                      const SizedBox(height: 20),

                      _buildAppearanceSection(),
                      const SizedBox(height: 20),

                      _buildGuardianSection(),

                      if (_isAdmin && _status == 2) ...[
                        const SizedBox(height: 20),
                        _buildBadgeSection(),
                      ],

                      if (_isAdmin) ...[
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
                              '수정 모드일 때 상태 변경이 가능합니다.',
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

  AppBar _buildAppBar() {
    return AppBar(
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
    );
  }

  Widget _buildRejectedBanner(dynamic reason) {
    final text = _display(reason, fallback: '이 예방등록 신청은 거절되었습니다.');

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
              text.startsWith('이 예방등록') ? text : '거절 사유: $text',
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

  Future<void> _addPhoto() async {
    const photoTypes = [
      {'label': '정면 사진', 'key': 'face_photo'},
      {'label': '전신 사진', 'key': 'full_body_photo'},
      {'label': '왼쪽 측면 사진', 'key': 'left_side_photo'},
      {'label': '오른쪽 측면 사진', 'key': 'right_side_photo'},
      {'label': '가족 사진 1', 'key': 'parent1_face_photo'},
      {'label': '가족 사진 2', 'key': 'parent2_face_photo'},
    ];

    final type = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('사진 종류 선택',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const Divider(height: 1),
            ...photoTypes.map((t) => ListTile(
                  title: Text(t['label']!),
                  onTap: () => Navigator.pop(ctx, t['key']),
                )),
          ],
        ),
      ),
    );

    if (type == null || !mounted) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null && mounted) {
      setState(() => _newImages.add({'file': File(picked.path), 'type': type}));
    }
  }

  void _deleteServerPhoto(int index) {
    setState(() {
      final id = _displayPhotos[index]['id'];
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

  void _openAddressSearch() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddressSearchPage(
          onSelected: (address) {
            setState(() => _addressCtrl.text = address);
          },
        ),
      ),
    );
  }

  Widget _buildPhotoSection() {
    final totalCount = _displayPhotos.length + _newImages.length;
    final safeIndex = _selectedPhotoIndex.clamp(0, totalCount == 0 ? 0 : totalCount - 1);

    Widget previewChild;
    if (totalCount > 0) {
      if (safeIndex < _displayPhotos.length) {
        final url = _photoUrl(_displayPhotos[safeIndex]);
        previewChild = url.isNotEmpty
            ? Image.network(url, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.person, size: 50, color: Colors.white))
            : const Icon(Icons.person, size: 50, color: Colors.white);
      } else {
        final newIdx = safeIndex - _displayPhotos.length;
        previewChild = Image.file(_newImages[newIdx]['file'] as File, fit: BoxFit.cover);
      }
    } else {
      previewChild = const Icon(Icons.person, size: 50, color: Colors.white);
    }

    final selectedServerPhoto =
        safeIndex < _displayPhotos.length ? _displayPhotos[safeIndex] : null;

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
                child: previewChild,
              ),
            ),
            Positioned(
              top: 5,
              left: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  selectedServerPhoto != null
                      ? _photoTypeLabel(selectedServerPhoto['photo_type']?.toString())
                      : safeIndex >= _displayPhotos.length ? '새 사진' : '사진',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
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
              const Text('등록 사진', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (totalCount == 0 && !_isEditing)
                const Text(
                  '첨부된 사진이 없습니다.',
                  style: TextStyle(color: Colors.black45, fontSize: 13),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ..._displayPhotos.asMap().entries.map((e) {
                      final i = e.key;
                      final url = _photoUrl(e.value);
                      final vs = e.value['validation_status']?.toString();
                      return _buildThumbnail(
                        index: i,
                        child: url.isNotEmpty
                            ? Image.network(url, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.person, size: 24))
                            : const Icon(Icons.person, size: 24),
                        validationStatus: vs,
                        onDelete: _isEditing ? () => _deleteServerPhoto(i) : null,
                      );
                    }),
                    ..._newImages.asMap().entries.map((e) {
                      final i = _displayPhotos.length + e.key;
                      final file = e.value['file'] as File;
                      return _buildThumbnail(
                        index: i,
                        child: Image.file(file, fit: BoxFit.cover),
                        onDelete: _isEditing ? () => _deleteNewPhoto(e.key) : null,
                      );
                    }),
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
              if (selectedServerPhoto != null) ...[
                const SizedBox(height: 12),
                _buildValidationMessage(selectedServerPhoto),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildThumbnail({
    required int index,
    required Widget child,
    String? validationStatus,
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
          if (validationStatus != null && onDelete == null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: _validationColor(validationStatus),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1),
                ),
              ),
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
        '${_validationLabel(status)} · $message${confidence == null ? '' : ' · 신뢰도 $confidence'}',
        style: TextStyle(
          fontSize: 12,
          color: _validationColor(status),
          height: 1.3,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _dropdownBox(String label, TextEditingController ctrl, List<String> opts) {
    if (!_isEditing) {
      return _editableBox(label, ctrl);
    }
    final val = opts.contains(ctrl.text) ? ctrl.text : opts[0];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _pointColor, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.black54)),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: val,
              isExpanded: true,
              iconSize: 18,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
              items: opts
                  .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => ctrl.text = v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _genderSelectBox() {
    if (!_isEditing) {
      return _editableBox('성별', _genderCtrl);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _pointColor, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('성별',
              style: TextStyle(fontSize: 11, color: Colors.black54)),
          const SizedBox(height: 8),
          Row(
            children: _genderOpts.map((g) {
              final selected = _genderCtrl.text == g;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _genderCtrl.text = g),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? _pointColor
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: selected
                          ? Border.all(
                              color: const Color(0xFFF0C800), width: 1.5)
                          : Border.all(color: Colors.black12),
                    ),
                    child: Text(g,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        )),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
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
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: '주소를 검색하세요',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
                  labelText: '주소',
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
            controller: _addressDetailCtrl,
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: '세부 주소 예: 101호, 3층 등',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRrnRow(
    String label,
    TextEditingController frontCtrl,
    TextEditingController backCtrl,
    dynamic rawFront,
    dynamic rawBack,
  ) {
    if (!_isEditing) {
      return _readOnlyBox(label, _formatRrn(rawFront, rawBack));
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _pointColor, width: 2),
                  ),
                  child: TextField(
                    controller: frontCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '앞 6자리',
                      counterText: '',
                    ),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('-',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _pointColor, width: 2),
                  ),
                  child: TextField(
                    controller: backCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 7,
                    obscureText: true,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: '뒤 7자리',
                      counterText: '',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTargetInfoSection() {
    return _buildSection(
      title: '등록 대상자 정보',
      children: [
        Row(
          children: [
            Expanded(child: _editableBox('이름', _nameCtrl)),
            const SizedBox(width: 10),
            Expanded(child: _genderSelectBox()),
          ],
        ),
        const SizedBox(height: 10),
        _editableBox('전화번호', _phoneCtrl),
        if (_isEditing)
          _buildAddressEditField()
        else
          _editableBox('주소', _addressCtrl),
        _editableBox('자주 가는 장소', _frequentPlaceCtrl),
        _editableBox('기타 참고사항', _noteCtrl, maxLines: 3),
        _buildRrnRow(
          '주민등록번호',
          _rrnFrontCtrl,
          _rrnBackCtrl,
          _detail?['rrn_front'],
          _detail?['rrn_back'],
        ),
     ],
    );
  }

  Widget _buildAppearanceSection() {
    return _buildSection(
      title: '신체 및 특징 정보',
      children: [
        Row(
          children: [
            Expanded(child: _dropdownBox('키',     _heightCtrl,   _heightOpts)),
            const SizedBox(width: 10),
            Expanded(child: _dropdownBox('몸무게', _weightCtrl,   _weightOpts)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _dropdownBox('체격',   _bodyTypeCtrl, _bodyTypeOpts)),
            const SizedBox(width: 10),
            Expanded(child: _dropdownBox('얼굴형', _faceTypeCtrl, _faceShapeOpts)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _dropdownBox('두발 색상', _hairColorCtrl, _hairColorOpts)),
            const SizedBox(width: 10),
            Expanded(child: _dropdownBox('두발 형태', _hairStyleCtrl, _hairStyleOpts)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _dropdownBox('혈액형',    _bloodTypeCtrl, _bloodTypeOpts)),
            const SizedBox(width: 10),
            Expanded(child: _dropdownBox('눈동자 색', _eyeColorCtrl,  _eyeColorOpts)),
          ],
        ),
        const SizedBox(height: 10),
        _editableBox('신체 특징', _physicalFeatureCtrl, maxLines: 3),
        _editableBox('건강 정보', _healthInfoCtrl, maxLines: 3),
      ],
    );
  }

  Widget _buildGuardianSection() {
    return _buildSection(
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
              _editablePinkBox('보호자 이름', _guardianNameCtrl),
              const SizedBox(height: 16),
              _editablePinkBox('보호자 전화번호', _guardianPhoneCtrl),
              const SizedBox(height: 16),
              _buildRrnRow(
                '보호자 주민등록번호',
                _guardianRrnFrontCtrl,
                _guardianRrnBackCtrl,
                _detail?['guardian_rrn_front'],
                _detail?['guardian_rrn_back'],
              ),
          ]
          ),
        ),
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }

  Widget _editableBox(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
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
              controller: controller,
              maxLines: maxLines,
              decoration: InputDecoration(
                labelText: label,
                border: InputBorder.none,
              ),
            )
          : Text('$label : ${controller.text.isEmpty ? '정보 없음' : controller.text}'),
    );
  }

  Widget _editablePinkBox(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFEEEE),
            borderRadius: BorderRadius.circular(12),
            border: _isEditing
                ? Border.all(color: _pointColor, width: 2)
                : Border.all(color: Colors.transparent, width: 2),
          ),
          child: _isEditing
              ? TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                  ),
                )
              : Text(
                  controller.text.isEmpty ? '정보 없음' : controller.text,
                  style: const TextStyle(fontSize: 14),
                ),
        ),
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
      child: Text('$label : $value'),
    );
  }

Widget _buildBadgeSection() {
  String serial = '정보 없음';

  // 1. 백엔드가 device_code를 최상위 필드로 내려주는 경우
  final directDeviceCode =
      _detail?['device_code']?.toString().trim();

  if (directDeviceCode != null &&
      directDeviceCode.isNotEmpty &&
      directDeviceCode != 'null') {
    serial = directDeviceCode;
  } else {
    // 2. device 객체 안에 내려주는 경우
    final device = _detail?['device'];

    if (device is Map) {
      for (final key in [
        'device_code',
        'device_uid',
        'uid',
        'code',
        'serial',
      ]) {
        final value = device[key]?.toString().trim();

        if (value != null &&
            value.isNotEmpty &&
            value != 'null') {
          serial = value;
          break;
        }
      }
    }
  }

  return _buildSection(
    title: '뱃지 정보',
    children: [
      _readOnlyBox(
        '뱃지 일련번호',
        serial,
      ),
    ],
  );
}

Widget _buildAdminStatusSection() {
  return Container(
    margin: const EdgeInsets.only(top: 20),
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
            Text(
              '관리자 전용: 예방등록 상태 변경',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        Row(
          children: [
            _statusBtn('접수 중', 0),
            _statusBtn('확인 중', 1),
          ],
        ),

        const SizedBox(height: 8),

        Row(
          children: [
            _statusBtn('등록 완료', 2),
            _statusBtn('거절됨', 3),
          ],
        ),

        // ✅ 거절 상태 선택 시에만 거절 사유 입력칸 표시
        if (_status == 3) ...[
          const SizedBox(height: 16),

          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '거절 사유',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
          ),

          const SizedBox(height: 8),

          TextField(
            controller: _rejectedReasonCtrl,
            enabled: _isEditing,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: '예: 정면 사진이 명확하지 않아 재등록이 필요합니다.',
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.red.shade100),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.red.shade100),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.red.shade300),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

Widget _statusBtn(String label, int idx) {
  final active = _status == idx;
  final isReject = idx == 3;
  final activeColor = isReject ? const Color(0xFFFFCDD2) : _pointColor;
  final textColor =
      active && isReject ? Colors.red.shade800 : Colors.black;

  return Expanded(
    child: GestureDetector(
      onTap: _isEditing ? () => _updateStatus(idx) : null,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: active && isReject
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

  Widget _buildBottomButton() {
    if (!_canEdit) {
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
                  final rawPhotos = (_detail?['photo_items'] as List?) ??
    (_detail?['photos'] as List?) ??
    [];

_displayPhotos = rawPhotos.map<Map<String, dynamic>>((p) {
  if (p is Map) {
    final m = Map<String, dynamic>.from(p);
    m['image'] = m['url'] ?? m['image_url'] ?? m['photo'] ?? m['file'] ?? m['image'];
    return m;
  }
  return {'image': p.toString()};
}).toList();

    final mainPhoto = _detail?['main_photo']?.toString() ?? '';

    if (_displayPhotos.isEmpty && mainPhoto.isNotEmpty) {
      _displayPhotos = [
        {
          'id': null,
          'image_url': mainPhoto,
          'image': mainPhoto,
          'photo_type': 'face',
          'validation_status': null,
          'validation_message': '대표 사진',
        }
      ];
    }
                });
                _addressDetailCtrl.text = '';
                final detail = _detail;
                if (detail != null) {
                  _setDetail(detail);
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
                  child: Text(
                    '취소',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: InkWell(
              onTap: _saveEdit,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(
                  color: _pointColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text(
                    '수정완료',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return InkWell(
      onTap: () {
        setState(() {
          _originalStatus = _status;
          _isEditing = true;
        });
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1BE),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Center(
          child: Text(
            '수정하기',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
      ),
    );
  }
}

