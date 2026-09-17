import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/missing_list_model.dart';
import 'missing_detail.dart';

class MissingListPage extends StatefulWidget {
  const MissingListPage({super.key});

  @override
  State<MissingListPage> createState() => _MissingListPageState();
}

class _MissingListPageState extends State<MissingListPage> {
  String selectedCategory = "전체";
  String selectedRegion = "전체";
  Future<List<MissingListPerson>>? currentFuture;

  String convertGender(String gender) {
    switch (gender.toLowerCase()) {
      case "male":
        return "남";
      case "female":
        return "여";
      default:
        return gender;
    }
  }

  final categories = ["전체", "장애", "치매", "아동", "기타"];
  final regions = [
    "전체", "서울", "경기", "인천", "강원",
    "충북", "충남", "대전", "세종",
    "경북", "경남", "대구", "부산", "울산",
    "전북", "전남", "광주", "제주",
  ];
  
  @override
  void initState() {
    super.initState();
    selectedTab = "finding";
    currentFuture = fetchFinding();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<List<MissingListPerson>> fetchData(Uri url) async {
  try {
    final response = await http.get(url);
    if (response.statusCode != 200) return [];

    final decoded = jsonDecode(response.body);

    // ✅ results 키가 있으면 페이지네이션 응답, 없으면 일반 List
    final List data = decoded is Map ? decoded['results'] : decoded;

    return data.map<MissingListPerson>((e) => MissingListPerson.fromJson(e)).toList();
  } catch (e) {
    debugPrint("🔥 fetchData 에러 = $e");
    return [];
  }
}

  // 🔥 찾는 중 API
  Future<List<MissingListPerson>> fetchFinding() async {
    final queryParams = <String, String>{};

    // 검색어
    if (_searchQuery.trim().isNotEmpty) {
      queryParams['search'] = _searchQuery.trim();
    }

    // 카테고리
    if (selectedCategory != "전체") {
      queryParams['category'] = selectedCategory;
    }

    // 지역
    if (selectedRegion != "전체") {
      queryParams['sido'] = selectedRegion;
      // 또는 서버에서 region 단일 검색을 더 잘 처리한다면:
      // queryParams['region'] = selectedRegion;
    }

    final url = Uri.parse("${ApiConfig.baseUrl}/missingperson/cards/")
        .replace(queryParameters: queryParams.isEmpty ? null : queryParams);

    return await fetchData(url);
  }

  // 🔥 보호 중 API
  Future<List<MissingListPerson>> fetchProtecting() async {
    final queryParams = <String, String>{};

    if (_searchQuery.trim().isNotEmpty) {
      queryParams['search'] = _searchQuery.trim();
    }

    if (selectedCategory != "전체") {
      queryParams['category'] = selectedCategory;
    }

    if (selectedRegion != "전체") {
      queryParams['sido'] = selectedRegion;
    }

    final url = Uri.parse("${ApiConfig.baseUrl}/protectedperson/cards/")
        .replace(queryParameters: queryParams.isEmpty ? null : queryParams);

    return await fetchData(url);
  }

  // ----------------------------------------------------
  // 🔥 상단 네비 + 탭바
  // ----------------------------------------------------
  String selectedTab = "finding";  // 또는 "protecting"

  bool _isSearching = false;
  String _searchQuery = "";
  final TextEditingController _searchCtrl = TextEditingController();

  Widget _buildTopBar() {
    final bool isFindingTab = selectedTab == "finding";

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 1️⃣ 뒤로가기 버튼 (수정됨)
              GestureDetector(
                onTap: () {
                  // 현재 화면을 종료하고 이전 화면으로 돌아갑니다.
                  Navigator.pop(context); 
                },
                child: const Icon(Icons.arrow_back, size: 28, color: Colors.black),
              ),

              GestureDetector(
                onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
                child: Image.asset("assets/images/dasibom_logo.png", height: 40),
              ),

              // 2️⃣ 홈 버튼 (수정됨)
              GestureDetector(
                onTap: () => setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) { // ✅ 닫을 때 초기화
                    _searchQuery = "";
                    _searchCtrl.clear();
                  }
                }),
                child: Icon(
                  _isSearching ? Icons.close : Icons.search,
                  size: 28, color: Colors.black,
                ),
              ),
            ],
          ),
        ),

      const SizedBox(height: 4),

      if (_isSearching)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: TextField(
            controller: _searchCtrl,
            autofocus: true,
            decoration: InputDecoration(
              hintText: "이름, 카테고리, 나이, 성별 검색",
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (v) {
              setState(() {
                _searchQuery = v;

                if (selectedTab == "finding") {
                  currentFuture = fetchFinding();
                } else {
                  currentFuture = fetchProtecting();
                }
              });
            },
          ),
        ),

      // 탭 2개 ( 아래 개별 라인 )
      Row(
        children: [
          // 🔹 왼쪽 탭
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (selectedTab != "finding") {   // 🔥 여기
                  setState(() {
                    selectedTab = "finding";
                    currentFuture = fetchFinding();
                  });
                }
              },
              child: Column(
                children: [
                  Text(
                    "찾는 중이에요",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: isFindingTab ? Colors.black : Colors.grey,
                    ),
                  ),
                  Container(
                    height: 2,
                    width: double.infinity,
                    color: isFindingTab
                        ? Colors.black
                        : Colors.grey.withValues(alpha: 0.3),
                    margin: const EdgeInsets.only(top: 6),
                  )
                ],
              ),
            ),
          ),

          // 🔹 오른쪽 탭
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (selectedTab != "protecting") {   // 🔥 여기
                  setState(() {
                    selectedTab = "protecting";
                    currentFuture = fetchProtecting();
                  });
                }
              },
              child: Column(
                children: [
                  Text(
                    "보호 중이에요",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: isFindingTab ? Colors.grey : Colors.black,
                    ),
                  ),
                  Container(
                    height: 2,
                    width: double.infinity,
                    color: isFindingTab
                        ? Colors.grey.withValues(alpha: 0.3)
                        : Colors.black,
                    margin: const EdgeInsets.only(top: 6),
                  )
                ],
              ),
            ),
          ),
        ],
      ),

      const SizedBox(height: 16),
    ],
    
  );
  
}

  Widget _buildRegionFilter() {
    return SizedBox(
      height: 34,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: regions.length,
        itemBuilder: (context, index) {
          final region = regions[index];
          final isSelected = selectedRegion == region;
          return GestureDetector(
            onTap: () => setState(() {
              selectedRegion = region;

              if (selectedTab == "finding") {
                currentFuture = fetchFinding();
              } else {
                currentFuture = fetchProtecting();
              }
            }),
            child: Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFFDE14C) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? const Color(0xFFFDE14C) : Colors.grey.shade300,
                ),
              ),
              child: Text(
                region,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: Colors.black87,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

// ----------------------------------------------------
// 🔥 Missing Card (수정된 코드)
// ----------------------------------------------------
Widget _buildMissingCard(MissingListPerson item) {
  return InkWell( // 1️⃣ 터치 감지 위젯 추가
    onTap: () {
      // 2️⃣ 상세 페이지로 이동 (Navigator 활용)
      Navigator.push(
        context,
        MaterialPageRoute(
          // 3️⃣ 클릭한 item 데이터를 상세 페이지로 전달
          builder: (context) => MissingDetailPage(
            person: item,
            isProtecting: selectedTab == 'protecting',
          ),
        ),
      );
    },
    borderRadius: BorderRadius.circular(18), // 물결 효과 범위 지정
    child: Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8DE),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(2, 3),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ... (기존 카테고리 태그 및 카드 내용 코드 동일) ...
          Positioned(
            top: -12,
            left: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE02D),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                item.category,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
            child: Column(
              children: [
                Expanded(
                  child: OverflowBox( // ✅ ClipRect 대신 OverflowBox
                    alignment: Alignment.topCenter,
                    maxHeight: double.infinity,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: item.photo != null && item.photo!.isNotEmpty
                                ? Image.network(item.photo!, fit: BoxFit.cover)
                                : const Center(child: Icon(Icons.person)),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("이름 : ${item.name}", maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text("성별 : ${convertGender(item.gender)}", maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text("나이 : ${item.age}", maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text("등록 : ${item.registeredDate}", maxLines: 1, overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    ),
  );
}

  // ----------------------------------------------------
  // 🔥 전체 build
  // ----------------------------------------------------
@override
Widget build(BuildContext context) {
  debugPrint("🟡 build 호출됨");
  return Scaffold(
    backgroundColor: const Color(0xFFFFFEF9),
    body: SafeArea(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopBar(),     // ⬅ 여기!!!!!

              // 🔸 카테고리 필터
              Padding(
                // 전체 좌우 여백을 살짝 조정 (취향에 따라 조절 가능)
                padding: const EdgeInsets.symmetric(horizontal: 0), 
                child: Row(
                  children: categories.map((cat) {
                    final isSelected = selectedCategory == cat;
                    
                    // ✨ 핵심 변경: Expanded로 감싸서 공간을 균등하게 배분
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() {
                          selectedCategory = cat;

                          if (selectedTab == "finding") {
                            currentFuture = fetchFinding();
                          } else {
                            currentFuture = fetchProtecting();
                          }
                        }),
                        child: Container(
                          height: 40,
                          alignment: Alignment.center,
                          // 버튼 사이의 간격을 위해 좌우 margin을 줍니다.
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.yellow[600] : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.grey.shade400),
                          ),
                          child: Text(
                            cat,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13, // 5개가 들어가야 하므로 글자 크기를 살짝 줄임
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

              const SizedBox(height: 8),
              _buildRegionFilter(),
              const SizedBox(height: 10),

              // 🔹 Grid List
              Expanded(
                child: FutureBuilder<List<MissingListPerson>>(
                  future: currentFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (!snapshot.hasData || snapshot.hasError) {
                      return const Center(child: Text("데이터를 불러오지 못했습니다."));
                    }

                    final filtered = snapshot.data!;

                    if (filtered.isEmpty) {
                      return const Center(child: Text("등록된 실종자가 없습니다."));
                    }

                    return LayoutBuilder(
                      builder: (context, constraints) {
                        final screenWidth = constraints.maxWidth;

                        final crossAxisCount = 2;
                        final spacing = 12.0;

                        final totalSpacing = spacing * (crossAxisCount - 1);
                        final itemWidth = (screenWidth - totalSpacing) / crossAxisCount;

                        // 카드 내부 구조 기준 세로 비율 계산
                        final itemHeight = itemWidth * 1.55; 
                        final aspectRatio = itemWidth / itemHeight;

                        return GridView.builder(
                          padding: const EdgeInsets.only(top: 15, bottom: 20, left: 5, right: 5),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            childAspectRatio: aspectRatio,
                            crossAxisSpacing: spacing,
                            mainAxisSpacing: 23,
                          ),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) => _buildMissingCard(filtered[i]),
                        );
                      },
                    );
                  },
                ),
              ),
            ]
          ),
        ),
      ),
    );
  }
}