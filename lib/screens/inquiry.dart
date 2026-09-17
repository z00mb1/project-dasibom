import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';

class InquiryPage extends StatefulWidget {
  const InquiryPage({super.key});

  @override
  State<InquiryPage> createState() => _InquiryPageState();
}

class _InquiryPageState extends State<InquiryPage> {
  bool _isAdmin = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> _inquiries = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role');
    if (!mounted) return;
    setState(() => _isAdmin = role == 'admin');
    await _fetchInquiries();
  }

  Future<void> _fetchInquiries() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access') ?? '';
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/support/inquiry/"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        final list = (data is List
            ? data
            : (data['results'] ?? data['inquiries'] ?? [])) as List;
        setState(() {
          _inquiries =
              list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        });
      }
    } catch (e) {
      debugPrint("문의 목록 로드 실패: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showWriteSheet() {
    final ctrl = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        bool isSubmitting = false;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("문의 작성",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    "궁금한 점이나 불편사항을 남겨주세요.",
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: ctrl,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(14),
                        hintText: "문의 내용을 입력해 주세요.",
                        hintStyle: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              if (ctrl.text.trim().isEmpty) {
                                messenger.showSnackBar(const SnackBar(
                                    content: Text("문의 내용을 입력해 주세요.")));
                                return;
                              }
                              setModalState(() => isSubmitting = true);
                              try {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                final token = prefs.getString('access') ?? '';
                                final res = await http.post(
                                  Uri.parse(
                                      "${ApiConfig.baseUrl}/support/inquiry/"),
                                  headers: {
                                    "Authorization": "Bearer $token",
                                    "Content-Type": "application/json",
                                  },
                                  body: jsonEncode(
                                      {"content": ctrl.text.trim()}),
                                );
                                if (!ctx.mounted) return;
                                Navigator.pop(ctx);
                                messenger.showSnackBar(SnackBar(
                                  content: Text(
                                    res.statusCode == 200 ||
                                            res.statusCode == 201
                                        ? "문의가 접수되었습니다."
                                        : "문의 접수에 실패했습니다.",
                                  ),
                                ));
                                if (res.statusCode == 200 ||
                                    res.statusCode == 201) {
                                  _fetchInquiries();
                                }
                              } catch (e) {
                                if (!ctx.mounted) return;
                                Navigator.pop(ctx);
                                messenger.showSnackBar(const SnackBar(
                                    content: Text("문의 접수에 실패했습니다.")));
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFDE14C),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.black54))
                          : const Text("문의 접수하기",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
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

  void _showAnswerSheet(Map<String, dynamic> inquiry) {
    final ctrl = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final id = inquiry['id'];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        bool isSubmitting = false;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("답변 작성",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      inquiry['content']?.toString() ?? '',
                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: ctrl,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(14),
                        hintText: "답변 내용을 입력해 주세요.",
                        hintStyle: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              if (ctrl.text.trim().isEmpty) {
                                messenger.showSnackBar(const SnackBar(
                                    content: Text("답변 내용을 입력해 주세요.")));
                                return;
                              }
                              setModalState(() => isSubmitting = true);
                              try {
                                final prefs =
                                    await SharedPreferences.getInstance();
                                final token = prefs.getString('access') ?? '';
                                final res = await http.patch(
                                  Uri.parse(
                                      "${ApiConfig.baseUrl}/support/inquiry/$id/"),
                                  headers: {
                                    "Authorization": "Bearer $token",
                                    "Content-Type": "application/json",
                                  },
                                  body: jsonEncode({
                                    "answer": ctrl.text.trim(),
                                    "is_answered": true,
                                  }),
                                );
                                if (!ctx.mounted) return;
                                Navigator.pop(ctx);
                                messenger.showSnackBar(SnackBar(
                                  content: Text(res.statusCode == 200
                                      ? "답변이 등록되었습니다."
                                      : "답변 등록에 실패했습니다."),
                                ));
                                if (res.statusCode == 200) _fetchInquiries();
                              } catch (e) {
                                if (!ctx.mounted) return;
                                Navigator.pop(ctx);
                                messenger.showSnackBar(const SnackBar(
                                    content: Text("답변 등록에 실패했습니다.")));
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text("답변 등록",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8DE),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isAdmin ? "문의 현황" : "문의하기",
          style: const TextStyle(
              color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      floatingActionButton: _isAdmin
          ? null
          : FloatingActionButton.extended(
              onPressed: _showWriteSheet,
              backgroundColor: const Color(0xFFFDE14C),
              foregroundColor: Colors.black,
              elevation: 2,
              icon: const Icon(Icons.edit),
              label: const Text("문의 작성",
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchInquiries,
              child: _inquiries.isEmpty
                  ? _buildEmpty()
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                      itemCount: _inquiries.length,
                      itemBuilder: (context, index) =>
                          _buildInquiryCard(_inquiries[index]),
                    ),
            ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.55,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.help_outline, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text(
                  _isAdmin
                      ? "접수된 문의가 없습니다."
                      : "아직 문의 내역이 없어요.\n아래 버튼을 눌러 문의해 주세요!",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.grey.shade500, fontSize: 14, height: 1.6),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInquiryCard(Map<String, dynamic> inquiry) {
    final isAnswered =
        inquiry['is_answered'] == true || inquiry['status'] == 'answered';
    final content = inquiry['content']?.toString() ?? '';
    final answer = inquiry['answer']?.toString() ?? '';
    final createdAt = _formatDate(inquiry['created_at']?.toString());
    final reporterName = inquiry['reporter_name']?.toString() ??
        inquiry['user_name']?.toString() ??
        inquiry['username']?.toString() ??
        '사용자';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: isAnswered
                  ? const Color(0xFFE8F5E9)
                  : const Color(0xFFFFF9C4),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(
                  isAnswered ? Icons.check_circle_outline : Icons.schedule,
                  size: 15,
                  color: isAnswered
                      ? Colors.green.shade600
                      : Colors.orange.shade700,
                ),
                const SizedBox(width: 5),
                Text(
                  isAnswered ? "답변 완료" : "답변 대기 중",
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: isAnswered
                        ? Colors.green.shade700
                        : Colors.orange.shade800,
                  ),
                ),
                const Spacer(),
                if (_isAdmin) ...[
                  Text(reporterName,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(width: 8),
                ],
                Text(createdAt,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black45)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(content,
                    style: const TextStyle(
                        fontSize: 14, height: 1.5, color: Colors.black87)),
                if (isAnswered && answer.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.support_agent,
                          size: 14, color: Colors.blue.shade400),
                      const SizedBox(width: 4),
                      Text("운영팀 답변",
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade600,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(answer,
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                          height: 1.5)),
                ],
                if (_isAdmin && !isAnswered) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showAnswerSheet(inquiry),
                      icon: const Icon(Icons.reply, size: 16),
                      label: const Text("답변 달기"),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blueGrey,
                        side: const BorderSide(color: Colors.blueGrey),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    try {
      final dt = DateTime.parse(raw).toLocal();
      return "${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}";
    } catch (_) {
      return raw;
    }
  }
}
