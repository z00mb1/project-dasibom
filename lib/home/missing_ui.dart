import '../config/api_config.dart';
import '../config/utils.dart';
import 'package:flutter/material.dart';

/// ===============================
/// 📌 1. 모델 (백엔드 JSON 구조에 맞게 수정)
/// ===============================
class MissingPerson {
  final int id;
  final String name;
  final int age;
  final String gender;
  final String category;
  final String? photoUrl;
  final String registeredDate;

  MissingPerson({
    required this.id,
    required this.name,
    required this.age,
    required this.gender,
    required this.category,
    this.photoUrl,
    required this.registeredDate,
  });

  factory MissingPerson.fromJson(Map<String, dynamic> json) {
    // 🚀 [비판적 보완] 백엔드는 photos 리스트가 아니라 photo 문자열을 직접 줍니다.
    String? imageUrl = extractPhotoUrl(json['photo']);
    
    // 만약 서버 주소가 포함되지 않은 상대 경로라면 baseUrl을 붙여줍니다.
    // 현재 백엔드는 full URL(http://...)을 주므로 그대로 사용하거나 검증 로직 추가
    if (imageUrl != null && !imageUrl.startsWith('http')) {
      imageUrl = "${ApiConfig.baseUrl}$imageUrl";
    }

    return MissingPerson(
      id: json['id'] ?? 0,
      name: json['name']?.toString() ?? '이름 없음',
      // 백엔드 키값: current_age
      age: int.tryParse(json['current_age']?.toString() ?? '') ?? 0,
      // 백엔드 키값: gender_display
      gender: json['gender_display']?.toString() ?? '미상',
      // 백엔드 키값: category_display
      category: json['category_display']?.toString() ?? '기타',
      photoUrl: imageUrl,
      // 백엔드 키값: registered_date
      registeredDate: json['registered_date']?.toString() ?? '',
    );
  }
}

/// ===============================
/// 📌 2. 카드 UI (기존 레이아웃 유지 및 최적화)
/// ===============================
class MissingCard extends StatelessWidget {
  final MissingPerson person;

  const MissingCard({super.key, required this.person});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8), 
      padding: const EdgeInsets.all(6), // 카드 전체 여백 최소화
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9E5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- 텍스트 정보 영역 ---
            Expanded(
              flex: 13,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), // 내부 세로 여백 최소화
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center, 
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 🚀 모든 텍스트 크기를 13으로 통일하여 호출
                    _buildInfoText("이름", person.name),
                    _buildInfoText("성별", person.gender),
                    _buildInfoText("나이", "${person.age}세"),
                    _buildInfoText("유형", person.category),
                    _buildInfoText("등록일", person.registeredDate, isLast: true),
                  ],
                ),
              ),
            ),
            
            const SizedBox(width: 6), 

            // --- 사진 영역 ---
            Expanded(
              flex: 9, // 🚀 [수정] 사진 가로 비중을 살짝 줄여서 전체 높이 하락 유도
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFDEE5F3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(
                    // 🚀 [핵심] 비율을 1:1(정사각형)에 가깝게 하면 세로가 더 짧아집니다.
                    aspectRatio: 1.0, 
                    child: person.photoUrl != null && person.photoUrl!.isNotEmpty
                        ? Image.network(
                            person.photoUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Center(child: Icon(Icons.person, size: 30, color: Colors.grey)),
                          )
                        : const Center(child: Icon(Icons.person, size: 30, color: Colors.grey)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 🚀 [수정] 텍스트 크기와 스타일을 완전히 동일하게 맞춘 함수
  Widget _buildInfoText(String label, String value, {bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 2), // 줄 사이 간격 최소화
      child: Text(
        "$label : $value",
        style: const TextStyle(
          fontSize: 15, // 🚀 글자 크기 13으로 통일
          color: Colors.black87,
          height: 1.1, // 🚀 줄 간격을 바짝 붙임
          fontWeight: FontWeight.w400, // 볼드체 제외, 기본 서체 사용
        ),
      ),
    );
  }
}

/// ===============================
/// 📌 3. 섹션 UI
/// ===============================
class MissingSection extends StatelessWidget {
  final String title;
  final List<MissingPerson> list;

  const MissingSection({
    super.key,
    required this.title,
    required this.list,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (list.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text("등록된 실종자가 없습니다.", style: TextStyle(color: Colors.grey)),
          )
        else
          // 🚀 [비판적 보완] 시안에 맞춰 첫 번째 사람만 보여주거나 리스트로 뿌려줍니다.
          MissingCard(person: list.first),
      ],
    );
  }
}