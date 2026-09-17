import 'package:flutter/material.dart';

// 🚀 추후 이 파일들을 만들어서 주석을 풀고 연결할 예정입니다.
import 'citizen_form_tab.dart';
import 'citizen_status_tab.dart';

  class CitizenPage extends StatefulWidget {
    final String? targetName;
    final int? targetGender;
    final String? targetPhotoUrl;
    final String? targetMissingSeq;
    final int initialTabIndex; // ✅ 추가

  const CitizenPage({
    super.key,
    this.targetName,
    this.targetGender,
    this.targetPhotoUrl,
    this.targetMissingSeq,
    this.initialTabIndex = 0, // ✅ 추가
  });

  @override
  State<CitizenPage> createState() => _CitizenPageState();
}

class _CitizenPageState extends State<CitizenPage> {
  late int _selectedTabIndex;

  @override
  void initState() {
    super.initState();
    _selectedTabIndex = widget.initialTabIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:const Color(0xFFFFFEF9),
      body: SafeArea(
        child: Column(
          children: [
            // 1. 상단 앱바
            _buildTopBar(),
            
            // 2. 탭 선택 메뉴 (시민 제보 / 제보 현황)
            _buildCustomTabBar(),
            
            // 3. 선택된 탭에 따라 바뀌는 메인 화면 영역
            Expanded(
              child: _selectedTabIndex == 0
                  // 🚀 2. 받은 데이터를 CitizenFormTab으로 토스!
                  ? CitizenFormTab(
                      initialName: widget.targetName,
                      initialGender: widget.targetGender,
                      initialPhotoUrl: widget.targetPhotoUrl,
                      initialMissingSeq: widget.targetMissingSeq,
                      onSuccess: () => setState(() => _selectedTabIndex = 1),
                    )
                  : const CitizenStatusTab(),
            ),
          ],
        ),
      ),
    );
  }

  // --- 🎨 하위 위젯 빌더 ---

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back_ios_new, size: 28),
          ),
          GestureDetector(
            onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
            child: Image.asset("assets/images/dasibom_logo.png", height: 40,
                errorBuilder: (_, __, ___) => const Icon(Icons.favorite_border, color: Colors.pink, size: 30)),
          ),
          const SizedBox(width: 28),
        ],
      ),
    );
  }

  Widget _buildCustomTabBar() {
    return Row(
      children: [
        _buildTabItem(title: "시민 제보", index: 0),
        _buildTabItem(title: "제보 현황", index: 1),
      ],
    );
  }

  Widget _buildTabItem({required String title, required int index}) {
    final bool isActive = _selectedTabIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTabIndex = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            // 선택된 탭은 검은색 밑줄, 아닌 탭은 연한 회색 밑줄
            border: Border(
              bottom: BorderSide(
                color: isActive ? Colors.black87 : Colors.grey.shade300,
                width: isActive ? 2.0 : 1.0,
              ),
            ),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive ? Colors.black87 : Colors.grey.shade400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}