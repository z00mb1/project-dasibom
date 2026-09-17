import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

// ── 액션 타입 ──────────────────────────────────────────────────────────────
enum _ActionType {
  kioskEmergency,
  tipReceived,
  reportReceived,
  tipStatusChanged,
  missingRegistered,
  missingRejected,
  caseUpdated,

  tipDeleted,
  reportDeleted,
  missingFound,
  missingStatusChanged,
  missingDeleted,

  preventionRegistered,
  preventionUpdated,
  preventionDeactivated,
  preventionDeleted,
  preventionRejected,
  preventionCompleted,
  preventionStatusChanged,

  locationShared,
  montageCreated,
  montageApplied,
  montageUpdated,
}

// ── 로그 항목 모델 ──────────────────────────────────────────────────────────
class _LogEntry {
  final int id;
  final DateTime timestamp;       // 정렬·그룹핑용 (ISO 파싱)
  final String displayTimestamp;  // 화면 표시용 문자열
  final _ActionType actionType;
  final String targetName;
  final String? caseId;
  final String? fromStatus;
  final String? toStatus;
  final String adminName;
  final String? guardianName;
  final String? wardName;
  final String? kioskNumber;

  const _LogEntry({
    required this.id,
    required this.timestamp,
    required this.displayTimestamp,
    required this.actionType,
    required this.targetName,
    this.caseId,
    this.fromStatus,
    this.toStatus,
    required this.adminName,
    this.guardianName,
    this.wardName,
    this.kioskNumber,
  });

  static DateTime _parseTimestamp(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return DateTime.now();
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      try {
        return DateTime.parse(raw.replaceFirst(' ', 'T')).toLocal();
      } catch (_) {
        return DateTime.now();
      }
    }
  }

  factory _LogEntry.fromJson(Map<String, dynamic> json) {
    final rawDisplay = json['display_timestamp']?.toString() ??
        json['timestamp']?.toString() ?? '';

    return _LogEntry(
      id: json['id'] ?? 0,
      timestamp: _parseTimestamp(
        json['timestamp_iso'] ??
        json['created_at'] ??
        json['timestamp'] ??
        json['ts'] ??
        json['date'],
      ),
      displayTimestamp: rawDisplay,
      actionType: _parseActionType(json['actionType'] ?? json['action_type'] ?? ''),
      targetName: json['targetName'] ?? json['target_name'] ?? '대상자',
      caseId: json['caseId'] ?? json['case_id'],
      fromStatus: _displayStatus(json['fromStatus'] ?? json['from_status']),
      toStatus: _displayStatus(json['toStatus'] ?? json['to_status']),
      adminName: json['adminName'] ?? json['admin_name'] ?? '관리자',
      guardianName: (json['guardianName'] ?? json['guardian_name'])?.toString(),
      wardName: (json['wardName'] ?? json['ward_name'])?.toString(),
      kioskNumber: (json['kioskNumber'] ?? json['kiosk_number'])?.toString(),
    );
  }

  static String? _displayStatus(dynamic value) {
    if (value == null) return null;

    final status = value.toString().trim();

    switch (status) {
      case 'received':
        return '접수 중';
      case 'reviewing':
        return '확인 중';
      case 'completed':
        return '등록 완료';
      case 'rejected':
        return '거절';
      case 'missing':
        return '실종';
      case 'found':
        return '발견';
      default:
        return status.isEmpty ? null : status;
    }
  }

  String get description {
    switch (actionType) {
      case _ActionType.kioskEmergency:
        return '$targetName 긴급신고 발생';
      case _ActionType.tipReceived:
        return '$targetName 관련 제보 접수';
      case _ActionType.tipStatusChanged:
        return '$targetName 상태 변경';
      case _ActionType.tipDeleted:
        return '$targetName 제보 삭제';
      case _ActionType.reportReceived:
        return '$targetName 실종 신고 접수';
      case _ActionType.reportDeleted:
        return '$targetName 신고 삭제';
      case _ActionType.missingRegistered:
        return '$targetName 실종자 등록 완료';
      case _ActionType.missingRejected:
        return '$targetName 거절 처리';
      case _ActionType.missingFound:
        return '$targetName 발견 완료 처리';
      case _ActionType.missingStatusChanged:
        return '$targetName 실종자 상태 변경';
      case _ActionType.missingDeleted:
        return '$targetName 실종자 삭제';
      case _ActionType.caseUpdated:
        return '$targetName 정보 수정';
      case _ActionType.preventionRegistered:
        return '$targetName 실종예방등록 접수';
      case _ActionType.preventionUpdated:
        return '$targetName 실종예방등록 수정';
      case _ActionType.preventionDeactivated:
        return '$targetName 실종예방등록 비활성화';
      case _ActionType.preventionDeleted:
        return '$targetName 실종예방등록 삭제';
      case _ActionType.preventionRejected:
        return '$targetName 실종예방등록 거절';
      case _ActionType.preventionCompleted:
        return '$targetName 실종예방등록 완료';
      case _ActionType.preventionStatusChanged:
        return '$targetName 실종예방등록 상태 변경';
      case _ActionType.locationShared:
        return '$targetName 위치 공유';
      case _ActionType.montageCreated:
        return '$targetName 몽타주 생성';
      case _ActionType.montageApplied:
        return '$targetName 몽타주 적용';
      case _ActionType.montageUpdated:
        return '$targetName 몽타주 수정';
    }
  }

  Color get dotColor {
    switch (actionType) {
      case _ActionType.kioskEmergency:
        return Colors.red.shade600;
      case _ActionType.tipReceived:
      case _ActionType.reportReceived:
        return const Color(0xFFFDE14C);
      case _ActionType.preventionRegistered:
      case _ActionType.preventionUpdated:
      case _ActionType.preventionCompleted:
        return const Color(0xFFFFDF60);
      case _ActionType.tipStatusChanged:
      case _ActionType.missingStatusChanged:
      case _ActionType.preventionStatusChanged:
        return Colors.blue.shade300;
      case _ActionType.missingRegistered:
      case _ActionType.missingFound:
        return Colors.green.shade400;
      case _ActionType.missingRejected:
      case _ActionType.preventionRejected:
        return Colors.red.shade300;
      case _ActionType.tipDeleted:
      case _ActionType.reportDeleted:
      case _ActionType.missingDeleted:
      case _ActionType.preventionDeleted:
      case _ActionType.preventionDeactivated:
        return Colors.red.shade200;
      case _ActionType.caseUpdated:
        return Colors.grey.shade400;
      case _ActionType.locationShared:
        return Colors.teal.shade300;
      case _ActionType.montageCreated:
      case _ActionType.montageApplied:
      case _ActionType.montageUpdated:
        return Colors.purple.shade300;
    }
  }

  Color get badgeColor {
    switch (actionType) {
      case _ActionType.kioskEmergency:
        return const Color(0xFFFFEBEE);
      case _ActionType.tipReceived:
      case _ActionType.reportReceived:
      case _ActionType.preventionRegistered:
      case _ActionType.preventionUpdated:
      case _ActionType.preventionCompleted:
        return const Color(0xFFFFF8DC);
      case _ActionType.tipStatusChanged:
      case _ActionType.missingStatusChanged:
      case _ActionType.preventionStatusChanged:
        return Colors.blue.shade50;
      case _ActionType.missingRegistered:
      case _ActionType.missingFound:
        return Colors.green.shade50;
      case _ActionType.missingRejected:
      case _ActionType.preventionRejected:
      case _ActionType.tipDeleted:
      case _ActionType.reportDeleted:
      case _ActionType.missingDeleted:
      case _ActionType.preventionDeleted:
      case _ActionType.preventionDeactivated:
        return Colors.red.shade50;
      case _ActionType.caseUpdated:
        return Colors.grey.shade100;
      case _ActionType.locationShared:
        return Colors.teal.shade50;
      case _ActionType.montageCreated:
      case _ActionType.montageApplied:
      case _ActionType.montageUpdated:
        return Colors.purple.shade50;
    }
  }

  Color get badgeTextColor {
    switch (actionType) {
      case _ActionType.kioskEmergency:
        return Colors.red.shade800;
      case _ActionType.tipReceived:
      case _ActionType.reportReceived:
      case _ActionType.preventionRegistered:
      case _ActionType.preventionUpdated:
      case _ActionType.preventionCompleted:
        return Colors.orange.shade800;
      case _ActionType.tipStatusChanged:
      case _ActionType.missingStatusChanged:
      case _ActionType.preventionStatusChanged:
        return Colors.blue.shade700;
      case _ActionType.missingRegistered:
      case _ActionType.missingFound:
        return Colors.green.shade700;
      case _ActionType.missingRejected:
      case _ActionType.preventionRejected:
      case _ActionType.tipDeleted:
      case _ActionType.reportDeleted:
      case _ActionType.missingDeleted:
      case _ActionType.preventionDeleted:
      case _ActionType.preventionDeactivated:
        return Colors.red.shade700;
      case _ActionType.caseUpdated:
        return Colors.grey.shade700;
      case _ActionType.locationShared:
        return Colors.teal.shade700;
      case _ActionType.montageCreated:
      case _ActionType.montageApplied:
      case _ActionType.montageUpdated:
        return Colors.purple.shade700;
    }
  }

  String get badgeLabel {
    switch (actionType) {
      case _ActionType.kioskEmergency:
        return '긴급신고';
      case _ActionType.tipReceived:
        return '제보 접수';
      case _ActionType.tipDeleted:
        return '제보 삭제';
      case _ActionType.tipStatusChanged:
        return '상태 변경';
      case _ActionType.reportReceived:
        return '신고 접수';
      case _ActionType.reportDeleted:
        return '신고 삭제';
      case _ActionType.missingRegistered:
        return '등록 완료';
      case _ActionType.missingRejected:
        return '거절';
      case _ActionType.missingFound:
        return '발견 완료';
      case _ActionType.missingStatusChanged:
        return '상태 변경';
      case _ActionType.missingDeleted:
        return '실종자 삭제';
      case _ActionType.caseUpdated:
        return '정보 수정';
      case _ActionType.preventionRegistered:
        return '예방등록 접수';
      case _ActionType.preventionUpdated:
        return '예방등록 수정';
      case _ActionType.preventionDeactivated:
        return '예방등록 비활성';
      case _ActionType.preventionDeleted:
        return '예방등록 삭제';
      case _ActionType.preventionRejected:
        return '예방등록 거절';
      case _ActionType.preventionCompleted:
        return '예방등록 완료';
      case _ActionType.preventionStatusChanged:
        return '예방등록 변경';
      case _ActionType.locationShared:
        return '위치 공유';
      case _ActionType.montageCreated:
        return '몽타주 생성';
      case _ActionType.montageApplied:
        return '몽타주 적용';
      case _ActionType.montageUpdated:
        return '몽타주 수정';
    }
  }
}

_ActionType _parseActionType(String value) {
  switch (value) {
    case 'kioskEmergency':
    case 'emergencyReceived':
      return _ActionType.kioskEmergency;

    case 'tipReceived':
      return _ActionType.tipReceived;
    case 'reportReceived':
      return _ActionType.reportReceived;
    case 'tipStatusChanged':
      return _ActionType.tipStatusChanged;
    case 'missingRegistered':
      return _ActionType.missingRegistered;
    case 'missingRejected':
      return _ActionType.missingRejected;
    case 'caseUpdated':
      return _ActionType.caseUpdated;

    case 'tipDeleted':
      return _ActionType.tipDeleted;
    case 'reportDeleted':
      return _ActionType.reportDeleted;
    case 'missingFound':
      return _ActionType.missingFound;
    case 'missingStatusChanged':
      return _ActionType.missingStatusChanged;
    case 'missingDeleted':
      return _ActionType.missingDeleted;

    case 'preventionRegistered':
      return _ActionType.preventionRegistered;
    case 'preventionUpdated':
      return _ActionType.preventionUpdated;
    case 'preventionDeactivated':
      return _ActionType.preventionDeactivated;
    case 'preventionDeleted':
      return _ActionType.preventionDeleted;
    case 'preventionRejected':
      return _ActionType.preventionRejected;
    case 'preventionCompleted':
      return _ActionType.preventionCompleted;
    case 'preventionStatusChanged':
      return _ActionType.preventionStatusChanged;

    case 'locationShared':
      return _ActionType.locationShared;
    case 'montageCreated':
      return _ActionType.montageCreated;
    case 'montageApplied':
      return _ActionType.montageApplied;
    case 'montageUpdated':
      return _ActionType.montageUpdated;

    default:
      return _ActionType.caseUpdated;
  }
}

// ── 페이지 ─────────────────────────────────────────────────────────────────
class AdminLogPage extends StatefulWidget {
  const AdminLogPage({super.key});

  @override
  State<AdminLogPage> createState() => _AdminLogPageState();
}

class _AdminLogPageState extends State<AdminLogPage> {
  bool _isLoading = false;
  List<_LogEntry> _logs = [];

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  @override
  void dispose() {
    super.dispose();
  }

  // 백엔드 API 연결 시 이 메서드에서 데이터를 가져와 _logs에 할당
  Future<void> _fetchLogs({
    String? actionType,
    String? targetType,
    String? keyword,
    String? startDate,
    String? endDate,
  }) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access');

      if (!mounted) return;

      if (accessToken == null || accessToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인이 필요합니다.')),
        );

        setState(() {
          _logs = [];
          _isLoading = false;
        });

        return;
      }

      final queryParams = <String, String>{};

      if (actionType != null && actionType.isNotEmpty) {
        queryParams['actionType'] = actionType;
      }
      if (targetType != null && targetType.isNotEmpty) {
        queryParams['target_type'] = targetType;
      }
      if (keyword != null && keyword.isNotEmpty) {
        queryParams['keyword'] = keyword;
      }
      if (startDate != null && startDate.isNotEmpty) {
        queryParams['start_date'] = startDate;
      }
      if (endDate != null && endDate.isNotEmpty) {
        queryParams['end_date'] = endDate;
      }

      final uri = Uri.parse(
        '${ApiConfig.baseUrl}/log/admin-timeline/',
      ).replace(queryParameters: queryParams.isEmpty ? null : queryParams);

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
        },
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        final List<dynamic> decoded = jsonDecode(utf8.decode(response.bodyBytes));

        final logs = decoded
            .map((item) => _LogEntry.fromJson(item as Map<String, dynamic>))
            .toList();

        logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

        setState(() {
          _logs = logs;
        });
      } else if (response.statusCode == 401) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('로그인이 만료되었습니다. 다시 로그인해 주세요.')),
        );
      } else if (response.statusCode == 403) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('관리자만 로그를 조회할 수 있습니다.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그 조회 실패: ${response.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('관리자 로그 조회 중 오류가 발생했습니다: $e')),
      );
    }

    if (!mounted) return;

    setState(() {
      _isLoading = false;
    });
  }

  // 날짜별 그룹화
  Map<String, List<_LogEntry>> get _grouped {
    final map = <String, List<_LogEntry>>{};
    for (final log in _logs) {
      final key =
          '${log.timestamp.year}/${log.timestamp.month.toString().padLeft(2, '0')}/${log.timestamp.day.toString().padLeft(2, '0')}';
      map.putIfAbsent(key, () => []).add(log);
    }
    return map;
  }

  bool _isToday(String dateKey) {
    final now = DateTime.now();
    final todayKey =
        '${now.year}/${now.month.toString().padLeft(2, '0')}/${now.day.toString().padLeft(2, '0')}';
    return dateKey == todayKey;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final dateKeys = grouped.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // 최신 날짜 먼저

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
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
                const Icon(Icons.favorite, color: Colors.pink),
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
              ? const Center(
                  child: Text('로그가 없습니다.',
                      style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  itemCount: dateKeys.length,
                  itemBuilder: (context, index) {
                    final key = dateKeys[index];
                    return _buildDateGroup(
                        key, grouped[key]!, _isToday(key));
                  },
                ),
    );
  }

  Widget _buildDateGroup(
      String dateKey, List<_LogEntry> entries, bool isToday) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 44, top: 16, bottom: 10),
          child: Row(
            children: [
              Text(
                isToday ? '$dateKey (오늘)' : dateKey,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${entries.length}건',
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          ),
        ),
        ...List.generate(entries.length, (i) {
          final isFirst = isToday && i == 0;
          final isLast = i == entries.length - 1;
          return _buildTimelineItem(entries[i], isFirst: isFirst,
              isLast: isLast);
        }),
      ],
    );
  }

  Widget _buildTimelineItem(_LogEntry entry,
      {required bool isFirst, required bool isLast}) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 타임라인 선 + 점
          SizedBox(
            width: 44,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!isLast)
                  Positioned(
                    top: 20,
                    bottom: 0,
                    child: Container(
                        width: 3, color: const Color(0xFFF0F0F0)),
                  ),
                Positioned(
                  top: 8,
                  child: Container(
                    width: isFirst ? 22 : 16,
                    height: isFirst ? 22 : 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: entry.dotColor,
                      boxShadow: isFirst
                          ? [
                              BoxShadow(
                                color: entry.dotColor.withValues(alpha: 0.4),
                                blurRadius: 6,
                                spreadRadius: 2,
                              )
                            ]
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 카드
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12, right: 4),
              child: _buildLogCard(entry, isFirst: isFirst),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(_LogEntry entry, {required bool isFirst}) {
    final isEmergency = entry.actionType == _ActionType.kioskEmergency;

    final time = entry.displayTimestamp.isNotEmpty
        ? entry.displayTimestamp
        : '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isEmergency ? const Color(0xFFFFFAFA) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isEmergency
              ? Colors.red.shade300
              : isFirst
                  ? entry.dotColor.withValues(alpha: 0.6)
                  : const Color(0xFFF0F0F0),
          width: isEmergency
              ? 2
              : isFirst
                  ? 1.5
                  : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                time,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black45,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 8),
              _buildBadge(
                entry.badgeLabel,
                entry.badgeColor,
                entry.badgeTextColor,
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 13,
                    color: Colors.black38,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    entry.adminName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black38,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),

          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.4,
              ),
              children: _buildDescriptionSpans(entry),
            ),
          ),

          if (entry.caseId != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isEmergency
                    ? const Color(0xFFFFEBEE)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '# ${entry.caseId}',
                style: TextStyle(
                  fontSize: 12,
                  color: isEmergency ? Colors.red.shade700 : Colors.black45,
                  fontFamily: 'monospace',
                  fontWeight: isEmergency ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<InlineSpan> _buildDescriptionSpans(_LogEntry entry) {
    final from = entry.fromStatus?.trim();
    final to = entry.toStatus?.trim();

    final hasStatusChange = from != null &&
        from.isNotEmpty &&
        to != null &&
        to.isNotEmpty;

    if (hasStatusChange) {
      return [
        TextSpan(
          text: entry.targetName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const TextSpan(text: ' 상태가 '),
        TextSpan(
          text: from,
          style: const TextStyle(
            color: Colors.black54,
            decoration: TextDecoration.lineThrough,
          ),
        ),
        const TextSpan(text: '에서 '),
        TextSpan(
          text: to,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _statusTextColor(to),
          ),
        ),
        const TextSpan(text: '(으)로 변경되었습니다'),
      ];
    }

    switch (entry.actionType) {
      case _ActionType.kioskEmergency:
        return [
          const TextSpan(
            text: '긴급신고 발생! ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          TextSpan(
            text: entry.targetName,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          const TextSpan(
            text: '에서 키오스크 긴급신고 버튼이 눌렸습니다.',
          ),
        ];

      case _ActionType.tipReceived:
        return [
          TextSpan(
            text: entry.targetName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const TextSpan(text: ' 관련 제보가 접수되었습니다'),
        ];

      case _ActionType.tipStatusChanged:
        return [
          TextSpan(
            text: entry.targetName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const TextSpan(text: ' 제보 상태가 변경되었습니다'),
        ];

      case _ActionType.reportReceived:
        return [
          TextSpan(
            text: entry.targetName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const TextSpan(text: ' 실종 신고가 접수되었습니다'),
        ];

      case _ActionType.missingRegistered:
        return [
          TextSpan(
            text: entry.targetName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const TextSpan(text: ' 실종자 등록이 완료되었습니다'),
        ];

      case _ActionType.missingRejected:
        return [
          TextSpan(
            text: entry.targetName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const TextSpan(text: ' 처리가 거절되었습니다'),
        ];

      case _ActionType.caseUpdated:
        return [
          TextSpan(
            text: entry.targetName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const TextSpan(text: ' 정보가 수정되었습니다'),
        ];

      case _ActionType.preventionRegistered:
        return [
          TextSpan(
            text: entry.targetName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const TextSpan(text: ' 실종예방등록이 접수되었습니다'),
        ];

      case _ActionType.preventionStatusChanged:
        return [
          TextSpan(text: entry.targetName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const TextSpan(text: ' 실종예방등록 상태가 변경되었습니다'),
        ];
      case _ActionType.tipDeleted:
        return [
          TextSpan(text: entry.targetName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const TextSpan(text: ' 제보가 삭제되었습니다'),
        ];
      case _ActionType.reportDeleted:
        return [
          TextSpan(text: entry.targetName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const TextSpan(text: ' 신고가 삭제되었습니다'),
        ];
      case _ActionType.missingFound:
        return [
          TextSpan(text: entry.targetName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const TextSpan(text: ' 발견 완료 처리되었습니다'),
        ];
      case _ActionType.missingStatusChanged:
        return [
          TextSpan(text: entry.targetName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const TextSpan(text: ' 실종자 상태가 변경되었습니다'),
        ];
      case _ActionType.missingDeleted:
        return [
          TextSpan(text: entry.targetName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const TextSpan(text: ' 실종자가 삭제되었습니다'),
        ];
      case _ActionType.preventionUpdated:
        return [
          TextSpan(text: entry.targetName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const TextSpan(text: ' 실종예방등록 정보가 수정되었습니다'),
        ];
      case _ActionType.preventionDeactivated:
        return [
          TextSpan(text: entry.targetName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const TextSpan(text: ' 실종예방등록이 비활성화되었습니다'),
        ];
      case _ActionType.preventionDeleted:
        return [
          TextSpan(text: entry.targetName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const TextSpan(text: ' 실종예방등록이 삭제되었습니다'),
        ];
      case _ActionType.preventionRejected:
        return [
          TextSpan(text: entry.targetName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const TextSpan(text: ' 실종예방등록이 거절되었습니다'),
        ];
      case _ActionType.preventionCompleted:
        return [
          TextSpan(text: entry.targetName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const TextSpan(text: ' 실종예방등록이 완료되었습니다'),
        ];
      case _ActionType.locationShared:
        return [
          TextSpan(
            text: entry.targetName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const TextSpan(text: '의 위치가 '),
          TextSpan(
            text: entry.wardName ?? '피보호자',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const TextSpan(text: '님의 보호자 '),
          TextSpan(
            text: entry.guardianName ?? '보호자',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const TextSpan(text: '에게 공유되었습니다'),
        ];
      case _ActionType.montageCreated:
        return [
          TextSpan(text: entry.targetName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const TextSpan(text: ' 몽타주가 생성되었습니다'),
        ];
      case _ActionType.montageApplied:
        return [
          TextSpan(text: entry.targetName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const TextSpan(text: ' 몽타주가 적용되었습니다'),
        ];
      case _ActionType.montageUpdated:
        return [
          TextSpan(text: entry.targetName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const TextSpan(text: ' 몽타주가 수정되었습니다'),
        ];
    }
  }

  Color _statusTextColor(String status) {
      switch (status) {
        case '확인 중':
          return Colors.blueAccent;
        case '등록 완료':
          return Colors.green;
        case '거절':
          return Colors.red;
        case '접수 중':
          return Colors.orange;
        default:
          return Colors.blueAccent;
      }
  }

  Widget _buildBadge(String label, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: textColor),
      ),
    );
  }
}
